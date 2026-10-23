/**
 * 学習言語ごとの**違いを1つの表に集める**。
 *
 * オーナー指示 2026-08-24:
 * > 「アプリ内の**すべての項目**について学習言語、英語と台湾華語で変更すべき
 * >  ことを変更して。例えば単語の詳細の項目や解説は英語と台湾華語で違うよね。
 * >  **他にあるはず。**」
 *
 * ## なぜ表にするのか
 * `zh-TW` 前提の決め打ちが**約90ファイル**に散っている。数えたら、
 * 「注音」「量詞」「台湾」「TOCFL」のどれかに触れているファイルがそれだけある。
 * 言語をもう1つ増やすとき、その90箇所を1つずつ見つけて直すことになる。
 * **見落としても型でもビルドでも落ちない** — 落ちるのは、英語版の利用者の
 * 画面に量詞の欄が出たときだけ。
 *
 * `target-lang.ts` で「どの言語か」は1箇所に寄せた。ここはその次の段で、
 * **「その言語では何がどう違うか」**を寄せる。
 *
 * ## 項目を**データ**にする
 * いちばん効くのがこれ。`sections` に並んでいる物だけがカードに出る。
 *
 *   - 量詞(`measure_words`)は英語に**存在しない**
 *   - 活用(`forms`)は中国語に**存在しない**
 *
 * これを「学習言語を直に比べる `if`」で書くと、画面と生成の2箇所に同じ条件が
 * 生えて必ず片方だけ直す(この app が声・写真・演出で繰り返した形)。
 * 並びを1つ置いて、画面も生成もそれを回す。
 *
 * ## この段では見た目を変えない
 * `zh-TW` の値は**いまと1つも変えていない**。英語の定義は書いてあるが、
 * `TARGET_LANGUAGES` にまだ `"en"` が無いので画面には出ない。
 * 検査で同じ絵が出ることが、この段の合格条件。
 *
 * 外の世界に触れるものをここに入れないこと。
 */

import { hasJapaneseOnlyKanji } from "./kanji-forms";
import { CEFR_SCALE, JLPT_SCALE, TOCFL_SCALE, type LevelScale } from "./level-scale";
import { DEFAULT_TARGET_LANGUAGE, normalizeTargetLanguage, speechLangOf } from "./target-lang";

/**
 * カードに並びうる項目。
 *
 * `card-sections.ts` の `SECTION_IDS` は**いま作っている物**の並びで、
 * こちらは**言語ごとに存在しうる物**の全体。英語だけの項目もここに居る。
 *
 * **ネットの画像・追加の例文・発音のコツ・覚え方**の4つは、どの言語の
 * `sections` からも外した（オーナー指示 2026-10-02「単語の項目から消して」）。
 * 名前はここに残す — 保存済みのカードの中身と、作り直しの窓口（iOS 版も使う）の型のため。
 */
export type ProfileSection =
  // 両方にある
  | "meaning"
  | "web_images"
  | "example"
  | "examples_extra"
  | "usage_chunks"
  | "related_words"
  | "pronunciation_tips"
  | "etymology"
  | "mnemonic"
  | "real_usage"
  // 台湾華語だけ
  | "measure_words"
  | "taiwan_note"
  // 英語だけ
  | "forms"
  | "countability"
  | "stress"
  | "phrasal_verbs"
  | "culture_note"
  // 日本語だけ(2026-10-01)。日本語の仕組みそのものから来る節:
  // 漢字の字ごとの意味と音訓・高低アクセント・活用・敬語(丁寧さ)・
  // 助数詞・語種(和語/漢語/外来語)・日本の一言メモ。
  | "kanji_breakdown"
  | "pitch_accent"
  | "conjugation"
  | "politeness"
  | "counters"
  | "word_origin"
  | "japan_note";

/**
 * 読みの種類。設定で「どちらか一方だけ」を出す。
 *
 * 日本語は `kana`(ひらがなの読み=ふりがな)が既定、`romaji`(ヘボン式)が2つめ。
 * 保存の欄は台湾華語と同じ「読み1・読み2」(`reading_zhuyin` / `pinyin` の列)を使う —
 * 列の名前は古いが、中身をどの表記として読むかはこの並びが決める(`neutralReadings`)。
 */
export type ReadingKind = "zhuyin" | "pinyin" | "ipa-us" | "ipa-uk" | "kana" | "romaji";

/**
 * 日記・スキャンの指示文で、**その言語ごとに変わる言い回し**。
 *
 * ## なぜ別の束にしたか
 * 日記の添削と書き出し(`journal.functions.ts`)・写真の検出(`scan.functions.ts`)は、指示文が
 * 「台湾華語(zh-TW)のネイティブ講師」「繁体字」「量詞」と**直に書かれていた**。
 * 日本語を学習言語に足した日(2026-10-01)に、日本語を学ぶ人へ「繁体字で添削して」と
 * 頼むことになる。言い回しの差だけをここに集め、指示文の骨組みは1つのまま回す。
 *
 * **台湾華語の値はいまの文を1文字も変えずに写した物。** 英語はまだ英語向けの文を
 * 持っていないので、今回は台湾華語と同じ値を使う(振る舞いを変えない — 直すのは別の回)。
 */
export type CoachPhrases = {
  /** 日記の添削者・先生の呼び名に付く言語名(「台湾華語(繁體字)」)。 */
  journalLanguage: string;
  /** 日記で「◯◯のネイティブ」と呼ぶ人(「台湾のネイティブ」)。 */
  journalNatives: string;
  /** 日記で書く字の名前(「繁體字」)。 */
  journalScript: string;
  /** 日記の書き出しの形の例(「我今天在…」)。 */
  journalOpener: string;
  /** 写真の検出の見出し(「◯◯の学習アプリの検出エンジンです」の◯◯)。 */
  scanEngineLabel: string;
  /** 写真の検出の字の決まり(1行)。 */
  scanScriptRule: string;
  /** 写真の検出で埋めさせる読みの欄の説明。 */
  scanReadingRule: string;
  /** 写真の検出の出力見本の1件(`headword`〜`meaning_ja` の部分)。 */
  scanSample: string;
  /** 部品の検出で言語を呼ぶ名前(「台湾華語(繁体字/注音)」)。 */
  partsLanguage: string;
  /** 部品の検出の字・級の決まり(1行)。 */
  partsRule: string;
  /** 部品の検出の例(「手→拇指/手掌/指甲/手腕」)。 */
  partsExample: string;
  /** 部品の検出の出力見本の1件(`headword`〜`meaning_ja` の部分)。 */
  partsSample: string;
  /** 4択の誤答を作るときの、その語の呼び方(「◯◯の単語」)。 */
  quizWordLabel: string;
};

/**
 * 単語帳の写真から語を読み取るときの言い回し。
 *
 * オーナー方針(2026-10-01)「単語帳の取り込みも学習言語に付いていく」。前は
 * 台湾華語に決め打ちで、英語・日本語の単語帳を撮っても繁体字に直そうとしていた。
 */
export type WordbookPhrases = {
  /** 「◯◯の学習アプリの、単語帳読み取りエンジンです」の◯◯。 */
  engineLabel: string;
  /** 字・綴りの決まり(1行)。 */
  scriptLine: string;
  /** 読みと意味を写す/補う決まり(1行)。 */
  readingLine: string;
  /** 出力見本の1件(`headword`〜`pinyin` の部分)。 */
  sample: string;
};

