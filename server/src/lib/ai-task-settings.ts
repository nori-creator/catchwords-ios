/**
 * **AI を呼ぶ用途ごとの設定**（オーナー依頼 2026-10-14「このアプリで使われている全ての AI の機能を、
 * 開発者の私だけ AI のモデル設定、機能とモデルごとのコスト管理できるようにして」
 * 「すべての AI 機能が失敗したときのバックアップを作って」「iOS にない奴は消して」）。
 *
 * - 用途（`ai-call-log.ts` の `AI_TASKS`）ごとに、使う AI（`app_config.ai_models.tasks[用途]`）と
 *   落ちた時の控え（`app_config.ai_models.backups[用途]`）を選べる。値は `"auto"` か `"会社:モデル"`。
 *   控えだけは `"off"`（控えを使わない）も選べる。
 * - 用途の設定が `"auto"` なら、これまでどおり機能の設定（`features`）→ 環境変数 → 既定。
 * - iOS の開発者画面は `ios: true` の用途だけを出す（iOS に無い機能 — 日記・フレーズカード・
 *   単語帳・チュートリアル・辞書の裏方など — は出さない）。Web の画面は今までどおり機能ごと。
 *
 * ここは表と純粋な関数だけ（試験・画面からも読める。DB にも鍵にも触らない）。
 * 振り分けは `ai-provider.server.ts`、管理の口は `admin-ai.server.ts`。
 */
import { AI_TASKS, type AiTask } from "./ai-call-log";
import { AUTO, normalizeFeatureValue, parseFeatureValue, type AiFeature } from "./ai-features";

/** 控えを使わない（落ちたらそのまま失敗にする）。 */
export const OFF = "off";

import type { UiLang } from "./i18n";

export type Label = Record<UiLang, string>;

export type AiTaskInfo = {
  id: AiTask;
  feature: AiFeature;
  /** 写真を読む用途（写真を読めるモデルしか選べない）。 */
  needsVision: boolean;
  /** iOS 版で使う用途（iOS の開発者画面に出す）。 */
  ios: boolean;
  label: Label;
  description: Label;
};

/** 写真を読む用途。 */
const VISION_TASKS: ReadonlySet<string> = new Set([
  "photo_candidates",
  "tutorial_candidates",
  "scan_detect",
  "scan_parts",
  "image_verify",
  "wordbook",
]);

/**
 * **iOS 版で AI が動く用途**（iOS の `NativeAPI.call` から辿った物。2026-10-14）。
 * - 撮った後の候補（suggestWords）・母語で調べた候補（suggestWordCandidates）
 * - 単語カード（generateCard）・表示言語での意味（getReaderMeanings / getWordExplanation）
 * - 項目の作り直し・空欄の補完（regenerateCardSection）
 * - 報告（reportAndFixSection: 項目の特定・読みの突き合わせ2回・直してよいかの判定・直しの案）
 * - ネットの画像（画像の候補を探す口: 意味の判断・絵の確認）
 *
 * 4択の誤答の作り置き（`distractors`）は iOS で保存した語では作らない（iOS の4択は語を選ぶ形で、
 * AI の誤答＝意味を使わない。`stickers.functions.ts`）ので、ここには入れない。
 */
export const IOS_AI_TASKS: readonly AiTask[] = [
  "photo_candidates",
  "word_candidates",
  "card",
  "reader_meaning",
  "section_regen",
  "report_locate",
  "reading_check_1",
  "reading_check_2",
  "correction_judge",
  "image_sense",
  "image_verify",
];

const L = (ja: string, en: string, zh: string): Label => ({
  ja,
  en,
  "zh-TW": zh,
});

