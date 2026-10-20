import { useCallback, useEffect, useState } from "react";
import type { TargetLanguage } from "./target-lang";

/**
 * 軽量i18n(2026-07-25): アプリの主要な操作面(ナビ・見出し・設定)を
 * 切り替える。設定の「表示言語」= profiles.ui_language を localStorage に
 * ミラーして、プロフィール取得を待たずに描画できるようにする。
 * 学習コンテンツ(単語の意味・解説)は対象外 — それは学習者の母語設定の話。
 *
 * ## 2026-08-25: 繁體中文を足した
 * オーナー決定「日本語、英語、台湾華語に絞って」。英語を学ぶ台湾人にとって、
 * ここが無いと**アプリが日本語か英語のまま**で、指摘⑬の半分が埋まらない。
 */

export type UiLang = "ja" | "en" | "zh-TW";

/** 表示言語の一覧。**先頭が既定**(サーバー側と初回描画はこれ)。 */
export const UI_LANGS = ["ja", "en", "zh-TW"] as const;

/** 表示言語を覚える鍵（`__root.tsx` の描画前スクリプトも同じ鍵を読む）。 */
export const UI_LANG_STORAGE_KEY = "ui-lang-v1";
const KEY = UI_LANG_STORAGE_KEY;
const EVENT = "ui-lang-changed";

/** 知らない値を既定に落とす。**未知の言語のまま描かない。** */
export function normalizeUiLang(raw: string | null | undefined): UiLang {
  const v = (raw ?? "").trim();
  return (UI_LANGS as readonly string[]).includes(v) ? (v as UiLang) : "ja";
}

/**
 * **選んだことがあるか。** `getUiLang` は選んでいない人にも既定を返す
 * ので、「選んで日本語だった」と「一度も選んでいない」が区別できない
 * (`language-sync.ts` の注)。
 */
export function storedUiLang(): string | null {
  if (typeof window === "undefined") return null;
  try {
    return localStorage.getItem(KEY);
  } catch {
    return null;
  }
}

/**
 * **ブラウザの言語から、最初の表示言語を決める**（2026-10-03 実物確認「英語・中文の
 * ブラウザでもウェルカム画面が日本語」— 6回中4回）。表示言語を選ぶのはウェルカムの
 * 次の画面なので、それまでは端末の言語に合わせる。
 *
 * 先頭から順に見て、知っている言語に最初に当たった物を使う:
 * zh-TW / zh-Hant / zh-HK / zh-MO → 繁體中文、ja → 日本語、en → 英語。
 * 簡体字の中文（zh-CN など）は繁體中文にしない（字が違う）。何にも当たらなければ英語。
 */
export function browserUiLang(languages: readonly string[] | null | undefined): UiLang {
  for (const raw of languages ?? []) {
    const l = (raw ?? "").trim().toLowerCase();
    if (!l) continue;
    if (/^zh-(tw|hk|mo)\b/.test(l) || l.startsWith("zh-hant")) return "zh-TW";
    if (l === "ja" || l.startsWith("ja-")) return "ja";
    if (l === "en" || l.startsWith("en-")) return "en";
  }
  return "en";
}

/**
 * **最初の画面（ウェルカム）で使う表示言語。** 選んだことがあればそれ、無ければ
 * ブラウザの言語（`browserUiLang`）。選んだ値は**決して上書きしない**。
 */
export function initialUiLang(): UiLang {
  const stored = storedUiLang();
  if (stored && (UI_LANGS as readonly string[]).includes(stored)) return stored as UiLang;
  if (typeof navigator === "undefined") return "ja";
  const langs = navigator.languages?.length ? navigator.languages : [navigator.language];
  return browserUiLang(langs);
}

export function getUiLang(): UiLang {
  if (typeof window === "undefined") return "ja";
  try {
    return normalizeUiLang(localStorage.getItem(KEY));
  } catch {
    return "ja";
  }
}

/**
 * 表示言語の名前の翻訳キー。
 *
 * **`UI_LANGS` と対で持つ。** 設定の一覧はここを回すので、言語を足して
 * ここを直し忘れると型で落ちる（訳したのに選べない、が起きない）。
 */
export const UI_LANG_LABEL_KEYS: Record<UiLang, string> = {
  ja: "settings.langJa",
  en: "settings.langEn",
  "zh-TW": "settings.langZhTw",
};

/**
 * **プロンプトの中でその言語を何と呼ぶか。**
 *
 * `UI_LANG_LABEL_KEYS` は画面に出す名前(その言語自身で書く)、
 * こちらは AI への指示文の中で使う名前で、**指示文が日本語なので
 * 日本語で書く**。用途が違うので同じ表にはしない。
 *
 * server 側(`ai-provider.server.ts`)に置きたくなるが、そちらに置くと
 * `"zh-TW"` の直書きが1つ増えて `target-lang.test.ts` の門に当たる。
 * 表示言語の一覧を持っているのはここなので、名前もここが持つのが正しい。
 */
export const UI_LANG_PROMPT_NAMES: Record<UiLang, string> = {
  ja: "日本語",
  en: "英語",
  "zh-TW": "繁體中文(台湾)",
};

/**
 * **学んでいる言語**の名前の翻訳キー。
 *
 * `UI_LANG_LABEL_KEYS`(表示言語)とは別物。いまは両方に `ja` があるが、
 * 意味が違う — あちらは「画面を日本語にする」、こちらは「日本語を学ぶ」。
 * 同じ表にすると、日本語を学ぶ版を足した日に片方の意味が壊れる。
 *
 * 鍵の一覧そのものは `target-lang.ts` の `TARGET_LANGUAGES` が持つ。
 * ここは名前だけ。設定の一覧はここを回すので、言語を足して
 * ここを直し忘れると**型で落ちる**(選べない言語ができない)。
 */
export const TARGET_LANG_LABEL_KEYS: Record<TargetLanguage, string> = {
  "zh-TW": "settings.langZhTw",
  en: "settings.langEn",
  // 表示言語の「日本語」と同じ文言を使う(名前としては同じ)。意味は「日本語を学ぶ」。
  ja: "settings.langJa",
};

/**
 * 日付・数の書式に使う locale。
 *
 * **1箇所に集める。** これまで `localeOf(useUiLang())` が
 * 13箇所に散っていた。3つ目の言語を足すと、その全部で台湾の人が
 * **日本語の日付書式**になる — 型でもビルドでも lint でも落ちない。
 * この app が声・写真・演出で繰り返してきた形なので、口を1つにする。
 */
export function localeOf(lang: UiLang): string {
  return LOCALES[lang] ?? LOCALES.ja;
}

const LOCALES: Record<UiLang, string> = {
  ja: "ja-JP",
  en: "en-US",
  // 台湾の書式(民国暦ではなく西暦。2026/8/25 の順)。
  "zh-TW": "zh-TW",
};

/**
 * `lang` 属性に入れる値。
 *
 * 繁體中文は `zh-Hant` を必ず付ける — 漢字は同じ文字コードでも言語で
 * 字形が違う(直/直、每/毎)。付けないと日本語のフォントに落ちて、
 * 台湾の人に日本の字形が出る。
 */
export function htmlLangOf(lang: UiLang): string {
  return lang === "zh-TW" ? "zh-Hant-TW" : lang;
}

export function setUiLang(lang: UiLang) {
  try {
    localStorage.setItem(KEY, lang);
    window.dispatchEvent(new CustomEvent(EVENT));
  } catch {
    /* storage unavailable */
  }
}

/**
 * 表に出る文字は全部ここに在る。**外に出しているのは検査のため** —
 * 和文の約物の決めごと(`ja-punctuation.ts`)を辞書全体に当てて、
 * 手で直した決めごとが次の文字列で戻らないようにする。
 */