export type TargetProfile = {
  code: string;
  /** 読み上げに渡す BCP-47。**学習言語と同じとは限らない。** */
  speechLang: string;
  /**
   * `lang` 属性に入れる値。
   *
   * 漢字は同じ文字コードでも言語で字形が違う(直/直、每/毎)ので、
   * 繁体字は `zh-Hant` を必ず付ける。英語は付けなくても字形が変わらないので
   * `en` でよい(付けて困ることも無い)。
   */
  scriptLang: string;
  /**
   * 読みの表記。**先頭が既定**。
   * 設定の切替(`phonetic.tsx`)はこの並びから選ぶ。
   */
  readings: readonly ReadingKind[];
  /** その言語のカードに出る項目(上から順)。 */
  sections: readonly ProfileSection[];
  /**
   * **プロンプトの中でこの言語を何と呼ぶか。**
   *
   * 生成の指示文は日本語で書いてあり、その中に
   * 「台湾華語(繁体字)の単語「~」について」と**直に書かれていた**。
   * 英語のカードをそこへ流すと、AI は英語の語を渡されながら
   * 「台湾華語の単語だ」と言われる。呼び名は言語ごとに違うので、
   * 言語の表が持つ。
   *
   * アメリカ英語を既定にする決定(オーナー 2026-08-24)も、
   * ここに書いてあることで生成まで届く。
   */
  promptName: string;
  /** 日記・スキャンの言い回し(`CoachPhrases` の注)。 */
  coach: CoachPhrases;
  /** 単語帳の読み取りの言い回し。 */
  wordbook: WordbookPhrases;

  /**
   * **撮った写真から語を出すとき**の、その言語ならではの指示。
   *
   * ## なぜ表にするか
   * `ai.functions.ts` のプロンプトは
   * `data.targetLanguage === DEFAULT_TARGET_LANGUAGE ? 長い指示 : 1行`
   * という**2分岐**になっていた。台湾華語には40行の細かい指示（カテゴリの
   * 規則・「上位の分類語に逃げない」・使い分けを書く条件）が在るのに、
   * それ以外は「有用な名詞を5つ選んでください」の1行に落ちる。
   *
   * 撮る道を学習言語に繋いだ日(2026-08-25)から、英語の学習者が**実際に
   * その1行に当たる**。カテゴリは other だらけになり、`en` という
   * コードがそのままプロンプトに出る。
   *
   * カテゴリの規則も「写っている物そのものの名前を出す」も、
   * **写真の話であって言語の話ではない**ので両方に効く。
   * 言語で変わるのはここに並ぶ物だけ。
   */
  capture: {
    /** 字・綴りの決めごと。 */
    scriptRule: string;
    /** 級ごとの「どこまで細かい名前で呼ぶか」の例（易→難の3段）。 */
    specificity: readonly [string, string, string];
    /** 使い分けを書くべき語の例（母語では1語なのに分かれる物）。 */
    distinctionExamples: string;
    /** 品詞の書き方。 */
    posRule: string;
    /**
     * AI を待たずに札を置くときの**仮の品詞**。
     *
     * ここを `"名詞"` で決め打ちしていたので、英語を学ぶ人の札にも
     * 日本語の「名詞」が入って保存されていた(オーナー報告
     * 「項目に英語日本語台湾華語が混ざる」)。`posRule` が AI に出させる
     * 記号と**同じ体系**の値を置く — 後から本物のカードが上書きしても
     * 記号がちぐはぐにならない。
     */
    defaultPos: string;
    /** 一句(フレーズ)として保存するときの品詞。 */
    phrasePos: string;
    /**
     * JSON の見本に書く**見出し語の値の見本**。
     *
     * 指示の本文を言語ごとに直しても、**最後に貼る JSON の見本が
     * `"headword":"繁体字"` のまま**だと、AI はそちらに従う —
     * 見本は指示より強い。英語を選んでいるのに台湾華語の語しか
     * 出てこなかった原因の1つ(オーナー報告①)。
     */
    jsonHeadwordHint: string;
    /** JSON の見本に書く読みの欄の値の見本。英語には注音も拼音も無い。 */
    jsonReadingHint: string;
    /**
     * 「写っている物そのものの名前を出す」の**具体例**。
     * 料理名・服の形の名前を、その言語の実際の語で並べる。
     */
    namingExamples: string;
    /**
     * **並び順の例**（オーナー指示 2026-09-27「ネイティブが一般的によく使う
     * 呼び方を上に。正確な名前・固有名詞は下に置くが消さない。具体性は失わない」）。
     */
    commonFirstExamples: string;
    /** 読みの欄の指示（注音・拼音 / 米式・英式の IPA）。 */
    readingRule: string;
    /**
     * 語源の書き方。**言語ごとに見る物が違う。**
     *
     * ここを分けていなかったので、英語のカードにも
     * 「漢字の語源・成り立ち」「部首と意味」を作らせていた
     * (オーナー指示「英単語の由来 — 古代・他言語からの派生、
     * **接頭語・接尾語** — を解説して」)。
     */
    etymologyRule: string;
    /**
     * 同じ語根・接頭辞・接尾辞を持つ仲間の語をどう出すか。
     * **空文字なら作らせない**(学習言語が英語のときだけ、というオーナー指示)。
     */
    relativesRule: string;
    /**
     * 語源に添える2行目(華語は部首)。**英語には無い**ので空にさせる。
     * 欄そのものは残す — 古い台湾華語の語が既に持っている。
     */
    radicalsRule: string;
    /**
     * その言語の「一言メモ」の項目名。
     *
     * 台湾華語は `taiwan_note`(台湾ならではの雑学)、英語は `culture_note`。
     * **生成の側もここを見る** — 前は生成の指示に `taiwan_note` が直に
     * 書いてあったので、英語のカードには**台湾の雑学を書けと言いながら
     * `culture_note` は一度も埋まらない**という形になっていた。
     */
    noteField: "taiwan_note" | "culture_note" | "japan_note";
    /**
     * 4択の**受け皿の見出し語**。撮った語がまだ少ない人のための埋め草。
     *
     * オーナー報告 2026-08-26:
     * > 「復習の4択が学習言語英語なのに台湾華語の単語が混ざってる」
     *
     * ここは `quiz-choices.ts` に台湾の語で直書きされていた。英語を
     * 学んでいる人の4択に**中国語が3つ並ぶ**のはこれが最後の出どころ。
     * 誤答があからさまに場違いだと消去法で当てられてしまうので、
     * **その言語で日常的に見る語**を選ぶ。
     */
    quizFallbackHeadwords: readonly string[];
    /** 受け皿の語の読み(4択に注音/IPA を出すため)。 */
    quizFallbackReadings: Readonly<Record<string, { zhuyin: string; pinyin: string }>>;
    /** その一言メモに何を書くか。 */
    noteRule: string;
    /**
     * 部首の行を**画面に出してよい言語か**。
     *
     * 指示で空にさせても、古いデータや AI の勇み足で中身が入ることは在る。
     * 「指示」と「描いてよいか」は別の話なので、真偽値で別に持つ。
     */
    hasRadicals: boolean;
    /**
     * 発音のコツで**その言語のどこを見るか**。
     * 華語は声調、英語は強勢。**混ぜると意味が無い** —
     * 英語に「声調の型」と言っても書けることが無い。
     */
    pronunciationFocus: string;
    /**
     * 関連語の見本(「物の名前で反義語が無いときは一緒に使う語を出す」の例)。
     *
     * 前は `code.startsWith("zh") ? 台湾の例 : 英語の例` の2分岐で、
     * 日本語のカードに英語の例(bubble tea → ice)が渡っていた。
     */
    relatedExample: string;
    /**
     * 読みと品詞を**2つの AI に別々に聞く**ときの、読みの欄の指示
     * (報告からの直しの突き合わせ。`askReadingTwice`)。
     */
    readingLookupRule: string;
    /** 例文に入れてよい「生きた話題」の出どころ(人物・文化・食べ物…)。 */
    exampleLocalTopics: string;
    /** 生きた話題を使うときの優先(空なら言わない)。 */
    exampleLocalPreference: string;
    /**
     * スキャンの候補に「**台湾の言い方として疑わしいか**」の札を付けるか
     * (`rankScanCandidates` の `doubtful`)。台湾の標準語かを問う問いなので、
     * 日本語の語に掛けるとかなの語がすべて「疑わしい」になる。
     */
    taiwanTermCheck: boolean;
  };
  /** 級の目盛り。 */
  levels: LevelScale;
  /**
   * チャンク(型)の役割の記号。
   * 中国語は量詞(M)と助詞(Ptc)が要るが、英語は冠詞(Det)と前置詞(Prep)が要る。
   */
  chunkRoles: readonly string[];
  /**
   * **型を作らせるときの言い方。**
   *
   * オーナー報告 2026-08-26（3度目）「単語のチャンク型の項目が
   * 生成されてない」の片割れ。指示は丸ごと台湾華語向けに書かれていて、
   *
   *   ・「繁体字で8文字以内」… 英語には長さの目盛りとして意味が無い
   *   ・「量詞の欄と重なる型は作るな」… 英語に量詞は無い
   *   ・詞類表(V-sep / Ptc / Vs)… 英語に無い記号を選ばせている
   *
   * を英語のカードにもそのまま送っていた。**言語ごとに言い方を持つ。**
   */
  chunkPrompt: {
    /** 長さの決まり(その言語の数え方で書く)。 */
    lengthRule: string;
    /** その言語で気を付ける型の作り方。 */
    styleRule: string;
    /** `pos` に何を書くか(記号の一覧そのもの)。 */
    posRule: string;
    /**
     * 「公式・定理のような型」の例(`formulaChunkRule`)。
     * 前は `code.startsWith("zh")` の2分岐で、日本語に英語の例が渡っていた。
     */
    formulaExample: string;
    /** 型ぜんぶを文法的に正しく言うための、その言語の注意。 */
    formulaGrammar: string;
  };
  /** 見出し語として通してよいか。 */
  headwordOk: (raw: string) => boolean;
};