/** 用途の名前と説明（iOS は自分の辞書を持たずにこれを出せる）。 */
const TASK_TEXT: Record<string, { label: Label; description: Label }> = {
  photo_candidates: {
    label: L("写真の単語の候補", "Words from a photo", "照片的單字候選"),
    description: L(
      "撮った写真から単語の候補を出す（写真を読む）",
      "Suggests words for the photo just taken (reads the photo)",
      "從剛拍的照片提出單字候選（讀取照片）",
    ),
  },
  tutorial_candidates: {
    label: L("チュートリアルの写真の候補", "Tutorial photo words", "教學照片的單字候選"),
    description: L("Web 版のチュートリアル", "Web tutorial", "網頁版的教學"),
  },
  word_candidates: {
    label: L("母語で調べた語の候補", "Words for what you typed", "用母語查詢的單字候選"),
    description: L(
      "「違う単語を入力」で調べた語の候補",
      "Candidates for a word typed in your language",
      "「輸入其他單字」時的候選",
    ),
  },
  scan_detect: {
    label: L("スキャンの検出", "Scan detection", "掃描的偵測"),
    description: L("Web 版のスキャン", "Web scan", "網頁版的掃描"),
  },
  scan_parts: {
    label: L("「+細かく」の検出", "Detailed parts", "「+細部」的偵測"),
    description: L("Web 版のスキャン", "Web scan", "網頁版的掃描"),
  },
  image_sense: {
    label: L("画像の意味の判断", "Picture meaning", "判斷圖片的意思"),
    description: L(
      "写真の無い単語の画像をネットで探す前に、どの意味の絵を探すか決める",
      "Decides which sense to look for before searching the web for a picture",
      "在網路上找圖片前，決定要找哪個意思的圖",
    ),
  },
  image_verify: {
    label: L("画像の確認", "Picture check", "確認圖片"),
    description: L(
      "ネットで見つけた画像が単語に合うか見て確かめる（写真を読む）",
      "Looks at the pictures found on the web and checks they match the word",
      "看網路上找到的圖片是否符合單字（讀取圖片）",
    ),
  },
  wordbook: {
    label: L("単語帳の読み取り", "Wordbook page", "單字本的讀取"),
    description: L("Web 版の単語帳", "Web wordbook", "網頁版的單字本"),
  },
  card: {
    label: L("単語カード", "Word card", "單字卡"),
    description: L(
      "解説・例文・分類など、カードの中身を作る",
      "Writes the card: explanation, examples, category",
      "產生單字卡的內容：解說、例句、分類",
    ),
  },
  tutorial_card: {
    label: L("チュートリアルのカード", "Tutorial card", "教學的單字卡"),
    description: L("Web 版のチュートリアル", "Web tutorial", "網頁版的教學"),
  },
  tutorial_lesson: {
    label: L("チュートリアルのレッスン", "Tutorial lesson", "教學的課程"),
    description: L("Web 版のチュートリアル", "Web tutorial", "網頁版的教學"),
  },
  phrase_card: {
    label: L("フレーズカード", "Phrase card", "片語卡"),
    description: L("Web 版のフレーズカード", "Web phrase card", "網頁版的片語卡"),
  },
  section_regen: {
    label: L("項目の作り直し", "Section rewrite", "重新產生項目"),
    description: L(
      "単語ページの項目の作り直し・空欄の補完・報告での直しの案",
      "Rewrites a section of the word page, fills blanks, drafts fixes for reports",
      "重新產生單字頁的項目、補上空白、回報時的修正案",
    ),
  },
  chunk_verify: {
    label: L("使い方の型の点検", "Usage chunk check", "用法片語的檢查"),
    description: L(
      "カードを返す前に型だけを別の AI に見せる（AI_CHUNK_VERIFY=inline の時だけ。既定は使わない）",
      "Shows the usage chunks to a second AI before the card is returned (only with AI_CHUNK_VERIFY=inline; off by default)",
      "回傳單字卡前讓另一個 AI 檢查用法片語（僅在 AI_CHUNK_VERIFY=inline 時；預設不用）",
    ),
  },
  reader_meaning: {
    label: L("表示言語での意味", "Meaning in your language", "用顯示語言寫的意思"),
    description: L(
      "表示言語に合わせた短い意味を作る",
      "Writes the short meaning in the display language",
      "產生顯示語言的簡短意思",
    ),
  },
  distractors: {
    label: L("4択の誤答の作り置き", "Quiz wrong answers", "四選一的錯誤選項"),
    description: L(
      "Web 版の4択の意味の選択肢（iOS で保存した語では作らない）",
      "Meaning choices for the web quiz (not made for words saved on iOS)",
      "網頁版四選一的意思選項（iOS 儲存的單字不產生）",
    ),
  },
  journal_correct: {
    label: L("日記の添削", "Diary correction", "日記的批改"),
    description: L("Web 版の日記", "Web diary", "網頁版的日記"),
  },
  journal_prompts: {
    label: L("日記の書き出しの質問", "Diary prompts", "日記的提問"),
    description: L("Web 版の日記", "Web diary", "網頁版的日記"),
  },
  report_locate: {
    label: L("報告: 間違った項目を探す", "Report: find the wrong part", "回報：找出錯誤的項目"),
    description: L(
      "項目を選ばずに報告された時、どの項目が違うかを探す",
      "Finds which section is wrong when a report names none",
      "回報沒選項目時，找出哪個項目有錯",
    ),
  },
  reading_check_1: {
    label: L(
      "報告: 読み・品詞の確認（1人目）",
      "Report: reading check 1",
      "回報：讀音與詞性確認 1",
    ),
    description: L(
      "辞書に無い語の読み・品詞を確かめる",
      "Checks the reading and part of speech of a word not in the dictionary",
      "確認字典裡沒有的詞的讀音與詞性",
    ),
  },
  reading_check_2: {
    label: L(
      "報告: 読み・品詞の確認（2人目）",
      "Report: reading check 2",
      "回報：讀音與詞性確認 2",
    ),
    description: L(
      "1人目と別の AI にすると独立に確かめられる",
      "Use a different AI from check 1 for an independent check",
      "和第 1 位用不同的 AI，可以獨立確認",
    ),
  },
  correction_judge: {
    label: L("報告: 直してよいかの判定", "Report: approve the fix", "回報：判斷能否修正"),
    description: L(
      "直しの案が正しいかを別の目で確かめる",
      "Checks the proposed fix with a second opinion",
      "用另一雙眼睛確認修正案是否正確",
    ),
  },
  lexicon_audit: {
    label: L("辞書の点検", "Dictionary audit", "字典的檢查"),
    description: L("裏方（Web 版）", "Background job (web)", "後台（網頁版）"),
  },
  lexicon_corpus: {
    label: L("生きた例文の生成", "Example corpus", "產生實用例句"),
    description: L("裏方（Web 版）", "Background job (web)", "後台（網頁版）"),
  },
  report_triage: {
    label: L("利用者の報告の検証", "Report triage", "使用者回報的驗證"),
    description: L("裏方（Web 版）", "Background job (web)", "後台（網頁版）"),
  },
  category_backfill: {
    label: L("棚の分類の付け直し", "Category backfill", "分類的重新整理"),
    description: L("Web 版の図鑑", "Web dex", "網頁版的圖鑑"),
  },
};