export const DICT: Record<string, Record<UiLang, string>> = {
  "first.introStart": { ja: "はじめる", en: "Get started", "zh-TW": "開始使用" },
  // 最初の画面のキャッチフレーズ（オーナー指定 2026-10-03）。
  "first.introTagline": {
    ja: "日常のすべてが学びになる",
    en: "Every moment becomes a lesson",
    "zh-TW": "生活中處處都是學習",
  },
  "first.notificationsTitle": {
    ja: "学習の通知を\n設定しますか？",
    en: "Would you like\nlearning reminders?",
    "zh-TW": "要設定學習提醒嗎？",
  },
  "first.notificationsHint": {
    ja: "必要なものだけ選べます。あとから変更できます。",
    en: "Choose what feels useful. You can change this later.",
    "zh-TW": "只選需要的，之後隨時可以更改。",
  },
  "first.readyTitle": { ja: "準備ができました！", en: "You’re all set!", "zh-TW": "準備好了！" },
  "first.readyHint": {
    ja: "実際に1枚撮りながら、\n使い方を覚えましょう。",
    en: "Learn the app by catching\nyour first word.",
    "zh-TW": "一邊拍下第一張照片，\n一邊學會怎麼使用。",
  },
  "first.readyPhoto": {
    ja: "最初の発見は、もうすぐ。",
    en: "Your first discovery is close.",
    "zh-TW": "你的第一個發現，就快到了。",
  },
  "first.readyStart": {
    ja: "チュートリアルをはじめる",
    en: "Start the tutorial",
    "zh-TW": "開始新手教學",
  },
  "first.readyFootnote": {
    ja: "撮った写真は、あとからアカウントに保存できます。",
    en: "You can save your photo to your account afterward.",
    "zh-TW": "拍下的照片稍後可以存到帳號。",
  },
  "first.sampleFlower": { ja: "花", en: "flower", "zh-TW": "花" },
  "first.sampleCat": { ja: "猫", en: "cat", "zh-TW": "貓" },
  "first.sampleDex": {
    ja: "写真で集まる、ことばの図鑑 · 見本",
    en: "A photo collection of words · Example",
    "zh-TW": "用照片收藏的單字圖鑑 · 示範",
  },
  "first.setup": { ja: "はじめの設定", en: "Getting started", "zh-TW": "開始設定" },
  "first.goals": {
    ja: "学ぶ目的を\n教えてください",
    en: "What brings you\nhere?",
    "zh-TW": "你學語言的目的是？",
  },
  "first.goalsHint": {
    ja: "いくつでも選べます。例文の場面をあなたに合わせます。",
    en: "Choose any. We’ll tailor example situations to you.",
    "zh-TW": "可以複選，例句情境會配合你的目標。",
  },
  "first.interests": {
    ja: "好きなことから、\nことばを広げよう",
    en: "Start with what\nyou love.",
    "zh-TW": "從喜歡的事物，\n開始學單字。",
  },
  "first.interestsHint": {
    ja: "興味のあるテーマを選んでください（複数選択可）。",
    en: "Choose the topics you enjoy. Select as many as you like.",
    "zh-TW": "選擇感興趣的主題，可以複選。",
  },
  "first.timeNote": {
    ja: "短い時間でも大丈夫。あなたのペースで続けましょう。",
    en: "A few minutes is a great start. Go at your own pace.",
    "zh-TW": "幾分鐘也很好，照著自己的步調來。",
  },
  "first.goal.conversation": { ja: "日常会話", en: "Everyday conversation", "zh-TW": "日常會話" },
  "first.goal.travel": { ja: "旅行・留学", en: "Travel & study abroad", "zh-TW": "旅行、留學" },
  "first.goal.work": { ja: "仕事・キャリア", en: "Work & career", "zh-TW": "工作、職涯" },
  "first.goal.exams": { ja: "試験対策", en: "Exam preparation", "zh-TW": "考試準備" },
  "first.goal.culture": { ja: "趣味・教養", en: "Hobbies & culture", "zh-TW": "興趣、文化" },
  "first.goal.other": { ja: "その他", en: "Something else", "zh-TW": "其他" },
  "first.interest.food": { ja: "食べ物", en: "Food & drink", "zh-TW": "美食" },
  "first.interest.travel": { ja: "旅行", en: "Travel", "zh-TW": "旅行" },
  "first.interest.animals": { ja: "動物", en: "Animals", "zh-TW": "動物" },
  "first.interest.nature": { ja: "自然", en: "Nature", "zh-TW": "自然" },
  "first.interest.city": { ja: "建物・街", en: "City & buildings", "zh-TW": "建築、街景" },
  "first.interest.fashion": { ja: "ファッション", en: "Fashion", "zh-TW": "時尚" },
  "first.interest.business": { ja: "ビジネス", en: "Business", "zh-TW": "商業" },
  "first.interest.music": { ja: "音楽・映画", en: "Music & film", "zh-TW": "音樂、電影" },
  "first.interest.sports": { ja: "スポーツ", en: "Sports", "zh-TW": "運動" },
  "first.exploreTitle": {
    ja: "ひとつのことばを、\nもっと深く。",
    en: "One word.\nMore to discover.",
    "zh-TW": "一個單字，\n更多發現。",
  },
  "first.exploreHint": {
    ja: "意味・発音・例文・チャンクを、この1枚に。",
    en: "Meaning, sound, examples and chunks on one card.",
    "zh-TW": "意思、發音、例句、語塊，都在這一張。",
  },
  "first.sampleCoffee": { ja: "コーヒー", en: "coffee", "zh-TW": "咖啡" },
  "first.sampleAlbum": {
    ja: "写真とことばで残る、今日のアルバム · 見本",
    en: "A day of photos and words · Example",
    "zh-TW": "用照片和單字留下今天 · 示範",
  },
  "first.previewUnavailable": {
    ja: "この画面確認用プレビューではAI解析を利用できません。写真は端末に残っています。",
    en: "AI analysis is unavailable in this visual preview. Your photo is still on your device.",
    "zh-TW": "這個畫面預覽無法使用 AI 分析。照片仍保留在裝置上。",
  },
  "first.photoUnsupported": {
    ja: "この写真を読み込めませんでした。カメラで撮り直すか、JPEGの写真を選んでください。",
    en: "We couldn't read this photo. Retake it with the camera or select a JPEG image.",
    "zh-TW": "無法讀取這張照片。請用相機重拍，或選擇 JPEG 照片。",
  },
  "first.analysisTimeout": {
    ja: "写真の解析に時間がかかっています。写真は残っています。もう一度試してください。",
    en: "Photo analysis is taking too long. Your photo is safe; please retry.",
    "zh-TW": "照片分析花了太久時間。照片仍在，可以再試一次。",
  },
  "first.personalTitle": {
    ja: "あなたの場面で使ってみよう",
    en: "Use it in your world",
    "zh-TW": "用在你的生活裡",
  },
  "first.personalLoading": {
    ja: "あなたに合う例文を準備しています",
    en: "Preparing examples for you",
    "zh-TW": "正在準備適合你的例句",
  },
  "first.personalHint": {
    ja: "選んだ目的・興味に合わせた例文と解説",
    en: "Examples and notes tailored to your goals and interests",
    "zh-TW": "依照你的目標與興趣準備的例句與說明",
  },
  "first.personalFailed": {
    ja: "例文を読み込めませんでした",
    en: "Could not load your examples",
    "zh-TW": "無法載入例句",
  },
  "first.otherMeanings": { ja: "意味と使い分け", en: "Meanings & usage", "zh-TW": "意思與用法" },
  "first.visualSample": {
    ja: "画面の見本 · 撮影結果ではありません",
    en: "Visual example · Not a photo analysis result",
    "zh-TW": "畫面示範，非照片分析結果",
  },
  "first.display": {
    ja: "表示言語を\n選んでください",
    en: "Choose your\ndisplay language",
    "zh-TW": "選擇介面語言",
  },
  "first.displayHint": {
    ja: "メニューや説明に使う言語です。",
    en: "The language for menus and explanations.",
    "zh-TW": "選單與說明會使用這個語言。",
  },
  "first.target": {
    ja: "学びたい言語は？",
    en: "What would you\nlike to learn?",
    "zh-TW": "你想學哪種語言？",
  },
  "first.targetHint": {
    ja: "街で出会ったことばを、この言語で学びます。",
    en: "Learn how to say the things you encounter.",
    "zh-TW": "學會用這個語言說出生活中的事物。",
  },
  "first.time": {
    ja: "1日、どれくらい\n学びたい？",
    en: "A little time,\nevery day.",
    "zh-TW": "每天想學多久？",
  },
  "first.timeHint": {
    ja: "あなたのペースで。あとから変更できます。",
    en: "Go at your own pace. You can change this later.",
    "zh-TW": "依照自己的步調，之後可以調整。",
  },
  "first.minutes": { ja: "{n}分", en: "{n} min", "zh-TW": "{n} 分鐘" },
  "first.start": { ja: "体験をはじめる", en: "Try your first Catch", "zh-TW": "開始體驗" },
  "first.next": { ja: "次へ", en: "Next", "zh-TW": "下一步" },
  "first.back": { ja: "戻る", en: "Back", "zh-TW": "返回" },
  "first.backToTutorial": {
    ja: "チュートリアルに戻る",
    en: "Back to the tutorial",
    "zh-TW": "回到教學",
  },
  "first.settingsNote": {
    ja: "登録前の設定です。登録すると、そのままあなたのアカウントに引き継がれます。",
    en: "These are your settings before signing up. They carry over to your account when you sign up.",
    "zh-TW": "這是註冊前的設定。註冊後會直接沿用到你的帳號。",
  },
  "first.dailyTime": { ja: "1日の学習時間", en: "Daily study time", "zh-TW": "每天的學習時間" },
  "first.redoQuestions": {
    ja: "最初の質問に答え直す",
    en: "Answer the first questions again",
    "zh-TW": "重新回答一開始的問題",
  },
  "first.backToWelcome": {
    ja: "最初の画面に戻る",
    en: "Back to the welcome screen",
    "zh-TW": "回到最初的畫面",
  },
  "first.sampleSea": { ja: "海", en: "sea", "zh-TW": "海" },
  "first.dexSwipe": {
    ja: "横にスライドしてみましょう。出会った場面と一緒に見返せるので、思い出しやすくなります。",
    en: "Swipe sideways. Seeing where you found each word makes it easier to recall.",
    "zh-TW": "左右滑動看看。連同遇見它的場景一起回顧，更容易想起來。",
  },
  "first.dexTypes": {
    ja: "ここを押すと、集めた写真をまとめて見られます。地図やリストでも見られます。",
    en: "Tap here to see all your photos at once. There are map and list views too.",
    "zh-TW": "點這裡就能一次看所有照片，也可以用地圖或清單檢視。",
  },
  "first.dexOpen": {
    ja: "さっき撮った1枚です。押して、詳しく見てみましょう。",
    en: "This is the photo you just took. Tap it to see more.",
    "zh-TW": "這是你剛拍的照片，點一下看看詳細內容。",
  },
  "first.tryReview": {
    ja: "復習してみる",
    en: "Try a review",
    "zh-TW": "試著複習",
  },
  "first.completeTitle": {
    ja: "最初のキャッチ、完了！",
    en: "Your first Catch is complete!",
    "zh-TW": "完成第一次捕捉！",
  },
  "first.completeHint": {
    ja: "撮って、意味を知って、思い出す。\n身のまわりが、あなたの単語帳になります。",
    en: "Snap it. Understand it. Recall it.\nEverything around you becomes your word book.",
    "zh-TW": "拍下來、了解意思、再想起來。\n身邊的一切，都是你的單字本。",
  },
  "first.home": {
    ja: "撮った写真とことばが、その日のアルバムになります。単語帳に書き写す必要はありません。",
    en: "Your photos and words become a daily album. No copying into a notebook.",
    "zh-TW": "拍下的照片和單字，會變成當天的相簿。不必再抄進單字本。",
  },
  "first.tapCamera": {
    ja: "下のカメラを押してください。名前を知らない物でも大丈夫です。",
    en: "Tap the camera below. It's fine if you don't know what it's called.",
    "zh-TW": "點下方的相機。不知道名稱也沒關係。",
  },
  "first.dex": {
    ja: "集めたことばが、撮った写真と一緒に並びます。",
    en: "Every word you catch is kept with its photo.",
    "zh-TW": "收集的單字會和照片一起保存。",
  },
  "first.review": {
    ja: "写真を手がかりに思い出します。忘れかけた頃にまた出題されるので、記憶に残ります。",
    en: "Your photo is the clue. Words come back just before you'd forget them, so they stick.",
    "zh-TW": "以照片當提示來回想。單字會在快忘記時再出現，讓你記得更牢。",
  },
  "first.shoot": {
    ja: "撮るだけで、AIが写真から学べることばを見つけます。",
    en: "Just take the photo. AI finds words you can learn in it.",
    "zh-TW": "只要拍下來，AI 就會從照片裡找出可以學的單字。",
  },
  "first.shootCta": { ja: "1枚撮ってみる", en: "Take your first photo", "zh-TW": "拍下第一張照片" },
  "first.pick": {
    ja: "AIが写真から見つけたことばです。1つ押してください。",
    en: "AI found these words in your photo. Tap one.",
    "zh-TW": "這些是 AI 從照片裡找到的單字，點一個吧。",
  },
  "first.detail": {
    ja: "意味がすぐに出ます。スピーカーを押すと、発音を聞けます。",
    en: "The meaning shows up right away. Tap the speaker to hear it.",
    "zh-TW": "馬上就能看到意思。點喇叭可以聽發音。",
  },
  "first.peel": {
    ja: "あなたの写真が、この単語のカードになります。指ではがしてみましょう。",
    en: "Your photo becomes this word's card. Peel it off with your finger.",
    "zh-TW": "你的照片就是這個單字的卡片。用手指把它掀起來。",
  },
  "first.added": {
    ja: "図鑑に入りました",
    en: "Added to your Dex",
    "zh-TW": "已加入圖鑑",
  },
  "first.local": {
    ja: "この端末に、最初の1語が入りました。",
    en: "Your first word is now on this device.",
    "zh-TW": "第一個單字已儲存在這個裝置上。",
  },
  "first.keep": {
    ja: "登録して続ける",
    en: "Create an account to continue",
    "zh-TW": "註冊並繼續",
  },
  "first.account": {
    ja: "最初のことばを、\nあなたのものに。",
    en: "Make your first word\ntruly yours.",
    "zh-TW": "讓第一個單字，\n成為你的收藏。",
  },
  "first.accountHint": {
    ja: "登録して、この写真とことばをアカウントに保存。",
    en: "Sign up to save this photo and word to your account.",
    "zh-TW": "註冊帳號，保存這張照片和單字。",
  },
  "first.failed": {
    ja: "処理できませんでした。写真を残したまま、もう一度試せます。",
    en: "That did not work. Your photo is kept so you can retry.",
    "zh-TW": "處理失敗。照片仍保留著，可以再試一次。",
  },
  "first.busy": {
    ja: "いま体験が混み合っています。少し時間をおいて、もう一度試してください。写真は残っています。",
    en: "The trial is busy right now. Your photo is kept; please try again in a little while.",
    "zh-TW": "目前體驗人數較多。照片仍保留著，請稍後再試一次。",
  },
  "first.trialFull": {
    ja: "今日の体験の受け付けはいっぱいになりました。写真は残っています。明日もう一度試すか、アカウントを作ってアプリから使ってください。",
    en: "Today's trial slots are full. Your photo is kept. Please try again tomorrow, or create an account to use the app.",
    "zh-TW": "今天的體驗名額已滿。照片仍保留著。請明天再試一次，或註冊帳號後從 App 使用。",
  },
  "first.storage": {
    ja: "この端末に保存できませんでした。空き容量やブラウザの保存設定を確認してください。",
    en: "Could not save on this device. Check free space and browser storage settings.",
    "zh-TW": "無法儲存在這個裝置上，請確認剩餘空間與瀏覽器儲存設定。",
  },
  "first.noWords": {
    ja: "写真から言葉を見つけられませんでした。明るい所で、撮りたい物に近づいて撮り直してください。",
    en: "No words were found in this photo. Move closer to the object in good light and retake it.",
    "zh-TW": "無法從照片中找到單字。請在明亮的地方靠近想拍的東西，再拍一次。",
  },
  "first.aiFormat": {
    ja: "AIの返事を読み取れませんでした。もう一度試してください。写真は残っています。",
    en: "Could not read the AI's reply. Please try again; your photo is kept.",
    "zh-TW": "無法讀取 AI 的回覆。請再試一次，照片仍保留著。",
  },
  "first.retry": { ja: "もう一度試す", en: "Try again", "zh-TW": "再試一次" },
  "first.retake": { ja: "撮り直す", en: "Retake photo", "zh-TW": "重新拍照" },
  "first.guestUnavailable": {
    ja: "登録する前は、写真をAIで分析できません。見本の写真で、このあとの流れを体験できます。",
    en: "Photo analysis isn't available before you sign up. You can try the rest with a sample photo.",
    "zh-TW": "註冊前無法用 AI 分析照片。可以用範例照片體驗接下來的流程。",
  },
  "first.network": {
    ja: "通信できませんでした。電波やWi-Fiを確かめて、もう一度試してください。写真は残っています。",
    en: "Couldn't connect. Check your signal or Wi-Fi and try again. Your photo is kept.",
    "zh-TW": "無法連線。請確認訊號或 Wi-Fi 後再試一次，照片仍保留著。",
  },
  "first.useSample": {
    ja: "見本で体験を続ける",
    en: "Continue with a sample",
    "zh-TW": "用範例繼續體驗",
  },
  "first.sampleNote": {
    ja: "見本の写真と単語です。登録すると、自分の写真で使えます。",
    en: "Sample photo and word. Sign up to use your own photos.",
    "zh-TW": "這是範例照片與單字。註冊後就能用自己的照片。",
  },
  "first.importing": {
    ja: "最初のことばを引き継いでいます",
    en: "Saving your first word to your account",
    "zh-TW": "正在將第一個單字存入帳號",
  },
  "first.importFailed": {
    ja: "引き継ぎが完了していません。写真と単語は端末に残っています。再試行してください。",
    en: "Transfer is not complete. Your photo and word are still on this device. Please retry.",
    "zh-TW": "尚未完成轉存，照片和單字仍保留在裝置上。請重試。",
  },
  "first.confirm": {
    ja: "確認メールを送りました。メールのリンクを開いて登録を完了したら、このページに戻って「ログイン」してください。撮った写真と単語は、このブラウザで引き継がれます。",
    en: "We sent a confirmation email. After opening the link, come back to this page and sign in. Your photo and word carry over in this browser.",
    "zh-TW":
      "已寄出確認信。開啟信中的連結完成註冊後，請回到這個頁面「登入」。拍的照片和單字會在這個瀏覽器中接續。",
  },
  "auth.googleInApp": {
    ja: "LINEなどアプリの中で開いているため、Googleでは登録できません（Googleの決まりです）。メールかAppleで登録してください。",
    en: "Google sign-in isn't allowed inside other apps such as LINE (Google's policy). Please use email or Apple.",
    "zh-TW":
      "目前是在 LINE 等 App 裡開啟，依 Google 的規定無法用 Google 註冊。請改用電子郵件或 Apple。",
  },
  "auth.confirmedSignin": {
    ja: "確認が終わったので、ログインする",
    en: "I've confirmed — sign in",
    "zh-TW": "已完成確認，登入",
  },
  "first.signin": {
    ja: "アカウントをお持ちの方はログイン",
    en: "Already have an account? Sign in",
    "zh-TW": "已有帳號？登入",
  },
  // 最初の画面の下の1行。「ログイン」だけを青い文字（押せる所）にする（2026-10-03）。
  "first.signinPrompt": {
    ja: "アカウントをお持ちの方はこちらから",
    en: "Already have an account?",
    "zh-TW": "已有帳號？",
  },
  "first.signinLink": { ja: "ログイン", en: "Sign in", "zh-TW": "登入" },
  // ログイン済みでまだ初回の案内を終えていない人向け（ログインを押しても同じ画面に戻る輪を断つ）。
  "first.signedInNote": {
    ja: "ログインしました。「はじめる」から続けてください",
    en: "You're signed in. Tap Start to continue.",
    "zh-TW": "已登入，請點「開始」繼續",
  },
  "first.homeTitle": {
    ja: "今日のアルバム",
    en: "Today's album",
    "zh-TW": "今天的相簿",
  },
  "first.dexTitle": {
    ja: "写真でめくる",
    en: "Flip through your photos",
    "zh-TW": "翻閱你的照片",
  },
  "first.reviewPick": {
    ja: "問題に合うことばを選んでください。間違えても大丈夫です。",
    en: "Choose the word that fits the question. Mistakes are fine.",
    "zh-TW": "選出符合題目的單字。答錯也沒關係。",
  },
  "first.reviewNext": {
    ja: "答えを確かめたら「{next}」を押してください。",
    en: "Read the answer, then tap “{next}”.",
    "zh-TW": "看完答案後，點「{next}」。",
  },
  "first.reviewTitle": {
    ja: "自分の写真で復習",
    en: "Review with your photos",
    "zh-TW": "用自己的照片複習",
  },
  "first.shootTitle": {
    ja: "1枚撮ってみよう",
    en: "Take your first photo",
    "zh-TW": "拍下第一張照片",
  },
  "first.pickTitle": {
    ja: "覚えたいことばを選ぶ",
    en: "Pick a word to learn",
    "zh-TW": "選一個想學的單字",
  },
  "first.detailTitle": {
    ja: "意味と発音",
    en: "Meaning and sound",
    "zh-TW": "意思與發音",
  },
  "first.peelTitle": {
    ja: "はがして図鑑へ",
    en: "Peel it into your Dex",
    "zh-TW": "掀起來，放進圖鑑",
  },
  "first.shutterTitle": {
    ja: "気になる物を撮る",
    en: "Snap something nearby",
    "zh-TW": "拍下身邊的東西",
  },
  "first.addedHint": {
    ja: "写真と一緒に、この端末に保存しました。",
    en: "Saved on this device, together with your photo.",
    "zh-TW": "已經和照片一起存在這個裝置上。",
  },
  "first.dexViewsTitle": {
    ja: "ギャラリー表示にする",
    en: "Switch to gallery view",
    "zh-TW": "切換成圖片檢視",
  },
  "first.openTitle": {
    ja: "自分の単語を開く",
    en: "Open your word",
    "zh-TW": "打開你的單字",
  },
  "first.exploreCoachTitle": {
    ja: "単語の詳細",
    en: "Word details",
    "zh-TW": "單字詳情",
  },
  "first.reviewPickTitle": {
    ja: "答えてみよう",
    en: "Give it a try",
    "zh-TW": "試著回答",
  },
  "first.reviewNextTitle": {
    ja: "答え合わせ",
    en: "Check the answer",
    "zh-TW": "對答案",
  },
  "first.ready": { ja: "保存できました", en: "Saved", "zh-TW": "已儲存" },

  // --- 動的ページタイトル ---
  "page.cardDetail": {
    ja: "カード {id} — CatchWords",
    en: "Card {id} — CatchWords",
    "zh-TW": "字卡 {id} — CatchWords",
  },
  // --- OAuth 同意画面 ---
  "oauth.loadFailed": {
    ja: "認証リクエストを読み込めませんでした",
    en: "Couldn't load the authorization request",
    "zh-TW": "無法載入授權請求",
  },
  "oauth.unknownClient": {
    ja: "外部クライアント",
    en: "an external client",
    "zh-TW": "外部應用程式",
  },
  "oauth.noRedirect": {
    ja: "認証サーバーからリダイレクト先が返されませんでした。",
    en: "The authorization server didn't return a redirect target.",
    "zh-TW": "授權伺服器沒有回傳轉址位址。",
  },
  "oauth.connectTitle": {
    ja: "{client} を CatchWords に接続",
    en: "Connect {client} to CatchWords",
    "zh-TW": "將 {client} 連接到 CatchWords",
  },
  "oauth.explain": {
    ja: "このクライアントは、あなたとしてサインインした状態で CatchWords の有効なツールを呼び出せるようになります。",
    en: "This client will be able to call CatchWords' enabled tools while signed in as you.",
    "zh-TW": "這個應用程式將能以你的身分登入，並呼叫 CatchWords 已啟用的工具。",
  },
  "oauth.redirectTo": { ja: "リダイレクト先:", en: "Redirects to:", "zh-TW": "轉址到：" },
  "oauth.scope1": {
    ja: "・あなたの CatchWords プロフィール（表示名・アバター）",
    en: "· Your CatchWords profile (display name, avatar)",
    "zh-TW": "、你的 CatchWords 個人檔案（顯示名稱、頭像）",
  },
  "oauth.scope2": {
    ja: "・あなたのステッカー（単語カード・キャプション・撮影地）",
    en: "· Your stickers (word cards, captions, capture locations)",
    "zh-TW": "、你的貼紙（單字卡、感想、拍攝地點）",
  },
  "oauth.scope3": {
    ja: "・あなたの SRS 復習の予定",
    en: "· Your SRS review schedule",
    "zh-TW": "、你的 SRS 複習排程",
  },
  "oauth.rlsNote": {
    ja: "このアプリの権限とバックエンドポリシー(RLS)は引き続き適用されます。他ユーザーのデータは公開されません。",
    en: "This app's permissions and backend policies (RLS) still apply. Other users' data is never exposed.",
    "zh-TW": "這個 App 的權限與後端政策（RLS）仍然有效，其他使用者的資料不會被公開。",
  },
  "oauth.approve": { ja: "許可する", en: "Allow", "zh-TW": "允許" },
  "oauth.deny": { ja: "拒否する", en: "Deny", "zh-TW": "拒絕" },
  // --- 共通 ---
  "common.back": { ja: "戻る", en: "Back", "zh-TW": "返回" },
  // --- ページタイトル・復習 ---
  "page.home": { ja: "ホーム — CatchWords", en: "Home — CatchWords", "zh-TW": "首頁 — CatchWords" },
  "page.dex": { ja: "図鑑 — CatchWords", en: "Dex — CatchWords", "zh-TW": "圖鑑 — CatchWords" },
  "page.review": {
    ja: "復習 — CatchWords",
    en: "Review — CatchWords",
    "zh-TW": "複習 — CatchWords",
  },
  "page.scan": {
    ja: "スキャン | CatchWords",
    en: "Scan | CatchWords",
    "zh-TW": "掃描 | CatchWords",
  },
  "page.capture": {
    ja: "集める — CatchWords",
    en: "Catch — CatchWords",
    "zh-TW": "收集 — CatchWords",
  },
  "page.settings": {
    ja: "設定 — CatchWords",
    en: "Settings — CatchWords",
    "zh-TW": "設定 — CatchWords",
  },
  "page.onboarding": {
    ja: "ようこそ — CatchWords",
    en: "Welcome — CatchWords",
    "zh-TW": "歡迎 — CatchWords",
  },
  "page.auth": {
    ja: "ログイン — CatchWords",
    en: "Sign in — CatchWords",
    "zh-TW": "登入 — CatchWords",
  },
  "page.nativeAuth": {
    ja: "アプリにログイン — CatchWords",
    en: "Sign in to the app — CatchWords",
    "zh-TW": "登入 App — CatchWords",
  },
  "native.returning": {
    ja: "アプリに戻っています…",
    en: "Returning to the app…",
    "zh-TW": "正在返回 App…",
  },
  "native.openApp": {
    ja: "アプリに戻る",
    en: "Return to the app",
    "zh-TW": "返回 App",
  },
  "native.starting": {
    ja: "ログイン画面を開いています…",
    en: "Opening the sign-in page…",
    "zh-TW": "正在開啟登入頁面…",
  },
  "native.failed": {
    ja: "ログインを確認できませんでした。もう一度お試しください。",
    en: "We couldn't confirm your sign-in. Please try again.",
    "zh-TW": "無法確認登入。請再試一次。",
  },
  "native.retryGoogle": {
    ja: "Googleでやり直す",
    en: "Try again with Google",
    "zh-TW": "以 Google 重試",
  },
  "native.retryApple": {
    ja: "Appleでやり直す",
    en: "Try again with Apple",
    "zh-TW": "以 Apple 重試",
  },
  "native.badLink": {
    ja: "このリンクは使えません。iPhoneアプリのログイン画面からやり直してください。",
    en: "This link can't be used. Please start again from the iPhone app's sign-in screen.",
    "zh-TW": "此連結無法使用。請從 iPhone App 的登入畫面重新開始。",
  },
  "page.reset": {
    ja: "パスワード再設定 — CatchWords",
    en: "Reset password — CatchWords",
    "zh-TW": "重設密碼 — CatchWords",
  },
  "page.privacy": {
    ja: "プライバシーポリシー — CatchWords",
    en: "Privacy Policy — CatchWords",
    "zh-TW": "隱私權政策 — CatchWords",
  },
  "page.terms": {
    ja: "利用規約 — CatchWords",
    en: "Terms of Service — CatchWords",
    "zh-TW": "使用條款 — CatchWords",
  },
  "page.tokushoho": {
    ja: "特定商取引法に基づく表記 — CatchWords",
    en: "Legal notice — CatchWords",
    "zh-TW": "特定商業交易法標示 — CatchWords",
  },
  "page.support": {
    ja: "お問い合わせ・サポート — CatchWords",
    en: "Contact & Support — CatchWords",
    "zh-TW": "聯絡與支援 — CatchWords",
  },
  // --- 復習・単語カード ---
  // --- 日記の足場(要望 #88) ---
  "rv.streakLine": {
    ja: "復習が{n}日続いています",
    en: "{n}-day review streak",
    "zh-TW": "已經連續複習 {n} 天",
  },
  // --- 単語帳の取り込み(src/lib/wordbook.ts) ---
  // **取り込みではない。** 許可を取っていないので、見に行く先だけを出す。
  // --- 英語のコーパス(第4段) -----------------------------------------------
  // --- もう一度撮る提案(src/lib/retake.ts) ---
  "retake.hint": {
    ja: "「{w}」をもう一度撮ってみましょう",
    en: "Catch “{w}” again",
    "zh-TW": "再拍一次「{w}」看看",
  },
  "rv.overallTitle": {
    ja: "全体の記憶率（前後2週間）",
    en: "Overall retention (±2 weeks)",
    "zh-TW": "整體記憶率（前後兩週）",
  },
  /**
   * **％の意味を書いておく。** 語に出す数は1つだけ — いま思い出せる確率
   * （オーナー指示 2026-09-23「単語の数値は1つに統一したい」）。
   */
  "rv.tapForCurve": {
    ja: "タップで単語ごとの忘却曲線と「いつ忘れるか」の予測が見られます",
    en: "Tap to see each word's forgetting curve and when you're predicted to forget it",
    "zh-TW": "點一下可以看每個單字的遺忘曲線，以及「什麼時候會忘記」的預測",
  },
  "rv.today": { ja: "今日", en: "Today", "zh-TW": "今天" },
  "rv.targetAlt": { ja: "復習対象", en: "The word being reviewed", "zh-TW": "正在複習的單字" },
  "rv.topChunk": { ja: "よく使う形", en: "Most-used pattern", "zh-TW": "最常用的形式" },
  // 解説がまだ生成されていない語でも、答え合わせを空にしないための見出し
  // （オーナー報告 2026-09-15「復習の時に解説がない」）。
  "rv.meaning": { ja: "意味", en: "Meaning", "zh-TW": "意思" },
  "rv.example": { ja: "例文", en: "Example", "zh-TW": "例句" },
  "rv.relatedWords": { ja: "一緒に覚える語", en: "Words to learn with it", "zh-TW": "一起記的詞" },
  "rv.measureWords": { ja: "量詞", en: "Measure words", "zh-TW": "量詞" },
  "rv.goodToKnow": { ja: "知っておくと得", en: "Good to know", "zh-TW": "小知識" },
  "rv.kindSyn": { ja: "似", en: "Similar", "zh-TW": "近" },
  "rv.kindAnt": { ja: "反", en: "Opposite", "zh-TW": "反" },
  "rv.kindRel": { ja: "関", en: "Related", "zh-TW": "關" },
  "dex.truncated": {
    ja: "全{total}件のうち、新しい{n}件を表示しています。これより古いものはまだ出せていません。",
    en: "Showing the newest {n} of {total}. Older ones aren't loaded yet.",
    "zh-TW": "共 {total} 筆，目前顯示最新的 {n} 筆。比這更舊的還沒載入。",
  },
  // 「×3」はこのアプリが決めた記号なので、出ているときは意味を添える。
  "dex.metCountLegend": {
    ja: "は、その言葉に出会った回数です",
    en: "means how many times you've met that word",
    "zh-TW": "是遇到那個字的次數",
  },
  "dex.metCountAria": {
    ja: "{word} — {n}回出会った",
    en: "{word} — met {n} {n|time|times}",
    "zh-TW": "{word} — 遇到 {n} 次",
  },
  "dex.allCategories": { ja: "すべて", en: "All", "zh-TW": "全部" },
  "dex.calendar": { ja: "カレンダー", en: "Calendar", "zh-TW": "行事曆" },
  "dex.timeline": {
    ja: "その日のタイムライン",
    en: "Timeline of the day",
    "zh-TW": "當天的時間軸",
  },
  "dex.openTimeline": { ja: "タイムラインを開く", en: "Open timeline", "zh-TW": "打開時間軸" },
  "dex.closeTimeline": { ja: "タイムラインを閉じる", en: "Close timeline", "zh-TW": "關閉時間軸" },
  "dex.prevDay": { ja: "前の撮った日", en: "Previous day", "zh-TW": "上一個拍攝日" },
  "dex.nextDay": { ja: "次の撮った日", en: "Next day", "zh-TW": "下一個拍攝日" },
  "dex.cards": { ja: "カード", en: "Cards", "zh-TW": "卡片" },
  "dex.calendarEmpty": {
    ja: "まだ写真がありません。撮るとその日のマスに入ります。",
    en: "No photos yet. Each one lands on the day you took it.",
    "zh-TW": "還沒有照片。拍了就會放進那天的格子裡。",
  },
  "dex.prevMonth": { ja: "前の月", en: "Previous month", "zh-TW": "上個月" },
  "dex.nextMonth": { ja: "次の月", en: "Next month", "zh-TW": "下個月" },
  // **英語だけ空なのはわざと。** カレンダーの読み上げに付ける単位で、
  // 日本語と中文は「25日」、英語は「25」と数字だけで言う。
  // 空でないことを見る門（`i18n.test.ts`）に、ここだけ名指しで許してある。
  "dex.dayLabel": { ja: "{n}日", en: "Day {n}", "zh-TW": "{n}日" },
  "dex.allDays": { ja: "すべての日", en: "All days", "zh-TW": "所有日期" },
  "rv.whichIsBefore": { ja: "「", en: "Which one means “", "zh-TW": "「" },
  "rv.whichIsAfter": { ja: "」はどれ？", en: "”?", "zh-TW": "」是哪一個？" },
  /**
   * 読む人の言語の意味がまだ無い語の問い（オーナー報告 2026-10-02、絵つき
   * 「Which one means “グラタンマカロニ”?」）。別の言語の意味を「」に入れるより、
   * 写真で問う方が問題として成り立つ。意味は裏で作り、届けば上の形に戻る。
   */
  "rv.whichIsThis": { ja: "これはどれ？", en: "Which one is this?", "zh-TW": "這是哪一個？" },
  /**
   * 品詞の名前（チャンクの凡例と色の札）。**表示言語で出す**（オーナー報告 2026-10-02
   * 「英語の表示でも 名詞 / 動詞 / 状態動詞(形容詞) が日本語のまま」）。
   * 日本語は `pos.ts` の前の文言と1字も変えない。
   */
  "pos.g.n": { ja: "名詞", en: "Noun", "zh-TW": "名詞" },
  "pos.g.v": { ja: "動詞", en: "Verb", "zh-TW": "動詞" },
  "pos.g.vs": {
    ja: "状態動詞（形容詞）",
    en: "Stative verb (adj.)",
    "zh-TW": "狀態動詞（形容詞）",
  },
  "pos.g.vaux": { ja: "助動詞", en: "Auxiliary", "zh-TW": "助動詞" },
  "pos.g.adv": { ja: "副詞", en: "Adverb", "zh-TW": "副詞" },
  "pos.g.m": { ja: "量詞", en: "Measure word", "zh-TW": "量詞" },
  "pos.g.conj": { ja: "接続詞", en: "Conjunction", "zh-TW": "連接詞" },
  "pos.g.prep": { ja: "介詞", en: "Preposition", "zh-TW": "介詞" },
  "pos.g.ptc": { ja: "助詞", en: "Particle", "zh-TW": "助詞" },
  "pos.g.det": { ja: "限定詞", en: "Determiner", "zh-TW": "限定詞" },
  // 詞類表の記号ごとの名前（単語の詳細の品詞の札「Vs · 状態動詞(形容詞)」）。
  "pos.c.N": { ja: "名詞", en: "Noun", "zh-TW": "名詞" },
  "pos.c.V": { ja: "動詞（及物）", en: "Verb (transitive)", "zh-TW": "動詞（及物）" },
  "pos.c.Vi": { ja: "動詞（不及物）", en: "Verb (intransitive)", "zh-TW": "動詞（不及物）" },
  "pos.c.V-sep": { ja: "離合詞", en: "Separable verb", "zh-TW": "離合詞" },
  "pos.c.Vs": {
    ja: "状態動詞（形容詞）",
    en: "Stative verb (adj.)",
    "zh-TW": "狀態動詞（形容詞）",
  },
  "pos.c.Vst": {
    ja: "状態動詞（及物）",
    en: "Stative verb (transitive)",
    "zh-TW": "狀態動詞（及物）",
  },
  "pos.c.Vs-attr": {
    ja: "状態動詞（限定用法のみ）",
    en: "Stative verb (attributive only)",
    "zh-TW": "狀態動詞（只作定語）",
  },
  "pos.c.Vs-pred": {
    ja: "状態動詞（述語用法のみ）",
    en: "Stative verb (predicative only)",
    "zh-TW": "狀態動詞（只作謂語）",
  },
  "pos.c.Vs-sep": { ja: "状態離合詞", en: "Separable stative verb", "zh-TW": "狀態離合詞" },
  "pos.c.Vaux": { ja: "助動詞", en: "Auxiliary", "zh-TW": "助動詞" },
  "pos.c.Vp": { ja: "変化動詞", en: "Process verb", "zh-TW": "變化動詞" },
  "pos.c.Vpt": {
    ja: "変化動詞（及物）",
    en: "Process verb (transitive)",
    "zh-TW": "變化動詞（及物）",
  },
  "pos.c.Vp-sep": { ja: "変化離合詞", en: "Separable process verb", "zh-TW": "變化離合詞" },
  "pos.c.Adv": { ja: "副詞", en: "Adverb", "zh-TW": "副詞" },
  "pos.c.Conj": { ja: "接続詞", en: "Conjunction", "zh-TW": "連接詞" },
  "pos.c.Prep": { ja: "介詞（前置詞）", en: "Preposition", "zh-TW": "介詞" },
  "pos.c.M": { ja: "量詞", en: "Measure word", "zh-TW": "量詞" },
  "pos.c.Ptc": { ja: "助詞", en: "Particle", "zh-TW": "助詞" },
  "pos.c.Det": { ja: "限定詞", en: "Determiner", "zh-TW": "限定詞" },
  "rv.pronOf": { ja: "{c}の発音", en: "Pronunciation of {c}", "zh-TW": "{c}的發音" },
  /**
   * 並べ替えの取っ手。**▲▼ を1つにまとめた**(オーナー報告 2026-08-26、
   * 3度目「並び替えの欄が前よりも大きくなって見づらい」)。長押しで掴む道と、
   * 焦点を当てて ↑↓ で動かす道の両方がこのボタンに乗っている。
   */
  "card.reorder": { ja: "並べ替え", en: "Reorder", "zh-TW": "調整順序" },
  "card.toggleShow": { ja: "表示切替", en: "Show / hide", "zh-TW": "切換顯示" },
  "card.playPron": { ja: "発音を再生", en: "Play pronunciation", "zh-TW": "播放發音" },
  "card.pronZhuyin": { ja: "発音・注音", en: "Pronunciation & Zhuyin", "zh-TW": "發音、注音" },
  "card.posLabel": { ja: "品詞", en: "Part of speech", "zh-TW": "詞性" },
  "card.reportError": {
    ja: "この語の誤りを報告",
    en: "Report an error in this entry",
    "zh-TW": "回報這個字的錯誤",
  },
  "card.freqAria": { ja: "頻度 {n}/5", en: "Frequency {n}/5", "zh-TW": "頻率 {n}/5" },
  "card.pronOfWord": {
    ja: "「{word}」の発音",
    en: 'Pronunciation of "{word}"',
    "zh-TW": "「{word}」的發音",
  },
  "card.ytLabel": { ja: "YouTubeで聞く", en: "Hear it on YouTube", "zh-TW": "在 YouTube 上聽" },
  "card.ytHint": {
    ja: "台湾の動画をまとめて（複数見られます）",
    en: "Videos from Taiwan — a whole list of them",
    "zh-TW": "彙整台灣的影片（可以看好幾支）",
  },
  "card.yglLabel": {
    ja: "YouGlishで発音例",
    en: "Pronunciation samples on YouGlish",
    "zh-TW": "在 YouGlish 聽發音範例",
  },
  "card.yglHint": {
    ja: "1本ずつ。矢印で次の話者へ",
    en: "One clip at a time — arrows move to the next speaker",
    "zh-TW": "一支一支看，用箭頭換下一位說話者",
  },
  "card.dcardLabel": { ja: "Dcardで見る", en: "See it on Dcard", "zh-TW": "在 Dcard 上看" },
  "card.dcardHint": {
    ja: "台湾の若者のSNSでの使われ方",
    en: "How young people in Taiwan use it on social media",
    "zh-TW": "台灣年輕人在社群上怎麼用",
  },
  "card.newsLabel": {
    ja: "台湾のサイトで検索",
    en: "Search Taiwanese sites",
    "zh-TW": "在台灣的網站搜尋",
  },
  "card.newsHint": {
    ja: "台湾の記事だけに絞った検索結果",
    en: "Results limited to pages from Taiwan",
    "zh-TW": "只限台灣文章的搜尋結果",
  },
  "card.threadsLabel": {
    ja: "Threads で見る",
    en: "See it on Threads",
    "zh-TW": "在 Threads 上看",
  },
  "card.threadsHint": {
    ja: "台湾の人がいま書いている短い文",
    en: "Short posts people in Taiwan are writing now",
    "zh-TW": "台灣人現在正在寫的短句",
  },
  "card.moeLabel": {
    ja: "教育部國語辭典簡編本",
    en: "MOE Concised Mandarin Dictionary",
    "zh-TW": "教育部國語辭典簡編本",
  },
  "card.moeHint": {
    ja: "台湾教育部の公式辞書（定義・注音）",
    en: "Taiwan's official MOE dictionary (definitions, Zhuyin)",
    "zh-TW": "台灣教育部的官方辭典（釋義、注音）",
  },
  // --- 英語のカードの「実際の使われ方」(第4段) -----------------------------
  // **札の名前は使い回す**(YouTube / Threads / ニュース / 文の中)。
  // 一言だけ言語ごとに変える — 中身が変わるのはそこだけ。
  "card.ytHintEn": {
    ja: "英語圏の動画をまとめて（複数見られます）",
    en: "Videos from the English-speaking world — a whole list of them",
    "zh-TW": "彙整英語圈的影片（可以看好幾支）",
  },
  "card.yglHintEn": {
    ja: "アメリカ英語の話者で1本ずつ。矢印で次へ",
    en: "One American-English speaker at a time — arrows move to the next",
    "zh-TW": "一次一位美式英語的說話者，用箭頭換下一位",
  },
  "card.redditLabel": { ja: "Redditで見る", en: "See it on Reddit", "zh-TW": "在 Reddit 上看" },
  "card.redditHint": {
    ja: "普通の人が書いた文での使われ方",
    en: "How ordinary people actually write it",
    "zh-TW": "一般人實際上怎麼寫",
  },
  // Instagram(オーナー指示 2026-08-26「Threads ではなく Instagram に」)。
  "card.igLabel": {
    ja: "Instagram で見る",
    en: "See it on Instagram",
    "zh-TW": "在 Instagram 上看",
  },
  "card.igHint": {
    ja: "英語圏の人がその語に付けている投稿",
    en: "Posts English speakers tag with it",
    "zh-TW": "英語圈的人用這個字標記的貼文",
  },
  // **札の名前も替える。** 一言だけ替えて名前を使い回したら、英語の
  // カードに「在台灣的網站搜尋（台湾のサイトで検索）」と出た(絵で見つけた)。
  "card.newsLabelEn": {
    ja: "英語のサイトで検索",
    en: "Search English-language sites",
    "zh-TW": "在英語網站搜尋",
  },
  "card.newsHintEn": {
    ja: "英語のサイトだけに絞った検索結果",
    en: "Results limited to English-language pages",
    "zh-TW": "只限英語網站的搜尋結果",
  },
  "card.mwLabel": {
    ja: "Merriam-Webster",
    en: "Merriam-Webster",
    "zh-TW": "Merriam-Webster",
  },
  "card.mwHint": {
    ja: "アメリカ英語の標準的な辞書（定義・発音）",
    en: "The standard American English dictionary (definitions, pronunciation)",
    "zh-TW": "美式英語的標準辭典（釋義、發音）",
  },
  // --- 日本語のカードの「実際の使われ方」(2026-10-01) -----------------------
  // 日本語を学ぶのは英語か繁體中文で読む人。**名前に台湾・英語圏を入れない。**
  "card.ytHintJa": {
    ja: "日本の動画をまとめて（複数見られます）",
    en: "Videos from Japan — a whole list of them",
    "zh-TW": "彙整日本的影片（可以看好幾支）",
  },
  "card.yglHintJa": {
    ja: "日本語の話者で1本ずつ。矢印で次へ",
    en: "One Japanese speaker at a time — arrows move to the next",
    "zh-TW": "一次一位日語的說話者，用箭頭換下一位",
  },
  "card.xLabel": {
    ja: "X（Twitter）で見る",
    en: "See it on X (Twitter)",
    "zh-TW": "在 X（Twitter）上看",
  },
  "card.xHint": {
    ja: "日本の人がいま書いている短い文",
    en: "Short posts people in Japan are writing now",
    "zh-TW": "日本人現在正在寫的短句",
  },
  "card.chiebukuroLabel": {
    ja: "Yahoo!知恵袋で見る",
    en: "See it on Yahoo! Chiebukuro",
    "zh-TW": "在 Yahoo!知恵袋 上看",
  },
  "card.chiebukuroHint": {
    ja: "普通の人の質問と答え（使い分け・失礼にならないか）",
    en: "Everyday Q&A from people in Japan — nuance and politeness",
    "zh-TW": "日本一般人的問答（用法差別、會不會失禮）",
  },
  "card.newsLabelJa": {
    ja: "日本のサイトで検索",
    en: "Search Japanese sites",
    "zh-TW": "在日本的網站搜尋",
  },
  "card.newsHintJa": {
    ja: "日本の日本語の頁だけに絞った検索結果",
    en: "Results limited to Japanese-language pages from Japan",
    "zh-TW": "只限日本日文網頁的搜尋結果",
  },
  "card.weblioLabel": { ja: "Weblio辞書", en: "Weblio Dictionary", "zh-TW": "Weblio 辭典" },
  "card.weblioHint": {
    ja: "国語辞典・類語・用例をまとめて",
    en: "Japanese dictionaries, synonyms and usage examples in one place",
    "zh-TW": "國語辭典、近義詞、例句一次看",
  },
  "card.kotobankLabel": { ja: "コトバンク", en: "Kotobank", "zh-TW": "Kotobank" },
  "card.kotobankHint": {
    ja: "複数の辞書・事典を並べて読む",
    en: "Several Japanese dictionaries and encyclopedias side by side",
    "zh-TW": "多本日文辭典、百科並排查看",
  },
  "card.jishoLabel": { ja: "Jisho.org", en: "Jisho.org", "zh-TW": "Jisho.org" },
  "card.jishoHint": {
    ja: "学習者向け（英語の語釈・漢字の音訓）",
    en: "For learners — English definitions, kanji readings",
    "zh-TW": "給學習者（英文釋義、漢字音訓）",
  },
  // --- スキャン・カード詳細 ---
  "scan.cameraFailed": {
    ja: "カメラを起動できませんでした",
    en: "Couldn't start the camera",
    "zh-TW": "無法啟動相機",
  },
  "scan.cameraDenied": {
    ja: "カメラの使用が許可されていません。ブラウザの設定で許可するか、下の入力欄から言葉を調べられます。",
    en: "Camera access isn't allowed. Enable it in your browser settings, or look words up using the box below.",
    "zh-TW": "沒有取得相機權限。請到瀏覽器設定裡允許，或用下面的輸入欄查單字。",
  },
  "scan.cameraNotFound": {
    ja: "カメラが見つかりませんでした。下の入力欄から言葉を調べられます。",
    en: "No camera found. You can still look words up using the box below.",
    "zh-TW": "找不到相機。可以用下面的輸入欄查單字。",
  },
  "scan.cameraBusy": {
    ja: "カメラを他のアプリが使用中のようです。他のアプリを閉じて、もう一度お試しください。",
    en: "The camera seems to be in use by another app. Close it and try again.",
    "zh-TW": "相機似乎正被其他 App 使用。請關掉其他 App 再試一次。",
  },
  "scan.noVoice": {
    ja: "この端末は音声入力に対応していません。文字で入力してください。",
    en: "This device doesn't support voice input. Please type instead.",
    "zh-TW": "這個裝置不支援語音輸入，請用文字輸入。",
  },
  "scan.noFrame": {
    ja: "フレームを取得できませんでした",
    en: "Couldn't grab a frame",
    "zh-TW": "無法取得畫面",
  },
  "scan.detectFailed": { ja: "検出に失敗しました", en: "Detection failed", "zh-TW": "偵測失敗" },
  "scan.nothingFound": {
    ja: "文字が見つかりませんでした",
    en: "No words found",
    "zh-TW": "沒有找到文字",
  },
  "scan.nothingFoundHint": {
    ja: "看板やパッケージの中国語に近づけて、もう一度撮ってみてください。",
    en: "Get closer to some Chinese text (a sign or label) and scan again.",
    "zh-TW": "請靠近招牌或包裝上的中文，再拍一次看看。",
  },
  "scan.detectMs": { ja: "検出 {ms}ms", en: "detect {ms}ms", "zh-TW": "偵測 {ms}ms" },
  "scan.audioMs": { ja: "音声 {ms}ms", en: "audio {ms}ms", "zh-TW": "語音 {ms}ms" },
  "scan.whichOne": { ja: "どちらですか？", en: "Which one?", "zh-TW": "是哪一個呢？" },
  "scan.foundDaysAgoBefore": {
    ja: "✨ {n}日前に調べた「",
    en: "✨ You looked this up {n} {n|day|days} ago: ",
    "zh-TW": "✨ 這是 {n} 天前查過的「",
  },
  "scan.foundDaysAgoAfter": {
    ja: "」だ！撮って図鑑を完成させよう",
    en: " — shoot it to complete your Dex",
    "zh-TW": "」！拍下來把圖鑑補齊吧",
  },
  "scan.ownedTag": { ja: "取得済み", en: "Collected", "zh-TW": "已收集" },
  "scan.verified": { ja: "✓ 検証済み", en: "✓ Verified", "zh-TW": "✓ 已驗證" },
  "scan.aiUnverified": {
    ja: "AI生成・未検証",
    en: "AI generated · unverified",
    "zh-TW": "AI 生成、未驗證",
  },
  "scan.playPron": { ja: "発音を再生", en: "Play pronunciation", "zh-TW": "播放發音" },
  "card.title": { ja: "カード", en: "Card", "zh-TW": "字卡" },
  "card.backToDex": { ja: "図鑑へ戻る", en: "Back to Dex", "zh-TW": "回到圖鑑" },
  "card.notFound": {
    ja: "カードが見つかりませんでした。",
    en: "Card not found.",
    "zh-TW": "找不到這張字卡。",
  },
  "card.notFoundHint": {
    ja: "削除されたか、リンクが古いのかもしれません。",
    en: "It may have been deleted, or the link is out of date.",
    "zh-TW": "可能已經被刪除，或是連結太舊了。",
  },
  "card.flipSelfie": { ja: "自撮りを見る", en: "See the selfie", "zh-TW": "看自拍" },
  "card.tapForSelfie": {
    ja: "タップで自撮りへ",
    en: "Tap for the selfie",
    "zh-TW": "點一下看自拍",
  },
  "card.seeAll": {
    ja: "すべての解説を見る",
    en: "See the full explanation",
    "zh-TW": "看全部的說明",
  },
  "card.memoryCurve": {
    ja: "この単語の記憶曲線",
    en: "This word's memory curve",
    "zh-TW": "這個單字的記憶曲線",
  },
  "card.nextDue": { ja: "次回 {date}", en: "next {date}", "zh-TW": "下次 {date}" },
  // --- 図鑑 ---
  // --- 品詞グループ ---
  "pos.noun": { ja: "📛 名詞", en: "📛 Nouns", "zh-TW": "📛 名詞" },
  "pos.verb": { ja: "🏃 動詞", en: "🏃 Verbs", "zh-TW": "🏃 動詞" },
  "pos.adj": { ja: "🎨 形容詞", en: "🎨 Adjectives", "zh-TW": "🎨 形容詞" },
  "pos.phrase": { ja: "💬 フレーズ", en: "💬 Phrases", "zh-TW": "💬 片語" },
  "pos.other": { ja: "✨ その他", en: "✨ Other", "zh-TW": "✨ 其他" },
  // --- 図鑑カテゴリー ---
  // 絵文字はここに書かない。CATEGORY_META(lib/category.ts)が持つ —
  // ラベル文字列に混ぜてしまうと、絵文字だけ大きく出すといった扱いができない。
  "cat.fruit": { ja: "果物", en: "Fruit", "zh-TW": "水果" },
  "cat.vegetable": { ja: "野菜", en: "Vegetables", "zh-TW": "蔬菜" },
  "cat.drink": { ja: "飲み物", en: "Drinks", "zh-TW": "飲料" },
  "cat.food": { ja: "食べ物", en: "Food", "zh-TW": "食物" },
  "cat.dessert": { ja: "スイーツ", en: "Desserts", "zh-TW": "甜點" },
  "cat.vehicle": { ja: "乗り物", en: "Vehicles", "zh-TW": "交通工具" },
  "cat.transport": { ja: "交通", en: "Transport", "zh-TW": "交通" },
  "cat.animal": { ja: "動物", en: "Animals", "zh-TW": "動物" },
  "cat.plant": { ja: "植物", en: "Plants", "zh-TW": "植物" },
  "cat.flower": { ja: "花", en: "Flowers", "zh-TW": "花" },
  "cat.building": { ja: "建物", en: "Buildings", "zh-TW": "建築" },
  "cat.street": { ja: "街並み", en: "Streets", "zh-TW": "街景" },
  "cat.sign": { ja: "看板", en: "Signs", "zh-TW": "招牌" },
  "cat.shop": { ja: "お店", en: "Shops", "zh-TW": "店家" },
  "cat.home": { ja: "家", en: "Home", "zh-TW": "家" },
  "cat.furniture": { ja: "家具", en: "Furniture", "zh-TW": "家具" },
  "cat.appliance": { ja: "家電", en: "Appliances", "zh-TW": "家電" },
  "cat.kitchenware": { ja: "調理器具", en: "Kitchenware", "zh-TW": "廚具" },
  "cat.tool": { ja: "道具", en: "Tools", "zh-TW": "工具" },
  "cat.clothes": { ja: "服", en: "Clothes", "zh-TW": "衣服" },
  "cat.accessory": { ja: "アクセ", en: "Accessories", "zh-TW": "配件" },
  "cat.shoes": { ja: "靴", en: "Shoes", "zh-TW": "鞋子" },
  "cat.bag": { ja: "バッグ", en: "Bags", "zh-TW": "包包" },
  "cat.jewelry": { ja: "ジュエリー", en: "Jewelry", "zh-TW": "珠寶" },
  "cat.stationery": { ja: "文房具", en: "Stationery", "zh-TW": "文具" },
  "cat.book": { ja: "本", en: "Books", "zh-TW": "書" },
  "cat.tech": { ja: "テック", en: "Tech", "zh-TW": "科技" },
  "cat.gadget": { ja: "ガジェット", en: "Gadgets", "zh-TW": "3C 小物" },
  "cat.toy": { ja: "おもちゃ", en: "Toys", "zh-TW": "玩具" },
  "cat.game": { ja: "ゲーム", en: "Games", "zh-TW": "遊戲" },
  "cat.sport": { ja: "スポーツ", en: "Sports", "zh-TW": "運動" },
  "cat.instrument": { ja: "楽器", en: "Instruments", "zh-TW": "樂器" },
  "cat.nature": { ja: "自然", en: "Nature", "zh-TW": "自然" },
  "cat.weather": { ja: "天気", en: "Weather", "zh-TW": "天氣" },
  "cat.sky": { ja: "空", en: "Sky", "zh-TW": "天空" },
  "cat.water": { ja: "水", en: "Water", "zh-TW": "水" },
  "cat.mountain": { ja: "山", en: "Mountains", "zh-TW": "山" },
  "cat.body": { ja: "体の部位", en: "Body parts", "zh-TW": "身體部位" },
  "cat.face": { ja: "顔", en: "Face", "zh-TW": "臉" },
  "cat.hand": { ja: "手", en: "Hands", "zh-TW": "手" },
  "cat.clothing_part": { ja: "服の部分", en: "Clothing parts", "zh-TW": "衣服的部分" },
  "cat.person": { ja: "人", en: "People", "zh-TW": "人" },
  "cat.family": { ja: "家族", en: "Family", "zh-TW": "家人" },
  "cat.job": { ja: "仕事", en: "Work", "zh-TW": "工作" },
  "cat.art": { ja: "アート", en: "Art", "zh-TW": "藝術" },
  "cat.decoration": { ja: "装飾", en: "Decoration", "zh-TW": "裝飾" },
  "cat.character": { ja: "文字", en: "Characters", "zh-TW": "文字" },
  "cat.symbol": { ja: "記号", en: "Symbols", "zh-TW": "符號" },
  "cat.color": { ja: "色", en: "Colors", "zh-TW": "顏色" },
  "cat.shape": { ja: "形", en: "Shapes", "zh-TW": "形狀" },
  "cat.money": { ja: "お金", en: "Money", "zh-TW": "金錢" },
  "cat.document": { ja: "書類", en: "Documents", "zh-TW": "文件" },
  "cat.medicine": { ja: "薬", en: "Medicine", "zh-TW": "藥" },
  "cat.other": { ja: "その他", en: "Other", "zh-TW": "其他" },
  // --- 読み込み失敗(空とは別の状態として扱う) ---
  "err.loadTitle": { ja: "読み込めませんでした", en: "Couldn't load", "zh-TW": "無法載入" },
  "err.loadHint": {
    ja: "通信が不安定かもしれません。もう一度お試しください。",
    en: "The connection may be unstable. Please try again.",
    "zh-TW": "網路可能不太穩定，請再試一次。",
  },
  "err.offlineTitle": { ja: "オフラインです", en: "You're offline", "zh-TW": "目前離線" },
  "err.offlineHint": {
    ja: "電波が戻ったら、もう一度お試しください。",
    en: "Try again once you're back online.",
    "zh-TW": "等網路恢復後再試一次。",
  },
  // 「何を」読み込めなかったかの名前。画面ごとに1つ。
  "err.whatWordCard": { ja: "この単語のカード", en: "this word's card", "zh-TW": "這個單字的字卡" },
  "err.whatHome": { ja: "今日のページ", en: "today's page", "zh-TW": "今天的頁面" },
  "err.whatDex": { ja: "図鑑", en: "your Dex", "zh-TW": "圖鑑" },
  "err.whatSettings": { ja: "設定", en: "your settings", "zh-TW": "設定" },
  "err.whatReview": { ja: "今日の復習", en: "today's review", "zh-TW": "今天的複習" },
  "err.retrying": { ja: "再試行中…", en: "Retrying…", "zh-TW": "重試中…" },
  "err.retryingTitle": {
    ja: "もう一度読み込んでいます",
    en: "Trying again",
    "zh-TW": "正在重新載入",
  },
  "err.retryingHint": {
    ja: "少しお待ちください。",
    en: "This should only take a moment.",
    "zh-TW": "請稍等一下。",
  },
  "err.loadTitleOf": {
    ja: "{what}を読み込めませんでした",
    en: "Couldn't load {what}",
    "zh-TW": "無法載入{what}",
  },
  "err.retry": { ja: "もう一度", en: "Try again", "zh-TW": "再試一次" },
  "dex.shelf": { ja: "棚", en: "Shelf", "zh-TW": "書架" },
  "dex.shelfCount": { ja: "{n}", en: "{n}", "zh-TW": "{n}" },
  // --- 図鑑の部屋(棚のまとまり) ---
  "room.eat": { ja: "食べる", en: "Eat", "zh-TW": "吃" },
  "room.town": { ja: "街", en: "Town", "zh-TW": "街" },
  "room.house": { ja: "家", en: "Home", "zh-TW": "家" },
  "room.wear": { ja: "身につける", en: "Wear", "zh-TW": "穿戴" },
  "room.play": { ja: "学び・遊び", en: "Learn & play", "zh-TW": "學習、玩樂" },
  "room.nature": { ja: "自然", en: "Nature", "zh-TW": "自然" },
  "room.people": { ja: "人・体", en: "People", "zh-TW": "人、身體" },
  "room.marks": { ja: "しるし", en: "Marks", "zh-TW": "標記" },
  // --- 集める・キャッチ・設定 ---
  "cap.pendingNotFound": {
    ja: "保存されていた写真が見つかりませんでした",
    en: "Couldn't find the saved photo",
    "zh-TW": "找不到之前存下的照片",
  },
  "cap.photoReadFailed": {
    ja: "写真を読み込めませんでした。もう一度撮ってみてください。",
    en: "Couldn't read that photo. Please try taking it again.",
    "zh-TW": "無法讀取照片，請再拍一次看看。",
  },
  "cap.aiFailed": {
    ja: "AI処理に失敗しました",
    en: "AI processing failed",
    "zh-TW": "AI 處理失敗",
  },
  "cap.aiFailedRetry": {
    ja: "AI処理に失敗しました。もう一度お試しください。",
    en: "AI processing failed. Please try again.",
    "zh-TW": "AI 處理失敗，請再試一次。",
  },
  "cap.cardFailed": {
    ja: "カード生成に失敗しました",
    en: "Couldn't build the card",
    "zh-TW": "字卡產生失敗",
  },
  "cap.savedButLandingFailed": {
    ja: "図鑑には追加できました（演出の途中で問題が起きました）。",
    en: "It's in your Dex — something went wrong during the animation.",
    "zh-TW": "已經加進圖鑑了（動畫途中出了點狀況）。",
  },
  "cap.saveFailed": { ja: "保存に失敗しました", en: "Couldn't save", "zh-TW": "儲存失敗" },
  /**
   * 保存の関所が、学習言語の字でない見出し語を止めたとき（オーナー報告
   * 2026-10-02「英語の図鑑にノート」）。**何が起きたか**と**次に何をするか**を言う。
   */
  "err.notTargetLanguage": {
    ja: "学習している言語の単語ではないため、図鑑に入れられませんでした。別の候補を選んでください。",
    en: "This isn't a word in the language you're learning, so it wasn't added. Pick another word.",
    "zh-TW": "這不是你正在學的語言的單字，所以沒有加入圖鑑。請選擇其他單字。",
  },
  "cap.recordFailed": { ja: "記録に失敗しました", en: "Couldn't record that", "zh-TW": "紀錄失敗" },
  "cap.photoTaken": { ja: "撮った写真", en: "The photo you took", "zh-TW": "拍下的照片" },
  // 撮った後の候補（2段、オーナー指示 2026-09-27）。
  "cap.otherObjects": { ja: "ほかに写っている物", en: "Also in the photo", "zh-TW": "照片裡還有" },
  "cap.pickThis": { ja: "この語で図鑑に入れる", en: "Add this word", "zh-TW": "用這個詞加入圖鑑" },
  "cap.otherNames": { ja: "ほかの言い方", en: "Other ways to say it", "zh-TW": "其他說法" },
  "cap.otherNamesN": {
    ja: "ほかの言い方 {n}",
    en: "{n} other {n|name|names}",
    "zh-TW": "其他說法 {n}",
  },
  // 候補の印（オーナーの呼び名 2026-10-15、`candidate-register.ts` の NAME_REGISTER_LABELS と同じ言葉）。
  "cap.regSpecific": { ja: "より詳しい言い方", en: "More specific", "zh-TW": "更具體的說法" },
  "cap.regProper": { ja: "固有名詞", en: "Proper noun", "zh-TW": "專有名詞" },
  "cap.regCasual": { ja: "口語", en: "Colloquial", "zh-TW": "口語" },
  "cap.regAcademic": { ja: "学術的な言い方", en: "Academic / technical", "zh-TW": "學術說法" },
  "cap.inPhoto": { ja: "写っている物", en: "In the photo", "zh-TW": "照片裡的東西" },
  "cap.selfie": { ja: "自撮り", en: "Selfie", "zh-TW": "自拍" },
  "cap.wordPlaceholder": { ja: "例: 椅子", en: "e.g. 椅子", "zh-TW": "例：椅子" },
  "cap.reencBefore": { ja: "この言葉、", en: "You caught this word ", "zh-TW": "這個字，你在" },
  // **{date} が日本語から丸ごと抜けていた。** 「この言葉、にゲットしています。」
  // と、いつ撮ったのかが消えた文が出ていた(オーナーのスクリーンショット)。
  // 差し込み語の抜けは翻訳ファイルの中では目で気づけない。
  "cap.reencAt": {
    ja: "{date}に{place}で",
    en: "at {place} on {date}",
    "zh-TW": "{date} 於 {place}",
  },
  "cap.reencOn": { ja: "{date}に", en: "on {date}", "zh-TW": "{date}" },
  "cap.reencAfter": { ja: "ゲットしています。", en: ".", "zh-TW": "收集過了。" },
  "cap.reunionNth": { ja: "再会{n}回目", en: "Reunion #{n}", "zh-TW": "第 {n} 次重逢" },
  "photos.title": {
    ja: "この言葉に出会った記録",
    en: "Times you met this word",
    "zh-TW": "遇到這個字的紀錄",
  },
  "photos.count": { ja: "{n}枚", en: "{n} {n|photo|photos}", "zh-TW": "{n} 張" },
  // 図鑑の20のカテゴリー（iOS `DexCatalog.label` と同じ名前。`lib/dex-catalog.ts`）。
  "dexcat.1": { ja: "飲み物", en: "Drinks", "zh-TW": "飲料" },
  "dexcat.2": { ja: "料理・屋台", en: "Dishes & Street Food", "zh-TW": "料理、小吃" },
  "dexcat.3": { ja: "果物・野菜", en: "Fruit & Vegetables", "zh-TW": "水果、蔬菜" },
  "dexcat.4": { ja: "お菓子・パン", en: "Sweets & Bread", "zh-TW": "點心、麵包" },
  "dexcat.5": { ja: "食器・台所", en: "Tableware & Kitchen", "zh-TW": "餐具、廚房" },
  "dexcat.6": { ja: "家具・インテリア", en: "Furniture & Interior", "zh-TW": "家具、室內擺設" },
  "dexcat.7": { ja: "家電", en: "Appliances", "zh-TW": "家電" },
  "dexcat.8": { ja: "スマホ・パソコン", en: "Phones & Computers", "zh-TW": "手機、電腦" },
  "dexcat.9": { ja: "文房具・本", en: "Stationery & Books", "zh-TW": "文具、書" },
  "dexcat.10": { ja: "洗面・日用品", en: "Toiletries & Daily Goods", "zh-TW": "盥洗、日用品" },
  "dexcat.11": { ja: "服", en: "Clothes", "zh-TW": "衣服" },
  "dexcat.12": {
    ja: "靴・バッグ・小物",
    en: "Shoes, Bags & Accessories",
    "zh-TW": "鞋子、包包、配件",
  },
  "dexcat.13": { ja: "乗り物", en: "Vehicles", "zh-TW": "交通工具" },
  "dexcat.14": { ja: "建物・お店", en: "Buildings & Shops", "zh-TW": "建築、商店" },
  "dexcat.15": { ja: "道・街の物", en: "Streets & Street Things", "zh-TW": "道路、街上的東西" },
  "dexcat.16": { ja: "動物", en: "Animals", "zh-TW": "動物" },
  "dexcat.17": { ja: "植物・花", en: "Plants & Flowers", "zh-TW": "植物、花" },
  "dexcat.18": { ja: "空・自然", en: "Sky & Nature", "zh-TW": "天空、大自然" },
  "dexcat.19": { ja: "スポーツ・遊び", en: "Sports & Play", "zh-TW": "運動、遊戲" },
  "dexcat.20": { ja: "人・体", en: "People", "zh-TW": "人、身體" },
  // 図鑑のまだ捕まえていない物の影（読み上げ。iOS「まだ見つけていない言葉 {1}」）。
  "dex.shadowAria": {
    ja: "まだ見つけていない言葉 {word}",
    en: "Not found yet: {word}",
    "zh-TW": "還沒找到的詞：{word}",
  },
  // 同じ言葉に出会った回数（図鑑のマスの「×3」の読み上げ）。
  "dex.captureCount": {
    ja: "{n}回出会った",
    en: "Met {n} {n|time|times}",
    "zh-TW": "遇到 {n} 次",
  },
  "photos.first": { ja: "はじめて", en: "First", "zh-TW": "第一次" },
  "photos.alt": {
    ja: "{n}回目に撮った写真",
    en: "Photo from meeting {n}",
    "zh-TW": "第 {n} 次拍的照片",
  },
  "cap.reunionSaving": {
    ja: "この1枚を図鑑に足しています…",
    en: "Adding this photo to your Dex…",
    "zh-TW": "正在把這張加進圖鑑…",
  },
  "cap.photoAdded": {
    ja: "この写真を単語に追加しました",
    en: "Photo added to this word",
    "zh-TW": "已把這張照片加到這個字",
  },
  "cap.nextReview": {
    ja: " · 次の復習: {date}",
    en: " · next review: {date}",
    "zh-TW": " · 下次複習：{date}",
  },
  "sheet.catch": { ja: "キャッチ", en: "Catch", "zh-TW": "捕捉" },
  "sheet.file": { ja: "図鑑へ収める", en: "Add to Dex", "zh-TW": "收進圖鑑" },
  "sheet.landed": { ja: "図鑑に着地！", en: "Landed in your Dex!", "zh-TW": "降落在圖鑑了！" },
  "sheet.noWordInfo": {
    ja: "単語情報を取得できませんでした",
    en: "Couldn't get the word details",
    "zh-TW": "無法取得單字資訊",
  },
  "sheet.firstCatch": {
    ja: "はじめてのキャッチ！明日、この単語を覚えてるか聞くね",
    en: "Your first catch! Tomorrow I'll ask if you still remember it",
    "zh-TW": "第一次捕捉！明天會問你還記不記得這個字",
  },
  "sheet.reunion": {
    ja: "再会！自分の写真になりました✨",
    en: "Reunion! Now it's your own photo ✨",
    "zh-TW": "重逢！變成你自己的照片了 ✨",
  },
  "sheet.addedOne": {
    ja: "図鑑に1体増えました！",
    en: "One more in your Dex!",
    "zh-TW": "圖鑑多了一隻！",
  },
  "sheet.cardAdded": {
    ja: "図鑑にカードが入りました！",
    en: "Card added to your Dex!",
    "zh-TW": "字卡進到圖鑑了！",
  },
  "sheet.addedGhostFree": {
    ja: "図鑑に入りました。実物に出会ったら金色に光ります！",
    en: "Added to your Dex. It turns gold when you meet the real thing!",
    "zh-TW": "已經收進圖鑑。遇到實物時就會發出金色的光！",
  },
  "sheet.loading": { ja: "読み込み中…", en: "Loading…", "zh-TW": "載入中…" },
  "sheet.reunionNotRecorded": {
    ja: "キャッチはできましたが、復習の記録に失敗しました。この語はまた出てきます。",
    en: "Caught it, but the review record didn't save — this word will come round again.",
    "zh-TW": "捕捉成功了，但複習紀錄沒有存到。這個字之後還會再出現。",
  },
  "sheet.verified": { ja: "✓ 検証済み", en: "✓ Verified", "zh-TW": "✓ 已驗證" },
  "sheet.aiMade": { ja: "AI生成", en: "AI generated", "zh-TW": "AI 生成" },
  "sheet.optional": { ja: "（任意）", en: "(optional)", "zh-TW": "（選填）" },
  "sheet.noteLabel": { ja: "一言感想", en: "A quick note", "zh-TW": "一句話感想" },
  "sheet.notePlaceholder": {
    ja: "どこで見つけた？どんな気持ち？",
    en: "Where did you find it? How did it feel?",
    "zh-TW": "在哪裡發現的？當下什麼心情？",
  },
  "sheet.selfieLabel": { ja: "一緒に自撮り", en: "Selfie with it", "zh-TW": "一起自拍" },
  "sheet.retakeSelfie": { ja: "撮り直す", en: "Retake", "zh-TW": "重拍" },
  "sheet.addSelfie": { ja: "自撮りを追加", en: "Add a selfie", "zh-TW": "加上自拍" },
  "sheet.stopRepeat": { ja: "停止", en: "Stop", "zh-TW": "停止" },
  "sheet.repeat": {
    ja: "聞こえたまま復唱する",
    en: "Repeat what you heard",
    "zh-TW": "跟著唸一次",
  },
  "sheet.inputPlaceholder": {
    ja: "例: 芒果 / 請稍等",
    en: "e.g. 芒果 / 請稍等",
    "zh-TW": "例：芒果 / 請稍等",
  },
  "sheet.attached": { ja: "添付画像", en: "Attached image", "zh-TW": "附加的圖片" },
  "sheet.webImage": { ja: "ネット検索の画像", en: "Image from the web", "zh-TW": "網路搜尋的圖片" },
  "sheet.candidateN": { ja: "候補{n}", en: "Candidate {n}", "zh-TW": "候選 {n}" },
  "sheet.scene": { ja: "シーン: {s}", en: "Scene: {s}", "zh-TW": "場景：{s}" },
  "set.targetLangAria": { ja: "学習言語", en: "Target language", "zh-TW": "學習語言" },
  "set.levelGoalAria": { ja: "目標レベル", en: "Target level", "zh-TW": "目標等級" },
  "set.nativeAria": { ja: "母語", en: "Native language", "zh-TW": "母語" },
  "set.uiLangAria": { ja: "表示言語", en: "App language", "zh-TW": "顯示語言" },
  "set.deleteWord": { ja: "削除", en: "DELETE", "zh-TW": "刪除" },
  "set.qualitySamples": {
    ja: "直近{n}回のスキャンから算出（仕様§9の合格ライン）",
    en: "Computed from your last {n} {n|scan|scans} (spec §9 pass line)",
    "zh-TW": "由最近 {n} 次掃描計算（規格 §9 的合格標準）",
  },
  "set.placeLabel": { ja: "場所でリマインド", en: "Location reminders", "zh-TW": "地點提醒" },
  "set.placeDesc": {
    ja: "単語を撮った場所の近くに来ると、その単語を通知で思い出させます",
    en: "When you're back near where you caught a word, you'll get a reminder of it.",
    "zh-TW": "回到拍下單字的地方附近時，會用通知提醒你那個單字。",
  },
  "set.placeChecking": {
    ja: "許可を確認しています…",
    en: "Checking permission…",
    "zh-TW": "正在確認權限…",
  },
  "set.placeUnsupported": {
    ja: "このブラウザでは通知を使えません。iPhone の場合は Safari の共有ボタンから「ホーム画面に追加」して、そのアイコンから開くとオンにできます。",
    en: "This browser can't use notifications. On iPhone, add the app to your Home Screen from Safari's share menu and open it from that icon.",
    "zh-TW":
      "這個瀏覽器不能使用通知。如果是 iPhone，請從 Safari 的分享按鈕選「加入主畫面」，再從那個圖示打開就能開啟。",
  },
  "set.placeDenied": {
    ja: "通知が拒否されています。端末の設定 → 通知 からこのアプリの通知を許可すると、ここでオンにできます。",
    en: "Notifications are blocked. Allow them for this app in your device settings, then turn this on again.",
    "zh-TW": "通知被拒絕了。到裝置的設定 → 通知，允許這個 App 的通知之後，就能在這裡開啟。",
  },
  "set.placeDismissed": {
    ja: "許可のダイアログが閉じられました。もう一度タップすると出ます。",
    en: "The permission dialog was dismissed. Tap again to show it.",
    "zh-TW": "權限對話框被關掉了。再點一次就會出現。",
  },
  "set.placeError": {
    ja: "通知の許可を確認できませんでした。時間をおいてもう一度お試しください。",
    en: "Couldn't check notification permission. Please try again later.",
    "zh-TW": "無法確認通知權限，請過一會兒再試一次。",
  },
  // --- ログイン・発音練習 ---
  // 迎える面の言葉（オーナー指示 2026-09-17）。
  // > 「好きなものから言葉をのキャッチコピーを、日常があなただけの単語帳に。
  // >  変更して。撮って、集めて、覚えようはそのままでいい」
  "auth.heroA": { ja: "日常が", en: "Your days,", "zh-TW": "日常，" },
  "auth.heroB": {
    ja: "あなただけの単語帳に。",
    en: "your own vocabulary book.",
    "zh-TW": "成為你專屬的單字本。",
  },
  "auth.tagline": {
    ja: "撮って、集めて、覚えよう。",
    en: "Snap it, collect it, learn it.",
    "zh-TW": "拍下來、收集起來、記住它。",
  },
  "auth.emailLogin": {
    ja: "メールでログイン",
    en: "Sign in with email",
    "zh-TW": "用電子郵件登入",
  },
  "auth.noAccount": {
    ja: "アカウントをお持ちでない方は",
    en: "No account yet? ",
    "zh-TW": "還沒有帳號？",
  },
  "auth.haveAccount": {
    ja: "すでにアカウントをお持ちの方は",
    en: "Already have an account? ",
    "zh-TW": "已經有帳號了？",
  },
  "auth.signin": { ja: "ログイン", en: "Sign in", "zh-TW": "登入" },
  "auth.signup": { ja: "新規登録", en: "Sign up", "zh-TW": "註冊" },
  "auth.email": { ja: "メールアドレス", en: "Email", "zh-TW": "電子郵件" },
  "auth.password": { ja: "パスワード", en: "Password", "zh-TW": "密碼" },
  "auth.or": { ja: "または", en: "or", "zh-TW": "或" },
  "auth.google": { ja: "Googleで続ける", en: "Continue with Google", "zh-TW": "用 Google 繼續" },
  "auth.apple": { ja: "Appleで続ける", en: "Continue with Apple", "zh-TW": "用 Apple 繼續" },
  "auth.terms": { ja: "利用規約", en: "Terms of Service", "zh-TW": "使用條款" },
  "auth.privacy": { ja: "プライバシーポリシー", en: "Privacy Policy", "zh-TW": "隱私權政策" },
  "auth.confirmSent": {
    ja: "確認メールを送りました。受信トレイをご確認ください。",
    en: "Confirmation email sent — please check your inbox.",
    "zh-TW": "已寄出確認信，請查看你的收件匣。",
  },
  "auth.failed": { ja: "サインインに失敗しました", en: "Sign-in failed", "zh-TW": "登入失敗" },
  "auth.googleFailed": {
    ja: "Googleサインインに失敗しました",
    en: "Google sign-in failed",
    "zh-TW": "Google 登入失敗",
  },
  "auth.appleFailed": {
    ja: "Appleサインインに失敗しました",
    en: "Apple sign-in failed",
    "zh-TW": "Apple 登入失敗",
  },
  "pron.title": { ja: "発音練習", en: "Pronunciation practice", "zh-TW": "發音練習" },
  "pron.noTts": {
    ja: "このブラウザは音声合成に対応していません",
    en: "This browser doesn't support speech synthesis",
    "zh-TW": "這個瀏覽器不支援語音合成",
  },
  "pron.noAsr": {
    ja: "このブラウザは音声認識に対応していません(iOS Safari / Chrome 推奨)",
    en: "This browser doesn't support speech recognition (try iOS Safari or Chrome)",
    "zh-TW": "這個瀏覽器不支援語音辨識（建議用 iOS Safari 或 Chrome）",
  },
  "pron.asrError": {
    ja: "認識エラー: {e}",
    en: "Recognition error: {e}",
    "zh-TW": "辨識錯誤：{e}",
  },
  "pron.playNatural": {
    ja: "自然な速度で再生",
    en: "Play at natural speed",
    "zh-TW": "以自然速度播放",
  },
  "pron.slow": { ja: "ゆっくり", en: "Slow", "zh-TW": "放慢" },
  "pron.stopRec": { ja: "録音停止", en: "Stop recording", "zh-TW": "停止錄音" },
  "pron.startRec": { ja: "発音を録音", en: "Record your pronunciation", "zh-TW": "錄下發音" },
  "pron.listeningBefore": { ja: "聞き取り中…「", en: "Listening… say “", "zh-TW": "聆聽中…請說「" },
  "pron.listeningAfter": { ja: "」と言ってみてください", en: "”", "zh-TW": "」" },
  "pron.yours": { ja: "あなたの発音", en: "Your pronunciation", "zh-TW": "你的發音" },
  "pron.pressBefore": {
    ja: "マイクを押して「",
    en: "Tap the mic and say “",
    "zh-TW": "按下麥克風，說「",
  },
  "pron.pressAfter": { ja: "」と言ってみてください", en: "”", "zh-TW": "」看看" },
  "pron.score": { ja: "スコア", en: "Score", "zh-TW": "分數" },
  // --- フィード・ホーム・プロフィール・オンボーディング・再設定・ルート ---
  "home.waitingPhoto": {
    ja: "解析待ちの写真",
    en: "Photo waiting to be analyzed",
    "zh-TW": "等待分析的照片",
  },
  "home.bgPaper": { ja: "紙", en: "Paper", "zh-TW": "紙" },
  "home.bgFrame": { ja: "額縁", en: "Picture frame", "zh-TW": "畫框" },
  "home.bgNotebook": { ja: "ノート", en: "Notebook", "zh-TW": "筆記本" },
  "home.bgCork": { ja: "コルクと画鋲", en: "Corkboard", "zh-TW": "軟木板與圖釘" },
  "home.bgWall": { ja: "壁", en: "Wall", "zh-TW": "牆面" },
  "err.failed": { ja: "失敗しました", en: "Something went wrong", "zh-TW": "失敗了" },
  // ログイン・新規登録・パスワード再設定の失敗（`errors.ts` の `authErrorText`）。
  "autherr.invalidCredentials": {
    ja: "メールアドレスかパスワードが違います",
    en: "The email or password is incorrect",
    "zh-TW": "電子郵件或密碼不正確",
  },
  "autherr.emailNotConfirmed": {
    ja: "メールアドレスの確認がまだです。届いたメールのリンクを開いてください",
    en: "Your email isn't confirmed yet. Open the link in the email we sent you",
    "zh-TW": "電子郵件尚未驗證，請開啟我們寄給你的信件中的連結",
  },
  "autherr.alreadyRegistered": {
    ja: "このメールアドレスはすでに登録されています。ログインしてください",
    en: "This email is already registered. Please sign in",
    "zh-TW": "這個電子郵件已經註冊過了，請直接登入",
  },
  "autherr.weakPassword": {
    ja: "パスワードが短すぎるか、推測されやすいです。別のパスワードにしてください",
    en: "That password is too short or too easy to guess. Please choose another one",
    "zh-TW": "密碼太短或太容易被猜到，請換一個密碼",
  },
  "autherr.samePassword": {
    ja: "今のパスワードと同じです。別のパスワードにしてください",
    en: "That's the same as your current password. Please choose a new one",
    "zh-TW": "和目前的密碼相同，請換一個新的密碼",
  },
  "autherr.rateLimit": {
    ja: "短い時間に何度も試されました。しばらくしてからもう一度お試しください",
    en: "Too many attempts. Please wait a moment and try again",
    "zh-TW": "嘗試次數太多，請稍等一下再試",
  },
  "autherr.emailInvalid": {
    ja: "メールアドレスの形が正しくありません",
    en: "That doesn't look like a valid email address",
    "zh-TW": "電子郵件格式不正確",
  },
  "autherr.signupDisabled": {
    ja: "いまは新規登録を受け付けていません",
    en: "Sign-ups are closed right now",
    "zh-TW": "目前暫停開放註冊",
  },
  "autherr.linkExpired": {
    ja: "リンクの期限が切れています。もう一度やり直してください",
    en: "This link has expired. Please start again",
    "zh-TW": "連結已過期，請重新操作",
  },
  "autherr.network": {
    ja: "通信できませんでした。電波の良い所でもう一度お試しください",
    en: "Couldn't connect. Please check your connection and try again",
    "zh-TW": "無法連線，請確認網路後再試一次",
  },
  "err.dailyCap": {
    ja: "1日の利用上限に達しました。24時間以内に自動で回復します。",
    en: "You've reached today's limit. It resets automatically within 24 hours.",
    "zh-TW": "已達今日使用上限，24 小時內會自動恢復。",
  },
  "err.aiBusy": {
    ja: "本日のAIの利用が上限に達しました。時間をおいてもう一度お試しください。",
    en: "AI features have reached today's limit. Please try again later.",
    "zh-TW": "今天的 AI 使用量已達上限，請稍後再試。",
  },
  "err.usageCheck": {
    ja: "利用回数を確認できませんでした。少し待ってからもう一度お試しください。",
    en: "We couldn't check your usage just now. Please try again in a moment.",
    "zh-TW": "目前無法確認使用次數，請稍候再試一次。",
  },
  "err.aiConsent": {
    ja: "AIを使う機能は、AIへのデータ送信に同意すると使えます。",
    en: "AI features work once you agree to send data to AI services.",
    "zh-TW": "同意將資料傳送給 AI 服務後，才能使用 AI 功能。",
  },
  // 外部の AI へ送る前の確認（iOS の AIConsentView と同じ中身。2026-10-03）。
  "aiConsent.title": {
    ja: "AIへのデータ送信について",
    en: "About sending data to AI",
    "zh-TW": "關於將資料傳送給 AI",
  },
  "aiConsent.lead": {
    ja: "CatchWords は、写真から単語を見つけたり、単語カードを作ったり、日記を添削したりするために、外部のAIサービスを使います。使い始める前に、送る内容を確かめて、同意するかを選んでください。",
    en: "CatchWords uses external AI services to find words in your photos, make word cards and correct your diary. Before you start, please check what is sent and choose whether you agree.",
    "zh-TW":
      "CatchWords 會使用外部 AI 服務，從照片中找出單字、製作單字卡、批改日記。開始使用前，請確認傳送的內容，並選擇是否同意。",
  },
  "aiConsent.whatTitle": { ja: "送るもの", en: "What is sent", "zh-TW": "傳送的內容" },
  "aiConsent.whatBody": {
    ja: "撮った写真、端末から選んだ画像、スキャンの画面、調べた単語、入力した文章（日記・報告のメモ）、声で調べた言葉（文字にしたもの。音声そのものは送りません）、学ぶ言語やレベルなどの設定。メールアドレスや名前は送りません。",
    en: "Photos you take, images you choose from your device, scan frames, words you look up, text you type (diary entries, notes in reports), words you look up by voice (as text; the audio itself is not sent), and settings such as your learning language and level. Your email address and name are not sent.",
    "zh-TW":
      "你拍的照片、從裝置選擇的圖片、掃描畫面、查詢的單字、輸入的文字（日記、回報的備註）、用語音查詢的詞語（轉成的文字，不會傳送語音本身），以及學習語言、程度等設定。不會傳送電子郵件地址與姓名。",
  },
  "aiConsent.whoTitle": { ja: "送り先", en: "Who receives it", "zh-TW": "傳送對象" },
  "aiConsent.whoBody": {
    ja: "当社のサーバを通して、外部のAIサービス（Google など）に送ります。送り先の会社と国は、プライバシーポリシーに書いてあります。",
    en: "It is sent through our server to external AI services (such as Google). The companies and countries that receive it are listed in the Privacy Policy.",
    "zh-TW":
      "經由本公司的伺服器傳送給外部 AI 服務（例如 Google）。接收的公司與所在國家記載於隱私權政策。",
  },
  "aiConsent.whyTitle": { ja: "使い道", en: "Why", "zh-TW": "用途" },
  "aiConsent.whyBody": {
    ja: "写っている物の判定、単語カード・解説・例文の作成、日記の添削のためだけに使います。当社が写真や日記を AI の学習に使うことはありません。",
    en: "Only to recognize what is in the photo, to make word cards, explanations and example sentences, and to correct your diary. We never use your photos or diary to train AI.",
    "zh-TW":
      "僅用於辨識照片中的物品、製作單字卡、解說與例句，以及批改日記。本公司不會將你的照片或日記用於訓練 AI。",
  },
  "aiConsent.declineTitle": {
    ja: "同意しない場合",
    en: "If you don't agree",
    "zh-TW": "不同意的話",
  },
  "aiConsent.declineBody": {
    ja: "カメラ・スキャン・単語カードの作成・日記の添削など、AI を使う機能は使えません（何も送りません）。集めた単語を見ることや復習は、そのまま使えます。あとから「設定」で同意することも、取り消すこともできます。",
    en: "Features that use AI, such as the camera, scanning, making word cards and diary correction, will not work (nothing is sent). You can still view the words you collected and review them. You can agree or withdraw later in Settings.",
    "zh-TW":
      "相機、掃描、製作單字卡、批改日記等使用 AI 的功能將無法使用（不會傳送任何資料）。瀏覽已收集的單字與複習仍可照常使用。之後也可以在「設定」中同意或撤回。",
  },
  "aiConsent.detailsLink": {
    ja: "詳しくはプライバシーポリシー（第4条・第5条）をご覧ください",
    en: "See the Privacy Policy (sections 4 and 5) for details",
    "zh-TW": "詳情請參閱隱私權政策（第 4 條、第 5 條）",
  },
  "aiConsent.accept": { ja: "同意して始める", en: "Agree and start", "zh-TW": "同意並開始" },
  "aiConsent.decline": { ja: "同意しない", en: "Don't agree", "zh-TW": "不同意" },
  "aiConsent.agreedToast": {
    ja: "AIへのデータ送信に同意しました",
    en: "You agreed to send data to AI",
    "zh-TW": "已同意將資料傳送給 AI",
  },
  "aiConsent.saveFailed": {
    ja: "保存できませんでした。もう一度お試しください。",
    en: "Couldn't save. Please try again.",
    "zh-TW": "無法儲存，請再試一次。",
  },
  "aiConsent.settingsTitle": {
    ja: "AIへのデータ送信",
    en: "Sending data to AI",
    "zh-TW": "將資料傳送給 AI",
  },
  "aiConsent.statusAgreed": {
    ja: "同意しています（{date}）",
    en: "You agreed ({date})",
    "zh-TW": "已同意（{date}）",
  },
  "aiConsent.statusNone": {
    ja: "同意していません。AI を使う機能は止まっています。",
    en: "You haven't agreed. Features that use AI are turned off.",
    "zh-TW": "尚未同意。使用 AI 的功能目前已停用。",
  },
  "aiConsent.settingsHint": {
    ja: "写真・調べた単語・入力した文章を、外部のAIサービス（Google など）に送ってよいかの設定です。",
    en: "Whether your photos, the words you look up and the text you type may be sent to external AI services (such as Google).",
    "zh-TW": "是否允許將照片、查詢的單字與輸入的文字傳送給外部 AI 服務（例如 Google）。",
  },
  "aiConsent.review": {
    ja: "内容を確認して同意する",
    en: "Review and agree",
    "zh-TW": "確認內容並同意",
  },
  "aiConsent.withdraw": { ja: "同意を取り消す", en: "Withdraw consent", "zh-TW": "撤回同意" },
  "aiConsent.withdrawConfirm": {
    ja: "取り消すと、カメラ・スキャン・単語カードの作成・日記の添削など、AI を使う機能が使えなくなります。取り消しますか？",
    en: "If you withdraw, features that use AI, such as the camera, scanning, making word cards and diary correction, will stop working. Withdraw?",
    "zh-TW": "撤回後，相機、掃描、製作單字卡、批改日記等使用 AI 的功能將無法使用。確定要撤回嗎？",
  },
  "aiConsent.withdrawYes": { ja: "取り消す", en: "Withdraw", "zh-TW": "撤回" },
  "aiConsent.withdrawn": {
    ja: "同意を取り消しました",
    en: "Consent withdrawn",
    "zh-TW": "已撤回同意",
  },
  "err.proOnly": {
    ja: "Pro 限定の機能です",
    en: "This is a Pro feature",
    "zh-TW": "這是 Pro 限定功能",
  },
  "err.forbidden": {
    ja: "この操作はできません",
    en: "You can't do that here",
    "zh-TW": "無法進行這個操作",
  },
  "err.notFound": { ja: "見つかりませんでした", en: "Couldn't find it", "zh-TW": "找不到" },
  "err.tryAgain": {
    ja: "うまくいきませんでした。もう一度お試しください",
    en: "That didn't work. Please try again",
    "zh-TW": "沒有成功，請再試一次",
  },
  "rp.title": { ja: "パスワード再設定", en: "Reset password", "zh-TW": "重設密碼" },
  "auth.forgot": {
    ja: "パスワードを忘れた方",
    en: "Forgot password?",
    "zh-TW": "忘記密碼？",
  },
  "rp.sentTitle": {
    ja: "メールを送りました",
    en: "Check your email",
    "zh-TW": "已寄出電子郵件",
  },
  "rp.sentBody": {
    ja: "{email} に再設定用のリンクを送りました。メールを開いてリンクを押すと、新しいパスワードを決められます。届かないときは迷惑メールのフォルダも確認してください。",
    en: "We sent a reset link to {email}. Open the email and tap the link to choose a new password. If it doesn't arrive, check your spam folder.",
    "zh-TW":
      "已將重設連結寄到 {email}。打開郵件並點選連結，就能設定新的密碼。如果沒有收到，也請看看垃圾郵件匣。",
  },
  "rp.resend": { ja: "もう一度送る", en: "Send again", "zh-TW": "再寄一次" },
  "rp.hintRequest": {
    ja: "登録メールアドレスにリンクを送ります。",
    en: "We'll email a link to your registered address.",
    "zh-TW": "會把連結寄到你註冊的電子郵件。",
  },
  "rp.hintUpdate": {
    ja: "新しいパスワードを入力してください。",
    en: "Enter your new password.",
    "zh-TW": "請輸入新的密碼。",
  },
  "rp.email": { ja: "メールアドレス", en: "Email", "zh-TW": "電子郵件" },
  "rp.sendLink": { ja: "再設定リンクを送る", en: "Send reset link", "zh-TW": "寄出重設連結" },
  "rp.newPassword": { ja: "新しいパスワード", en: "New password", "zh-TW": "新密碼" },
  "rp.update": { ja: "パスワードを更新", en: "Update password", "zh-TW": "更新密碼" },
  "rp.backToLogin": { ja: "ログイン画面に戻る", en: "Back to sign in", "zh-TW": "回到登入畫面" },
  "rp.sent": {
    ja: "再設定リンクをメールで送りました。",
    en: "Reset link sent — check your email.",
    "zh-TW": "已用電子郵件寄出重設連結。",
  },
  "rp.sendFailed": { ja: "送信に失敗しました", en: "Could not send", "zh-TW": "寄送失敗" },
  "rp.updated": {
    ja: "パスワードを更新しました。",
    en: "Password updated.",
    "zh-TW": "密碼已更新。",
  },
  "rp.updateFailed": { ja: "更新に失敗しました", en: "Could not update", "zh-TW": "更新失敗" },
  "root.notFound": {
    ja: "ページが見つかりません",
    en: "Page not found",
    "zh-TW": "找不到這個頁面",
  },
  "root.notFoundHint": {
    ja: "指定されたページは存在しないか、移動された可能性があります。",
    en: "This page doesn't exist, or it may have moved.",
    "zh-TW": "指定的頁面可能不存在，或是已經搬走了。",
  },
  "root.toHome": { ja: "ホームへ", en: "Go home", "zh-TW": "回首頁" },
  "root.loadFailed": { ja: "読み込みに失敗しました", en: "Failed to load", "zh-TW": "載入失敗" },
  "root.loadFailedHint": {
    ja: "少し時間を置いてもう一度お試しください。",
    en: "Please wait a moment and try again.",
    "zh-TW": "請過一會兒再試一次。",
  },
  "root.retry": { ja: "再試行", en: "Retry", "zh-TW": "重試" },
  "root.sectionFailed": {
    ja: "この欄を表示できませんでした",
    en: "This section couldn't be shown",
    "zh-TW": "無法顯示這個區塊",
  },
  "root.errorDetail": { ja: "エラーの内容", en: "Error details", "zh-TW": "錯誤內容" },
  // --- 発見・投稿・日記 ---
  "common.anon": { ja: "名無し", en: "Anonymous", "zh-TW": "無名氏" },
  // --- 通知・相対時刻 ---
  "ago.seconds": { ja: "{n}秒前", en: "{n}s ago", "zh-TW": "{n} 秒前" },
  "ago.minutes": { ja: "{n}分前", en: "{n}m ago", "zh-TW": "{n} 分鐘前" },
  "ago.hours": { ja: "{n}時間前", en: "{n}h ago", "zh-TW": "{n} 小時前" },
  "ago.days": { ja: "{n}日前", en: "{n}d ago", "zh-TW": "{n} 天前" },
  "ago.months": { ja: "{n}ヶ月前", en: "{n}mo ago", "zh-TW": "{n} 個月前" },
  "ago.years": { ja: "{n}年前", en: "{n}y ago", "zh-TW": "{n} 年前" },
  "common.someone": { ja: "誰か", en: "Someone", "zh-TW": "某人" },
  // --- 場所の思い出し(文の前後) ---
  // **「」の中は母語**(オーナー指摘 2026-08-20)。
  // 押した先の問題は「写真+日本語 → 台湾華語を4択」なので、通知に
  // 台湾華語を出すと**開いた瞬間に答えが分かる**。
  "place.rememberBefore": { ja: "「", en: "Remember “", "zh-TW": "「" },
  // 言語の名前は**学習言語から**入れる（`{lang}` = `place.lang*`）。前は
  // 「中文」と決め打ちで、英語を学ぶ人にも中文と出ていた。
  // 名前はオーナー指示 2026-09-27「『中国語』ではなく『台湾華語』、英語では Mandarin」。
  "place.rememberAfter": {
    ja: "」は{lang}で？",
    en: "” in {lang}?",
    "zh-TW": "」用{lang}怎麼說？",
  },
  "place.langZh": { ja: "台湾華語", en: "Mandarin", "zh-TW": "華語" },
  "place.langEn": { ja: "英語", en: "English", "zh-TW": "英文" },
  // B「写真を大きく」（オーナー決定 2026-09-27）。写真が手がかりなので、題は短く問うだけ。
  // 報告: AIに間違っている所を見つけてもらう（オーナー指示 2026-09-27）。
  "card.reportAuto": {
    ja: "AIに見つけてもらう",
    en: "Let AI find it",
    "zh-TW": "讓 AI 找出來",
  },
  "card.reportAutoHint": {
    ja: "どこが変か一言（空でも送れます）",
    en: "What looks wrong? (optional)",
    "zh-TW": "哪裡怪怪的？（可以不填）",
  },
  "card.reportAutoSend": { ja: "直してもらう", en: "Fix it", "zh-TW": "請 AI 修正" },
  "card.reportNotFound": {
    ja: "AIは間違いを見つけられませんでした。報告として残しました",
    en: "AI couldn't find the mistake. Your report was saved",
    "zh-TW": "AI 沒有找到錯誤。已保留你的回報",
  },
  // 節目の日の記念アルバム（オーナー指示 2026-09-27）。`milestone-album.ts`。
  "memorial.title": {
    ja: "使い始めて{n}日の記念アルバム",
    en: "Your {n}-day album",
    "zh-TW": "使用第 {n} 天的紀念相簿",
  },
  "memorial.sub": {
    ja: "{n}日間で{count}語。思い出の{photos}枚をまとめました",
    en: "{count} {count|word|words} in {n} {n|day|days}. {photos} {photos|moment|moments} in one page",
    "zh-TW": "{n} 天收集了 {count} 個單字，精選 {photos} 張回憶",
  },
  // 記念アルバムを開く瞬間の演出（`MemorialReveal`、2026-09-28）。
  "memorial.kicker": { ja: "おめでとう", en: "Congratulations", "zh-TW": "恭喜" },
  "memorial.daysUnit": { ja: "日", en: "days", "zh-TW": "天" },
  "memorial.wordsCaught": {
    ja: "{count}語を集めました",
    en: "{count} {count|word|words} caught",
    "zh-TW": "收集了 {count} 個單字",
  },
  "memorial.openAlbum": { ja: "アルバムを開く", en: "Open the album", "zh-TW": "打開相簿" },
  "memorial.close": { ja: "閉じる", en: "Close", "zh-TW": "關閉" },
  "memorial.notifyTitle": {
    ja: "{n}日目の記念アルバムができました",
    en: "Your {n}-day album is ready",
    "zh-TW": "第 {n} 天的紀念相簿完成了",
  },
  "memorial.notifyBody": {
    ja: "使い始めて{n}日。これまでの思い出を1冊にまとめました",
    en: "{n} {n|day|days} in. Your favourite moments, in one album",
    "zh-TW": "使用第 {n} 天，把回憶整理成一本相簿",
  },
  // 復習の通知の時刻（オーナー指示 2026-09-27）。`review-reminder.ts`。
  "settings.notifications": { ja: "通知", en: "Notifications", "zh-TW": "通知" },
  "remind.label": { ja: "復習の通知", en: "Review reminders", "zh-TW": "複習提醒" },
  "remind.off": { ja: "オフ", en: "Off", "zh-TW": "關閉" },
  "remind.custom": { ja: "時刻を指定", en: "Set times", "zh-TW": "自訂時間" },
  "remind.ai": { ja: "自動", en: "Auto", "zh-TW": "自動" },
  "remind.addTime": { ja: "時刻を追加", en: "Add a time", "zh-TW": "新增時間" },
  "remind.removeTime": { ja: "この時刻を消す", en: "Remove this time", "zh-TW": "刪除這個時間" },
  "remind.webOnly": {
    ja: "ブラウザでは、アプリを開いている間だけ鳴ります。",
    en: "In the browser, reminders only work while the app is open.",
    "zh-TW": "在瀏覽器中，只有開著 App 時才會提醒。",
  },
  "remind.denied": {
    ja: "通知が許可されていません。端末の設定で CatchWords の通知をオンにしてください。",
    en: "Notifications are blocked. Turn them on for CatchWords in your device settings.",
    "zh-TW": "通知未被允許。請在裝置設定中開啟 CatchWords 的通知。",
  },
  "remind.title": { ja: "復習の時間です", en: "Time to review", "zh-TW": "該複習了" },
  // 通知は**写真つきの1問**（オーナー指示 2026-09-28）。写真があれば写真そのものを問う。
  "remind.quizPhoto": {
    ja: "これ、{lang}で言える？",
    en: "Can you say this in {lang}?",
    "zh-TW": "這個用{lang}怎麼說？",
  },
  "remind.quizWord": {
    ja: "「{meaning}」、{lang}で言える？",
    en: "How do you say \u201c{meaning}\u201d in {lang}?",
    "zh-TW": "「{meaning}」用{lang}怎麼說？",
  },
  // **撮った語の通知の題とホームの札**（オーナー指示 2026-10-07「〇〇前に撮ったのこの単語
  // 覚えてる？に通知の名前を変えて」）。言い方は `resurface.ts` の `caughtAgoLabel`。
  "remind.caughtToday": {
    ja: "今日撮ったこの単語、覚えてる？",
    en: "A word you caught today — remember it?",
    "zh-TW": "今天拍的這個單字，還記得嗎？",
  },
  "remind.caughtDays": {
    ja: "{n}日前に撮ったこの単語、覚えてる？",
    en: "A word you caught {n} {n|day|days} ago — remember it?",
    "zh-TW": "{n} 天前拍的這個單字，還記得嗎？",
  },
  "remind.caughtWeeks": {
    ja: "{n}週間前に撮ったこの単語、覚えてる？",
    en: "A word you caught {n} {n|week|weeks} ago — remember it?",
    "zh-TW": "{n} 週前拍的這個單字，還記得嗎？",
  },
  "remind.caughtMonths": {
    ja: "{n}か月前に撮ったこの単語、覚えてる？",
    en: "A word you caught {n} {n|month|months} ago — remember it?",
    "zh-TW": "{n} 個月前拍的這個單字，還記得嗎？",
  },
  "remind.caughtYears": {
    ja: "{n}年前に撮ったこの単語、覚えてる？",
    en: "A word you caught {n} {n|year|years} ago — remember it?",
    "zh-TW": "{n} 年前拍的這個單字，還記得嗎？",
  },
  // 押すとその語から復習が始まる（1問で終わらず、続けて今日の復習へ）。
  "remind.quizBody": {
    ja: "押すと、この単語から復習が始まります",
    en: "Tap to start your review with this word",
    "zh-TW": "點一下，從這個單字開始複習",
  },
  // **残りの数を出さない**（PRODUCT.md「Never present review backlog as debt」、オーナー決定
  // 2026-10-02「数字を出すと…やる気がなくなる」）。1分だけ、続けるかは本人が決める。
  "remind.body": {
    ja: "1分だけ、撮った単語に会いに行きませんか",
    en: "Got a minute? Say hi to the words you caught",
    "zh-TW": "花一分鐘，和你收集的單字見個面吧",
  },
  "remind.bodySrs": {
    ja: "いま1分だけ見直すと、ぐっと覚えやすくなります",
    en: "A one-minute look now helps your words stick",
    "zh-TW": "現在花一分鐘看一下，會記得更牢",
  },
  "remind.bodyEmpty": {
    ja: "撮った単語を見直しましょう",
    en: "Take another look at the words you caught",
    "zh-TW": "來看看你收集的單字吧",
  },
  "place.sayItIn": {
    ja: "ここで撮った、これ。{lang}で言える？",
    en: "You caught this here. Can you say it in {lang}?",
    "zh-TW": "在這裡拍到的這個，用{lang}怎麼說？",
  },
  // 「思い出す」ではなく「復習する」（オーナー指示 2026-09-27）。
  "place.review": { ja: "復習する", en: "Review", "zh-TW": "複習" },
  "place.later": { ja: "あとで", en: "Later", "zh-TW": "稍後" },
  // --- 場所の思い出し・共通 ---
  // 通知とカードの本文。**意味(訳)は入れない** — 通知そのものが
  // 「覚えてる?」という問いなので、答えを並べたら問いにならない。
  // 思い出す鍵は市の名前ではなく**いつ撮ったか**なので、日付を先に出し、
  // 日付が読めないときだけ場所の名前に落ちる。
  // 「ここ」ではなく**地名**で言う(オーナー指摘)。地名が取れない回だけ
  // 日付だけに落ちる。
  "place.caughtOnAt": {
    ja: "{date}に{name}で撮った言葉",
    en: "You caught this at {name} on {date}",
    "zh-TW": "{date} 在 {name} 拍到的字",
  },
  "place.caughtOn": {
    ja: "{date}に撮った言葉",
    en: "You caught this on {date}",
    "zh-TW": "{date} 拍到的字",
  },
  "place.caughtAt": {
    ja: "{name}で撮った言葉",
    en: "You caught this at {name}",
    "zh-TW": "在 {name} 拍到的字",
  },
  "place.caughtHereShort": {
    ja: "この辺りで撮った言葉",
    en: "You caught this around here",
    "zh-TW": "在這附近拍到的字",
  },
  "common.card": { ja: "カード", en: "Card", "zh-TW": "字卡" },
  "common.closeEdit": { ja: "編集を閉じる", en: "Close editing", "zh-TW": "關閉編輯" },
  "common.photoOf": {
    ja: "「{word}」の写真",
    en: 'Photo of "{word}"',
    "zh-TW": "「{word}」的照片",
  },
  "common.playWord": { ja: "「{word}」を聞く", en: 'Listen to "{word}"', "zh-TW": "聽「{word}」" },
  "common.imageOf": {
    ja: "「{word}」の画像",
    en: 'Image for "{word}"',
    "zh-TW": "「{word}」的圖片",
  },
  "common.stickerOf": {
    ja: "「{word}」のステッカー",
    en: 'Sticker for "{word}"',
    "zh-TW": "「{word}」的貼紙",
  },
  "common.memoryOf": {
    ja: "「{word}」の思い出",
    en: 'Memory of "{word}"',
    "zh-TW": "「{word}」的回憶",
  },
  "common.mapTitle": {
    ja: "撮影場所のマップ",
    en: "Map of where it was taken",
    "zh-TW": "拍攝地點的地圖",
  },
  "common.shotHere": { ja: "撮影地", en: "Where it was taken", "zh-TW": "拍攝地" },
  "common.selfieOf": {
    ja: "撮影者の自撮り",
    en: "Selfie of the person who caught it",
    "zh-TW": "拍攝者的自拍",
  },
  // 出所は**人の言葉で**。以前は「✓ 検証済み辞書 + AI詳細 · 点 0.92」で、
  // 0.92 はモデルの confidence(内部の数値)がそのまま漏れていた。
  // 学習者にとって意味が無く、「点」が何の点かも示していない(独立監査)。
  // --- ワードツリー・画像選択 ---
  "tree.branches": {
    ja: "枝 {done}/{total} 本 · 復習ごとに1本育つ",
    en: "{done} of {total} {total|branch|branches} · one grows per review",
    "zh-TW": "樹枝 {done}/{total} 根 · 每複習一次長一根",
  },
  // --- 忘却曲線 ---
  "curve.empty": {
    ja: "まだ復習データがありません。復習すると忘却曲線がここに表示されます。",
    en: "No review data yet. Review this word and its forgetting curve will appear here.",
    "zh-TW": "還沒有複習資料。複習之後，遺忘曲線就會顯示在這裡。",
  },
  "curve.axisNote": {
    ja: "縦軸＝いま思い出せる確率（写真の右上の％と同じ）",
    en: "Vertical axis = chance you can recall it now (the same % as on the photo)",
    "zh-TW": "縱軸＝現在想得起來的機率（和照片右上的％相同）",
  },
  "curve.legendPast": { ja: "これまで", en: "So far", "zh-TW": "到目前為止" },
  "curve.legendFuture": { ja: "復習しなかったら", en: "If not reviewed", "zh-TW": "如果不複習" },
  "curve.legendReview": { ja: "復習した日", en: "Reviewed", "zh-TW": "複習過的日子" },
  "curve.todayPct": { ja: "今日 {pct}%", en: "Today {pct}%", "zh-TW": "今天 {pct}%" },
  "curve.bestTick": { ja: "復習どき", en: "Review", "zh-TW": "複習時機" },
  "curve.daysAgo": { ja: "{n}日前", en: "{n}d ago", "zh-TW": "{n} 天前" },
  "curve.daysLater": { ja: "{n}日後", en: "in {n}d", "zh-TW": "{n} 天後" },
  "curve.nextDrop": {
    ja: "復習しないと {date}（{n}日後）に「{level}」になります",
    en: "Without review it becomes “{level}” on {date} (in {n}d)",
    "zh-TW": "不複習的話，{date}（{n} 天後）會變成「{level}」",
  },
  "curve.nextDropToday": {
    ja: "復習しないと 今日のうちに「{level}」になります",
    en: "Without review it becomes “{level}” later today",
    "zh-TW": "不複習的話，今天之內會變成「{level}」",
  },
  "curve.aria": {
    ja: "記憶の曲線。今日の記憶率 {pct}%、復習 {n} 回",
    en: "Memory curve. Today {pct}%, reviewed {n} {n|time|times}",
    "zh-TW": "記憶曲線。今天的記憶率 {pct}%，複習 {n} 次",
  },
  "curve.reviewNow": {
    ja: "今が復習どき",
    en: "Now is the time to review",
    "zh-TW": "現在就是複習時機",
  },
  "curve.reviewNowHint": {
    ja: "いま思い出すと、次に忘れるまでの期間が伸びます。",
    en: "Recalling it now makes the memory last longer.",
    "zh-TW": "現在回想，下次忘記前的時間會變長。",
  },
  "curve.reviewNowCta": { ja: "いま復習する", en: "Review now", "zh-TW": "現在複習" },
  "curve.reviewOn": {
    ja: "{date}（{n}日後）が復習どき",
    en: "Review on {date} (in {n}d)",
    "zh-TW": "{date}（{n} 天後）是複習時機",
  },
  "curve.reviewOnHint": {
    ja: "その日に復習に出ます。思い出すと記憶が長く続きます。復習しないと点線のように下がっていきます。",
    en: "It will come up in review that day. Recalling it then makes it last. Without review it drops like the dashed line.",
    "zh-TW": "那天會出現在複習裡。那時回想，記憶會更持久。不複習的話會像虛線一樣下降。",
  },
  // --- bottom nav ---
  "nav.home": { ja: "ホーム", en: "Home", "zh-TW": "首頁" },
  "nav.dex": { ja: "図鑑", en: "Dex", "zh-TW": "圖鑑" },
  "nav.camera": { ja: "カメラ", en: "Camera", "zh-TW": "相機" },
  "nav.review": { ja: "復習", en: "Review", "zh-TW": "複習" },
  "nav.settings": { ja: "設定", en: "Settings", "zh-TW": "設定" },
  // --- page titles ---
  "title.dex": { ja: "図鑑", en: "Dex", "zh-TW": "圖鑑" },
  "title.review": { ja: "復習", en: "Review", "zh-TW": "複習" },
  "title.settings": { ja: "設定", en: "Settings", "zh-TW": "設定" },
  "title.capture": { ja: "集める", en: "Catch", "zh-TW": "收集" },
  // --- review ---
  "review.today": { ja: "きょうの復習", en: "Today's review", "zh-TW": "今天的複習" },
  // --- dex ---
  "dex.yours": { ja: "あなたの図鑑", en: "Your Dex", "zh-TW": "你的圖鑑" },
  "dex.search": {
    ja: "単語・読み・意味で検索",
    en: "Search word / reading / meaning",
    "zh-TW": "用單字、讀音、意思搜尋",
  },
  // --- settings ---
  "settings.profile": { ja: "プロフィール", en: "Profile", "zh-TW": "個人檔案" },
  "settings.displayName": { ja: "表示名", en: "Display name", "zh-TW": "顯示名稱" },
  "settings.language": { ja: "言語", en: "Language", "zh-TW": "語言" },
  "settings.targetLang": { ja: "学習言語", en: "Target language", "zh-TW": "學習語言" },
  "settings.levelGoal": { ja: "目標レベル", en: "Target level", "zh-TW": "目標等級" },
  "settings.currentLevel": { ja: "今のレベル", en: "Current level", "zh-TW": "目前等級" },
  /**
   * オーナー指示 2026-08-26「設定の表示言語という項目を母語に名称を変更して」。
   *
   * 実体は変わらない（アプリの文字とカードの解説がこの言語で出る）。
   * 呼び名を「母語」にする — その人が**いちばん楽に読める言語**を
   * 選ぶ欄なので、そう言ったほうが選びやすい。
   */
  "settings.uiLang": { ja: "母語", en: "Your language", "zh-TW": "母語" },
  "settings.phonetic": { ja: "発音表記", en: "Phonetic notation", "zh-TW": "發音標記" },
  "settings.study": { ja: "学習設定", en: "Study settings", "zh-TW": "學習設定" },
  // 見え方は3つ。名前 + 一言で、何が変わるかを開く前に言う。
  "settings.feel": { ja: "音と手ざわり", en: "Sound & haptics", "zh-TW": "聲音與觸感" },
  "settings.soundLevel": { ja: "効果音", en: "Sound effects", "zh-TW": "音效" },
  "settings.soundOff": { ja: "オフ", en: "Off", "zh-TW": "關閉" },
  "settings.soundSubtle": { ja: "控えめ", en: "Subtle", "zh-TW": "輕微" },
  "settings.soundFull": { ja: "しっかり", en: "Full", "zh-TW": "完整" },
  "settings.haptics": { ja: "振動", en: "Haptics", "zh-TW": "震動" },
  "settings.appearance": { ja: "外観", en: "Appearance", "zh-TW": "外觀" },
  // 「テーマ」と「UIテーマ」が並ぶと区別できない（オーナー指示 2026-09-23）。
  "settings.theme": { ja: "画面の明るさ", en: "Light / dark", "zh-TW": "畫面明暗" },
  "home.placementNotSaved": {
    ja: "配置は保存できませんでした（表の準備がまだです）。この画面を開いている間は動いたままです。",
    en: "Layout could not be saved (the table isn't ready yet). It stays as you left it while this screen is open.",
    "zh-TW": "版面尚無法儲存（資料表尚未準備好）。在此畫面開啟期間會維持你擺放的樣子。",
  },
  "home.placementSaveFailed": {
    ja: "配置を保存できませんでした。通信を確かめて、もう一度お試しください。",
    en: "Couldn't save the layout. Check your connection and try again.",
    "zh-TW": "無法儲存版面。請檢查連線後再試一次。",
  },
  "settings.motion": { ja: "アニメーション", en: "Animation", "zh-TW": "動畫" },
  // キャッチの演出の大きさ（`lib/catch-animation-pref.ts`。ROADMAP Phase 4）。
  "settings.catchAnimation": { ja: "キャッチの演出", en: "Catch animation", "zh-TW": "捕捉動畫" },
  "settings.catchAnimationFull": { ja: "しっかり", en: "Full", "zh-TW": "完整" },
  "settings.catchAnimationShort": { ja: "短く", en: "Short", "zh-TW": "簡短" },
  "settings.catchAnimationOff": { ja: "オフ", en: "Off", "zh-TW": "關閉" },
  "settings.catchAnimationFullDesc": {
    ja: "毎回、音楽つきで大きく祝います。",
    en: "Every catch gets the full celebration with music.",
    "zh-TW": "每次都以音樂和完整動畫慶祝。",
  },
  "settings.catchAnimationOffDesc": {
    ja: "動きは出さず、発音だけ聞かせます。",
    en: "No animation — you'll still hear the pronunciation.",
    "zh-TW": "不播放動畫，仍會播放發音。",
  },
  // 設定の自動保存の小さな札（`components/SaveStatus.tsx`）。
  "settings.savedInline": { ja: "保存しました", en: "Saved", "zh-TW": "已儲存" },
  // ホームの「〇か月前に撮ったこの単語、覚えてる？」（`components/ResurfaceCard.tsx`、
  // `lib/resurface.ts`）。題は通知と同じ `remind.caught*`。押すとその語から復習が始まる。
  // 押す前に語を読み上げない（答えが分かってしまう）。
  "home.resurface.open": {
    ja: "この単語から復習を始める",
    en: "Start a review with this word",
    "zh-TW": "從這個單字開始複習",
  },
  "home.resurface.close": { ja: "今日は閉じる", en: "Hide for today", "zh-TW": "今天先關閉" },
  // **なぜ消えているのかが分かる言葉にする。** 端末の設定で消えている人は、
  // 自分で入れた覚えが無いので「動きを減らす」とだけ書かれても辿り着けない。
  "settings.motion.osReduces": {
    ja: "この端末は「動きを減らす」設定です（省電力モード、または ユーザー補助 →「アニメーションを削除」）。そのためアプリの演出が出ません。ここで「見せる」を選ぶと、端末の設定にかかわらず出ます。",
    en: "This device asks for reduced motion (battery saver, or Accessibility → Remove animations), so the app's animations are off. Choose “Show” to see them anyway.",
    "zh-TW":
      "此裝置要求減少動態效果（省電模式，或 協助工具 →「移除動畫」），因此動畫不會播放。選「顯示」即可不受裝置設定影響。",
  },
  "settings.motion.osAllows": {
    ja: "この端末は動きを許可しています。演出はそのまま出ます。",
    en: "This device allows motion. Animations play as normal.",
    "zh-TW": "此裝置允許動態效果，動畫會正常播放。",
  },
  "settings.motion.forcedFull": {
    ja: "端末の設定にかかわらず、演出を出しています。",
    en: "Animations play regardless of the device setting.",
    "zh-TW": "不受裝置設定影響，動畫會播放。",
  },
  "settings.motion.forcedReduce": {
    ja: "端末の設定にかかわらず、演出を減らしています。",
    en: "Animations are reduced regardless of the device setting.",
    "zh-TW": "不受裝置設定影響，動畫已減少。",
  },
  "settings.save": { ja: "保存", en: "Save", "zh-TW": "儲存" },
  "settings.saving": { ja: "保存中…", en: "Saving...", "zh-TW": "儲存中…" },
  "settings.saved": { ja: "保存しました", en: "Saved", "zh-TW": "已儲存" },
  "settings.signout": { ja: "サインアウト", en: "Sign out", "zh-TW": "登出" },
  // --- capture ---
  "capture.photoTitle": { ja: "撮影", en: "Photo", "zh-TW": "拍照" },
  "capture.photoHint": {
    ja: "見つけたものを枠の中へ",
    en: "Place what you found inside the frame",
    "zh-TW": "把發現的東西放進框內",
  },
  "capture.tapToShoot": { ja: "タップして撮影", en: "Tap to shoot", "zh-TW": "點一下拍照" },
  // 2026-10-02: どの理由でも「写真を選んで続けられる」ことを言う（行き止まりにしない）。
  "camhelp.title.inapp": {
    ja: "このアプリの中ではカメラを使えません",
    en: "The camera isn't available in this app",
    "zh-TW": "在這個 App 裡無法使用相機",
  },
  "camhelp.body.inapp": {
    ja: "SafariやChromeで開き直すと、カメラが使えます。写真を選んで続けることもできます。",
    en: "Reopen this page in Safari or Chrome to use the camera, or continue with a photo.",
    "zh-TW": "用 Safari 或 Chrome 重新開啟就能使用相機，也可以選擇照片繼續。",
  },
  "camhelp.title.denied": {
    ja: "カメラがオフになっています",
    en: "Camera access is off",
    "zh-TW": "相機權限已關閉",
  },
  "camhelp.body.denied": {
    ja: "下の手順でカメラを許可してください。写真を選んで続けることもできます。",
    en: "Allow the camera with the steps below, or continue with a photo.",
    "zh-TW": "請依照下方步驟允許使用相機，也可以選擇照片繼續。",
  },
  "camhelp.title.unavailable": {
    ja: "カメラを起動できませんでした",
    en: "Couldn't start the camera",
    "zh-TW": "無法啟動相機",
  },
  "camhelp.body.unavailable": {
    ja: "ほかのアプリがカメラを使っていたら閉じて、もう一度試してください。写真を選んで続けることもできます。",
    en: "If another app is using the camera, close it and try again, or continue with a photo.",
    "zh-TW": "如果有其他 App 正在使用相機，請先關閉再試一次，也可以選擇照片繼續。",
  },
  "camhelp.title.unsupported": {
    ja: "このブラウザではカメラを使えません",
    en: "This browser can't use the camera",
    "zh-TW": "這個瀏覽器無法使用相機",
  },
  "camhelp.body.unsupported": {
    ja: "写真を選んで続けるか、SafariかChromeの最新版でこのページを開いてください。",
    en: "Continue with a photo, or open this page in the latest Safari or Chrome.",
    "zh-TW": "可以選擇照片繼續，或用最新版的 Safari 或 Chrome 開啟這個頁面。",
  },
  // iPhone の Safari は、このサイトだけの許可がアドレス欄の「ぁあ」の中にある（2026-10-02）。
  "camhelp.iosSafari1": {
    ja: "アドレス欄の「ぁあ」または「…」を押し、「Webサイトの設定」を開く",
    en: "Tap “aA” (or “…”) in the address bar, then “Website Settings”",
    "zh-TW": "點網址列的「大小」(aA) 或「…」，再點「網站設定」",
  },
  "camhelp.iosSafari2": {
    ja: "「カメラ」を「許可」にして、「もう一度試す」を押す",
    en: "Set “Camera” to “Allow”, then tap “Try again”",
    "zh-TW": "把「相機」改成「允許」，再按「再試一次」",
  },
  "camhelp.iosSettings": {
    ja: "出てこないときは「設定」アプリ →「アプリ」→「Safari」→「カメラ」を「確認」か「許可」にする",
    en: "If it isn't there: Settings app → Apps → Safari → Camera → “Ask” or “Allow”",
    "zh-TW": "找不到時：「設定」App →「App」→「Safari」→「相機」改成「詢問」或「允許」",
  },
  "camhelp.howTo": {
    ja: "カメラを許可する方法",
    en: "How to allow the camera",
    "zh-TW": "如何允許使用相機",
  },
  // 撮る前の一枚（オーナー指示 2026-10-02「許可の画面がダサい…どこからでもカメラを
  // 許可して、新規登録前にこのアプリを体験できるように」→ 2026-10-03「写したものから…と
  // 緑のマークのあとの注意書きは消す」）。ブラウザの確認より先に、見出しと次に押す物だけ。
  "campriming.title": {
    ja: "カメラで、ことばを見つけよう",
    en: "Find words with your camera",
    "zh-TW": "用相機發現單字",
  },
  "campriming.next": {
    ja: "次に出るブラウザの確認では「許可」を選んでください。",
    en: "Then choose “Allow” when your browser asks.",
    "zh-TW": "接著瀏覽器詢問時，請選「允許」。",
  },
  "campriming.allow": { ja: "カメラを使う", en: "Use camera", "zh-TW": "使用相機" },
  "campriming.library": { ja: "写真を選ぶ", en: "Choose a photo", "zh-TW": "選擇照片" },
  "camhelp.iosChrome1": {
    ja: "iPhoneの「設定」→「アプリ」→「Chrome」を開く",
    en: "Open iPhone Settings → Apps → Chrome",
    "zh-TW": "打開 iPhone「設定」→「App」→「Chrome」",
  },
  "camhelp.iosChrome2": {
    ja: "「カメラ」をオンにして、この画面に戻る",
    en: "Turn on “Camera” and come back to this screen",
    "zh-TW": "開啟「相機」後回到這個畫面",
  },
  "camhelp.android1": {
    ja: "アドレス欄の左端のマーク（鍵や、つまみの形のアイコン）を押す",
    en: "Tap the icon at the left end of the address bar (a lock or slider icon)",
    "zh-TW": "點網址列最左邊的圖示（鎖頭或調整鈕的圖示）",
  },
  "camhelp.android2": {
    ja: "「権限」（または「サイトの設定」）→「カメラ」を「許可」にして、このページに戻る",
    en: "Open “Permissions” (or “Site settings”) → “Camera”, choose “Allow”, then come back to this page",
    "zh-TW": "點「權限」（或「網站設定」）→「相機」改成「允許」，再回到這個頁面",
  },
  "camhelp.android3": {
    ja: "出てこないときは、スマホの「設定」→「アプリ」→「{browser}」→「権限」→「カメラ」を「許可」にする",
    en: "If it isn't there, open phone Settings → Apps → {browser} → Permissions → Camera and choose “Allow”",
    "zh-TW":
      "如果找不到，請到手機「設定」→「應用程式」→「{browser}」→「權限」→「相機」改成「允許」",
  },
  "camhelp.desktop1": {
    ja: "アドレス欄の左のアイコンから、カメラを「許可」にする",
    en: "Use the icon at the left of the address bar to allow the camera",
    "zh-TW": "從網址列左邊的圖示把相機改成「允許」",
  },
  "camhelp.inappIos": {
    ja: "画面の「…」や共有ボタンから「Safariで開く」（またはブラウザで開く）を選ぶ。見つからないときは下の「リンクをコピー」を押し、Safariに貼り付けて開く",
    en: "Use the “…” or share button and choose “Open in Safari” (or open in browser). If you can't find it, tap “Copy link” below and paste it into Safari",
    "zh-TW":
      "從「…」或分享按鈕選擇「用 Safari 開啟」（或用瀏覽器開啟）。找不到時，按下方「複製連結」，再貼到 Safari 開啟",
  },
  "camhelp.inappOther": {
    ja: "画面の「…」メニューから「ブラウザで開く」を選ぶ。見つからないときは下の「リンクをコピー」を押し、Chromeに貼り付けて開く",
    en: "Use the “…” menu and choose “Open in browser”. If you can't find it, tap “Copy link” below and paste it into Chrome",
    "zh-TW": "從「…」選單選擇「用瀏覽器開啟」。找不到時，按下方「複製連結」，再貼到 Chrome 開啟",
  },
  "camhelp.openBrowser": {
    ja: "ブラウザで開き直す",
    en: "Open in your browser",
    "zh-TW": "用瀏覽器重新開啟",
  },
  "camhelp.retry": {
    ja: "もう一度カメラを試す",
    en: "Try the camera again",
    "zh-TW": "再試一次相機",
  },
  "camhelp.allowRetry": {
    ja: "許可したので、もう一度試す",
    en: "I allowed it — try again",
    "zh-TW": "已經允許，再試一次",
  },
  "camhelp.copyLink": {
    ja: "リンクをコピー",
    en: "Copy link",
    "zh-TW": "複製連結",
  },
  "camhelp.copied": {
    ja: "コピーしました。ブラウザに貼り付けて開いてください",
    en: "Copied. Paste it into your browser",
    "zh-TW": "已複製，請貼到瀏覽器開啟",
  },
  // オーナー指示 2026-09-15「文字で調べれば検索と名前を変えて」。
  "capture.typeWord": { ja: "検索", en: "Search", "zh-TW": "搜尋" },
  "capture.openScan": {
    ja: "かざして調べる",
    en: "Point to look up",
    "zh-TW": "對準物品查詢",
  },
  // カメラの画面に直接置く検索の欄(オーナー指示 2026-08-26)。
  "capture.searchPlaceholder": { ja: "検索", en: "Search", "zh-TW": "搜尋" },
  "capture.or": { ja: "または", en: "or", "zh-TW": "或" },
  // --- カメラの上に載る操作(`components/CameraChrome.tsx`) ---
  // オーナー指示 2026-09-15「検索・写真を撮る・スキャンの3つのモードを
  // カメラのアイコンを押した時に表示する」。
  "camera.modeGroup": { ja: "撮り方", en: "Camera mode", "zh-TW": "拍攝模式" },
  /** シャッターの左。**過去に撮った写真**への入口（オーナー指示 2026-09-16）。 */
  "camera.library": { ja: "写真", en: "Photos", "zh-TW": "照片" },
  /** シャッターの右。記号の下に出す短い名前（読み上げは `scan.flipCamera`）。 */
  "camera.flipShort": { ja: "切替", en: "Flip", "zh-TW": "切換" },
  "camera.zoomTo": { ja: "倍率 {x}倍", en: "Zoom to {x}×", "zh-TW": "縮放 {x} 倍" },
  // --- scan ---
  "scan.button": { ja: "スキャン", en: "Scan", "zh-TW": "掃描" },
  "scan.again": { ja: "もう一度", en: "Retake", "zh-TW": "再一次" },
  "scan.found": { ja: "見つかった単語", en: "Words found", "zh-TW": "找到的單字" },
  "scan.searchPlaceholder": {
    ja: "候補に無い？日本語で調べる（例: マンゴー）",
    en: "Not listed? Search in your language (e.g. mango)",
    "zh-TW": "候選裡沒有？用中文查（例：芒果）",
  },
  "scan.searchGo": { ja: "調べる", en: "Search", "zh-TW": "查詢" },
  "scan.voiceLabel": {
    ja: "聞こえた言葉を声で調べる",
    en: "Search by voice",
    "zh-TW": "用說的查聽到的字",
  },
  "scan.owned": { ja: "取得済み", en: "Collected", "zh-TW": "已收集" },
  "scan.new": { ja: "新しい", en: "New", "zh-TW": "新的" },
  "scan.reunion": { ja: "未撮影", en: "No photo yet", "zh-TW": "還沒拍過" },
  "scan.catch": { ja: "キャッチ", en: "Catch", "zh-TW": "捕捉" },
  "scan.addToDex": { ja: "図鑑に追加", en: "Add to Dex", "zh-TW": "加入圖鑑" },
  "scan.addShort": { ja: "追加", en: "Add", "zh-TW": "加入" },
  "scan.nextCandidate": { ja: "次の候補", en: "Next candidate", "zh-TW": "下一個候選" },
  "scan.analyzing": { ja: "AIが分析中…", en: "AI is analyzing…", "zh-TW": "AI 分析中…" },
  // AI 分析中の案 E（3つの段）。見る → 読む → 選ぶ。
  "scan.zoom": { ja: "ズーム", en: "Zoom", "zh-TW": "縮放" },
  "scan.flipCamera": {
    ja: "カメラを前後で切り替える",
    en: "Switch front / back camera",
    "zh-TW": "切換前後鏡頭",
  },
  "scan.speakNow": { ja: "話しかけてください", en: "Speak now", "zh-TW": "請開始說話" },
  // --- review extras ---
  // アルバムの編集を終えて保存する。**画面の下に固定**してある
  // （台紙に貼ると、下の札をいじっている人の画面から外れて押せない）。
  /**
   * 一部の設定が保存できなかったとき。**どれが落ちたかを名指しで言う。**
   * 「保存しました」とだけ出すと、次に開いたときに戻っている理由が
   * 誰にも分からない。
   */
  "settings.savedPartly": {
    ja: "一部が保存できませんでした（{fields}）。表の準備がまだかもしれません。",
    en: "Some settings couldn't be saved ({fields}). The table may not be ready yet.",
    "zh-TW": "有一部分沒有存到（{fields}）。資料表可能還沒準備好。",
  },
  // アルバムから外す・戻す（2026-09-28。図鑑からは消えない）
  "album.hide": {
    ja: "「{word}」をアルバムから外す",
    en: 'Remove "{word}" from the album',
    "zh-TW": "把「{word}」從相簿移除",
  },
  "album.hidden": {
    ja: "「{word}」をアルバムから外しました（図鑑には残っています）",
    en: '"{word}" removed from the album (still in your Dex)',
    "zh-TW": "已把「{word}」從相簿移除（圖鑑裡還在）",
  },
  "album.undo": { ja: "元に戻す", en: "Undo", "zh-TW": "復原" },
  "album.hiddenCount": {
    ja: "外した写真（{n}）",
    en: "Removed photos ({n})",
    "zh-TW": "已移除的照片（{n}）",
  },
  "album.restore": {
    ja: "「{word}」をアルバムに戻す",
    en: 'Put "{word}" back in the album',
    "zh-TW": "把「{word}」放回相簿",
  },
  "album.restoreShort": { ja: "戻す", en: "Restore", "zh-TW": "放回" },
  "album.done": { ja: "完了", en: "Done", "zh-TW": "完成" },
  "review.cappedTitle": {
    ja: "今日の分は終わりです",
    en: "That's today's batch",
    "zh-TW": "今天的進度完成了",
  },
  "review.cappedCta": {
    ja: "設定で枚数を変える",
    en: "Change the limit",
    "zh-TW": "到設定調整題數",
  },
  // 10枚の束を出し切っただけのとき。**「今日は終わり」と言ってはいけない** —
  // 上限を無制限にした人にも10枚ごとに出て、設定が効いていないように見えていた。
  "review.moreTitle": {
    ja: "ここまでの分、終わりました",
    en: "That's this batch",
    "zh-TW": "這一輪先到這裡",
  },
  // 残りの数は言わない（オーナー指示 2026-10-02「今日覚えるべき単語などの数字を出すと
  // …やる気がなくなるから出さない」）。
  "review.moreHint": {
    ja: "まだ期限が来ている語があります。続けられます。",
    en: "More words are due. You can keep going.",
    "zh-TW": "還有到複習時間的字，可以繼續。",
  },
  "review.moreCta": { ja: "続ける", en: "Keep going", "zh-TW": "繼續" },
  "review.empty": {
    ja: "今日復習する単語はありません。",
    en: "Nothing to review today.",
    "zh-TW": "今天沒有要複習的單字。",
  },
  "review.emptyHint": {
    ja: "新しい単語をキャッチすると、10分後に最初の復習が出ます。",
    en: "Catch a new word and its first review appears 10 minutes later.",
    "zh-TW": "捕捉到新單字後，10 分鐘後會出現第一次複習。",
  },
  "review.goCatch": { ja: "撮りに行く", en: "Go catch one", "zh-TW": "去拍照收集" },
  // 「ノルマ」は課された量という含意が強く、達成を祝う語ではない(独立監査)。
  "review.doneTitle": {
    ja: "今日の復習、終わりました",
    en: "Today's review is done",
    "zh-TW": "今天的複習結束了",
  },
  "review.doneScore": {
    ja: "{n}問中{c}問が正解",
    en: "{c} of {n} correct",
    "zh-TW": "{n} 題中答對 {c} 題",
  },
  "review.doneHint": {
    ja: "また明日の復習で会いましょう。",
    en: "See you in tomorrow's review.",
    "zh-TW": "明天複習時再見。",
  },
  "review.again": { ja: "もう少し続ける", en: "Keep going", "zh-TW": "再多做一點" },
  "review.toDex": { ja: "図鑑を見る", en: "Open Dex", "zh-TW": "看圖鑑" },
  "review.quizTag": { ja: "4択クイズ", en: "Multiple choice", "zh-TW": "四選一測驗" },
  "review.correct": { ja: "正解！", en: "Correct!", "zh-TW": "答對了！" },
  "review.tryAgain": { ja: "もう一度覚えよう", en: "Let's learn it again", "zh-TW": "再記一次吧" },
  "review.next": { ja: "次へ", en: "Next", "zh-TW": "下一題" },
  "review.openInDex": { ja: "図鑑で見る", en: "Open in Dex", "zh-TW": "在圖鑑查看" },
  // --- memory ---
  "memory.badgeAria": {
    ja: "記憶の状態: {label}（{n}%）",
    en: "Memory: {label} ({n}%)",
    "zh-TW": "記憶狀態：{label}（{n}%）",
  },
  "memory.level0": { ja: "忘れかけ", en: "Fading", "zh-TW": "快忘了" },
  "memory.level1": { ja: "あやうい", en: "Weak", "zh-TW": "有點不穩" },
  "memory.level2": { ja: "うろ覚え", en: "Fuzzy", "zh-TW": "記得模糊" },
  "memory.level3": { ja: "だいたい", en: "Fair", "zh-TW": "大致記得" },
  "memory.level4": { ja: "覚えている", en: "Remembered", "zh-TW": "記得" },
  "memory.level5": { ja: "はっきり", en: "Clear", "zh-TW": "很清楚" },
  "memory.reviews": { ja: "復習", en: "Reviews", "zh-TW": "複習" },
  "memory.times": { ja: "回", en: "×", "zh-TW": "次" },
  // --- word card sections ---
  "card.meaning": { ja: "意味", en: "Meaning", "zh-TW": "意思" },
  "card.web_images": { ja: "ネットの画像", en: "Images from the web", "zh-TW": "網路上的圖片" },
  "card.usage_context": {
    ja: "頻度・使う場面",
    en: "Frequency & where it's used",
    "zh-TW": "頻率、使用場合",
  },
  "card.example": { ja: "例文", en: "Example", "zh-TW": "例句" },
  "card.examples_extra": { ja: "追加の例文", en: "More examples", "zh-TW": "更多例句" },
  "card.usage_chunks": { ja: "使い方チャンク", en: "Usage chunks", "zh-TW": "語塊" },
  "card.measure_words": { ja: "量詞", en: "Measure words", "zh-TW": "量詞" },
  // オーナー指示 2026-08-27 ⑧「項目のタイトルを類義語・反義語・関連語に変更する」。
  // 中の札(類義語/反義語/関連語)と同じ言い方に揃える — 見出しだけ
  // 「にてる言葉」と柔らかいと、**同じ物を2つの名前で呼んでいる**ことになる。
  "card.related_words": {
    ja: "類義語・反義語・関連語",
    en: "Synonyms, antonyms & related",
    "zh-TW": "近義詞、反義詞、相關詞",
  },
  "card.fillCta": { ja: "カードを仕上げる", en: "Finish this card", "zh-TW": "把字卡補完" },
  // 単語の詳細の「意味」に、読む人の言語の意味がまだ無い時（空の箱にしない）。
  "card.meaningPending": {
    ja: "あなたの言語の意味を用意しています…",
    en: "Getting the meaning in your language…",
    "zh-TW": "正在準備你的語言的意思…",
  },
  "card.filling": { ja: "作っています…", en: "Writing it…", "zh-TW": "製作中…" },
  "card.fillFailed": {
    ja: "うまく作れませんでした。通信を確かめて、もう一度お試しください。",
    en: "Couldn't write it. Check your connection and try again.",
    "zh-TW": "沒有順利做出來。請確認網路後再試一次。",
  },
  "card.fillRetry": { ja: "もう一度ためす", en: "Try again", "zh-TW": "再試一次" },
  "card.pronunciation_tips": { ja: "発音のコツ", en: "Pronunciation tips", "zh-TW": "發音訣竅" },
  "card.etymology": { ja: "語源・部首", en: "Origin & radicals", "zh-TW": "字源、部首" },
  // 部首の無い言語(英語)の見出し。**「語源・部首」は英語では嘘。**
  "card.etymologyOnly": { ja: "語源", en: "Word origin", "zh-TW": "字源" },
  "card.mnemonic": { ja: "覚え方", en: "Memory hook", "zh-TW": "記憶方法" },
  "card.taiwan_note": { ja: "台湾メモ", en: "Taiwan note", "zh-TW": "台灣筆記" },
  "card.real_usage": { ja: "実際の使われ方", en: "Seen in the wild", "zh-TW": "實際上怎麼用" },
  // --- 英語のカードだけの節 ------------------------------------------------
  // 台湾華語のカードには出ない。**それでも3言語ぶん訳す** — 英語を学ぶ
  // 台湾の人はアプリを繁體中文で使うので、節の名前が日本語で出たら
  // その人の画面が壊れている。
  "card.forms": { ja: "活用", en: "Word forms", "zh-TW": "詞形變化" },
  "card.countability": { ja: "数え方と冠詞", en: "Countability", "zh-TW": "可數與冠詞" },
  "card.stress": { ja: "強く読む所", en: "Stress", "zh-TW": "重音" },
  "card.phrasal_verbs": { ja: "句動詞", en: "Phrasal verbs", "zh-TW": "片語動詞" },
  "card.culture_note": { ja: "文化の一言", en: "Culture note", "zh-TW": "文化筆記" },
  // --- 日本語のカードだけの節(2026-10-01) ---------------------------------
  // 日本語を学ぶのは英語か繁體中文で読む人なので、その2つが本番の文言。
  "card.kanji_breakdown": { ja: "漢字の内訳", en: "Kanji breakdown", "zh-TW": "漢字拆解" },
  "card.pitch_accent": { ja: "高低アクセント", en: "Pitch accent", "zh-TW": "高低重音" },
  "card.conjugation": { ja: "活用", en: "Conjugation", "zh-TW": "動詞與形容詞變化" },
  "card.politeness": { ja: "丁寧さ・敬語", en: "Politeness & keigo", "zh-TW": "禮貌程度與敬語" },
  "card.counters": { ja: "助数詞", en: "Counters", "zh-TW": "助數詞" },
  "card.word_origin": { ja: "語種", en: "Word origin type", "zh-TW": "詞的來源類型" },
  "card.japan_note": { ja: "日本メモ", en: "Japan note", "zh-TW": "日本筆記" },
  // 活用の名前。**表の左の列**に出る短い名前で、文にしない。
  "card.formPlural": { ja: "複数形", en: "Plural", "zh-TW": "複數" },
  "card.formPast": { ja: "過去形", en: "Past", "zh-TW": "過去式" },
  "card.formPastParticiple": { ja: "過去分詞", en: "Past participle", "zh-TW": "過去分詞" },
  "card.formIng": { ja: "-ing 形", en: "-ing form", "zh-TW": "-ing 形" },
  "card.formThird": { ja: "三単現", en: "3rd person", "zh-TW": "第三人稱單數" },
  "card.formComparative": { ja: "比較級", en: "Comparative", "zh-TW": "比較級" },
  "card.formSuperlative": { ja: "最上級", en: "Superlative", "zh-TW": "最高級" },
  // 数え方。
  "card.countable": { ja: "数えられる", en: "Countable", "zh-TW": "可數" },
  "card.uncountable": { ja: "数えられない", en: "Uncountable", "zh-TW": "不可數" },
  "card.countBoth": { ja: "どちらもある", en: "Both", "zh-TW": "兩者皆可" },
  "card.article": { ja: "冠詞", en: "Article", "zh-TW": "冠詞" },
  "card.sections": {
    ja: "表示する項目と順番",
    en: "Sections & order",
    "zh-TW": "要顯示的項目與順序",
  },
  "card.regen": {
    ja: "この項目をAIで作り直す(Pro)",
    en: "Regenerate this section (Pro)",
    "zh-TW": "用 AI 重做這個項目（Pro）",
  },
  // 口語⇄書面の札（card.register / card.reg*）は 2026-10-15 に画面から外した（オーナー決定）。
  // 「今週出会う見込み」とレア度。**数字と出所は必ず同じ画面に居させる。**
  // 出所。**推定を実測の顔で出さない。**
  // 〇〇限定（オーナー指示 2026-08-27 ⑤「台南限定、台湾限定、ポケモンの
  // 〇〇地方のポケモンみたいな」）。その語を持っていること自体が珍しい、
  // という話なので、場面の札とは別格に出す。
  "card.limitedTo": { ja: "{place}限定", en: "{place} only", "zh-TW": "{place}限定" },
  "card.season.spring": { ja: "春", en: "spring", "zh-TW": "春天" },
  "card.season.summer": { ja: "夏", en: "summer", "zh-TW": "夏天" },
  "card.season.autumn": { ja: "秋", en: "autumn", "zh-TW": "秋天" },
  "card.season.winter": { ja: "冬", en: "winter", "zh-TW": "冬天" },
  "card.encKind.limited": { ja: "限定", en: "Only here", "zh-TW": "限定" },
  "card.encounterLabels": {
    ja: "出会いやすい所",
    en: "Where you'll meet it",
    "zh-TW": "容易遇到的地方",
  },
  "card.encKind.place": { ja: "場所", en: "Place", "zh-TW": "地點" },
  "card.encKind.media": { ja: "媒体", en: "Media", "zh-TW": "媒介" },
  "card.encKind.situation": { ja: "状況", en: "Situation", "zh-TW": "情境" },
  "card.encKind.emotion": { ja: "気持ち", en: "Feeling", "zh-TW": "心情" },
  "card.encKind.time": { ja: "時刻", en: "Time", "zh-TW": "時間" },
  "card.encKind.season": { ja: "季節", en: "Season", "zh-TW": "季節" },
  "card.encKind.trait": { ja: "性質", en: "What it's like", "zh-TW": "性質" },
  // 束の見出し(オーナー指示 2026-08-28 ②「それぞれのカテゴライズを
  // 同じように表示すると混乱するから…表示を工夫して」)。
  // **問いの形で置く。** 「場所」より「どこで」のほうが、その札が何に
  // 答えている物なのかが分かる。
  "card.axis.limited": { ja: "ここだけ", en: "Only here", "zh-TW": "只有這裡" },
  "card.axis.where": { ja: "どこで", en: "Where", "zh-TW": "在哪裡" },
  "card.axis.when": { ja: "いつ", en: "When", "zh-TW": "什麼時候" },
  "card.axis.scene": { ja: "どんな場面で", en: "In what situation", "zh-TW": "什麼場合" },
  "card.axis.trait": { ja: "どんな物か", en: "What it's like", "zh-TW": "是什麼樣的東西" },
  "card.axis.feeling": { ja: "どんな気持ちで", en: "With what feeling", "zh-TW": "什麼心情" },
  "card.frequency": { ja: "頻度", en: "Frequency", "zh-TW": "頻率" },
  // オーナー指示 2026-08-27 ⑧「項目のタイトルを類義語・反義語・関連語に
  // 変更する」。「類義」だけでは何の一覧なのかが読み取れない。
  "card.synonym": { ja: "類義語", en: "Synonyms", "zh-TW": "近義詞" },
  "card.antonym": { ja: "反義語", en: "Antonyms", "zh-TW": "反義詞" },
  "card.relatedTag": { ja: "関連語", en: "Related words", "zh-TW": "相關詞" },
  // 語根・接頭辞・接尾辞の仲間(学習言語が英語のときだけ出る)。
  "card.etymologyRelatives": {
    ja: "同じ部品を持つ語",
    en: "Words sharing the parts",
    "zh-TW": "有相同部件的字",
  },
  "card.radicals": { ja: "部首", en: "Radicals", "zh-TW": "部首" },
  "card.noImages": {
    ja: "画像が見つかりませんでした。",
    en: "No images found.",
    "zh-TW": "找不到圖片。",
  },
  "card.searchGoogle": {
    ja: "Google画像検索で見る",
    en: "See on Google Images",
    "zh-TW": "用 Google 圖片搜尋看看",
  },
  "card.delete": { ja: "削除", en: "Delete", "zh-TW": "刪除" },
  "card.deleteConfirm": {
    ja: "もう一度タップで削除",
    en: "Tap again to delete",
    "zh-TW": "再點一次就刪除",
  },
  "card.changePhoto": { ja: "写真を変更", en: "Change photo", "zh-TW": "更換照片" },
  "card.report": { ja: "報告", en: "Report", "zh-TW": "回報" },
  "card.reportWhat": { ja: "どこが違う？", en: "What's wrong?", "zh-TW": "哪裡不對？" },
  "card.regenAll": {
    ja: "✨ 解説を再生成",
    en: "✨ Regenerate details",
    "zh-TW": "✨ 重新產生解說",
  },
  "card.regenPro": {
    ja: "解説の再生成は Pro 限定",
    en: "Regenerating details is Pro-only",
    "zh-TW": "重新產生解說是 Pro 限定",
  },
  "card.enrichFailed": {
    ja: "詳しい解説を作れませんでした",
    en: "Couldn't generate the details",
    "zh-TW": "無法產生詳細解說",
  },
  "card.enrichRetry": { ja: "もう一度ためす", en: "Try again", "zh-TW": "再試一次" },
  // --- home ---
  "install.title": {
    ja: "アプリとしてスマホに入れる",
    en: "Install as an app",
    "zh-TW": "安裝成手機 App",
  },
  "install.bannerTitle": {
    ja: "CatchWords をホーム画面に",
    en: "Add CatchWords to your home screen",
    "zh-TW": "把 CatchWords 加到主畫面",
  },
  "install.why": {
    ja: "ホーム画面のアイコンから、アプリのように全画面ですぐ開けます。",
    en: "Open it full screen from your home screen, just like an app.",
    "zh-TW": "從主畫面的圖示就能像 App 一樣全螢幕開啟。",
  },
  "install.button": { ja: "インストール", en: "Install", "zh-TW": "安裝" },
  "install.done": {
    ja: "インストール済みです。",
    en: "Already installed.",
    "zh-TW": "已安裝。",
  },
  "install.iosStep1": {
    ja: "Safari の共有ボタンを押す（見当たらない時は「…」の中）",
    en: "Tap Share in Safari (inside “…” if you don't see it)",
    "zh-TW": "點 Safari 的分享按鈕（找不到時在「…」裡）",
  },
  "install.iosStep2": {
    ja: "「ホーム画面に追加」を選ぶ",
    en: "Choose “Add to Home Screen”",
    "zh-TW": "選擇「加入主畫面」",
  },
  "install.iosStep3": {
    ja: "右上の「追加」を押す",
    en: "Tap “Add” in the top right",
    "zh-TW": "點右上角的「新增」",
  },
  "install.androidStep1": {
    ja: "Chrome の右上のメニュー（︙）を押す",
    en: "Tap the menu (⋮) in Chrome",
    "zh-TW": "點 Chrome 右上角的選單（⋮）",
  },
  "install.androidStep2": {
    ja: "「アプリをインストール」か「ホーム画面に追加」を選ぶ",
    en: "Choose “Install app” or “Add to Home screen”",
    "zh-TW": "選擇「安裝應用程式」或「加到主畫面」",
  },
  "install.desktopStep": {
    ja: "アドレスバーの右のインストールの印を押す",
    en: "Click the install icon at the right of the address bar",
    "zh-TW": "點網址列右側的安裝圖示",
  },
  "install.inApp": {
    ja: "LINE などのアプリの中では入れられません。右上のメニューから「Safari（または Chrome）で開く」を選んでください。",
    en: "You can't install from inside apps like LINE. Use the menu to open this page in Safari or Chrome.",
    "zh-TW": "在 LINE 等 App 內無法安裝。請從選單選擇「用 Safari（或 Chrome）開啟」。",
  },
  "home.emptyCta": { ja: "今日の一枚を撮る", en: "Take today's photo", "zh-TW": "拍下今天的一張" },
  // 白紙の日の一言（オーナー指示 2026-09-23、`lib/home-blank.ts`）。
  "home.blankLearnOne": {
    ja: "今日も知らない単語を1つ覚えよう！",
    en: "Learn one new word today!",
    "zh-TW": "今天也來記一個新單字吧！",
  },
  "home.blankWhatIsThat": {
    ja: "目の前にあるもの、何て言う？",
    en: "What's the word for what's in front of you?",
    "zh-TW": "眼前的東西，要怎麼說？",
  },
  "home.blankStreak": {
    ja: "{n}日連続で新しい単語に出会っています！",
    en: "You've met new words {n} {n|day|days} in a row!",
    "zh-TW": "已經連續 {n} 天遇見新單字了！",
  },
  "home.blankNth": {
    ja: "{n}枚目の単語を記録してみよう！",
    en: "Catch your word No. {n}!",
    "zh-TW": "來記錄第 {n} 個單字吧！",
  },
  // 見開きの右ページ(ホームでその場で書く)。
  // これまでのページの束ね方(src/lib/album-span.ts)。
  // 日本語の画面に英語の飾り文字を置かない(日付の見出しと同じ理由)。
  "home.pastPages": { ja: "これまでのページ", en: "Past Pages", "zh-TW": "以前的頁面" },
  // 雑誌の表紙(オーナー指示 2026-09-17「ホームのデザインを雑誌や
  // ホームアルバム風にしたい」「一番上には今日の日付を書いて」)。
  // 右上の数字（これまでに捕まえた語）。裸の数字では何の数か分からないので
  // 小さく添える（見本の絵は裸だが、実物では読む人が意味を取れない）。
  // 表紙の手書きの一言。**手元に在る事実だけで書く** — その日いちばん多く
  // 出てくる場所の名前と、語の数。場所が1つも無い日は場所を言わない。
  "home.tagline": {
    ja: "今日は{n}つの言葉に出会った。",
    en: "Caught {n} {n|word|words} today.",
    "zh-TW": "今天遇到了 {n} 個字。",
  },
  "home.taglineAt": {
    ja: "{place}で、{n}つの言葉に出会った。",
    en: "{n} {n|word|words}, around {place}.",
    "zh-TW": "在{place}，遇到了 {n} 個字。",
  },
  "home.background": { ja: "ホームの壁紙", en: "Home wallpaper", "zh-TW": "首頁桌布" },
  // --- common ---
  "common.close": { ja: "閉じる", en: "Close", "zh-TW": "關閉" },
  // ヘッダーのアイコンを押すと出る、自分の記録。
  "me.open": { ja: "自分の記録を見る", en: "See your record", "zh-TW": "看自己的紀錄" },
  "me.you": { ja: "あなた", en: "You", "zh-TW": "你" },
  // **撮った連続と復習した連続は別の数。** 片方だけ「続いている」と書くと
  // どちらのことか分からない(要望の「連続何日」は復習のほう)。
  "me.captureStreak": {
    ja: "撮った日が続いている",
    en: "Capture streak",
    "zh-TW": "連續拍照的天數",
  },
  "me.reviewStreak": {
    ja: "復習した日が続いている",
    en: "Review streak",
    "zh-TW": "連續複習的天數",
  },
  "me.days": { ja: "{n}日", en: "{n} {n|day|days}", "zh-TW": "{n} 天" },
  "me.captured": { ja: "集めた言葉", en: "Words caught", "zh-TW": "收集到的字" },
  "me.level": { ja: "レベル", en: "Level", "zh-TW": "等級" },
  // **やった数と待っている数を混ぜない。** 「今日の復習」で待っている数を
  // 出していたので、やった数と読めてしまっていた。
  "me.doneToday": { ja: "今日やった復習", en: "Reviewed today", "zh-TW": "今天做的複習" },
  "me.due": { ja: "待っている復習", en: "Waiting", "zh-TW": "等著複習的" },
  "common.loading": { ja: "読み込み中", en: "Loading", "zh-TW": "載入中" },
  // 規約・プライバシーの繁體中文版はまだ無い（法的な文なので機械訳しない）。
  // アルバムに書き込む（試作、`AlbumInk`）。
  // 日記の字体（`diary-fonts.ts`。2026-09-28「本物の手書きのような字体…選べて」）
  "diary.fontHand": { ja: "手書き", en: "Handwritten", "zh-TW": "手寫" },
  "diary.fontPencil": { ja: "えんぴつ", en: "Pencil", "zh-TW": "鉛筆" },
  "diary.fontCasual": { ja: "ゆるい", en: "Casual", "zh-TW": "隨手寫" },
  "diary.fontBrush": { ja: "楷書", en: "Brush", "zh-TW": "楷書" },
  "diary.fontPlain": { ja: "ふつう", en: "Plain", "zh-TW": "一般" },
  // 法務の3つの頁（2026-10-03。本文は components/legal/ の言語ごとの文書）。
  "legal.tokushoho": {
    ja: "特定商取引法に基づく表記",
    en: "Legal notice (Specified Commercial Transactions Act)",
    "zh-TW": "特定商業交易法標示",
  },
  "legal.support": { ja: "お問い合わせ・サポート", en: "Contact & Support", "zh-TW": "聯絡與支援" },
  "legal.linksAria": { ja: "規約と表記", en: "Legal documents", "zh-TW": "條款與標示" },
  "legal.sectionTitle": { ja: "規約と表記", en: "Legal", "zh-TW": "條款與標示" },
  "legal.langSwitchAria": { ja: "表示言語", en: "Language", "zh-TW": "顯示語言" },
  // 待ちの演出の3段。**どの版でも同じ言葉を使う** — 版ごとに直書きしていた
  // せいで、英語にしても日本語のままの版が7つ残っていた(オーナー指摘 2026-08-20)。
  "scan.stageSensing": {
    ja: "シーンを感知しています",
    en: "Sensing the scene…",
    "zh-TW": "正在感測場景",
  },
  "scan.stageReading": {
    ja: "対象を解析しています",
    en: "Reading the object…",
    "zh-TW": "正在解析對象",
  },
  "scan.stageMatching": {
    ja: "辞書と照合しています",
    en: "Matching the dictionary…",
    "zh-TW": "正在跟辭典比對",
  },
  // 結晶の版だけは言葉づかいが違う(そういう演出として作ってある)。
  "scan.crystalSensing": {
    ja: "銀の露をひろげています",
    en: "Spreading silver dew…",
    "zh-TW": "銀色的露珠正在散開",
  },
  "scan.crystalReading": {
    ja: "世界を読んでいます",
    en: "Reading the world…",
    "zh-TW": "正在閱讀這個世界",
  },
  "scan.crystalMatching": {
    ja: "言葉が結晶化します",
    en: "Words are crystallizing…",
    "zh-TW": "文字要結晶了",
  },
  // 全画面の版は短い言い切り。
  "scan.fullSensing": { ja: "空間を捉える", en: "Catching the space", "zh-TW": "捕捉空間" },
  "scan.fullReading": {
    ja: "文字と物を読む",
    en: "Reading words and things",
    "zh-TW": "讀取文字與物體",
  },
  "scan.fullMatching": {
    ja: "中文と照合",
    en: "Matching Mandarin",
    "zh-TW": "與中文比對",
  },
  "scan.justAMoment": { ja: "少しだけ待ってね", en: "Just a moment", "zh-TW": "再等一下下喔" },
  "common.cancel": { ja: "キャンセル", en: "Cancel", "zh-TW": "取消" },
  // 見出し語を直す(オーナー指示 2026-08-26「単語のカードの見出しの単語自体を
  // 変更できるようにして」)。AI が別の語を当てたときに、その場で直せる。
  "card.editHead": { ja: "単語を直す", en: "Edit the word", "zh-TW": "修改單字" },
  "card.editHeadSave": { ja: "直す", en: "Save", "zh-TW": "儲存" },
  "caption.edit": { ja: "ひと言を直す", en: "Edit the note", "zh-TW": "修改一句話" },
  "caption.add": { ja: "ひと言を書く", en: "Add a note", "zh-TW": "寫一句話" },
  "caption.editTitle": { ja: "ひと言", en: "Note", "zh-TW": "一句話" },
  "caption.editHint": {
    ja: "空にして保存すると、ひと言を消します。",
    en: "Save it empty to remove the note.",
    "zh-TW": "清空後儲存，就會刪除這句話。",
  },
  "caption.save": { ja: "保存", en: "Save", "zh-TW": "儲存" },
  "caption.saved": { ja: "ひと言を保存しました", en: "Note saved", "zh-TW": "已儲存這句話" },
  "caption.failed": {
    ja: "ひと言を保存できませんでした",
    en: "Couldn't save the note",
    "zh-TW": "無法儲存這句話",
  },
  "card.editHeadDone": { ja: "単語を直しました", en: "Word updated", "zh-TW": "已修改單字" },
  "card.editHeadNotTarget": {
    ja: "学習している言語の単語を入れてください",
    en: "Enter a word in the language you are learning",
    "zh-TW": "請輸入你正在學的語言的單字",
  },
  "common.retry": { ja: "もう一度", en: "Retry", "zh-TW": "再一次" },
  // --- word card (extra) ---
  "card.generate": { ja: "作る", en: "Generate", "zh-TW": "產生" },
  "card.flipToSelfie": {
    ja: "タップで自撮りへ",
    en: "Tap to flip to selfie",
    "zh-TW": "點一下看自拍",
  },
  "card.flipBack": { ja: "タップで戻る", en: "Tap to flip back", "zh-TW": "點一下翻回去" },
  "card.selfie": { ja: "自撮り", en: "Selfie", "zh-TW": "自拍" },
  "card.noSelfie": { ja: "自撮りはまだありません", en: "No selfie yet", "zh-TW": "還沒有自拍" },
  "card.changePhotoConfirm": {
    ja: "この写真を変更しますか？",
    en: "Change this photo?",
    "zh-TW": "要更換這張照片嗎？",
  },
  "card.replacePhotoConfirm": {
    ja: "いまの写真を、この画像に差し替えますか？元には戻せません。",
    en: "Replace the current photo with this image? This can't be undone.",
    "zh-TW": "要把現在的照片換成這張圖片嗎？換了就回不去了。",
  },
  "card.deleteConfirmDialog": {
    ja: "本当に削除しますか？この操作は取り消せません。",
    en: "Delete this card? This cannot be undone.",
    "zh-TW": "確定要刪除嗎？這個動作無法復原。",
  },
  "card.deleteFailed": {
    ja: "削除に失敗しました。",
    en: "Could not delete.",
    "zh-TW": "刪除失敗。",
  },
  "card.photoFailed": {
    ja: "画像の変更に失敗しました。",
    en: "Could not change the photo.",
    "zh-TW": "更換圖片失敗。",
  },
  "card.pickAnotherImage": {
    ja: "この画像が違うときは、別の画像を選べます",
    en: "Not the right picture? Pick another one",
    "zh-TW": "如果這張圖不對，可以選別的",
  },
  "card.findingImage": {
    ja: "🌐 画像をネットから探しています…",
    en: "🌐 Finding an image online…",
    "zh-TW": "🌐 正在從網路上找圖片…",
  },
  // 自動の1枚を入れられなかった時（前は「探しています…」のまま止まった。2026-10-07）。
  "card.imageNotFound": {
    ja: "画像を見つけられませんでした。下から選ぶか、写真を撮ってください",
    en: "Couldn't find an image. Pick one below or take a photo",
    "zh-TW": "找不到圖片。請從下面選一張，或拍一張照片",
  },
  // Pro の「AIで絵を作る」（オーナー指示 2026-10-07）。
  "card.aiImage": { ja: "AIで絵を作る", en: "Make a picture with AI", "zh-TW": "用 AI 畫一張圖" },
  "card.aiImageMaking": {
    ja: "AIで絵を作っています…",
    en: "Making a picture with AI…",
    "zh-TW": "正在用 AI 畫圖…",
  },
  "card.aiImageDone": {
    ja: "AIで作った絵にしました",
    en: "Now using the AI picture",
    "zh-TW": "已換成 AI 畫的圖",
  },
  "card.aiImageFailed": {
    ja: "AIで絵を作れませんでした。",
    en: "Couldn't make a picture with AI.",
    "zh-TW": "無法用 AI 畫圖。",
  },
  "card.regenerating": { ja: "再生成中…", en: "Regenerating…", "zh-TW": "重新產生中…" },
  "card.reportFixing": { ja: "確かめています…", en: "Checking…", "zh-TW": "確認中…" },
  "card.reportFixed": {
    ja: "「{item}」を直しました",
    en: "Fixed “{item}”",
    "zh-TW": "已修正「{item}」",
  },
  "card.reportQueued": {
    ja: "報告を受け付けました。確かめてから直します",
    en: "Report received. We'll check it before changing anything",
    "zh-TW": "已收到回報，確認後會修正",
  },
  "card.reportFailed": {
    ja: "報告に失敗しました",
    en: "Could not send the report",
    "zh-TW": "回報失敗",
  },
  "card.otherImages": { ja: "別の画像", en: "Other images", "zh-TW": "其他圖片" },
  "card.useThisImage": { ja: "この画像にする", en: "Use this image", "zh-TW": "就用這張" },
  "card.imageSet": { ja: "画像を変更しました", en: "Photo updated", "zh-TW": "已更換圖片" },
  "card.openMap": { ja: "地図で開く", en: "Open in Maps", "zh-TW": "用地圖打開" },
  "card.openGoogleMaps": {
    ja: "Google マップで開く →",
    en: "Open in Google Maps →",
    "zh-TW": "用 Google 地圖打開 →",
  },
  "card.photoSpot": { ja: "撮影地", en: "Where it was caught", "zh-TW": "拍攝地" },
  // --- input catch ---
  /**
   * **学習言語の名前を差し込む**（オーナー報告 2026-08-26
   * 「学習言語英語…検索に台湾華語を入力してもエラーが起きて、英単語が
   * 表示されない」）。
   *
   * ここは「中文の単語が見つかりませんでした」と決め打ちだったので、
   * **英語を学んでいる人にも中文の話をしていた**。探しに行った先も
   * 出す名前も英語なのに、返る言葉だけが中国語 —
   * 打った人には壊れているようにしか見えない。
   */
  "input.notTargetLang": {
    ja: "{lang}の単語が見つかりませんでした。別の言い方で調べてみてください。",
    en: "Couldn't find a {lang} word for that. Try describing it differently.",
    "zh-TW": "找不到{lang}的單字。請換個說法查查看。",
  },
  "dex.movedTo": {
    ja: "「{word}」を{cat}へ移しました",
    en: "Moved “{word}” to {cat}",
    "zh-TW": "已將「{word}」移到{cat}",
  },
  "shelf.home.label": {
    ja: "月ごとのアルバムの本棚",
    en: "Monthly album shelf",
    "zh-TW": "每月相簿書架",
  },
  "shelf.home.building": {
    ja: "本棚を組み立てています…",
    en: "Setting up the shelf…",
    "zh-TW": "正在擺好書架…",
  },
  "shelf.home.failed": {
    ja: "本棚を表示できませんでした",
    en: "Couldn't show the shelf",
    "zh-TW": "無法顯示書架",
  },
  "shelf.home.back": { ja: "棚に戻す", en: "Put back", "zh-TW": "放回書架" },
  "shelf.home.pageView": { ja: "ページの見せ方", en: "Page view", "zh-TW": "頁面顯示方式" },
  "shelf.home.spread": { ja: "見開き", en: "Spread", "zh-TW": "跨頁" },
  "shelf.home.single": { ja: "片ページ", en: "One page", "zh-TW": "單頁" },
  "shelf.home.backToSpread": { ja: "見開きに戻る", en: "Back to spread", "zh-TW": "回到跨頁" },
  "shelf.home.prev": { ja: "前のページ", en: "Previous page", "zh-TW": "上一頁" },
  "shelf.home.next": { ja: "次のページ", en: "Next page", "zh-TW": "下一頁" },
  "shelf.home.leftPage": { ja: "左のページ", en: "Left page", "zh-TW": "左頁" },
  "shelf.home.rightPage": { ja: "右のページ", en: "Right page", "zh-TW": "右頁" },
  "shelf.home.cover": { ja: "表紙", en: "Cover", "zh-TW": "封面" },
  // 本の左ページを長押しして開く、ホームと同じ並べ替えの画面（2026-10-02）。
  "shelf.home.arrange": { ja: "アルバムの配置", en: "Arrange the album", "zh-TW": "相簿的排法" },
  "shelf.home.arrangeHint": {
    ja: "ホームのアルバムと同じ置き方。「完了」で本にも反映されます。",
    en: "Same layout as the home album. “Done” updates the book too.",
    "zh-TW": "和首頁相簿同一種排法。按「完成」後書裡也會更新。",
  },

  "shelf.home.pencilSkip": {
    ja: "タップで書き終える",
    en: "Tap to finish writing",
    "zh-TW": "點一下寫完",
  },
  "shelf.home.diaryFont": { ja: "日記の字体", en: "Diary font", "zh-TW": "日記字體" },
  "shelf.home.writeDiary": { ja: "日記を書く", en: "Write a diary", "zh-TW": "寫日記" },
  "shelf.home.rewriteDiary": { ja: "日記を書き直す", en: "Edit the diary", "zh-TW": "修改日記" },
  "shelf.home.diaryOf": { ja: "{date}の日記", en: "Diary for {date}", "zh-TW": "{date}的日記" },
  "shelf.home.cancel": { ja: "やめる", en: "Cancel", "zh-TW": "取消" },
  "shelf.home.writeOnPage": { ja: "ページに書く", en: "Write on the page", "zh-TW": "寫到頁面上" },
  "shelf.home.saveFailed": {
    ja: "日記を保存できませんでした",
    en: "Couldn't save the diary",
    "zh-TW": "無法儲存日記",
  },
  "shelf.home.titlePage": {
    ja: "{n}日ぶんの見開き",
    en: "{n} {n|day|days} of spreads",
    "zh-TW": "{n}天的跨頁",
  },
  "dex.moveFailed": {
    ja: "移せませんでした。もう一度試してください",
    en: "Couldn't move it. Please try again.",
    "zh-TW": "無法移動，請再試一次。",
  },
  // --- dex view labels ---
  "dex.gallery": { ja: "ギャラリー表示", en: "Gallery view", "zh-TW": "圖片檢視" },
  "dex.list": { ja: "リスト表示", en: "List view", "zh-TW": "清單檢視" },
  "dex.map": { ja: "地図表示", en: "Map view", "zh-TW": "地圖檢視" },
  "dex.searchAria": { ja: "図鑑を検索", en: "Search Dex", "zh-TW": "搜尋圖鑑" },
  // 図鑑の絞り込み(オーナー指摘 2026-08-21「ボタンを押したら選択肢が
  // 出てきて選べるように」)。ボタンの名前は**選んでいないときに出る名前**。
  // 本棚(オーナー指摘 2026-08-21「リアルな本の本棚を作って、背表紙の
  //  タイトルが見えるように」)。読み上げ用の棚の名前。
  "shelf.books": { ja: "単語帳の本棚", en: "Wordbook shelf", "zh-TW": "單字本的書架" },
  // 見込みの幅(オーナー指摘 2026-08-21「適当すぎる」)。
  // **点だけを信じさせない** — 人が増えれば幅は狭くなる。
  // ホームの本棚と見開き(オーナー指摘 2026-08-21 ⑬⑭)。
  "dex.filterCategory": { ja: "カテゴリー", en: "Category", "zh-TW": "分類" },
  "dex.filterDay": { ja: "日付", en: "Date", "zh-TW": "日期" },
  "dex.filterOpen": { ja: "{name}を選ぶ", en: "Choose {name}", "zh-TW": "選擇{name}" },
  "dex.filterClearAll": {
    ja: "絞り込みをすべて解除",
    en: "Clear all filters",
    "zh-TW": "清除所有篩選",
  },
  "dex.clearSearch": { ja: "検索をクリア", en: "Clear search", "zh-TW": "清除搜尋" },
  "dex.noMatch": {
    ja: "に一致する単語はありません。",
    en: "— no matching words.",
    "zh-TW": "沒有符合的單字。",
  },
  "dex.emptyTitle": {
    ja: "まだ何もキャッチしていません。",
    en: "Nothing caught yet.",
    "zh-TW": "還沒有捕捉到任何東西。",
  },
  "dex.emptyHint": {
    ja: "街で見かけた言葉にカメラをかざすと、ここに図鑑が育ちます。",
    en: "Point the camera at words around you and your Dex starts growing.",
    "zh-TW": "把相機對準在街上看到的東西，圖鑑就會慢慢豐富起來。",
  },
  "dex.emptyCta": { ja: "最初の一枚を撮る", en: "Take your first photo", "zh-TW": "拍下第一張" },
  // 学習言語を変えて図鑑が空になったとき。**「まだ何もキャッチして
  // いません」は嘘**で、その人は別の言語で何十枚も持っている。
  // 集めた物が消えたように見える画面はこのアプリで一番やってはいけない。
  "dex.emptyOtherLangTitle": {
    ja: "{lang}の図鑑はまだ空です。",
    en: "Your {lang} Dex is still empty.",
    "zh-TW": "{lang}的圖鑑還是空的。",
  },
  "dex.emptyOtherLangHint": {
    ja: "ほかの学習言語に {n} 枚あります。設定で学習言語を戻すと、そちらが見えます。",
    en: "You have {n} in another target language. Switch back in Settings to see them.",
    "zh-TW": "另一個學習語言裡有 {n} 張。到設定切回去就看得到。",
  },
  "dex.emptyOtherLangCta": {
    ja: "学習言語を変える",
    en: "Change target language",
    "zh-TW": "更改學習語言",
  },
  // --- settings (admin) ---
  "settings.devOnly": {
    ja: "開発者専用（あなたにしか表示されません）",
    en: "Developer only (visible to you alone)",
    "zh-TW": "開發者專用（只有你看得到）",
  },
  "settings.themeCompare": {
    ja: "配色デザイン（開発者のみ）",
    en: "Color design (developers only)",
    "zh-TW": "配色設計（僅限開發者）",
  },
  "settings.themeKeep": { ja: "保持", en: "Kept", "zh-TW": "保留" },
  "aiStats.heading": {
    ja: "速さと正確さ（モデルごと）",
    en: "Speed and accuracy by model",
    "zh-TW": "各模型的速度與準確度",
  },
  "aiStats.note": {
    ja: "実際に使われた分から数えます（機能 → 用途 → モデル）。モデルを切り替えると行が増えるので、前後を見比べられます。時間は AI に頼んでから答えが返るまで。写真・語・文は記録しません。",
    en: "Counted from real use (feature → task → model). Switching a model adds a new row, so you can compare before and after. Time runs from the request to the AI until its answer arrives. Photos, words and text are not recorded.",
    "zh-TW":
      "依實際使用統計（功能 → 用途 → 模型）。切換模型後會多出一列，可以比較前後。時間是從向 AI 提出請求到回答傳回為止。不記錄照片、單字與文字。",
  },
  "aiStats.period": {
    ja: "期間",
    en: "Period",
    "zh-TW": "期間",
  },
  "aiStats.days": {
    ja: "{n}日",
    en: "{n} d",
    "zh-TW": "{n} 天",
  },
  "aiStats.mine": {
    ja: "自分の分だけ",
    en: "Only my own use",
    "zh-TW": "只看自己的使用",
  },
  "aiStats.loadFailed": {
    ja: "読み込めませんでした",
    en: "Couldn't load",
    "zh-TW": "無法載入",
  },
  "aiStats.empty": {
    ja: "この期間の記録はまだありません。AI を使う機能を使うと、ここに数が出ます（この画面ができた後の分から）。",
    en: "No records for this period yet. Numbers appear here once AI features are used (counting starts with this update).",
    "zh-TW": "這段期間還沒有紀錄。使用 AI 功能後，數字會出現在這裡（從這次更新之後開始計算）。",
  },
  "aiStats.truncated": {
    ja: "記録が多いため、一部だけで数えています。",
    en: "Too many records — counted from part of them.",
    "zh-TW": "紀錄太多，只用其中一部分計算。",
  },
  "aiStats.other": {
    ja: "その他",
    en: "Other",
    "zh-TW": "其他",
  },
  "aiStats.current": {
    ja: "いま",
    en: "Now",
    "zh-TW": "目前",
  },
  "aiStats.speed": {
    ja: "{n}回 · 成功 {ok}% · 中央値 {p50}秒 · 90% {p90}秒",
    en: "{n} {n|call|calls} · {ok}% OK · median {p50}s · 90% {p90}s",
    "zh-TW": "{n} 次 · 成功 {ok}% · 中位數 {p50} 秒 · 90% {p90} 秒",
  },
  "aiStats.timeouts": {
    ja: "時間切れ {n}",
    en: "{n} timed out",
    "zh-TW": "逾時 {n}",
  },
  "aiStats.failed": {
    ja: "失敗 {n}",
    en: "{n} failed",
    "zh-TW": "失敗 {n}",
  },
  "aiStats.cancelled": {
    ja: "追いかけで取り消し {n}",
    en: "{n} cancelled (hedge)",
    "zh-TW": "因並行而取消 {n}",
  },
  "aiStats.picks": {
    ja: "候補の当たり: 1番目 {top1}% · 3番目まで {top3}%（選んだ {n} 回）",
    en: "Picks: 1st {top1}% · top 3 {top3}% ({n} {n|pick|picks})",
    "zh-TW": "候選命中：第 1 個 {top1}% · 前 3 個 {top3}%（選了 {n} 次）",
  },
  "aiStats.unusable": {
    ja: "使えない返事 {p}%（{n}/{of}）",
    en: "Unusable replies {p}% ({n}/{of})",
    "zh-TW": "無法使用的回應 {p}%（{n}/{of}）",
  },
  "aiStats.cost": {
    ja: "1回 約 ${c}",
    en: "~${c} per call",
    "zh-TW": "每次約 ${c}",
  },
  "aiStats.tokens": {
    ja: "入力 {i} · 出力 {o} トークン",
    en: "{i} in · {o} out tokens",
    "zh-TW": "輸入 {i} · 輸出 {o} 個 token",
  },
  "aiStats.testsHeading": {
    ja: "固定の写真の試し（モデルごと）",
    en: "Fixed-photo tests by model",
    "zh-TW": "固定照片測試（各模型）",
  },
  "aiStats.testScore": {
    ja: "正解が1番目 {top1}% · 3番目まで {top3}%（{n} 枚）",
    en: "Correct 1st {top1}% · top 3 {top3}% ({n} {n|photo|photos})",
    "zh-TW": "正解在第 1 個 {top1}% · 前 3 個 {top3}%（{n} 張）",
  },
  "aiStats.testSpeed": {
    ja: "答えた写真の時間: 中央値 {p50}秒 · 90% {p90}秒",
    en: "Answered photos: median {p50}s · 90% {p90}s",
    "zh-TW": "有回應的照片：中位數 {p50} 秒 · 90% {p90} 秒",
  },
  "aiStats.testFailed": {
    ja: "答えなし {n} 枚（時間切れ・失敗。時間には入れず、正解の率では外れ）",
    en: "{n} without an answer (timeout or error; not in the times, counted as misses)",
    "zh-TW": "沒有回應 {n} 張（逾時或失敗；不計入時間，正解率中算答錯）",
  },
  "aiStats.testErrors": {
    ja: "届かなかった {n} 枚は数えていません（写真の読み込み・通信・権限の失敗。一覧の ! の行）",
    en: "Not counted: {n} {n|photo|photos} that didn't get through (loading, network or permission error; the ! rows)",
    "zh-TW": "未計入：{n} 張沒有送達（照片載入、連線或權限失敗；清單中的 ! 列）",
  },
  "aiStats.testHeading": {
    ja: "固定の写真で試す",
    en: "Test with fixed photos",
    "zh-TW": "用固定照片測試",
  },
  "aiStats.testNote": {
    ja: "本番の設定は変えずに、選んだモデルへ正解の付いた写真 {n} 枚を流し、撮った後の候補と同じ指示で、正解が何番目に出るかと時間を測ります。利用者には影響しません。1日 300 枚まで。",
    en: "Without changing the live setting, sends {n} labelled {n|photo|photos} to the chosen model with the same prompt as photo candidates, and measures where the right answer ranks and how long it takes. Users are not affected. Up to 300 photos a day.",
    "zh-TW":
      "不改變正式設定，把 {n} 張附有正解的照片送給選擇的模型，用與拍照候選相同的指示，測量正解排第幾與所需時間。不影響使用者。每天最多 300 張。",
  },
  "aiStats.testModel": {
    ja: "試すモデル",
    en: "Model to test",
    "zh-TW": "要測試的模型",
  },
  "aiStats.testAuto": {
    ja: "いまのスキャンの AI",
    en: "Current scan AI",
    "zh-TW": "目前的掃描 AI",
  },
  "aiStats.testLanguage": {
    ja: "学習言語",
    en: "Learning language",
    "zh-TW": "學習語言",
  },
  "aiStats.lang.zh-TW": {
    ja: "台湾華語",
    en: "Taiwanese Mandarin",
    "zh-TW": "台灣華語",
  },
  "aiStats.lang.en": {
    ja: "英語",
    en: "English",
    "zh-TW": "英語",
  },
  "aiStats.lang.ja": {
    ja: "日本語",
    en: "Japanese",
    "zh-TW": "日語",
  },
  "aiStats.testRun": {
    ja: "試す",
    en: "Run test",
    "zh-TW": "開始測試",
  },
  "aiStats.testRunning": {
    ja: "試しています… {i}/{n}",
    en: "Testing… {i}/{n}",
    "zh-TW": "測試中… {i}/{n}",
  },
  "aiStats.testStop": {
    ja: "止める",
    en: "Stop",
    "zh-TW": "停止",
  },
  "aiStats.testWant": {
    ja: "正解",
    en: "expected",
    "zh-TW": "正解",
  },
  "aiStats.task.photo_candidates": {
    ja: "撮った写真の候補",
    en: "Photo word candidates",
    "zh-TW": "拍照的單字候選",
  },
  "aiStats.task.tutorial_candidates": {
    ja: "チュートリアルの写真の候補",
    en: "Tutorial photo candidates",
    "zh-TW": "教學照片的候選",
  },
  "aiStats.task.word_candidates": {
    ja: "母語で調べた語の候補",
    en: "Candidates for a typed word",
    "zh-TW": "用母語查詢的候選",
  },
  "aiStats.task.scan_detect": {
    ja: "スキャンの物・文字の検出",
    en: "Scan: objects and text",
    "zh-TW": "掃描：物品與文字偵測",
  },
  "aiStats.task.scan_parts": {
    ja: "「+細かく」の部分の検出",
    en: '"More detail": parts',
    "zh-TW": "「+更細」的部位偵測",
  },
  "aiStats.task.image_sense": {
    ja: "語の絵の意味を決める",
    en: "Picture sense for a word",
    "zh-TW": "決定單字圖片的意思",
  },
  "aiStats.task.image_verify": {
    ja: "語の絵を確かめる",
    en: "Checking word pictures",
    "zh-TW": "確認單字圖片",
  },
  "aiStats.task.wordbook": {
    ja: "単語帳の読み取り",
    en: "Reading wordbook pages",
    "zh-TW": "讀取單字本",
  },
  "aiStats.task.card": {
    ja: "単語カード（解説）",
    en: "Word card (explanation)",
    "zh-TW": "單字卡（解說）",
  },
  "aiStats.task.tutorial_card": {
    ja: "チュートリアルのカード",
    en: "Tutorial card",
    "zh-TW": "教學的單字卡",
  },
  "aiStats.task.tutorial_lesson": {
    ja: "チュートリアルのレッスン",
    en: "Tutorial lesson",
    "zh-TW": "教學的課程",
  },
  "aiStats.task.phrase_card": {
    ja: "フレーズカード",
    en: "Phrase card",
    "zh-TW": "片語卡",
  },
  "aiStats.task.section_regen": {
    ja: "項目の作り直し",
    en: "Regenerating a section",
    "zh-TW": "重新產生項目",
  },
  "aiStats.task.reader_meaning": {
    ja: "読む人の言語での意味",
    en: "Meaning in the reader's language",
    "zh-TW": "讀者語言的意思",
  },
  "aiStats.task.distractors": {
    ja: "4択の誤答の作り置き",
    en: "Quiz distractors",
    "zh-TW": "四選一的錯誤選項",
  },
  "aiStats.task.journal_correct": {
    ja: "日記の添削",
    en: "Diary correction",
    "zh-TW": "日記批改",
  },
  "aiStats.task.journal_prompts": {
    ja: "日記の書き出しの質問",
    en: "Diary prompts",
    "zh-TW": "日記的寫作提問",
  },
  "aiStats.task.report_locate": {
    ja: "報告された項目の特定",
    en: "Locating a reported item",
    "zh-TW": "找出被回報的項目",
  },
  "aiStats.task.reading_check_1": {
    ja: "読みの突き合わせ（1人目）",
    en: "Reading check (1st)",
    "zh-TW": "讀音核對（第一位）",
  },
  "aiStats.task.correction_judge": {
    ja: "作り直しの判定",
    en: "Judging a correction",
    "zh-TW": "判斷是否重新產生",
  },
  "aiStats.task.reading_check_2": {
    ja: "読みの突き合わせ（2人目）",
    en: "Reading check (2nd)",
    "zh-TW": "讀音核對（第二位）",
  },
  "aiStats.task.lexicon_audit": {
    ja: "辞書の点検",
    en: "Dictionary audit",
    "zh-TW": "辭典檢查",
  },
  "aiStats.task.lexicon_corpus": {
    ja: "生きた例文の生成",
    en: "Generating live examples",
    "zh-TW": "產生實用例句",
  },
  "aiStats.task.report_triage": {
    ja: "利用者の報告の検証",
    en: "Checking user reports",
    "zh-TW": "驗證使用者回報",
  },
  "aiStats.task.category_backfill": {
    ja: "棚の分類の付け直し",
    en: "Re-sorting shelves",
    "zh-TW": "重新分類書架",
  },
  "aiStats.task.native_ai": {
    ja: "iOS の自由文の窓口",
    en: "iOS free-form AI",
    "zh-TW": "iOS 的自由文字窗口",
  },
  "aiStats.testThinkingOff": {
    ja: "Claude に考えさせない（速い方）",
    en: "Don't let Claude think (faster)",
    "zh-TW": "不讓 Claude 思考（較快）",
  },
  "aiStats.testThinkingNote": {
    ja: "選ばないと、Claude 5 は考えてから答えます（いまの本番の呼び方と同じ）。",
    en: "Unchecked, Claude 5 thinks before answering (the same way the live app calls it now).",
    "zh-TW": "不勾選時，Claude 5 會先思考再回答（與目前正式版的呼叫方式相同）。",
  },
  "aiStats.variant.thinking-off": {
    ja: "考えない",
    en: "no thinking",
    "zh-TW": "不思考",
  },
  "aiSet.title": {
    ja: "AI の設定（開発者）",
    en: "AI settings (developer)",
    "zh-TW": "AI 設定（開發者）",
  },
  "aiSet.loading": {
    ja: "読み込み中…",
    en: "Loading…",
    "zh-TW": "載入中…",
  },
  "aiSet.loadFailed": {
    ja: "設定を読み込めませんでした",
    en: "Couldn't load the settings",
    "zh-TW": "無法載入設定",
  },
  "aiSet.statusOk": {
    ja: "✓ AI は動いています（既定: {p}）",
    en: "✓ AI is working (default: {p})",
    "zh-TW": "✓ AI 運作中（預設：{p}）",
  },
  "aiSet.statusNg": {
    ja: "AI が動いていません: {e}",
    en: "AI is not working: {e}",
    "zh-TW": "AI 無法運作：{e}",
  },
  "aiSet.featuresHeading": {
    ja: "機能ごとの AI",
    en: "AI per feature",
    "zh-TW": "各功能的 AI",
  },
  "aiSet.featuresNote": {
    ja: "「自動」は最新の Gemini を使います（スキャンは Flash-Lite、ほかは Flash）。選ぶとすぐに切り替わります。鍵は Secrets に入れます。",
    en: '"Auto" uses the newest Gemini (Flash-Lite for scanning, Flash for everything else). A change applies right away. Keys live in Secrets.',
    "zh-TW":
      "「自動」會使用最新的 Gemini（掃描用 Flash-Lite，其他用 Flash）。選擇後立即切換。金鑰放在 Secrets。",
  },
  "aiSet.current": {
    ja: "いま",
    en: "Now",
    "zh-TW": "目前",
  },
  "aiSet.autoCurrent": {
    ja: "自動（最新 {tier}）→ {m}",
    en: "Auto (newest {tier}) → {m}",
    "zh-TW": "自動（最新 {tier}）→ {m}",
  },
  "aiSet.auto": {
    ja: "自動（最新 {tier}）",
    en: "Auto (newest {tier})",
    "zh-TW": "自動（最新 {tier}）",
  },
  "aiSet.pickAria": {
    ja: "{f} の AI",
    en: "AI for {f}",
    "zh-TW": "{f} 的 AI",
  },
  "aiSet.noKey": {
    ja: "鍵が未設定",
    en: "no key",
    "zh-TW": "未設定金鑰",
  },
  "aiSet.noModels": {
    ja: "使えるモデルなし",
    en: "no usable models",
    "zh-TW": "沒有可用的模型",
  },
  "aiSet.listFailed": {
    ja: "一覧を取れません",
    en: "couldn't list models",
    "zh-TW": "無法取得模型清單",
  },
  "aiSet.saved": {
    ja: "保存しました",
    en: "Saved",
    "zh-TW": "已儲存",
  },
  "aiSet.save": {
    ja: "保存",
    en: "Save",
    "zh-TW": "儲存",
  },
  "aiSet.feature.scan": {
    ja: "スキャン",
    en: "Scan",
    "zh-TW": "掃描",
  },
  "aiSet.feature.card": {
    ja: "単語カード",
    en: "Word cards",
    "zh-TW": "單字卡",
  },
  "aiSet.feature.review": {
    ja: "復習の添削・ヒント",
    en: "Review feedback and hints",
    "zh-TW": "複習的批改與提示",
  },
  "aiSet.feature.journal": {
    ja: "日記の添削",
    en: "Diary correction",
    "zh-TW": "日記批改",
  },
  "aiSet.feature.audit": {
    ja: "自己点検",
    en: "Self-check",
    "zh-TW": "自我檢查",
  },
  "aiSet.feature.reading_check": {
    ja: "読みの突き合わせ",
    en: "Reading cross-check",
    "zh-TW": "讀音交叉核對",
  },
  "aiSet.feature.lexicon": {
    ja: "辞書の手入れ",
    en: "Dictionary upkeep",
    "zh-TW": "辭典維護",
  },
  "aiSet.featureDesc.scan": {
    ja: "写真の物・文字の検出、単語の候補、単語帳の読み取り（写真を読めるモデルだけ）。",
    en: "Finds objects and text in photos, suggests words and reads wordbook pages (image-capable models only).",
    "zh-TW": "偵測照片中的物品與文字、提出單字候選、讀取單字本（僅限能讀圖片的模型）。",
  },
  "aiSet.featureDesc.card": {
    ja: "単語・フレーズのカード作り、項目の作り直し、意味の訳。",
    en: "Builds word and phrase cards, regenerates sections and translates meanings.",
    "zh-TW": "製作單字與片語卡、重新產生項目、翻譯意思。",
  },
  "aiSet.featureDesc.review": {
    ja: "スピーキングの添削とヒント。",
    en: "Speaking feedback and hints.",
    "zh-TW": "口說批改與提示。",
  },
  "aiSet.featureDesc.journal": {
    ja: "日記の添削と書き出しの質問。",
    en: "Diary corrections and writing prompts.",
    "zh-TW": "日記批改與寫作提問。",
  },
  "aiSet.featureDesc.audit": {
    ja: "報告された誤りの特定と、作り直した項目の判定。",
    en: "Finds reported mistakes and judges regenerated items.",
    "zh-TW": "找出被回報的錯誤，並判斷重新產生的項目。",
  },
  "aiSet.featureDesc.reading_check": {
    ja: "読み・品詞を2人目として確かめる。自己点検と別の AI にすると独立に確かめられます。",
    en: "A second opinion on readings and parts of speech. Pick a different AI from Self-check for an independent check.",
    "zh-TW": "以第二意見確認讀音與詞性。與自我檢查使用不同的 AI，就能獨立確認。",
  },
  "aiSet.featureDesc.lexicon": {
    ja: "辞書の点検、利用者の報告の検証、生きた例文の生成（毎日の裏方）。",
    en: "Audits dictionary entries, checks user reports and writes fresh example sentences (daily background work).",
    "zh-TW": "檢查辭典條目、驗證使用者回報、產生道地例句（每日背景作業）。",
  },
  "aiSet.imageHeading": {
    ja: "画像（文字検索の AI 画像）",
    en: "Images (AI images for text search)",
    "zh-TW": "圖片（文字搜尋的 AI 圖片）",
  },
  "aiSet.imageNote": {
    ja: "文字で見つけた単語の詳細と復習に、AI 画像を1枚作ります。ホームのアルバムには出しません。",
    en: "Makes one AI image for words found by text, shown in word details and reviews (not in the home album).",
    "zh-TW": "為以文字找到的單字製作一張 AI 圖片，顯示在單字詳情與複習中（不會出現在首頁相簿）。",
  },
  "aiSet.imageProvider": {
    ja: "画像を作るサービス",
    en: "Image service",
    "zh-TW": "圖片服務",
  },
  "aiSet.imageModel": {
    ja: "画像モデル",
    en: "Image model",
    "zh-TW": "圖片模型",
  },
  "aiSet.imageOff": {
    ja: "画像生成を停止",
    en: "Image generation off",
    "zh-TW": "停止產生圖片",
  },
  "aiSet.imageTest": {
    ja: "試しに1枚作る",
    en: "Try one image",
    "zh-TW": "試做一張",
  },
  "aiSet.imageTesting": {
    ja: "作っています…",
    en: "Generating…",
    "zh-TW": "產生中…",
  },
  "aiSet.imageTestOk": {
    ja: "作れました",
    en: "Image created",
    "zh-TW": "已產生",
  },
  "aiSet.imageTestFail": {
    ja: "作れませんでした",
    en: "Couldn't create an image",
    "zh-TW": "無法產生圖片",
  },
  "aiSet.ttsHeading": {
    ja: "発音の声",
    en: "Pronunciation voices",
    "zh-TW": "發音的聲音",
  },
  "aiSet.ttsNote": {
    ja: "学習言語ごとに声を選び、試しに鳴らしてから保存します。選ばない言語は既定の声（{p}）です。",
    en: "Pick a voice per learning language, play a sample, then save. Languages left on default use {p}.",
    "zh-TW": "為每種學習語言選擇聲音，試聽後再儲存。未選擇的語言使用預設聲音（{p}）。",
  },
  "aiSet.ttsLangZh": {
    ja: "台湾華語",
    en: "Taiwanese Mandarin",
    "zh-TW": "台灣華語",
  },
  "aiSet.ttsLangEn": {
    ja: "英語",
    en: "English",
    "zh-TW": "英語",
  },
  "aiSet.ttsLangJa": {
    ja: "日本語",
    en: "Japanese",
    "zh-TW": "日語",
  },
  "aiSet.ttsTwNote": {
    ja: "Azure か Gemini を選ぶと、アプリ全体でこの台湾の声1つだけを使います（ほかの声に切り替えません）。",
    en: "With Azure or Gemini, this becomes the one Taiwanese voice used across the app (it never switches to another voice).",
    "zh-TW": "選擇 Azure 或 Gemini 時，整個 App 只使用這一個台灣聲音（不會切換到其他聲音）。",
  },
  "aiSet.ttsIncomplete": {
    ja: "声が選ばれていないため、既定の声で鳴っています。",
    en: "No voice is chosen yet, so the default voice plays.",
    "zh-TW": "尚未選擇聲音，目前使用預設聲音。",
  },
  "aiSet.ttsProvider": {
    ja: "声の会社",
    en: "Voice provider",
    "zh-TW": "聲音供應商",
  },
  "aiSet.ttsDefaultVoice": {
    ja: "既定の声",
    en: "Default voice",
    "zh-TW": "預設聲音",
  },
  "aiSet.ttsGender": {
    ja: "声の性別",
    en: "Voice gender",
    "zh-TW": "聲音性別",
  },
  "aiSet.ttsFemale": {
    ja: "女性",
    en: "Female",
    "zh-TW": "女性",
  },
  "aiSet.ttsMale": {
    ja: "男性",
    en: "Male",
    "zh-TW": "男性",
  },
  "aiSet.ttsVoice": {
    ja: "声の ID",
    en: "Voice ID",
    "zh-TW": "聲音 ID",
  },
  "aiSet.ttsModel": {
    ja: "モデル",
    en: "Model",
    "zh-TW": "模型",
  },
  "aiSet.ttsDiagnose": {
    ja: "診断（台湾の声の一覧を出す）",
    en: "Diagnose (list Taiwanese voices)",
    "zh-TW": "診斷（列出台灣聲音）",
  },
  "aiSet.ttsDiagKeyOk": {
    ja: "鍵あり。",
    en: "Key found.",
    "zh-TW": "有金鑰。",
  },
  "aiSet.ttsDiagKeyNo": {
    ja: "鍵がありません。",
    en: "No key.",
    "zh-TW": "沒有金鑰。",
  },
  "aiSet.ttsDiagVoices": {
    ja: "台湾の声: 女性 {f}・男性 {m}",
    en: "Taiwanese voices: {f} female, {m} male",
    "zh-TW": "台灣聲音：女性 {f}、男性 {m}",
  },
  "aiSet.ttsTry": {
    ja: "試しに鳴らす",
    en: "Play sample",
    "zh-TW": "試聽",
  },
  "aiSet.ttsTook": {
    ja: "{ms} ms で届きました",
    en: "Arrived in {ms} ms",
    "zh-TW": "{ms} 毫秒送達",
  },
  // 広告（開発者だけ、オーナー指示 2026-09-27）。`ad-policy.ts`。
  "settings.ads": {
    ja: "広告（開発者だけ）",
    en: "Ads (developer only)",
    "zh-TW": "廣告（僅開發者）",
  },
  "ads.enabled": { ja: "広告を出す", en: "Show ads", "zh-TW": "顯示廣告" },
  "ads.enabledDesc": {
    ja: "無料の人だけ。撮る・スキャン・保存の最中や、開いた瞬間には出しません",
    en: "Free users only. Never during capture, scan or saving, or at launch",
    "zh-TW": "只對免費使用者。拍照、掃描、儲存時與剛打開時不會顯示",
  },
  "ads.grace": {
    ja: "使い始めてから出さない日数",
    en: "Days without ads after sign-up",
    "zh-TW": "開始使用後不顯示廣告的天數",
  },
  "ads.batches": {
    ja: "復習の区切りの広告: 復習を何回終えるごとに1回",
    en: "Review-end ad: once every N review sets",
    "zh-TW": "複習結束廣告：每完成幾次複習顯示一次",
  },
  "ads.gap": {
    ja: "復習の区切りの広告の間隔（分以上）",
    en: "Minimum minutes between review-end ads",
    "zh-TW": "複習結束廣告的最短間隔（分鐘）",
  },
  "ads.maxDay": {
    ja: "復習の区切りの広告の1日の上限",
    en: "Review-end ads per day (max)",
    "zh-TW": "每天複習結束廣告的上限",
  },
  "ads.native": {
    ja: "図鑑の一覧: 何枚ごとに広告1枠",
    en: "Dex list: one ad slot every N cards",
    "zh-TW": "圖鑑列表：每幾張卡片放一個廣告",
  },
  "ads.rewarded": {
    ja: "ごほうび広告（見たら今日の切り抜きが1枚増える）",
    en: "Rewarded ad (watch to get one more cutout today)",
    "zh-TW": "獎勵廣告（看完今天可多去背一張）",
  },
  // 広告の場所ごとのオン・オフ（2026-09-28「あとからどこに広告つけるか変更できるように」）。
  "ads.places": { ja: "広告を出す場所", en: "Where ads appear", "zh-TW": "廣告位置" },
  "ads.reviewEnd": {
    ja: "復習の区切り（Web は終わりの画面の下の札）",
    en: "After review sets (on the web: a card below the end screen)",
    "zh-TW": "複習告一段落時（網頁版：結束畫面下方的卡片）",
  },
  "ads.afterCatch": {
    ja: "捕まえた後（全画面）— 既定オフ",
    en: "After catching (full-screen) — off by default",
    "zh-TW": "收集之後（全螢幕）— 預設關閉",
  },
  "ads.catches": {
    ja: "捕まえた後: 何回ごとに1回",
    en: "After catching: once every N catches",
    "zh-TW": "收集之後：每幾次顯示一次",
  },
  "ads.dexNative": {
    ja: "図鑑の一覧（札の形）",
    en: "Dex list (card-style)",
    "zh-TW": "圖鑑列表（卡片形式）",
  },
  "ads.diaryNative": {
    ja: "日記の間（札の形）",
    en: "Between diary days (card-style)",
    "zh-TW": "日記之間（卡片形式）",
  },
  "ads.diaryEvery": {
    ja: "日記: 何日ごとに広告1枠",
    en: "Diary: one ad slot every N days",
    "zh-TW": "日記：每幾天放一個廣告",
  },
  "ads.subscription": {
    ja: "サブスク（Pro の購入口）を出す",
    en: "Show the Pro subscription",
    "zh-TW": "顯示 Pro 訂閱",
  },
  "ads.subscriptionDesc": {
    ja: "オフの間は開発者にだけ見えます。アプリ版（iPhone・Android）ではストアの課金が入るまで出しません",
    en: "Only developers see it while off. Not shown in the iOS/Android apps until store billing is added",
    "zh-TW": "關閉時只有開發者看得到。在 iPhone／Android App 加入商店付款前不會顯示",
  },
  // Pro の購入口（Web 版）。
  "pro.title": { ja: "CatchWords Pro", en: "CatchWords Pro", "zh-TW": "CatchWords Pro" },
  "pro.active": { ja: "Pro をご利用中です", en: "You're on Pro", "zh-TW": "你正在使用 Pro" },
  "pro.monthly": { ja: "月ごとで始める", en: "Start monthly", "zh-TW": "按月開始" },
  "pro.yearly": { ja: "年ごとで始める", en: "Start yearly", "zh-TW": "按年開始" },
  "pro.notConfigured": {
    ja: "支払いの準備がまだです（開発者: Stripe の鍵と値段を Secrets に入れてください）",
    en: "Payments aren't set up yet (developer: add the Stripe key and prices to Secrets)",
    "zh-TW": "付款尚未設定（開發者：請在 Secrets 加入 Stripe 金鑰與價格）",
  },
  "pro.failed": {
    ja: "支払いの画面を開けませんでした。少し待ってからもう一度お試しください",
    en: "Couldn't open checkout. Please try again shortly",
    "zh-TW": "無法開啟付款頁面，請稍後再試",
  },
  "pro.devOnly": {
    ja: "開発者にだけ見えています（サブスクはまだオフ）",
    en: "Visible to developers only (subscription is still off)",
    "zh-TW": "只有開發者看得到（訂閱尚未開啟）",
  },
  // 値段の書き方（Stripe から読んだ値段。`price-label.ts`）。
  "price.month": { ja: "{price}／月", en: "{price}/month", "zh-TW": "{price}／月" },
  "price.year": { ja: "{price}／年", en: "{price}/year", "zh-TW": "{price}／年" },
  "price.week": { ja: "{price}／週", en: "{price}/week", "zh-TW": "{price}／週" },
  "price.day": { ja: "{price}／日", en: "{price}/day", "zh-TW": "{price}／天" },
  // 2以上の周期だけで使う（1 は上の4つ）。
  "price.every": {
    ja: "{price}（{n}{unit}ごと）",
    en: "{price} every {n} {unit}",
    "zh-TW": "{price}（每 {n} {unit}）",
  },
  "price.unit.month": { ja: "か月", en: "months", "zh-TW": "個月" },
  "price.unit.year": { ja: "年", en: "years", "zh-TW": "年" },
  "price.unit.week": { ja: "週間", en: "weeks", "zh-TW": "週" },
  "price.unit.day": { ja: "日", en: "days", "zh-TW": "天" },
  "price.taxIncl": { ja: "（税込）", en: "(tax incl.)", "zh-TW": "（含稅）" },
  "price.taxExcl": { ja: "（税別）", en: "(excl. tax)", "zh-TW": "（未稅）" },
  "pro.yearlyPerMonth": {
    ja: "月あたり約 {price}",
    en: "about {price}/month",
    "zh-TW": "每月約 {price}",
  },
  "pro.yearlySave": {
    ja: "月ごとより {n}% お得",
    en: "save {n}% vs monthly",
    "zh-TW": "比按月省 {n}%",
  },
  "pro.trial": {
    ja: "初めての方は最初の {n} 日間無料です。終わる前にメールでお知らせします。終わるまでに解約しなければ、その後は自動で料金がかかります。",
    en: "New subscribers get the first {n} {n|day|days} free. We'll email you before it ends. Unless you cancel before then, you'll be charged automatically afterwards.",
    "zh-TW": "首次訂閱者前 {n} 天免費。結束前會以電子郵件通知。若在結束前未取消，之後會自動收費。",
  },
  "pro.autoRenew": {
    ja: "解約しない限り、同じ周期で自動的に更新され、料金がかかります。",
    en: "Renews automatically for the same period and is charged until you cancel.",
    "zh-TW": "除非取消，會以相同週期自動續訂並收費。",
  },
  "pro.cancelAnytime": {
    ja: "いつでもこの欄の「サブスクリプションを管理」から解約でき、次の更新日からは請求されません。",
    en: "Cancel any time from “Manage subscription” here; you won't be charged from the next renewal date.",
    "zh-TW": "可隨時在這裡的「管理訂閱」取消，自下一個續訂日起不再收費。",
  },
  "pro.noRefund": {
    ja: "法令で必要な場合を除き、支払い済みの料金は返金されません。",
    en: "Payments are not refunded except where required by law.",
    "zh-TW": "除法令另有規定外，已支付的費用不予退還。",
  },
  "pro.agree": {
    ja: "購入すると、利用規約に同意したことになります。",
    en: "By subscribing you agree to the Terms of Service.",
    "zh-TW": "購買即表示你同意使用條款。",
  },
  "pro.manage": {
    ja: "サブスクリプションを管理",
    en: "Manage subscription",
    "zh-TW": "管理訂閱",
  },
  "pro.manageHint": {
    ja: "解約・お支払い方法の変更・領収書の確認は、Stripe の管理画面で行えます。",
    en: "Cancel, change your payment method or see receipts on Stripe's management page.",
    "zh-TW": "取消訂閱、變更付款方式與查看收據，都可以在 Stripe 的管理頁面進行。",
  },
  "pro.manageFailed": {
    ja: "管理画面を開けませんでした。少し待ってからもう一度お試しください",
    en: "Couldn't open the management page. Please try again shortly",
    "zh-TW": "無法開啟管理頁面，請稍後再試",
  },
  "pro.preparing": {
    ja: "Pro は準備中です。",
    en: "Pro isn't available yet.",
    "zh-TW": "Pro 準備中。",
  },
  "pro.priceUnavailable": {
    ja: "料金を読み込めませんでした。少し待ってからもう一度開いてください",
    en: "Couldn't load the price. Please try again shortly",
    "zh-TW": "無法載入價格，請稍後再試",
  },
  "pro.legalNotReadyAdmin": {
    ja: "特定商取引法に基づく表記がそろっていないため、販売を止めています（開発者向け）",
    en: "Sales are blocked until the legal notice (Specified Commercial Transactions Act) is complete (for developers)",
    "zh-TW": "特定商業交易法標示尚未齊備，因此暫停販售（開發者用）",
  },
  "pro.testModeOnly": {
    ja: "テスト用の鍵なので開発者だけ試せます。本番の鍵では、表記がそろうまで買えません",
    en: "Test key: only developers can try this. With a live key, nobody can buy until the legal notice is complete",
    "zh-TW": "目前是測試用金鑰，只有開發者能試用。使用正式金鑰時，標示齊備前無法購買",
  },
  "pro.adminMissing": {
    ja: "開発者向け — 足りない設定: {list}",
    en: "For developers — missing settings: {list}",
    "zh-TW": "開發者用 — 缺少的設定：{list}",
  },
  "pro.err.portalNotConfigured": {
    ja: "Stripe のカスタマーポータルがまだ設定されていません（開発者: Stripe の管理画面で設定を保存してください）",
    en: "The Stripe customer portal isn't set up yet (developer: save the portal settings in the Stripe dashboard)",
    "zh-TW": "Stripe 的訂閱管理頁面尚未設定（開發者：請在 Stripe 後台儲存 Customer portal 的設定）",
  },
  "pro.err.noCustomer": {
    ja: "このアカウントの購入記録が見つかりませんでした",
    en: "No purchase was found for this account",
    "zh-TW": "找不到這個帳號的購買紀錄",
  },
  "pro.err.legalNotReady": {
    ja: "販売の準備がまだ整っていません",
    en: "Sales aren't open yet",
    "zh-TW": "販售尚未準備就緒",
  },
  "pro.err.notConfigured": {
    ja: "支払いの準備がまだです",
    en: "Payments aren't set up yet",
    "zh-TW": "付款尚未設定",
  },
  "pro.err.termsChanged": {
    ja: "料金または無料期間が変わりました。新しい内容をご確認ください。",
    en: "The price or free trial has changed. Please review the new details.",
    "zh-TW": "價格或免費期已變更，請確認新的內容。",
  },
  // 申込みの最終確認（特定商取引法 12 条の6。`checkout-terms.ts`・`ProCheckoutConfirm`）。
  "checkout.title": { ja: "お申込み内容の確認", en: "Review your order", "zh-TW": "確認申請內容" },
  "checkout.lead": {
    ja: "有料の定期購入のお申込みです。内容をご確認のうえ、下のボタンで支払いの画面へ進んでください。",
    en: "This is an order for a paid subscription. Please review the details, then continue to payment with the button below.",
    "zh-TW": "這是付費定期訂閱的申請。請確認內容後，按下方按鈕前往付款頁面。",
  },
  "checkout.item": {
    ja: "商品（サービスの内容・数量）",
    en: "Service and quantity",
    "zh-TW": "商品（服務內容與數量）",
  },
  "checkout.itemValue": {
    ja: "{plan}：CatchWords Pro（有料プラン）の利用権 1件（このアカウント1つ分）。{cycle}ごとの定期購入です。",
    en: "{plan}: one CatchWords Pro (paid plan) subscription for this account. Billed every {cycle}.",
    "zh-TW": "{plan}：CatchWords Pro（付費方案）使用權 1 份（限本帳號）。每 {cycle} 的定期訂閱。",
  },
  "checkout.planMonthly": { ja: "月ごとプラン", en: "Monthly plan", "zh-TW": "按月方案" },
  "checkout.planYearly": { ja: "年ごとプラン", en: "Yearly plan", "zh-TW": "按年方案" },
  "checkout.cycleMonth": { ja: "1か月", en: "month", "zh-TW": "1 個月" },
  "checkout.cycleYear": { ja: "1年", en: "year", "zh-TW": "1 年" },
  "checkout.price": { ja: "価格", en: "Price", "zh-TW": "價格" },
  "checkout.priceValue": {
    ja: "{price}（2回目以降も同じ金額）",
    en: "{price} (the same amount for every renewal)",
    "zh-TW": "{price}（第 2 次起金額相同）",
  },
  "checkout.priceExclNote": {
    ja: "（税別。税を含む合計は次の支払いの画面に表示されます）",
    en: "(excl. tax; the total including tax is shown on the next payment screen)",
    "zh-TW": "（未稅；含稅總額會顯示在下一個付款頁面）",
  },
  "checkout.trial": { ja: "無料期間", en: "Free trial", "zh-TW": "免費期" },
  "checkout.trialValue": {
    ja: "最初の{n}日間は無料です。{date}に初回の料金 {price} がかかります（それまでに解約すれば料金はかかりません）。",
    en: "The first {n} {n|day|days} are free. The first charge of {price} is on {date} (cancel before then and you pay nothing).",
    "zh-TW": "前 {n} 天免費。{date} 將收取首次費用 {price}（在此之前取消則不收費）。",
  },
  "checkout.payment": { ja: "支払いの時期", en: "When you pay", "zh-TW": "付款時間" },
  "checkout.paymentTrial": {
    ja: "初回は {date}（無料期間の終わり）。以後 {cycle}ごとに自動で請求されます。",
    en: "First charge on {date} (end of the free trial), then automatically every {cycle}.",
    "zh-TW": "首次於 {date}（免費期結束時），之後每 {cycle} 自動收費。",
  },
  "checkout.paymentNow": {
    ja: "初回はお申込みの時。以後 {cycle}ごとに自動で請求されます。",
    en: "First charge when you subscribe, then automatically every {cycle}.",
    "zh-TW": "首次於申請時，之後每 {cycle} 自動收費。",
  },
  "checkout.method": { ja: "支払い方法", en: "Payment method", "zh-TW": "付款方式" },
  "checkout.methodValue": {
    ja: "クレジットカードなど、次の支払いの画面（Stripe）で選べる方法。",
    en: "Credit card or another method offered on the next payment screen (Stripe).",
    "zh-TW": "信用卡等，可在下一個付款頁面（Stripe）選擇的方式。",
  },
  "checkout.start": { ja: "利用開始", en: "When it starts", "zh-TW": "開始使用" },
  "checkout.startValue": {
    ja: "お申込みの手続きが終わり次第、すぐに使えます。",
    en: "Immediately after the order is completed.",
    "zh-TW": "申請手續完成後即可使用。",
  },
  "checkout.renew": {
    ja: "契約期間・自動更新",
    en: "Term and auto-renewal",
    "zh-TW": "合約期間與自動續訂",
  },
  "checkout.renewValue": {
    ja: "{cycle}ごとに自動で更新されます。解約しない限り続きます。",
    en: "Renews automatically every {cycle} until you cancel.",
    "zh-TW": "每 {cycle} 自動續訂，除非取消將持續。",
  },
  "checkout.applyPeriod": { ja: "申込みの期間", en: "Order period", "zh-TW": "申請期間" },
  "checkout.applyPeriodValue": {
    ja: "期間の定めはありません（いつでも申し込めます）。",
    en: "No limited order period (you can subscribe at any time).",
    "zh-TW": "沒有期間限制（隨時可申請）。",
  },
  "checkout.cancel": { ja: "解約", en: "Cancelling", "zh-TW": "取消訂閱" },
  "checkout.cancelValue": {
    ja: "いつでも 設定 › CatchWords Pro ›「サブスクリプションを管理」から解約できます。次の更新日より前に解約すれば、それ以降の請求はありません。解約しても、支払い済みの期間の終わりまで使えます。",
    en: "Cancel any time in Settings › CatchWords Pro › “Manage subscription”. Cancel before the next renewal date and you won't be charged again. You keep Pro until the end of the period you paid for.",
    "zh-TW":
      "可隨時在「設定 › CatchWords Pro ›『管理訂閱』」取消。在下一個續訂日前取消，之後不再收費。取消後仍可使用到已付款期間結束。",
  },
  "checkout.cancelValueTrial": {
    ja: "いつでも 設定 › CatchWords Pro ›「サブスクリプションを管理」から解約できます。無料期間中に解約すれば、料金は一切かかりません。その後も、次の更新日より前に解約すれば以後の請求はありません。",
    en: "Cancel any time in Settings › CatchWords Pro › “Manage subscription”. Cancel during the free trial and you pay nothing. After that, cancel before the next renewal date and you won't be charged again.",
    "zh-TW":
      "可隨時在「設定 › CatchWords Pro ›『管理訂閱』」取消。在免費期內取消則完全不收費。之後在下一個續訂日前取消，就不會再收費。",
  },
  "checkout.refund": {
    ja: "申込みの撤回・返金",
    en: "Withdrawal and refunds",
    "zh-TW": "撤回申請與退款",
  },
  "checkout.refundValue": {
    ja: "通信販売にはクーリング・オフはありません。デジタルサービスのため、お申込み後の撤回・支払い済みの料金の返金はできません（法令で必要な場合を除く）。",
    en: "There is no cooling-off period for online purchases. Because this is a digital service, orders cannot be withdrawn and payments are not refunded after you subscribe, except where required by law.",
    "zh-TW":
      "網路購物沒有冷靜期（日本法）。由於是數位服務，申請後無法撤回，已支付的費用亦不退還（法令另有規定者除外）。",
  },
  "checkout.readTerms": { ja: "詳しい条件:", en: "Full terms:", "zh-TW": "詳細條件：" },
  "checkout.submit": {
    ja: "規約に同意して購入する（定期購入）",
    en: "Agree to the Terms and buy (subscription)",
    "zh-TW": "同意條款並購買（定期訂閱）",
  },
  "checkout.nextStep": {
    ja: "次の支払いの画面（Stripe）でお支払い情報を入れて、お申込みが確定します。",
    en: "Enter your payment details on the next screen (Stripe) to complete the order.",
    "zh-TW": "在下一個付款頁面（Stripe）輸入付款資訊後，申請即完成。",
  },
  "checkout.back": { ja: "戻る", en: "Back", "zh-TW": "返回" },
  "pro.err.disabled": {
    ja: "いまは Pro を購入できません",
    en: "Pro can't be purchased right now",
    "zh-TW": "目前無法購買 Pro",
  },
  "ads.note": {
    ja: "Web 版は「広告を出す」がオンで、運営者 ID と広告ユニット ID が入っている時だけ広告が出ます。開発者（あなた）は Pro 扱いなので、自分の画面には出ません（確認は確認用ページか別のテスト用アカウントで）。アプリ版（Android）は AdMob を入れるまで出ません。手順は docs/monetization.md。",
    en: "On the web, ads appear only when “Show ads” is on and the publisher ID and ad unit IDs are set. Developers (you) count as Pro, so you won't see ads yourself — check with the preview page or a separate test account. The Android app shows no ads until AdMob is added. Steps: docs/monetization.md.",
    "zh-TW":
      "網頁版只有在「顯示廣告」開啟，且已填入發布商 ID 與廣告單元 ID 時才會出現廣告。開發者（你）視同 Pro，自己的畫面不會出現廣告（請用預覽頁或另一個測試帳號確認）。App 版（Android）在加入 AdMob 前不會顯示。步驟見 docs/monetization.md。",
  },
  "ads.label": { ja: "広告", en: "Ad", "zh-TW": "廣告" },
  "ads.adsenseTitle": {
    ja: "Google AdSense（Web 版）",
    en: "Google AdSense (web)",
    "zh-TW": "Google AdSense（網頁版）",
  },
  "ads.publisherId": {
    ja: "運営者 ID（ca-pub- で始まる番号）",
    en: "Publisher ID (starts with ca-pub-)",
    "zh-TW": "發布商 ID（以 ca-pub- 開頭）",
  },
  "ads.slotDex": {
    ja: "図鑑の一覧の広告ユニット ID",
    en: "Dex list ad unit ID",
    "zh-TW": "圖鑑列表的廣告單元 ID",
  },
  "ads.slotDiary": {
    ja: "日記の間の広告ユニット ID",
    en: "Between-diary-days ad unit ID",
    "zh-TW": "日記之間的廣告單元 ID",
  },
  "ads.slotReviewEnd": {
    ja: "復習の区切りの広告ユニット ID",
    en: "Review-end ad unit ID",
    "zh-TW": "複習結束的廣告單元 ID",
  },
  "ads.badFormat": {
    ja: "形が違います（運営者 ID は「ca-pub-」と数字、広告ユニット ID は数字だけ）。保存していません",
    en: "Wrong format (publisher ID is “ca-pub-” plus digits; ad unit IDs are digits only). Not saved",
    "zh-TW": "格式不正確（發布商 ID 是「ca-pub-」加數字，廣告單元 ID 只有數字）。尚未儲存",
  },
  "ads.adsTxt": {
    ja: "/ads.txt に自動で出る1行",
    en: "Line served automatically at /ads.txt",
    "zh-TW": "自動出現在 /ads.txt 的一行",
  },
  "ads.webOnlyNote": {
    ja: "Web 版では、ごほうび広告と全画面広告は出しません（Google の決まりで、Web の全画面・ごほうびはゲーム専用）。下の2つはアプリ版（AdMob）のための設定です。",
    en: "The web version never shows rewarded or full-screen ads (Google allows them only for web games). The two switches below are for the app version (AdMob).",
    "zh-TW":
      "網頁版不會顯示獎勵廣告與全螢幕廣告（依 Google 規定，網頁的全螢幕與獎勵廣告僅限遊戲）。下面兩項是 App 版（AdMob）用的設定。",
  },
  "ads.saved": {
    ja: "広告の設定を保存しました",
    en: "Ad settings saved",
    "zh-TW": "已儲存廣告設定",
  },
  "settings.usersLink": {
    ja: "利用者ごとの情報（開発者だけ）",
    en: "Per-user details (developer only)",
    "zh-TW": "各使用者的資訊（僅開發者）",
  },
  "settings.betaLink": {
    ja: "ベータの指標（開発者だけ）",
    en: "Beta metrics (developer only)",
    "zh-TW": "Beta 指標（僅開發者）",
  },
  "settings.devMetrics": {
    ja: "開発者（速度計測）",
    en: "Developer (speed metrics)",
    "zh-TW": "開發者（速度測量）",
  },
  "settings.deleteAccount": { ja: "アカウントを削除", en: "Delete account", "zh-TW": "刪除帳號" },
  "settings.avatar": { ja: "プロフィール写真", en: "Profile photo", "zh-TW": "大頭貼" },
  "settings.avatarPick": { ja: "写真を選ぶ", en: "Choose photo", "zh-TW": "選照片" },
  "settings.avatarChange": { ja: "変更", en: "Change", "zh-TW": "更換" },
  "settings.avatarClear": { ja: "外す", en: "Remove", "zh-TW": "移除" },
  "settings.avatarSaving": { ja: "保存中…", en: "Saving…", "zh-TW": "儲存中…" },
  "settings.avatarSaved": {
    ja: "プロフィール写真を変えました",
    en: "Profile photo updated",
    "zh-TW": "已更換大頭貼",
  },
  "settings.avatarFailed": {
    ja: "写真を保存できませんでした",
    en: "Couldn't save the photo",
    "zh-TW": "無法儲存照片",
  },
  "settings.avatarNone": {
    ja: "プロフィール写真はまだありません",
    en: "No profile photo yet",
    "zh-TW": "還沒有大頭貼",
  },
  "settings.reviewLimit": { ja: "1日の復習枚数", en: "Cards per day", "zh-TW": "每天複習的張數" },
  "settings.reviewLimitNone": { ja: "無制限", en: "All", "zh-TW": "無限制" },
  "settings.light": { ja: "ライト", en: "Light", "zh-TW": "淺色" },
  "settings.dark": { ja: "ダーク", en: "Dark", "zh-TW": "深色" },
  "settings.system": { ja: "システム", en: "System", "zh-TW": "跟隨系統" },
  "settings.saveFailed": { ja: "保存に失敗しました", en: "Could not save", "zh-TW": "儲存失敗" },
  // 復習の画面のつまみと**同じ言葉**にする。設定で選ぶのはあの切替の既定値
  // なので、名前が違うと同じ物だと分からない。「ライト」は復習の重さを指す
  // 造語で、明るさの設定(settings.light)と字面が同じになって二重に紛らわしい
  // ので落とす(オーナー指摘「ライトonって名前は不自然」)。
  // --- 主役の写真を選ぶ(要望 #17) ---
  "photo.pickTitle": {
    ja: "この札の主役の写真",
    en: "Main photo for this card",
    "zh-TW": "這張貼紙的主角照片",
  },
  "photo.forAlbum": {
    ja: "アルバムでの見え方",
    en: "How it looks in the album",
    "zh-TW": "在相簿裡的樣子",
  },
  "photo.forDetail": {
    ja: "単語の詳細での見え方",
    en: "How it looks on the word page",
    "zh-TW": "在單字頁面的樣子",
  },
  "photo.selfieNow": { ja: "いま自撮りを撮る", en: "Take a selfie now", "zh-TW": "現在自拍" },
  "photo.selfieFailed": {
    ja: "自撮りを保存できませんでした",
    en: "Could not save the selfie",
    "zh-TW": "自拍儲存失敗",
  },
  "photo.roleObject": { ja: "元の写真", en: "Photo", "zh-TW": "原本的照片" },
  "photo.roleCutout": { ja: "切り抜き", en: "Cut-out", "zh-TW": "去背圖" },
  "photo.roleSelfie": { ja: "自撮り", en: "Selfie", "zh-TW": "自拍" },
  "photo.rolePlaceholder": { ja: "ネット画像", en: "Web image", "zh-TW": "網路圖片" },
  "cap.networkTimeout": {
    ja: "通信に時間がかかっています。写真は端末に保存しました。",
    en: "The connection is taking too long. Your photo is saved on this device.",
    "zh-TW": "連線時間過長，照片已儲存在此裝置。",
  },
  "photo.replaceFile": {
    ja: "別の写真に差し替える",
    en: "Replace with another photo",
    "zh-TW": "換成別的照片",
  },
  "photo.saveFailedMigration": {
    ja: "この端末のデータベースがまだ新しい設定に対応していません（管理者に連絡してください）。",
    en: "The database hasn't been migrated for this setting yet (please contact the admin).",
    "zh-TW": "這台裝置的資料庫還不支援新的設定（請聯絡管理者）。",
  },
  /**
   * オーナー指示 2026-08-26「設定の札の主役の画像って項目名前変えて。
   * また画面ごとのボタンも削除して」。
   *
   * 「主役」は作り手の言葉で、この欄が何を決めるのかを言っていない。
   * 決まるのは **既定でどの写真から見せるか** なので、そう書く。
   */
  /**
   * オーナー指示 2026-09-22「初めに見せる写真じゃなくて**表示するタイプ**と
   * 設定の名前を変えて」。切り抜きを止めてから選択肢が2つになり、
   * 「はじめに見せる」＝順番の話に聞こえるのが実態と合わなくなった。
   */
  "settings.photoPref": {
    ja: "表示するタイプ",
    en: "Photo type",
    "zh-TW": "顯示的類型",
  },
  "settings.photoLibrarySync": {
    ja: "カメラロールに保存",
    en: "Save to Camera Roll",
    "zh-TW": "儲存到相機膠卷",
  },
  "settings.photoLibrarySyncDesc": {
    ja: "撮った写真をスマホの写真アプリにも残します（アプリ版のみ）",
    en: "Keeps a copy of each photo in your phone's Photos app (app version only).",
    "zh-TW": "拍下的照片也會存進手機的相簿（僅限 App 版）。",
  },
  "cap.photoLibrarySaveFailed": {
    ja: "図鑑には追加しましたが、スマホへの写真保存ができませんでした。端末の許可を確認してください。",
    en: "Added to your Dex, but the photo could not be saved to this phone. Check device permissions.",
    "zh-TW": "已加入圖鑑，但無法將照片儲存到手機。請檢查裝置權限。",
  },
  "dex.calMonthSummary": {
    ja: "{n}枚・{d}日",
    en: "{n} {n|photo|photos} · {d} {d|day|days}",
    "zh-TW": "{n} 張、{d} 天",
  },
  "dex.calPhotos": { ja: "{n}枚", en: "{n} {n|photo|photos}", "zh-TW": "{n} 張" },
  "dex.timelineBack": { ja: "カレンダーに戻る", en: "Back to calendar", "zh-TW": "返回行事曆" },
  "dex.timelineTitle": { ja: "この日の記録", en: "This day's captures", "zh-TW": "這一天的紀錄" },
  "settings.photoObject": { ja: "元の写真", en: "Photo", "zh-TW": "原本的照片" },
  "settings.photoSelfie": { ja: "自撮り", en: "Selfie", "zh-TW": "自拍" },
  "settings.zhuyin": { ja: "ㄅㄆㄇ 注音", en: "ㄅㄆㄇ Zhuyin", "zh-TW": "ㄅㄆㄇ 注音" },
  "settings.pinyin": { ja: "abc ピンイン", en: "abc Pinyin", "zh-TW": "abc 拼音" },
  // --- 出典（商用利用の条件。`src/lib/data-sources.ts` と対で持つ） ---
  "settings.sources": { ja: "データの出典", en: "Data sources", "zh-TW": "資料來源" },
  "settings.sourcesHint": {
    ja: "単語の意味・発音・レベルは、下のデータをもとに作っています。",
    en: "Word meanings, pronunciations and levels are built from the data below.",
    "zh-TW": "單字的意思、發音和等級，都是根據下面的資料做出來的。",
  },
  "sources.required": { ja: "出典の明記が条件", en: "Attribution required", "zh-TW": "須註明出處" },
  "sources.ecdict": {
    ja: "英語の意味・品詞・活用・頻度・検定タグ",
    en: "English meanings, part of speech, inflections, frequency and exam tags",
    "zh-TW": "英文的意思、詞性、變化、頻率、檢定標籤",
  },
  "sources.cmudict": {
    ja: "アメリカ英語の発音",
    en: "American English pronunciation",
    "zh-TW": "美式英語的發音",
  },
  "sources.cefrjWordlist": {
    ja: "英単語の CEFR レベル",
    en: "CEFR levels for English words",
    "zh-TW": "英文單字的 CEFR 等級",
  },
  "sources.cefrjGrammar": {
    ja: "英文法の CEFR レベル",
    en: "CEFR levels for English grammar",
    "zh-TW": "英文文法的 CEFR 等級",
  },
  // CEFR-J の作り手（明記が利用の条件）。日本語は原典の表記と1字も変えない（`data-sources.ts`）。
  "sources.cefrjAuthor": {
    ja: "投野由紀夫研究室（東京外国語大学）",
    en: "Yukio Tono Laboratory, Tokyo University of Foreign Studies",
    "zh-TW": "投野由紀夫研究室（東京外國語大學）",
  },
  "sources.cefrjLicense": {
    ja: "CEFR-J（商用可）",
    en: "CEFR-J (commercial use permitted)",
    "zh-TW": "CEFR-J（可商業使用）",
  },
  "sources.opencc": {
    ja: "簡体字から台湾正体字への変換",
    en: "Simplified to Taiwanese traditional Chinese",
    "zh-TW": "簡體字轉台灣正體字",
  },
  "sources.pinyinPro": {
    ja: "台湾華語の読み（拼音・注音）の確認",
    en: "Checking Taiwan Mandarin readings (pinyin and zhuyin)",
    "zh-TW": "核對華語讀音（拼音、注音）",
  },
  // 日本語の読み(2026-10-01)。学ぶ人は英語か繁體中文で読むので、その2つが本番の文言。
  "settings.kana": { ja: "ふりがな", en: "Kana (furigana)", "zh-TW": "假名（振假名）" },
  "settings.romaji": { ja: "ローマ字", en: "Romaji", "zh-TW": "羅馬拼音" },
  "settings.langJa": { ja: "日本語", en: "Japanese", "zh-TW": "日本語" },
  "settings.langEn": { ja: "English", en: "English", "zh-TW": "English" },
  // 符号は見せない。この束の他の4行(日本語 / English / 母語 / 表示言語)は
  // どれも言語の名前だけを出すのに、ここだけ `(zh-TW)` を足していた。
  /**
   * 学習言語としての中国語の呼び名。
   *
   * オーナー指示 2026-08-26（言い直し）:
   * > 「アプリ全体で台湾華語と表示されているのを**繁體字（台灣）**に変更して。
   * >  英語は **Mandarin（Taiwan）** で。」
   *
   * 中身（辞書・発音・例文）は台湾の正体字と注音のままで、**呼び名だけ**を
   * 変える。「台灣華語」は教える側の用語なので、その人が普段使う言い方に寄せる。
   */
  "settings.langZhTw": {
    ja: "繁體字（台灣）",
    en: "Mandarin (Taiwan)",
    "zh-TW": "繁體字（台灣）",
  },
  "settings.deleteWarn": {
    ja: "集めた単語カード・写真・復習の記録・日記など、すべてのデータが完全に削除されます。この操作は取り消せません。",
    en: "Every card, photo, review record and journal entry is permanently deleted. This cannot be undone.",
    "zh-TW": "收集的單字卡、照片、複習紀錄、日記等所有資料都會被完全刪除。這個動作無法復原。",
  },
  "settings.deleteTypeLabel": {
    ja: "確認のため「削除」と入力してください",
    en: "Type DELETE to confirm",
    "zh-TW": "請輸入「刪除」以確認",
  },
  "settings.deleteButton": {
    ja: "アカウントを完全に削除する",
    en: "Permanently delete my account",
    "zh-TW": "完全刪除帳號",
  },
  "settings.deleting": { ja: "削除しています…", en: "Deleting…", "zh-TW": "刪除中…" },
  "settings.deleteDone": {
    ja: "アカウントを削除しました。ご利用ありがとうございました。",
    en: "Your account has been deleted. Thank you for using CatchWords.",
    "zh-TW": "帳號已刪除。謝謝你的使用。",
  },
  "settings.deleteFailed": {
    ja: "削除に失敗しました。もう一度お試しください。",
    en: "Could not delete. Please try again.",
    "zh-TW": "刪除失敗，請再試一次。",
  },
  "settings.metricDetect": {
    ja: "スキャン検出（中央値）",
    en: "Scan detection (median)",
    "zh-TW": "掃描偵測（中位數）",
  },
  "settings.metricAudio": {
    ja: "タップ→音声再生（中央値）",
    en: "Tap → audio (median)",
    "zh-TW": "點擊→播放語音（中位數）",
  },
  "settings.metricTarget": { ja: "目標", en: "target", "zh-TW": "目標" },
  "settings.metricNone": { ja: "計測なし", en: "no data", "zh-TW": "沒有測量資料" },
  "settings.kpiLink": {
    ja: "KPIダッシュボードを開く →",
    en: "Open the KPI dashboard →",
    "zh-TW": "開啟 KPI 儀表板 →",
  },
  // --- review (memory details) ---
  "review.preparing": {
    ja: "今日の出題を準備中…",
    en: "Preparing today's set…",
    "zh-TW": "正在準備今天的題目…",
  },
  "review.gradeFailed": {
    ja: "結果を保存できませんでした。この単語は次回もう一度出題されます。",
    en: "Couldn't save your result — this word will come up again next time.",
    "zh-TW": "無法儲存結果。這個單字下次會再出一次。",
  },
  /** 記憶の帯は色だけで、畳んでいる間は読む字が無い。声の案内はこれを読む。 */
  "review.memoryBreakdown": { ja: "記憶の内訳", en: "Memory breakdown", "zh-TW": "記憶分布" },
  "review.memoryLoading": {
    ja: "記憶データを準備中です。",
    en: "Preparing memory data…",
    "zh-TW": "正在準備記憶資料。",
  },
  // --- capture flow ---
  "capture.selfieTitle": {
    ja: "ステップ 2: 自撮りを撮る（任意）",
    en: "Step 2: Take a selfie (optional)",
    "zh-TW": "步驟 2：拍自拍（選填）",
  },
  "capture.selfieHint": {
    ja: "対象物と一緒に自分も撮ると、後で振り返るときに記憶が蘇ります。",
    en: "A photo of you with the thing makes the memory much easier to recall.",
    "zh-TW": "和拍攝對象一起把自己也拍進去，之後回顧時記憶會更鮮明。",
  },
  "capture.addSelfie": { ja: "自撮りを追加", en: "Add a selfie", "zh-TW": "加上自拍" },
  "capture.skipNext": { ja: "スキップして次へ", en: "Skip for now", "zh-TW": "跳過，進下一步" },
  "capture.redo": { ja: "やり直す", en: "Start over", "zh-TW": "重來" },
  "capture.clipped": {
    ja: "物が写真の端で切れています。シールでもここで切れるので、少し離れて撮り直すと全部収まります。",
    en: "The object is cut off at the edge of the photo, so the sticker will be cut too. Step back a little and retake to fit it all.",
    "zh-TW": "物品在照片邊緣被切到了，貼紙也會被切掉。稍微退後重拍，就能完整收進去。",
  },
  "capture.retake": { ja: "撮り直す", en: "Retake", "zh-TW": "重拍" },
  "capture.searchByImage": {
    ja: "カメラロールの画像で調べる",
    en: "Search with a photo from your library",
    "zh-TW": "用相簿裡的照片查詢",
  },
  "catEdit.title": { ja: "カテゴリー", en: "Categories", "zh-TW": "分類" },
  "catEdit.moveTitle": {
    ja: "この写真のカテゴリー",
    en: "Category for this photo",
    "zh-TW": "這張照片的分類",
  },
  "catEdit.yours": { ja: "使っているカテゴリー", en: "Your categories", "zh-TW": "使用中的分類" },
  "catEdit.others": {
    ja: "ほかのカテゴリー（{n}）",
    en: "Other categories ({n})",
    "zh-TW": "其他分類（{n}）",
  },
  "catEdit.create": {
    ja: "新しいカテゴリーを作る",
    en: "Create a new category",
    "zh-TW": "建立新分類",
  },
  "catEdit.namePlaceholder": { ja: "カテゴリーの名前", en: "Category name", "zh-TW": "分類名稱" },
  "catEdit.emoji": { ja: "絵文字", en: "Emoji", "zh-TW": "表情符號" },
  "catEdit.save": { ja: "保存", en: "Save", "zh-TW": "儲存" },
  "catEdit.delete": { ja: "削除", en: "Delete", "zh-TW": "刪除" },
  "catEdit.resetName": {
    ja: "元の名前に戻す",
    en: "Restore original name",
    "zh-TW": "恢復原本名稱",
  },
  "catEdit.rename": {
    ja: "「{name}」の名前を変える",
    en: 'Rename "{name}"',
    "zh-TW": "修改「{name}」的名稱",
  },
  "catEdit.deleteConfirm": {
    ja: "「{name}」を削除しますか？中の写真は削除されず、元のカテゴリーに戻ります。",
    en: 'Delete "{name}"? Its photos stay and go back to their original categories.',
    "zh-TW": "要刪除「{name}」嗎？裡面的照片不會刪除，會回到原本的分類。",
  },
  "catEdit.nameInvalid": {
    ja: "名前は1〜24文字で入れてください。",
    en: "Use 1 to 24 characters for the name.",
    "zh-TW": "名稱請輸入 1～24 個字。",
  },
  "catEdit.saveFailed": {
    ja: "保存できませんでした。もう一度お試しください。",
    en: "Couldn't save. Please try again.",
    "zh-TW": "無法儲存，請再試一次。",
  },
  "catEdit.roomMine": { ja: "マイカテゴリー", en: "My categories", "zh-TW": "我的分類" },
  "catEdit.manage": { ja: "カテゴリーを編集", en: "Edit categories", "zh-TW": "編輯分類" },
  "catEdit.change": { ja: "カテゴリーを変える", en: "Change category", "zh-TW": "變更分類" },
  // カテゴリーの側から単語を入れる・外す（2026-09-28）
  "catEdit.members": {
    ja: "「{name}」の単語を選ぶ",
    en: 'Choose words for "{name}"',
    "zh-TW": "選擇「{name}」的單字",
  },
  "catEdit.membersShort": { ja: "単語を選ぶ", en: "Choose words", "zh-TW": "選擇單字" },
  "catEdit.membersCount": {
    ja: "{n}語が入っています",
    en: "{n} {n|word|words} in this category",
    "zh-TW": "目前有 {n} 個單字",
  },
  "catEdit.membersSearch": { ja: "単語をさがす", en: "Find a word", "zh-TW": "搜尋單字" },
  "catEdit.membersFrom": { ja: "いま: {name}", en: "Now: {name}", "zh-TW": "目前：{name}" },
  "catEdit.membersApply": {
    ja: "{n}件を変更",
    en: "Apply {n} {n|change|changes}",
    "zh-TW": "變更 {n} 項",
  },
  "catEdit.membersNoRemove": {
    ja: "「その他」からは外せません。ほかのカテゴリーへ入れてください。",
    en: 'Words can\'t be removed from "Other" — add them to another category instead.',
    "zh-TW": "無法從「其他」移出，請把單字加入別的分類。",
  },
  "capture.pickTitle": {
    ja: "ステップ 3: 単語を選ぶ",
    en: "Step 3: Pick a word",
    "zh-TW": "步驟 3：選單字",
  },
  "capture.pickHint": {
    ja: "AIが候補を提案しました。学びたい単語を選んでください。",
    en: "Here's what the AI found — pick the word you want to learn.",
    "zh-TW": "AI 提出了幾個候選，請選你想學的單字。",
  },
  "capture.otherWord": {
    ja: "違う単語を入力",
    en: "Type a different word",
    "zh-TW": "輸入別的單字",
  },
  // オーナー指示 2026-09-15「これにするは検索ボタンに変えて」。
  "capture.useThis": { ja: "検索", en: "Search", "zh-TW": "搜尋" },
  "capture.noSelfie": { ja: "自撮りなし", en: "No selfie", "zh-TW": "沒有自拍" },
  "place.thisWord": { ja: "この言葉", en: "this word", "zh-TW": "這個詞" },
  "settings.selfieMode": {
    ja: "自撮りモード",
    en: "Selfie mode",
    "zh-TW": "自拍模式",
  },
  "settings.selfieModeDesc": {
    ja: "単語を撮ったあと、続けてその場の自分を撮る画面に進みます",
    en: "After catching a word, go straight to a selfie of the moment.",
    "zh-TW": "拍下單字後，會接著進入自拍畫面，留下當下的自己。",
  },
  "capture.selfieSkip": { ja: "スキップ", en: "Skip", "zh-TW": "略過" },
  "capture.selfieLive": {
    ja: "ものと一緒に、もう一枚",
    en: "One more, with you",
    "zh-TW": "和它一起，再拍一張",
  },
  "cap.reencRetry": { ja: "写真の追加を再試行", en: "Retry adding photo", "zh-TW": "重試新增照片" },
  "capture.peelHint": {
    ja: "好きな方向にはがしてキャッチ",
    en: "Peel in any direction to catch",
    "zh-TW": "往任何方向撕，捕捉單字",
  },
  "capture.flipHint": {
    ja: "画像をタップで自撮りにフリップ",
    en: "Tap the photo to flip to your selfie",
    "zh-TW": "點圖片翻到自拍",
  },
  "capture.note": {
    ja: "一言メモ（任意）",
    en: "A quick note (optional)",
    "zh-TW": "一句話筆記（選填）",
  },
  "capture.notePlaceholder": {
    ja: "どんな場面で出会った？",
    en: "Where did you run into it?",
    "zh-TW": "在什麼場合遇到的？",
  },
  "capture.addToDex": { ja: "図鑑に追加", en: "Add to Dex", "zh-TW": "加進圖鑑" },
  "capture.offlineTitle": {
    ja: "解析できなかったので写真を預かりました",
    en: "Couldn't analyze it — we kept your photo",
    "zh-TW": "沒能分析，先幫你把照片收著了",
  },
  "capture.offlineHint": {
    ja: "あとでホームの「解析待ち」から続きができます。撮った瞬間は逃していません。",
    en: "Continue later from “Waiting for analysis” on Home. The moment isn't lost.",
    "zh-TW": "之後可以從首頁的「等待分析」繼續。拍下的那一刻沒有錯過。",
  },
  "capture.savedReason": {
    ja: "理由: {reason}",
    en: "Reason: {reason}",
    "zh-TW": "原因：{reason}",
  },
  "capture.savedRetry": {
    ja: "いますぐもう一度試す",
    en: "Try again now",
    "zh-TW": "現在就再試一次",
  },
  "capture.cancel": { ja: "やめる", en: "Cancel", "zh-TW": "取消" },
  // 文字で調べた語の検索が失敗した時（打った語は欄に残る — もう一度押せばやり直せる）。
  "textSearch.failed": {
    ja: "調べられませんでした。もう一度検索してください",
    en: "Couldn’t look that up. Please search again.",
    "zh-TW": "查詢失敗，請再搜尋一次",
  },
  // 母語で打った語の、学習言語の候補（`TextCandidateList`）。
  "textPick.back": { ja: "検索に戻る", en: "Back to search", "zh-TW": "回到搜尋" },
  "textPick.title": {
    ja: "「{query}」の言い方",
    en: "Ways to say “{query}”",
    "zh-TW": "「{query}」的說法",
  },
  "textPick.hint": {
    ja: "覚えたい言い方を選んでください",
    en: "Pick the one you want to learn",
    "zh-TW": "請選擇想學的說法",
  },
  "textPick.preparing": {
    ja: "シールを用意しています",
    en: "Preparing the sticker",
    "zh-TW": "正在準備貼紙",
  },
  // 文体の札（どの候補も同じ物差しで1つ。`CANDIDATE_REGISTERS`。2026-10-09）。
  "textPick.register.spoken": { ja: "話し言葉", en: "Spoken", "zh-TW": "口語" },
  "textPick.register.written": { ja: "書き言葉", en: "Written", "zh-TW": "書面語" },
  "textPick.register.both": {
    ja: "会話でも文章でも",
    en: "Spoken & written",
    "zh-TW": "口語書面都用",
  },
  "textPick.register.technical": { ja: "専門用語", en: "Technical", "zh-TW": "專業用語" },
  "textPick.register.signage": {
    ja: "表示・メニューの言葉",
    en: "Signs & menus",
    "zh-TW": "標示與菜單用語",
  },
  "textPick.scene": { ja: "場面", en: "Where", "zh-TW": "場合" },
  "textPick.difference": { ja: "違い", en: "Diff", "zh-TW": "差別" },
  "capture.toHome": { ja: "ホームへ", en: "Go Home", "zh-TW": "回首頁" },
  "capture.oneMore": { ja: "もう一枚撮る", en: "Take another", "zh-TW": "再拍一張" },
  "capture.reunion": { ja: "再会！", en: "Reunion!", "zh-TW": "重逢！" },
  "capture.rememberQ": {
    ja: "意味、覚えてる？ — タップして答え合わせ",
    en: "Do you remember it? — tap to check",
    "zh-TW": "還記得意思嗎？— 點一下對答案",
  },
  "capture.remembered": { ja: "覚えてた！", en: "I remembered!", "zh-TW": "記得！" },
  "capture.forgot": { ja: "忘れてた…", en: "I forgot…", "zh-TW": "忘記了…" },
  "capture.reviewBest": {
    ja: "現実世界での復習、最強です 🎉",
    en: "Real-world review — the strongest kind 🎉",
    "zh-TW": "在真實世界裡複習，效果最強 🎉",
  },
  "capture.willAsk": {
    ja: "大丈夫、明日また出題します",
    en: "No worries — we'll ask again tomorrow",
    "zh-TW": "沒關係，明天會再出一次",
  },
  "capture.shootAnother": {
    ja: "別のものを撮る",
    en: "Shoot something else",
    "zh-TW": "拍別的東西",
  },
  "capture.seeInDex": { ja: "図鑑で見る", en: "See it in Dex", "zh-TW": "在圖鑑裡看" },
  "home.pendingDiscard": { ja: "捨てる", en: "Discard", "zh-TW": "丟掉" },
  // **結果を言う。** 「本当に捨てる?」では何が消えるか分からない。
  // この帯は複数枚を数えているが、捨てるのは上に写っている1枚だけ。
  "home.pendingDiscardConfirm": {
    ja: "この写真を捨てる",
    en: "Discard this photo",
    "zh-TW": "丟掉這張照片",
  },
  "home.pendingDiscardCancel": { ja: "やめる", en: "Cancel", "zh-TW": "取消" },
  "home.pendingCta": {
    ja: "タップしてAI解析を再開する",
    en: "Tap to resume AI analysis",
    "zh-TW": "點一下重新開始 AI 分析",
  },
  "home.pendingCount": {
    ja: "解析待ちの写真 {n}枚",
    en: "{n} {n|photo|photos} waiting for analysis",
    "zh-TW": "等待分析的照片 {n} 張",
  },
  "card.openMapsLabel": {
    ja: "Google マップで開く →",
    en: "Open in Google Maps →",
    "zh-TW": "用 Google 地圖打開 →",
  },
};