/**
 * かな(ひらがな・カタカナ)。長音符 ー は含めない — 単体では判定に使えない。
 *
 * **この3つと `core` は `target-language.ts` から動かしてきた物。**
 * あちらに置いたまま同じ判定をここにも書くと、`NON_CJK_LETTER` に
 * キリル文字が入っているのはあちらだけ、という食い違いが生まれる
 * (実際、最初の版のここは `[A-Za-z]` だけだった)。**正は1つ。**
 */
const KANA = /[ぁ-ゟァ-ヺヽヾ]/;
/**
 * 漢字(CJK統合漢字 + 拡張A + 繰り返し記号 々 + 漢数字のゼロ 〇)。
 *
 * 〇 は 2026-10-02 に足した（「二〇二六年」の 〇 は漢字の仲間として書かれる。
 * 足さないと 〇 だけの所で判定が漢字を見失う）。
 */
const HAN = /[㐀-䶿一-鿿々〇]/;
/** ラテン文字とキリル文字、ハングル。 */
const NON_CJK_LETTER = /[A-Za-zЀ-ӿ가-힯]/;

/** 英語の見出し語に使ってよい字(ラテン文字・アクセント付き・数字・&)。 */
const EN_HEADWORD = /^[A-Za-z0-9À-ÖØ-öø-ɏ&]+$/;
/** 英語の文字(数字だけの物を見出し語にしない)。 */
const EN_LETTER = /[A-Za-zÀ-ÖØ-öø-ɏ]/;

/**
 * 漢字に**じかに**くっついた大文字1〜3字(「T恤」の T、「卡拉OK」の OK)を落とす。
 *
 * 落とすのはこの形だけ。「烤肉 (BBQ)」の BBQ は漢字との間に空白と括弧が
 * 挟まる注釈なので残す（残ると落ちる → `coerceTargetHeadword` が「烤肉」に直す）。
 * 小文字の語（「文旦juice」）・4字以上（「文旦JUICE」）も残す。
 *
 * 後読み `(?<=…)` は使わない — 古い iPhone の Safari(16.4 未満)は
 * 正規表現そのものを読めず、**この表を読み込んだ画面が丸ごと動かなくなる**。
 */
function dropHanLatinAffixes(raw: string): string {
  return raw.replace(/[A-Za-z]+/g, (run, at: number, whole: string) => {
    if (run.length > 3 || !/^[A-Z]+$/.test(run)) return run;
    const before = whole[at - 1] ?? "";
    const after = whole[at + run.length] ?? "";
    return HAN.test(before) || HAN.test(after) ? "" : run;
  });
}