/** 設定できる用途の表（iOS の自由文の窓口 `native_ai` は機能の無い用途なので外す）。 */
export const AI_TASK_INFOS: readonly AiTaskInfo[] = AI_TASKS.flatMap((t) => {
  if (!t.feature) return [];
  const text = TASK_TEXT[t.id] ?? { label: L(t.id, t.id, t.id), description: L("", "", "") };
  return [
    {
      id: t.id,
      feature: t.feature,
      needsVision: VISION_TASKS.has(t.id),
      ios: (IOS_AI_TASKS as readonly string[]).includes(t.id),
      label: text.label,
      description: text.description,
    },
  ];
});

export function taskInfo(task: string): AiTaskInfo | null {
  return AI_TASK_INFOS.find((t) => t.id === task) ?? null;
}

/** 用途の名前（費用の表で、記録に残っている物だけ分かればよい）。知らなければ id のまま。 */
export function taskLabel(task: string): Label {
  return TASK_TEXT[task]?.label ?? L(task, task, task);
}

/** 保存されている `ai_models` の形（鍵は持たない）。 */
export type AiModelsConfig = {
  features?: Partial<Record<string, string>>;
  tasks?: Record<string, string>;
  backups?: Record<string, string>;
};

function strings(raw: unknown, keep: (k: string) => boolean): Record<string, string> {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return {};
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(raw as Record<string, unknown>)) {
    if (keep(k) && typeof v === "string" && v.trim()) out[k] = v.trim();
  }
  return out;
}

/** 用途ごとの値（`"auto"` は保存しない）。 */
export function taskValues(raw: unknown): Record<string, string> {
  const t = (raw as { tasks?: unknown } | null)?.tasks;
  return strings(t, (k) => !!taskInfo(k));
}

/** 用途ごとの控え（`"auto"` は保存しない。`"off"` は残す）。 */
export function backupValues(raw: unknown): Record<string, string> {
  const b = (raw as { backups?: unknown } | null)?.backups;
  return strings(b, (k) => !!taskInfo(k));
}

/**
 * 保存する `ai_models` を組む。**空の表は書かない**（古い全体の上書き — `provider` / `fast` 等 —
 * はここで消える）。
 */
export function buildAiModelsConfig(parts: {
  features: Partial<Record<string, string>>;
  tasks: Record<string, string>;
  backups: Record<string, string>;
}): AiModelsConfig {
  const out: AiModelsConfig = { features: parts.features };
  if (Object.keys(parts.tasks).length) out.tasks = parts.tasks;
  if (Object.keys(parts.backups).length) out.backups = parts.backups;
  return out;
}

/**
 * 控えの値を確かめて保存する形にする（`"auto"` / `"off"` / `"会社:モデル"`）。形が違えば投げる。
 */
export function normalizeBackupValue(value: unknown): string {
  if (typeof value === "string" && value.trim().toLowerCase() === OFF) return OFF;
  return normalizeFeatureValue(value);
}

/** 控えの値を読む。`off` は `"off"`、`auto`・空は null、`"会社:モデル"` は会社とモデル。 */
export function parseBackupValue(
  value: unknown,
): "off" | { provider: string; model: string } | null {
  if (typeof value === "string" && value.trim().toLowerCase() === OFF) return OFF;
  const spec = parseFeatureValue(value);
  return spec?.provider ? spec : null;
}

export { AUTO };