export function useUiLang(): UiLang {
  // 初回は必ず "ja" を返す。
  //
  // サーバー側は localStorage を読めないので "ja" で描画する。ここで
  // クライアントの初回レンダーだけ localStorage を読んで "en" を返すと、
  // hydration でサーバーとクライアントの文字列が食い違い、React が
  // 「Hydration failed」を出してツリー全体を作り直す。1回分の描画が無駄に
  // なるうえ、コンソールが常にエラーで埋まって本当の不具合が埋もれる。
  //
  // 代わりにマウント後の effect で本当の言語に切り替える。英語表示の人には
  // 一瞬だけ日本語が見えるが、これは localStorage に言語を持つ設計上の
  // トレードオフ(サーバーに知らせるには Cookie にする必要がある)。
  const [lang, setLang] = useState<UiLang>("ja");
  useEffect(() => {
    const h = () => {
      const next = getUiLang();
      setLang(next);
      // 読み上げソフトや繁体字以外の字形選択のため、文書の言語も合わせる。
      const attr = htmlLangOf(next);
      if (document.documentElement.lang !== attr) document.documentElement.lang = attr;
    };
    h();
    window.addEventListener(EVENT, h);
    window.addEventListener("storage", h);
    return () => {
      window.removeEventListener(EVENT, h);
      window.removeEventListener("storage", h);
    };
  }, []);
  return lang;
}