/** 見た目だけの飾り(空白・約物・記号)を落とす。 */
export function headwordCore(text: string): string {
  return (text ?? "")
    .replace(/\s+/g, "")
    .replace(/[，、。．・…！？!?,.:;：；「」『』（）()【】〔〕[\]{}"'‘’“”—–\-~〜]/g, "");
}

const core = headwordCore;

/**
 * 台湾華語の日記・スキャンの言い回し。
 *
 * **指示文に直に書かれていた文を1文字も変えずに写した物。** 英語も今回はこれを使う
 * (`EN_PROFILE.coach` の注)。
 */
const ZH_TW_COACH: CoachPhrases = {
  journalLanguage: "台湾華語(繁體字)",
  journalNatives: "台湾のネイティブ",
  journalScript: "繁體字",
  journalOpener: "「我今天在…」",
  scanEngineLabel: "台湾華語(zh-TW / 繁体字 / 注音)",
  scanScriptRule:
    "台湾教育部準拠の正式な繁体字を使用。大陸簡体字・大陸独自語彙は禁止(例: 出租车✗ → 計程車○)。",
  scanReadingRule:
    "各項目に zhuyin(注音)・pinyin・meaning_ja(日本語訳)・pos(名詞/動詞など日本語)を必ず埋める。",
  scanSample:
    '      "headword": "繁体字",\n' +
    '      "zhuyin": "ㄇㄤˊ ㄍㄨㄛˇ",\n' +
    '      "pinyin": "mángguǒ",\n' +
    '      "meaning_ja": "マンゴー",',
  partsLanguage: "台湾華語(繁体字/注音)",
  partsRule: "台湾教育部準拠の正式な繁体字。TOCFL 1〜3レベル優先",
  partsExample: "手→拇指/手掌/指甲/手腕",
  partsSample: '"headword":"拇指","zhuyin":"ㄇㄨˇ ㄓˇ","pinyin":"mǔzhǐ","meaning_ja":"親指"',
  quizWordLabel: "台湾華語の単語",
};

/**
 * 台湾華語(繁体字)。
 *
 * **この定義はいまの動きをそのまま写した物。** 1つも変えていない。
 */
export const ZH_TW_PROFILE: TargetProfile = {
  // **決め打ちの文字列をここに書かない。** 学習言語そのものの値は
  // `target-lang.ts` が唯一の正で、そこを見る門が `target-lang.test.ts` に
  // 立っている(実際この門が、最初の版の決め打ちを捕まえた)。
  code: DEFAULT_TARGET_LANGUAGE,
  speechLang: speechLangOf(DEFAULT_TARGET_LANGUAGE),
  scriptLang: "zh-Hant",
  readings: ["zhuyin", "pinyin"],
  sections: [
    "meaning",
    "example",
    "usage_chunks",
    "measure_words",
    "related_words",
    "taiwan_note",
    "real_usage",
  ],
  levels: TOCFL_SCALE,
  promptName: "台湾華語(繁体字)",
  coach: ZH_TW_COACH,
  wordbook: {
    engineLabel: "台湾華語(zh-TW / 繁体字 / 注音)",
    scriptLine: "台湾教育部準拠の繁体字で返す。簡体字で書かれていれば繁体字に直す。",
    readingLine:
      "注音・拼音・意味が**その頁に書かれていればそれを写す**。書かれていなければ、\n" +
      "  その語の正しい読みと意味を補ってよい(読みと意味は補ってよい唯一の項目)。",
    sample: '"headword":"繁体字","reading_zhuyin":"注音","pinyin":"拼音"',
  },
  capture: {
    scriptRule: "台湾教育部準拠の正式な繁体字（中国大陸の簡体字は不可）",
    specificity: [
      "**日常でその物を指すときの普通の名前**で呼ぶ(例: 「短袖」より「T恤」、「三杯雞」はそのまま「三杯雞」)。",
      "**店や献立で実際に使われる名前**まで細かく(例: 服なら「短袖」「洋裝」、料理なら「三杯雞」「滷肉飯」)。",
      "**その道の人が使う正確な名前**まで細かく(例: 「純棉短袖」「客家小炒」)。一般名詞は既に知っている。",
    ],
    distinctionExamples:
      "衛生紙→「トイレに置く方」/ 面紙→「持ち歩く箱・ポケット」、" +
      "湯→「スープ(お湯ではない)」のように、母語からの連想を外す必要があるとき",
    defaultPos: "N",
    phrasePos: "片語",
    jsonHeadwordHint: "繁体字",
    jsonReadingHint: '"reading_zhuyin":"注音","pinyin":"拼音"',
    namingExamples:
      "料理なら料理名（三杯雞・滷肉飯・珍珠奶茶）であって、材料名（雞肉・米）ではない。\n" +
      "  服なら形の名前（短袖・洋裝・外套）であって、上位の分類（衣服・服裝）ではない。\n" +
      "- **上位の分類語に逃げない。** 「衣服」「食物」「飲料」「動物」は、\n" +
      "  それ以上細かく呼べない写真のときだけ。",
    commonFirstExamples:
      "柚子（文旦ではなく、台湾の人がふだん呼ぶ柚子を上に。文旦は下に残す）、" +
      "奇岩・岩（女王頭は固有名詞なので下に残す）。" +
      "卡車帽・焗烤通心粉のように、あまり口にしない名前は下に置く",
    posRule:
      "台湾の詞類表の記号で: N/V/Vi/V-sep/Vs/Vst/Vs-attr/Vs-pred/Vs-sep/Vaux/Vp/Vpt/Vp-sep/Adv/Conj/Prep/M/Ptc/Det のどれか。\n" +
      "  V=及物動作動詞(買/做)、Vi=不及物(跑/坐)、Vs=状態動詞・形容詞(冷/漂亮)、Vst=及物状態(喜歡)、Vaux=助動詞(會/能)、Vp=変化動詞(破/感冒)、M=量詞、Ptc=助詞。",
    readingRule: "- reading_zhuyin: 注音（ㄅㄆㄇ）。台湾教育部準拠。\n- pinyin: 拼音",
    etymologyRule: "漢字の語源・成り立ち(1〜2文)",
    /**
     * **仲間の語はどの学習言語でも出す**(オーナー指示 2026-08-26
     * 「やっぱり全ての学習言語で語源の項目の欄で、同じ語源や由来がある
     * 関連単語は表示して」)。英語だけなのは**接頭辞・接尾辞の分解**のほう。
     *
     * 華語で「同じ由来」がいちばん役に立つのは**同じ字(語素)を共有する語**。
     * 「電」を覚えれば電腦・電視・停電がまとめて読めるようになる。
     */
    relativesRule:
      "同じ字(語素)を共有する**仲間の語を2〜4語**。\n" +
      "  各 {word, note}。note はその字がその語で持つ意味を**5〜12字**で。\n" +
      "  例: 電話 なら 電腦(電で動く機械) / 電視(電で見る) / 停電(電が止まる)。\n" +
      "  **その字が本当に同じ意味で働いているときだけ**並べる。\n" +
      "  たまたま同じ字が入っているだけの語は入れない — 覚え違いの種になる。\n" +
      "  仲間が無ければ**空配列**。無理に埋めない。",
    radicalsRule: "部首と意味(1文)",
    noteField: "taiwan_note",
    quizFallbackHeadwords: ["蘋果", "公車", "雨傘", "便當"],
    quizFallbackReadings: {
      蘋果: { zhuyin: "ㄆㄧㄥˊ ㄍㄨㄛˇ", pinyin: "píngguǒ" },
      公車: { zhuyin: "ㄍㄨㄥ ㄔㄜ", pinyin: "gōngchē" },
      雨傘: { zhuyin: "ㄩˇ ㄙㄢˇ", pinyin: "yǔsǎn" },
      便當: { zhuyin: "ㄅㄧㄢˋ ㄉㄤ", pinyin: "biàndāng" },
    },
    noteRule:
      "台湾ならではの一言雑学（文化・習慣・歴史・流行）を1〜2文。" +
      "誤用しやすい語法の注意があれば1文追加",
    hasRadicals: true,
    pronunciationFocus: "この語の声調の型",
    relatedExample: "珍珠奶茶 → 甜度・冰塊・吸管・手搖飲",
    readingLookupRule:
      "台湾（教育部）の標準の読みを答えてください。reading は注音（声調記号つき、音節ごとに半角スペース区切り）、reading_alt は拼音（声調記号つき）。",
    exampleLocalTopics:
      "台湾の芸能人・歌手・スポーツ選手・歴史上の人物、台湾の文化・習慣・食べ物・街",
    exampleLocalPreference: "使うなら台湾のものを優先する。",
    taiwanTermCheck: true,
  },
  // S(主語)/V(動詞)/O(目的語)/M(修飾・量詞)/C(接続・介詞)/Ptc(助詞)
  chunkRoles: ["S", "V", "O", "M", "C", "Ptc"],
  chunkPrompt: {
    lengthRule:
      "型1つは繁体字で8文字以内・パーツ4つ以内。超えるものは型ではなく例文。" +
      "**句点・感嘆符・疑問符を入れない** — 文ではなく、そのまま口に乗せる塊。",
    styleRule:
      // オーナー指示 2026-08-27 ⑫⑮「量詞の項目があるから、チャンクでは
      // 同じようなものを表示させないで」「決して被らせないで」。
      "**量詞を1つも使わない。** 量詞は別の欄で読むので、ここに出てきた時点で" +
      "重なっている(動詞が付いていても同じ)。pos に M を付ける札を作らない。\n" +
      "動詞+目的語だけに寄せず、状態動詞(Vs)・助動詞(Vaux)・副詞(Adv)・介詞(Prep)の型も" +
      "**頻度が高ければ**入れる(品詞を埋めるために低頻度の型を作らない)。",
    posRule:
      "pos は台湾の詞類表の記号を使う: N(名詞)/V(及物動詞)/Vi(不及物)/V-sep(離合詞)/" +
      "Vs(状態動詞=形容詞)/Vst(状態及物)/Vs-attr/Vs-pred/Vs-sep/Vaux(助動詞)/" +
      "Vp(変化動詞)/Vpt/Vp-sep/Adv(副詞)/Conj(接続詞)/Prep(介詞)/M(量詞)/Ptc(助詞)/Det(限定詞)。" +
      "**文を構成する全パーツに付ける**(助詞の「的」「了」「嗎」、副詞の「很」「已經」、" +
      "限定詞の「這」も省かない)。役割記号(S/O/C/P)は使わない。" +
      // 2026-10-22 オーナー「用の品詞が間違ってる」→ 教育部《重編國語辭典》の 用 [介]「表示憑藉」、
      // TBCL の 用 V/Prep（例: 我用筷子吃飯）に合わせる。同じ形の語は同じ記号に揃える。
      "\n用・拿・跟・給・在・幫・從・往・對・替 が「名詞＋動詞」の前に来て手段・相手・場所を表すときは Prep" +
      "(用＋湯匙＋吃飯 → Prep/N/V、跟＋朋友＋見面 → Prep/N/V、在＋家＋吃飯 → Prep/N/V)。" +
      "後ろに別の動詞が無く、その語自体が型の動詞なら V(用＋電腦、拿＋東西、給＋他)。" +
      "把・被 は Ptc。",
    formulaExample:
      // 量詞を含む例（點＋一杯＋珍珠奶茶）は置かない — 量詞の型は表示で落とす（C10）。
      "見面 → 跟＋朋友＋見面、吵架 → 跟＋男朋友＋吵架 / 動不動就＋吵架、牽 → 牽著＋他＋的手、珍珠奶茶 → 珍珠奶茶＋半糖少冰 / 加＋珍珠、芒果 → 芒果＋很＋甜",
    formulaGrammar:
      "形容詞（状態動詞）を述語にするときは、裸で置かず程度副詞（很・超・好・太 など）を必ず入れる" +
      "（✗ 滷味＋入味 → ○ 滷味＋很＋入味、✗ 珍珠奶茶＋好喝 → ○ 珍珠奶茶＋超＋好喝）。" +
      // 2026-10-09「嘴邊肉＋切 / 嘴邊肉をする」— 屋台の頼み方「嘴邊肉切一盤」から量詞だけを抜いた形。
      "目的語は動詞の後ろに置く（✗ 嘴邊肉＋切 → ○ 切＋嘴邊肉）。" +
      "屋台の頼み方（嘴邊肉切一盤）のように量詞が無いと成り立たない形は、量詞を抜いて型にせず、別の型を選ぶ。" +
      // 2026-10-14「紙箱＋裝＋東西 これ正しくない / 裝＋熱水馬克杯 / 去冰が動詞になってる」。
      "容器と中身: 裝 の目的語は中身（✗ 裝＋紙箱 / ✗ 紙箱＋裝＋東西 → ○ 用＋紙箱＋裝＋東西 / ○ 把＋東西＋裝進＋紙箱、" +
      "○ 用＋馬克杯＋喝＋咖啡）。飲み物の注文の言い方（去冰・少冰・半糖・微糖・熱的）は飲み物の後ろ（○ 可樂＋去冰、○ 紅茶＋半糖）。",
  },
  headwordOk: (raw) => {
    // 「T恤」「卡拉OK」「Q彈」のような**漢字にくっついた大文字1〜3字**は、
    // 台湾華語の語の一部として普通に書く（候補の指示文も「短袖」より「T恤」と
    // 言っている）。そこだけ欧文を許し、ほかは落とす（下の注）。
    const s = core(dropHanLatinAffixes(raw ?? ""));
    if (!s) return false;
    // かなを含む(「シャーペン」)、欧文を含む(「pencil」)は通さない。
    // 通すと**自分の母語を台湾華語の単語として覚える**ことになる。
    if (KANA.test(s)) return false;
    if (NON_CJK_LETTER.test(s)) return false;
    // **漢字だけの日本語も通さない**（2026-10-15、`kanji-forms.ts`）。「図鑑」「駅」の 図・駅 は
    // 台湾では 圖・驛 と書く — 通すと日本語の字のまま台湾華語の語として覚える。
    if (hasJapaneseOnlyKanji(s)) return false;
    return HAN.test(s);
  },
};

/**
 * 英語(アメリカ英語を既定)。
 *
 * オーナー決定 2026-08-24: 「**アメリカ英語を既定**」
 * (台湾の学習者の多数派で、TOEFL もアメリカ英語)
 *
 * ## 台湾華語と項目が違う所
 * - `measure_words` **無し** … 英語に量詞は無い
 * - `forms` **有り** … 複数形・過去・過去分詞・比較級。ECDICT の
 *   `exchange` 欄から**AI呼び出しゼロ**で入る
 * - `countability` **有り** … 可算/不可算と冠詞。中国語話者の最大の誤り
 *   (中国語に冠詞が無い)
 * - `stress` **有り** … どの音節を強く読むか。通じるかどうかを最も左右する
 * - `phrasal_verbs` **有り** … 動詞のカードで量詞の枠が空く所に入る
 * - `taiwan_note` → `culture_note` … 米/英の違い(elevator / lift)
 */
export const EN_PROFILE: TargetProfile = {
  code: "en",
  speechLang: "en-US",
  scriptLang: "en",
  // 読み1・読み2の列に入る IPA(生成と辞書が書く)。**画面には出さない**
  // (オーナー指示 2026-09-30・2026-10-02「英語の発音記号」は消す。`phonetic.tsx`)。
  readings: ["ipa-us", "ipa-uk"],
  sections: [
    "meaning",
    "example",
    "usage_chunks",
    "forms",
    "countability",
    "phrasal_verbs",
    "related_words",
    "stress",
    "culture_note",
    "real_usage",
  ],
  levels: CEFR_SCALE,
  // オーナー決定 2026-08-24「アメリカ英語を既定」。生成にもそう言う。
  promptName: "英語(アメリカ英語)",
  // 英語向けの日記の文はまだ無い。**今回は台湾華語の文のまま**にして
  // 振る舞いを変えない(英語の人に「繁体字で」と頼んでいるのは前からの課題)。
  coach: ZH_TW_COACH,
  // 単語帳はオーナー方針で学習言語に付いていく(2026-10-01)。
  wordbook: {
    engineLabel: "英語(アメリカ英語)",
    scriptLine:
      "アメリカ英語の綴りで返す(colour → color)。見出し語は原形(複数形・過去形にしない)。",
    readingLine:
      "意味が**その頁に書かれていればそれを写す**。書かれていなければ、その語の正しい意味を補ってよい。\n" +
      "  英語に注音・拼音は無いので reading_zhuyin と pinyin は空文字。",
    sample: '"headword":"English word","reading_zhuyin":"","pinyin":""',
  },
  capture: {
    scriptRule: "アメリカ英語の綴り（color / center。イギリス式の綴りは使わない）",
    specificity: [
      "**日常でその物を指すときの普通の名前**で呼ぶ(例: 「garment」より「T-shirt」、「beverage」より「coffee」)。",
      "**店や献立で実際に使われる名前**まで細かく(例: 服なら「hoodie」「blazer」、料理なら「fried rice」「clam chowder」)。",
      "**その道の人が使う正確な名前**まで細かく(例: 「raglan sleeve」「cold brew」)。一般名詞は既に知っている。",
    ],
    distinctionExamples:
      "shrimp→「小ぶり・アメリカでの普通の言い方」/ prawn→「大ぶり・英豪でよく使う」、" +
      "napkin→「食事のときの紙・布」/ tissue→「鼻をかむ方」のように、母語からの連想を外す必要があるとき",
    defaultPos: "noun",
    phrasePos: "phrase",
    jsonHeadwordHint: "English word",
    // 英語に注音・拼音は無い。**空文字を見本に置く** — ここに
    // `"注音"` と書いてあると、AI は何かを埋めようとして
    // ローマ字や IPA を注音の欄に入れてくる。
    jsonReadingHint: '"reading_zhuyin":"","pinyin":""',
    namingExamples:
      "料理なら料理名（beef noodle soup・bubble tea・eggs benedict）であって、材料名（beef・rice）ではない。\n" +
      "  服なら形の名前（hoodie・blazer・cardigan）であって、上位の分類（clothes・clothing）ではない。\n" +
      "- **上位の分類語に逃げない。** 「clothes」「food」「drink」「animal」は、\n" +
      "  それ以上細かく呼べない写真のときだけ。",
    commonFirstExamples:
      "cap（trucker cap は下に残す）、rock / rock formation（Queen's Head のような固有名詞は下に残す）",
    posRule:
      "英語の品詞で: noun/verb/adjective/adverb/preposition/conjunction/pronoun/determiner/interjection のどれか。\n" +
      "  句動詞は verb、複合名詞は noun。",
    readingRule:
      "- reading_zhuyin: **空文字**（英語に注音は無い）\n" +
      "- pinyin: **空文字**（英語に拼音は無い）\n" +
      "- ipa_us: アメリカ英語の IPA（強勢記号 ˈ ˌ を必ず付ける。例: ʌmˈbrɛlə）\n" +
      "- ipa_uk: イギリス英語の IPA（違いが無ければアメリカ式と同じで良い）",
    etymologyRule:
      "語の由来(1〜2文)。ラテン語・ギリシャ語・古英語などの**出どころ**を書く。\n" +
      "  そのうえで**接頭辞・接尾辞・語根に分解**し、その部品が持つ意味を書く。\n" +
      "  例: re-(再び) + ject(投げる) → reject / bio-(生命) + -logy(学問) → biology。\n" +
      "  分解できない語(get, dog など)は無理に分けず、出どころだけを書く。",
    /**
     * **仲間の語**(オーナー指示「同じ語源や接頭辞、接尾辞を持つ関連語、
     * 派生語があれば紹介して」)。語根を1つ覚えると芋づるで増えるのが
     * 英語の語彙の性質なので、ここがいちばん効く。
     */
    relativesRule:
      "同じ語根・接頭辞・接尾辞を持つ**仲間の語を2〜4語**。\n" +
      "  各 {word, note}。note はその部品が何を意味するかを**5〜12字**で。\n" +
      "  例: reject なら inject(中へ投げる) / eject(外へ投げる) / project(前へ投げる)。\n" +
      "  **共通の部品が本当に同じ意味のときだけ**並べる。綴りが似ているだけの語\n" +
      "  (understand と stand など)は入れない — 覚え違いの種になる。\n" +
      "  仲間が無ければ**空配列**。無理に埋めない。",
    // 英語に部首は無い。**空にさせる** — 何か書けと言うと、AI は
    // 綴りの一部を「部首」と呼び始める。
    radicalsRule: "**空文字**(英語に部首は無い)",
    /**
     * オーナー指示 2026-08-26:
     * > 「台湾人が学習言語英語で勉強する時、単語の項目の台湾ノートは
     * >  要らない。そのかわりひと言単語に関する雑学や知識やを
     * >  コメントをかいて」
     *
     * 台湾の話ではなく、**その語そのものの雑学**を書く場所にする。
     */
    noteField: "culture_note",
    // 街で日常的に見る語。読みはアメリカ英語の IPA(既定の読み)。
    quizFallbackHeadwords: ["apple", "bus", "umbrella", "lunch box"],
    quizFallbackReadings: {
      apple: { zhuyin: "ˈæpəl", pinyin: "ˈæpl" },
      bus: { zhuyin: "bʌs", pinyin: "bʌs" },
      umbrella: { zhuyin: "ʌmˈbrelə", pinyin: "ʌmˈbrelə" },
      "lunch box": { zhuyin: "ˈlʌntʃ bɑks", pinyin: "ˈlʌntʃ bɒks" },
    },
    noteRule:
      "その語にまつわる**一言雑学**を1〜2文。" +
      "語源の面白い由来・商標や作品での使われ方・その語から来た言い回し・" +
      "英語圏の習慣など、**読んで記憶に引っかかること**を選ぶ。" +
      "米国と英国で言い方が違う語(elevator / lift)なら、その違いを1文足す。" +
      "**台湾の話は書かない**",
    hasRadicals: false,
    pronunciationFocus: "この語のどの音節を強く読むか",
    relatedExample: "bubble tea → sweetness level, ice, straw",
    readingLookupRule:
      "reading はアメリカ英語の IPA、reading_alt はイギリス英語の IPA（どちらも / / なし）。",
    exampleLocalTopics: "英語圏と世界で広く知られた人物・作品・スポーツ・文化・習慣",
    exampleLocalPreference: "",
    // 本来は要らない問い(英語の語に「台湾の標準か」を聞いている)。今回は振る舞いを変えない。
    taiwanTermCheck: true,
  },
  // S/V/O/Adv(副詞)/Prep(前置詞)/Det(冠詞・限定詞)
  chunkRoles: ["S", "V", "O", "Adv", "Prep", "Det"],
  chunkPrompt: {
    // **語の数で言う。** 「8文字以内」と言うと `put on socks` すら作れない。
    lengthRule:
      "型1つは4語以内・パーツ4つ以内。超えるものは型ではなく例文。" +
      "**ピリオド・感嘆符・疑問符を入れない** — 文ではなく、そのまま口に乗せる塊。",
    styleRule:
      "冠詞(a/the)・前置詞・複数形の -s まで**型の中に入れる** — " +
      "中国語話者がいちばん落とすのがそこなので、型がそれを含んでいないと練習にならない。\n" +
      "動詞+目的語だけに寄せず、形容詞+名詞・前置詞句・句動詞の型も**頻度が高ければ**入れる。",
    posRule:
      "pos は英語の品詞の記号を使う: n(名詞)/v(動詞)/adj(形容詞)/adv(副詞)/" +
      "prep(前置詞)/det(冠詞・限定詞)/pron(代名詞)/conj(接続詞)/aux(助動詞)/part(不変化詞)。" +
      "**全パーツに付ける**(a / the / on も省かない)。役割記号(S/O/C/P)は使わない。",
    formulaExample:
      "meet → meet up with + a friend、argue → argue with + my boyfriend、hold → hold + his + hand",
    formulaGrammar:
      "冠詞・前置詞・語形変化を省かない（✗ argue with boyfriend → ○ argue with + my boyfriend）。",
  },
  headwordOk: (raw) => {
    const s = core(raw);
    if (!s) return false;
    // 漢字・かなを含む物は英語の見出し語ではない(母語のまま入るのを止める)。
    if (KANA.test(s) || HAN.test(s)) return false;
    // ラテン文字を**含む**ではなく、ラテン文字**だけ**でできていること。
    // 「안녕」も「Привет」も英語の見出し語ではない。飾り(空白・約物・
    // アポストロフィ・ハイフン)は `core` が既に落としているので、
    // "night market" は "nightmarket"、"don't" は "dont" になって通る。
    //
    // 2026-10-02: 数字・アクセント付きのラテン文字・& も通す
    // （"7-Eleven" "café" "jalapeño" "R&B"）。保存の関所（`upsertWord`）が
    // この判定を使うようになったので、英語として正しい語を落とすと
    // その語が図鑑に入れられなくなる。**文字が1つも無い物（"123"）は落とす。**
    return EN_HEADWORD.test(s) && EN_LETTER.test(s);
  },
};

/**
 * 日本語(現代の標準語。東京式アクセント)。
 *
 * 2026-10-01 に足した。**iOS 版が先**に出すので、Web の選択肢
 * (`WEB_TARGET_CHOICES`)にはまだ並べない。学ぶのは英語か繁體中文で読む人で、
 * 解説は必ずその人の表示言語で書く(`explanationLanguageRule`)— 日本語を
 * 学ぶ人に日本語の解説を渡しても読めない。
 *
 * ## 台湾華語・英語と項目が違う所 — 日本語の仕組みから来る物
 * - `kanji_breakdown` **有り** … 語の中の漢字1字ずつの意味と音読み・訓読み。
 *   日本語の漢字は1字に読みが複数あり、語ごとにどれを使うかが決まる
 *   (生: 生活=せい / 生まれる=う / 生ビール=なま)。かなだけの語には無い
 * - `pitch_accent` **有り** … 高低アクセント(東京式)。箸(ハ↘シ)と橋(ハシ↗)は
 *   高さの型だけで別の語になる。英語の強勢・中国語の声調とも違う仕組み
 * - `conjugation` **有り** … 動詞・い形容詞・な形容詞の活用(辞書形・ます形・
 *   て形・ない形・た形)。名詞には無い
 * - `politeness` **有り** … 敬語・丁寧さ。同じ意味でも相手で語が変わる
 *   (食べる / 召し上がる / いただく)。日本語でいちばん「母語に無い」所
 * - `counters` **有り** … 助数詞(一本・一枚・一匹)。台湾華語の量詞に似ているが別物
 *   で、数との組み合わせで音が変わる(いっぽん・さんぼん・ろっぽん)
 * - `word_origin` **有り** … 語種(和語・漢語・外来語)。硬さ・場面がこれでほぼ決まる
 *   (宿屋 / 旅館 / ホテル)
 * - `taiwan_note` / `culture_note` → `japan_note` … 日本ならではの一言
 * - `measure_words` / `forms` / `stress` **無し**
 */
const JA_COACH: CoachPhrases = {
  journalLanguage: "日本語(現代の標準語)",
  journalNatives: "日本のネイティブ",
  journalScript: "日本語(漢字かな交じり)",
  journalOpener: "「今日は…で…」",
  scanEngineLabel: "日本語(標準語 / 漢字かな交じり / ひらがなの読み)",
  scanScriptRule:
    "現代日本語の標準的な表記を使用(常用漢字で書くのが普通の語は漢字、外来語はカタカナ)。中国語の簡体字・繁体字の字形は禁止(例: 图书馆✗ 圖書館✗ → 図書館○)。",
  scanReadingRule:
    "各項目に zhuyin(この欄は**ひらがなの読み**)・pinyin(この欄は**ヘボン式ローマ字**)・meaning_ja(解説の言語での意味)・pos(名詞/動詞など日本語)を必ず埋める。",
  scanSample:
    '      "headword": "日本語の語",\n' +
    '      "zhuyin": "まんごー",\n' +
    '      "pinyin": "mangō",\n' +
    '      "meaning_ja": "意味(解説の言語で)",',
  partsLanguage: "日本語(漢字かな交じり/ひらがなの読み)",
  partsRule: "現代日本語の標準的な表記(外来語はカタカナ)。JLPT N5〜N3 の語を優先",
  partsExample: "手→親指/手のひら/爪/手首",
  partsSample:
    '"headword":"親指","zhuyin":"おやゆび","pinyin":"oyayubi","meaning_ja":"意味(解説の言語で)"',
  quizWordLabel: "日本語の単語",
};

/** 日本語の文字(かな・漢字・長音符・々・〆・ヶ)だけでできているか。 */
const JA_ONLY = /^[ぁ-ゟァ-ヺー・ヽヾ㐀-䶿一-鿿々〇〆ヶ]+$/;

export const JA_PROFILE: TargetProfile = {
  code: "ja",
  speechLang: speechLangOf("ja"),
  // `lang="ja"` を付ける。付けないと、繁體中文の画面では漢字が台湾の字形で出る
  // (直・骨・角 の形が違う)。
  scriptLang: "ja",
  readings: ["kana", "romaji"],
  sections: [
    "meaning",
    "example",
    "usage_chunks",
    "kanji_breakdown",
    "conjugation",
    "politeness",
    "counters",
    "related_words",
    "pitch_accent",
    "word_origin",
    "japan_note",
    "real_usage",
  ],
  levels: JLPT_SCALE,
  promptName: "日本語(現代の標準語)",
  coach: JA_COACH,
  wordbook: {
    engineLabel: "日本語(漢字かな交じり / ひらがなの読み)",
    scriptLine:
      "現代日本語の標準的な表記で返す(外来語はカタカナ)。動詞・形容詞は辞書形で。中国語の字形で書かれていれば日本の字形に直す。",
    readingLine:
      "読み(ひらがな)・意味が**その頁に書かれていればそれを写す**。書かれていなければ、\n" +
      "  その語の正しい読みと意味を補ってよい(読みと意味は補ってよい唯一の項目)。\n" +
      "  reading_zhuyin の欄に**ひらがなの読み**、pinyin の欄に**ヘボン式ローマ字**を入れる。",
    sample: '"headword":"日本語の語","reading_zhuyin":"ひらがなの読み","pinyin":"ヘボン式ローマ字"',
  },
  capture: {
    scriptRule:
      "現代日本語の標準的な表記（常用漢字で書くのが普通の語は漢字、ふだん仮名で書く語は仮名、外来語はカタカナ。" +
      "中国語の簡体字・繁体字の字形は使わない — 例: 气・氣 ではなく 気、图书馆 ではなく 図書館）",
    specificity: [
      "**日常でその物を指すときの普通の名前**で呼ぶ(例: 「衣類」より「Tシャツ」、「飲料」より「お茶」)。",
      "**店や献立で実際に使われる名前**まで細かく(例: 服なら「パーカー」「ワンピース」、料理なら「親子丼」「味噌汁」)。",
      "**その道の人が使う正確な名前**まで細かく(例: 「ラグランスリーブ」「だし巻き卵」)。一般名詞は既に知っている。",
    ],
    distinctionExamples:
      "お湯→「温めた水」/ 水→「冷たい・常温の水」(日本語では温度で語が分かれる)、" +
      "着る→「シャツ・上着(上半身・全身)」/ 履く→「靴・ズボン・スカート(下半身)」/ かぶる→「帽子(頭)」のように、" +
      "母語からの連想を外す必要があるとき",
    defaultPos: "名詞",
    phrasePos: "フレーズ",
    jsonHeadwordHint: "日本語の語(漢字かな交じり)",
    // **欄の名前は台湾華語のときのまま。** 中身を言語ごとに読み替える
    // (`readings` の並び: 読み1=かな、読み2=ローマ字)。見本にも書いておかないと、
    // AI は「注音」の欄に注音を入れようとする。
    jsonReadingHint: '"reading_zhuyin":"ひらがなの読み","pinyin":"ヘボン式ローマ字"',
    namingExamples:
      "料理なら料理名（親子丼・味噌汁・たこ焼き）であって、材料名（鶏肉・米）ではない。\n" +
      "  服なら形の名前（パーカー・ワンピース・カーディガン）であって、上位の分類（服・衣類）ではない。\n" +
      "- **上位の分類語に逃げない。** 「服」「食べ物」「飲み物」「動物」は、\n" +
      "  それ以上細かく呼べない写真のときだけ。",
    commonFirstExamples:
      "帽子・キャップ（トラッカーキャップは下に残す）、じゃがいも（メークインは品種名なので下に残す）、" +
      "岩（〜岩のような固有名詞は下に残す）。ふだん口にしない硬い名前（馬鈴薯）は下に置く",
    posRule:
      "日本語の品詞で: 名詞/動詞/い形容詞/な形容詞/副詞/助詞/助動詞/接続詞/連体詞/感動詞/代名詞 のどれか。\n" +
      "  動詞は活用の種類を括弧で添える(動詞(五段) / 動詞(一段) / 動詞(する) / 動詞(来る))。「する」が付いて動詞になる名詞は 名詞(する)。",
    readingRule:
      "- reading_zhuyin: **ひらがなの読み**(ふりがな。この欄の名前は古いが、日本語ではかなの読みを入れる)。\n" +
      "  漢字を含む語はその語での正しい読みを全部ひらがなで(例: 今日 → きょう、生ビール → なまびーる)。\n" +
      "  カタカナだけの語は見出し語と同じカタカナでよい。\n" +
      "- pinyin: **ヘボン式ローマ字**(この欄も名前は古いが、日本語ではローマ字を入れる)。\n" +
      "  長音はマクロンで書く(例: とうきょう → tōkyō、がっこう → gakkō、ラーメン → rāmen)。",
    etymologyRule:
      "語の成り立ち・由来(1〜2文)。和語なら古い形や元の意味(例: ありがとう ← 有り難し「めったにない」)、" +
      "漢語なら漢字の組み合わせが表す意味、外来語ならどの言語のどの語から来たか(例: パン ← ポルトガル語 pão)。\n" +
      "  **和語・漢語・外来語の分類そのものは word_origin の欄に書くので、ここでは由来の話を書く。**",
    /**
     * 日本語で「同じ由来」がいちばん効くのも、**同じ漢字を共有する語**。
     * 「電」を覚えれば電車・電気・停電がまとめて読める(読みも同じ音読みになることが多い)。
     */
    relativesRule:
      "同じ漢字を共有する**仲間の語を2〜4語**。\n" +
      "  各 {word, note}。note はその漢字がその語で持つ意味を**5〜12字**で。\n" +
      "  例: 電話 なら 電車(電気で走る車) / 電気(電の力) / 停電(電気が止まる)。\n" +
      "  **その漢字が本当に同じ意味で働いているときだけ**並べる。\n" +
      "  読みが同じだけの語・たまたま同じ字が入っているだけの語は入れない — 覚え違いの種になる。\n" +
      "  かなだけの語(和語・外来語)で仲間が無ければ**空配列**。無理に埋めない。",
    // 漢字1字ずつの意味と音訓は `kanji_breakdown` が持つ。ここで部首を語らせると
    // 同じ話が2つの節に出る。
    radicalsRule: "**空文字**(漢字1字ずつの意味と読みは kanji_breakdown の欄に書く)",
    noteField: "japan_note",
    // 街で日常的に見る語。読みはひらがな(既定の読み)とヘボン式。
    quizFallbackHeadwords: ["りんご", "バス", "傘", "お弁当"],
    quizFallbackReadings: {
      りんご: { zhuyin: "りんご", pinyin: "ringo" },
      バス: { zhuyin: "バス", pinyin: "basu" },
      傘: { zhuyin: "かさ", pinyin: "kasa" },
      お弁当: { zhuyin: "おべんとう", pinyin: "obentō" },
    },
    noteRule:
      "日本ならではの一言雑学（文化・習慣・マナー・季節・地域差）を1〜2文。" +
      "その語を日本で使うときに知っておくと役立つことを選ぶ(例: お弁当 → コンビニで「温めますか」と聞かれる)。" +
      "誤用しやすい語法の注意があれば1文追加",
    hasRadicals: false,
    pronunciationFocus:
      "この語の高低アクセントの型(東京式)と、長音・促音(っ)・撥音(ん)を1拍として保つこと",
    relatedExample: "お弁当 → お箸・電子レンジ・コンビニ・おにぎり",
    readingLookupRule:
      "日本語(東京の標準語)の読みを答えてください。reading はひらがなの読み(カタカナ語はカタカナのまま)、reading_alt はヘボン式ローマ字(長音はマクロン: tōkyō)。",
    exampleLocalTopics:
      "日本の芸能人・歌手・スポーツ選手・歴史上の人物、アニメ・漫画・ゲーム、日本の文化・習慣・食べ物・季節の行事・街",
    exampleLocalPreference: "使うなら日本のものを優先する。",
    taiwanTermCheck: false,
  },
  // S(主語)/O(目的語)/V(述語)/M(修飾)/Ptc(助詞)/Aux(助動詞)
  chunkRoles: ["S", "O", "V", "M", "Ptc", "Aux"],
  chunkPrompt: {
    // かな・漢字・カタカナを1字と数える。カタカナ語が長いので台湾華語(8)より広い。
    lengthRule:
      "型1つは12文字以内・パーツ4つ以内(かな・漢字・カタカナを1字と数える)。超えるものは型ではなく例文。" +
      "**句点・感嘆符・疑問符を入れない** — 文ではなく、そのまま口に乗せる塊。",
    styleRule:
      "**助詞(を・に・で・が・へ・と)を型の中に必ず入れる** — どの助詞を取るかが学習者のいちばん崩れる所で、" +
      "型の中身そのもの(例: 傘をさす / 電車に乗る / 風邪をひく)。\n" +
      "動詞は辞書形で置く(ます形にしない)。名詞+助詞+動詞だけに寄せず、形容詞+名詞・副詞+動詞・決まり文句の型も" +
      "**頻度が高ければ**入れる。**助数詞(一本・一枚)だけの型は作らない** — 助数詞は別の欄で読む。",
    posRule:
      "pos は日本語の品詞の記号を使う: N(名詞)/V(動詞)/Adj-i(い形容詞)/Adj-na(な形容詞)/Adv(副詞)/" +
      "Ptc(助詞)/Aux(助動詞)/Cop(だ・です)/Pron(代名詞)/Det(連体詞: この・その)/Conj(接続詞)/Ctr(助数詞)。" +
      "**全パーツに付ける**(助詞の「を」「に」「が」も省かない)。役割記号(S/O/C/P)は使わない。",
    formulaExample:
      "会う → 友達＋に＋会う、けんか → 彼氏＋と＋けんかする、傘 → 傘＋を＋さす、お茶 → お茶＋を＋入れる / 冷たい＋お茶",
    formulaGrammar:
      "助詞を省かない（✗ 傘＋さす → ○ 傘＋を＋さす）。動詞は辞書形、形容詞は名詞の前に置く形で書く（✗ 彼氏けんか → ○ 彼氏＋と＋けんかする）。",
  },
  headwordOk: (raw) => {
    // 「Tシャツ」「Eメール」「Uターン」のように**頭に大文字1〜2字+カタカナ**の
    // 語は日本語として普通に使う。そこだけは欧文を許し、ほかは落とす
    // (「pencil」「シャーペンpen」を日本語の見出し語にしない)。
    const s = core(raw).replace(/^[A-ZＡ-Ｚ]{1,2}(?=[ァ-ヺー])/, "");
    if (!s) return false;
    if (NON_CJK_LETTER.test(s)) return false;
    // 日本語の文字だけでできていること。数字・ハングル・注音(ㄅㄆㄇ)は通さない。
    if (!JA_ONLY.test(s)) return false;
    return KANA.test(s) || HAN.test(s);
  },
};

const PROFILES: Record<string, TargetProfile> = {
  [ZH_TW_PROFILE.code]: ZH_TW_PROFILE,
  [EN_PROFILE.code]: EN_PROFILE,
  [JA_PROFILE.code]: JA_PROFILE,
};

/**
 * その学習言語のプロフィール。
 *
 * **知らない値は既定に落とす。** 未知の言語のまま動かすと、項目が1つも
 * 無いカードや、読み上げの言語が空のまま喋る画面ができる。
 */
export function targetProfile(code: string | null | undefined): TargetProfile {
  const normalized = normalizeTargetLanguage(code);
  return PROFILES[normalized] ?? PROFILES[DEFAULT_TARGET_LANGUAGE] ?? ZH_TW_PROFILE;
}

/**
 * その項目はこの言語のカードに出るか。
 *
 * **学習言語を直に比べる `if` を書かないための口。** 条件を画面と生成の
 * 2箇所に書くと、必ず片方だけ直して食い違う。
 */
export function hasSection(profile: TargetProfile, section: ProfileSection): boolean {
  return profile.sections.includes(section);
}

/** その言語で使う読みの既定(設定がまだ無いとき)。 */
export function defaultReading(profile: TargetProfile): ReadingKind {
  return profile.readings[0];
}

/**
 * **AI への指示文の中で、その表記を何と呼ぶか。**
 *
 * 画面の名前(`readingChoices`)は読む人の言語で書くが、指示文は日本語で
 * 書いているので別に持つ(`UI_LANG_LABEL_KEYS` と `UI_LANG_PROMPT_NAMES`
 * が別なのと同じ理由)。
 */
const READING_PROMPT_NAMES: Record<ReadingKind, string> = {
  zhuyin: "注音",
  pinyin: "拼音",
  "ipa-us": "IPA(アメリカ英語)",
  "ipa-uk": "IPA(イギリス英語)",
  kana: "ひらがなの読み",
  romaji: "ヘボン式ローマ字",
};

/**
 * その言語の「1つめの読み・2つめの読み」の呼び名。
 *
 * 呼ぶ側が `lang === "en" ? "IPA" : "注音"` と書き始めると、学習言語が
 * 増えた日にその分岐だけ増えない。並びの正は `readings` ただ1つ。
 */
export function readingPromptNames(profile: TargetProfile): { primary: string; alt: string } {
  const [first, second] = profile.readings;
  return {
    primary: READING_PROMPT_NAMES[first],
    alt: second ? READING_PROMPT_NAMES[second] : "",
  };
}