/**
 * 文中の `{name}` を値に差し替える。
 *
 * **英語の単数・複数**（2026-10-03 全画面の点検「1 photos」「met 1 times」「Caught 1 words
 * today」）: `{n|photo|photos}` と書くと、`n` が 1 のとき左、それ以外は右になる。
 * 日本語・繁體中文には数の形が無いので使わない（英語の文だけに書く）。数そのものは
 * 今まで通り `{n}` で入れる — `"{n} {n|photo|photos}"`。
 */
export function fill(tpl: string, vars?: Vars): string {
  if (!vars) return tpl;
  return tpl
    .replace(/\{(\w+)\|([^{}|]*)\|([^{}|]*)\}/g, (m, k, one, other) =>
      k in vars ? (Number(vars[k]) === 1 ? one : other) : m,
    )
    .replace(/\{(\w+)\}/g, (m, k) => (k in vars ? String(vars[k]) : m));
}

export type Vars = Record<string, string | number>;

/**
 * `const t = useT(); t("nav.home")` — 未登録キーはキーをそのまま返す。
 *
 * 数や名前が入る文は `{}` で埋め込む:
 *   t("tree.branches", { done: 3, total: 8 })
 *     ja: "枝 {done}/{total} 本" → 「枝 3/8 本」
 *     en: "{done} of {total} branches"
 * language ごとに語順が違うので、文を分割して連結してはいけない。
 * 「{n}日前」のような文も、英語では "{n} days ago" と語順が変わる。
 */
export function useT(): (key: string, vars?: Vars) => string {
  const lang = useUiLang();
  // useCallback で包む理由: 毎回新しい関数を返すと、t を useEffect や
  // useCallback の依存に入れた途端に毎レンダー再実行される。逆に依存から
  // 外すと eslint に怒られ、言語を切り替えても中の文が古いままになる。
  // 言語ごとに1つの関数にしておけば、依存に素直に入れられる。
  return useCallback(
    (key: string, vars?: Vars) => fill(DICT[key]?.[lang] ?? DICT[key]?.ja ?? key, vars),
    [lang],
  );
}

/**
 * React の外(通知の文面など)で翻訳したいとき用。
 * フックが使えないので、その場で localStorage を読む。
 */
export function tStatic(key: string, vars?: Vars): string {
  const lang = getUiLang();
  return fill(DICT[key]?.[lang] ?? DICT[key]?.ja ?? key, vars);
}
