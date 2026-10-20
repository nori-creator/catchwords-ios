import { z } from "zod";
import { ExtrasSchema, hasExtrasContent, normalizeExtras } from "./extras";
import { DEFAULT_TARGET_LANGUAGE } from "./target-lang";
import { readerMeaning, readerText, scrubExtrasForReader } from "./note-language";
import { lacksNotes } from "./explanation-cache";

/**
 * **共有の語（`words`）を、利用者の送った中身で書き換えさせない関所**（監査 2026-10-03）。
 *
 * `words` は `(language, headword)` で全員が同じ1行を見る。書くのはサーバ（service role）
 * だけだが、中身は画面が送ってくる（`updateWordExtras` の `patch` / `extras`、
 * `saveSticker` → `upsertWord` の `word.extras`）。前は「その語の札を持っている」ことしか
 * 確かめていなかったので、札を1枚持てば**他人のカードの意味・例文・読みを好きな文に
 * 書き換えられた**。
 *
 * ここで決める約束（サーバが守る。画面の `shouldWriteSharedColumns` は送る量を減らすだけ）:
 * - 共有の列（意味・読み・品詞・級・例文・例文訳）は**いま空の列だけ埋めてよい**。
 *   埋まっている列は誰の送った物でも上書きしない。人が確かめた語（`verified`）は一切触らない。
 * - 共有の `extras` も同じ。空の解説なら丸ごと入れてよいが、中身がある解説には
 *   **同じ言語で空の項目だけ**を足す（別の言語の解説を混ぜない）。
 * - 読む人ごとの解説（`word_explanations`）も同じ言語・母語で読む全員の行なので、
 *   **空の所だけ**埋める（`fillReaderExplanation`、2026-10-03 H2）。大きさにも上限を置く。
 * - **埋める中身はサーバが作った物**（`generated-cards.ts` の控え）。画面の送った文は、
 *   控えの表がまだ無い環境（移行待ち）でだけ使う（2026-10-03 H2 / M3）。
 *
 * 報告からの直し（`reportAndFixSection`）と項目の作り直し（`regenerateCardSection`）は
 * サーバが自分で作って確かめた物を書く別の道なので、ここは通らない。
 */

/** 共有の語の、正としての列。 */
export const SHARED_WORD_COLUMNS = [
  "meaning_ja",
  "reading_zhuyin",
  "pinyin",
  "part_of_speech",
  "level",
  "example_sentence",
  "example_translation",
] as const;
export type SharedWordColumn = (typeof SHARED_WORD_COLUMNS)[number];

const filledText = (v: unknown): boolean => typeof v === "string" && v.trim().length > 0;

const filledValue = (v: unknown): boolean =>
  Array.isArray(v)
    ? v.length > 0
    : typeof v === "string"
      ? v.trim().length > 0
      : v != null && !(typeof v === "object" && Object.keys(v as object).length === 0);

/**
 * 共有の列のうち、**書いてよい分だけ**を返す。
 *
 * - 人が確かめた語（`verified`）は何も書かない
 * - いま空の列だけ、送られた空でない値で埋める
 * - 知らない鍵は捨てる（`SHARED_WORD_COLUMNS` だけ）
 * - `lang`（書く文の言語）を渡したら、別の言語の行には意味・例文訳・例文を書かない
 *   （`mayWriteSharedReaderText`）。読み・品詞・級は書く
 */
export function fillEmptySharedColumns(
  current: SharedRowText | null | undefined,
  patch: Partial<Record<string, string | null | undefined>> | null | undefined,
  opts: { verified: boolean; lang?: string },
): Partial<Record<SharedWordColumn, string>> {
  const out: Partial<Record<SharedWordColumn, string>> = {};
  if (!patch || opts.verified) return out;
  // 別の言語の行には、読む人の言語の列（意味・例文訳と、その組の例文）を書かない。
  const textOk = opts.lang === undefined || mayWriteSharedReaderText(current, opts.lang);
  for (const col of SHARED_WORD_COLUMNS) {
    if (!textOk && READER_TEXT_COLUMNS.includes(col)) continue;
    const next = patch[col];
    if (!filledText(next)) continue;
    if (filledText(current?.[col])) continue;
    out[col] = (next as string).trim();
  }
  return out;
}

/** 解説の言語の目印。空なら古いデータの既定（日本語）。 */
function extrasLanguage(e: Record<string, unknown>): string {
  const v = e.explain_lang;
  return (typeof v === "string" && v.trim()) || "ja";
}

/**
 * 共有の列のうち、**読む人の言語で書く物**（とその組の例文）。読み・品詞・級は学習言語の側の物で、
 * どの言語の人が埋めてもよい。
 */
const READER_TEXT_COLUMNS: readonly SharedWordColumn[] = [
  "meaning_ja",
  "example_translation",
  "example_sentence",
];

type SharedRowText = Partial<Record<SharedWordColumn, string | null | undefined>> & {
  extras?: unknown;
};

const asRecord = (v: unknown): Record<string, unknown> =>
  v && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, unknown>) : {};

/**
 * **共有の行の、読む人の言語の文（意味・例文訳・解説）が書かれている言語**。行に1つしか無い:
 * `extras.explain_lang`。目印の無い古い行は、表示言語が日本語だけだった頃の物なので日本語。
 */
export function sharedRowLanguage(row: SharedRowText | null | undefined): string {
  return extrasLanguage(asRecord(row?.extras));
}

/** 共有の行に、読む人の言語の文がまだ1つも無いか（どの言語の行でもない）。 */
export function sharedRowHasReaderText(row: SharedRowText | null | undefined): boolean {
  if (!row) return false;
  if (filledText(row.meaning_ja) || filledText(row.example_translation)) return true;
  return hasExtrasContent(normalizeExtras(asRecord(row.extras)));
}

/**
 * **その言語の文で、共有の行を埋めてよいか**（2026-10-20 オーナー指示「決して言語が混ざらないようにして」）。
 *
 * 共有の行は1語に1行で、意味・例文訳・解説の言語の目印は行に1つ。別の言語の人が空の列を埋めると、
 * 目印と中身の言語が食い違う（2026-10-20 の本番で 312 行のうち約10行）。食い違った行は、目印で選ぶ
 * 画面（iOS の `ReaderLanguage.resolve`）にも、文字で選ぶ画面にも見分けられない（英語とスペイン語は
 * 同じ文字）。だから、行の言語と同じ言語の人だけが埋め、まだ何も無い行だけは最初の人の言語になる
 * （そのとき目印も付ける — `claimSharedRowLanguage`）。別の言語の人の解説は `word_explanations` に入る。
 */
export function mayWriteSharedReaderText(
  row: SharedRowText | null | undefined,
  lang: string,
): boolean {
  return !sharedRowHasReaderText(row) || sharedRowLanguage(row) === lang;
}

/**
 * まだ何も無い行に読む人の言語の文を書く時、**目印もその言語にする**（`update` に足す）。目印の無いまま
 * 英語の意味を書くと、その行は「日本語の行」と読まれる。
 */
export function claimSharedRowLanguage(
  update: Record<string, unknown>,
  row: SharedRowText | null | undefined,
  lang: string,
): Record<string, unknown> {
  if (sharedRowHasReaderText(row)) return update;
  const writesText =
    READER_TEXT_COLUMNS.some((c) => c !== "example_sentence" && filledText(update[c])) ||
    "extras" in update;
  if (!writesText) return update;
  const extras = { ...asRecord(row?.extras), ...asRecord(update.extras) };
  if (extrasLanguage(extras) === lang && extras.explain_lang === lang) return update;
  return { ...update, extras: { ...extras, explain_lang: lang } };
}

/**
 * 共有の `extras` に**足してよい分だけ**を足した全体を返す。変わらなければ null。
 *
 * - 送られた解説が空 → 何もしない
 * - いまの共有の解説が空 → 送られた物を入れる（初めての解説。知らない鍵は残す）
 * - いまの共有の解説に中身があり、言語が違う → 何もしない（混ぜると読めない言語が出る。
 *   その人向けの解説は `word_explanations` に入る）
 * - 同じ言語 → **空の項目だけ**埋める。埋まっている項目は上書きしない
 */
/**
 * **場面の札は、札・目印・パーツを組で埋める**（PR #189 の点検 — 目印の無い札を別の文の札にしない）。
 * 空の所だけ埋める決まりを鍵ごとに当てると、目印の無い札（人が書いた・目印より前の札）の横に、別の札の
 * 目印だけが入り、その札が「この文の札」になってしまう。だから:
 * - 前の行に札が在れば、届いた札・目印・パーツは使わない（前の札は入れ替えない）
 * - 前の行に札が無く、届いた札で埋めたら、目印（とパーツが届いていればパーツ）もその札の物にする
 */
const SCENE_PAIR = ["example_scene", "example_scene_for", "example_chunks"] as const;
const hasScene = (e: Record<string, unknown>) =>
  typeof e.example_scene === "string" && e.example_scene.trim().length > 0;

function withoutSceneIfLabelled(
  prev: Record<string, unknown>,
  inc: Record<string, unknown>,
): Record<string, unknown> {
  if (!hasScene(prev)) return inc;
  const out = { ...inc };
  for (const k of SCENE_PAIR) delete out[k];
  return out;
}

function keepScenePair(
  out: Record<string, unknown>,
  prev: Record<string, unknown>,
  inc: Record<string, unknown>,
): void {
  if (hasScene(prev) || !hasScene(out) || !hasScene(inc)) return;
  out.example_scene_for = typeof inc.example_scene_for === "string" ? inc.example_scene_for : "";
  if (Array.isArray(inc.example_chunks) && inc.example_chunks.length > 0) {
    out.example_chunks = inc.example_chunks;
  }
}

export function fillEmptySharedExtras(
  prevRaw: unknown,
  incoming: Record<string, unknown> | null | undefined,
  /**
   * 共有の行の列（意味・例文訳）。渡したら、解説が空でも**別の言語の意味が載った行**には入れない
   * （日本語の意味の横にスペイン語の解説と目印を入れると、その行の意味が「スペイン語」と読まれる）。
   */
  row?: SharedRowText | null,
): Record<string, unknown> | null {
  if (!incoming || !hasExtrasContent(normalizeExtras(incoming))) return null;
  const prev = asRecord(prevRaw);
  if (!hasExtrasContent(normalizeExtras(prev))) {
    if (row && !mayWriteSharedReaderText({ ...row, extras: prev }, extrasLanguage(incoming))) {
      return null;
    }
    return { ...prev, ...incoming };
  }
  if (extrasLanguage(prev) !== extrasLanguage(incoming)) return null;
  const inc = withoutSceneIfLabelled(prev, incoming);
  const out: Record<string, unknown> = { ...prev };
  let changed = false;
  for (const [k, v] of Object.entries(inc)) {
    if (k === "explain_lang" || k === "explain_l1") continue;
    if (!filledValue(v) || filledValue(prev[k])) continue;
    out[k] = v;
    changed = true;
  }
  if (changed) keepScenePair(out, prev, inc);
  return changed ? out : null;
}

/**
 * サーバの控え（`generated-cards.ts` の `TrustedCard`）から、共有の列に書いてよい値だけを
 * 取り出す。`fillEmptySharedColumns` の `patch` と、新しい語の行（`upsertWord`）に使う。
 */
export function sharedColumnsFromCard(
  card: Partial<Record<string, unknown>> | null | undefined,
): Partial<Record<SharedWordColumn, string>> {
  const out: Partial<Record<SharedWordColumn, string>> = {};
  if (!card) return out;
  for (const col of SHARED_WORD_COLUMNS) {
    const v = card[col];
    if (filledText(v)) out[col] = (v as string).trim();
  }
  return out;
}

// --- 読む人ごとの解説の行（`word_explanations`）--------------------------------

export type ReaderRowContent = {
  meaning: string;
  example_translation?: string | null;
  extras: Record<string, unknown>;
};

export type ReaderRowWrite =
  | { kind: "insert"; row: ReaderRowContent }
  | { kind: "update"; patch: Partial<ReaderRowContent> }
  | { kind: "skip"; reason: "verified" | "nothing" };

/**
 * **読む人ごとの解説の行も、空の所だけ埋める**（監査 2026-10-03 H2）。
 *
 * `word_explanations` は `(語, 解説の言語, 母語)` が同じ全員で共有する行。前は
 * `updateWordExtras` の送った解説で**行ごと上書き**していたので、札を1枚持てば同じ言語で
 * 読む全員の解説を好きな文に変えられた。
 *
 * - 行が無い → 置く
 * - 人が確かめた行（`verified`）→ 触らない
 * - 意味・例文訳: いまの値が空か、**読む人の言語で書かれていない**（昔、共有の意味＝
 *   別の言語を写していた行。`ARCHITECTURE.md` の 2026-10-02）ときだけ埋める
 * - 解説: いまの解説が別の言語で書かれていれば丸ごと入れ替える（同じ鍵の行に別の言語の
 *   解説が載っているのは壊れた行）。同じ言語なら**空の項目だけ**足す
 *
 * 画面（`keepShownFields`）も「見えている項目は残し、空だけ埋める」ので、正しく使っている
 * 人の見え方は変わらない。
 */
export function fillReaderExplanation(
  existing: {
    meaning?: string | null;
    example_translation?: string | null;
    extras?: unknown;
    source?: string | null;
  } | null,
  incoming: ReaderRowContent,
  readerLang: string,
): ReaderRowWrite {
  const meaningFits = (t: string) => readerMeaning(t, readerLang).trim().length > 0;
  const textFits = (t: string) => readerText(t, readerLang).trim().length > 0;
  // **入れる物も読む人の言語の物だけ**（2026-10-20）。この行は同じ言語で読む全員に出る。
  const tr = incoming.example_translation;
  incoming = {
    ...incoming,
    meaning: meaningFits(incoming.meaning ?? "") ? incoming.meaning : "",
    ...(typeof tr === "string" && tr.trim() && !textFits(tr) ? { example_translation: "" } : {}),
    extras: scrubExtrasForReader(incoming.extras, readerLang),
  };
  if (!existing) return { kind: "insert", row: incoming };
  if (existing.source === "verified") return { kind: "skip", reason: "verified" };
  const patch: Partial<ReaderRowContent> = {};

  const curMeaning = (existing.meaning ?? "").trim();
  const nextMeaning = (incoming.meaning ?? "").trim();
  if (nextMeaning && (!curMeaning || !meaningFits(curMeaning))) {
    if (nextMeaning !== curMeaning) patch.meaning = nextMeaning;
  }

  const curTr = (existing.example_translation ?? "").trim();
  const nextTr = (incoming.example_translation ?? "").trim();
  if (nextTr && textFits(nextTr) && (!curTr || !textFits(curTr))) {
    if (nextTr !== curTr) patch.example_translation = nextTr;
  }

  const prev =
    existing.extras && typeof existing.extras === "object" && !Array.isArray(existing.extras)
      ? (existing.extras as Record<string, unknown>)
      : {};
  const incAll = (incoming.extras ?? {}) as Record<string, unknown>;
  if (hasExtrasContent(normalizeExtras(incAll))) {
    const prevLang = typeof prev.explain_lang === "string" ? prev.explain_lang.trim() : "";
    const prevHas = hasExtrasContent(normalizeExtras(prev));
    if (!prevHas || (prevLang && prevLang !== readerLang)) {
      patch.extras = { ...prev, ...incAll };
    } else {
      const inc = withoutSceneIfLabelled(prev, incAll);
      const out: Record<string, unknown> = { ...prev };
      let changed = false;
      for (const [k, v] of Object.entries(inc)) {
        if (k === "explain_lang" || k === "explain_l1") {
          if (!filledValue(prev[k]) && filledValue(v)) {
            out[k] = v;
            changed = true;
          }
          continue;
        }
        // 語だけで解説（note）が1つも無い関連語は「中身がある」に数えない
        // （`keepShownFields` と同じ。2026-09-30 保溫瓶）。
        const prevFilled = filledValue(prev[k]) && !(k === "related_words" && lacksNotes(prev[k]));
        if (!filledValue(v) || prevFilled) continue;
        out[k] = v;
        changed = true;
      }
      if (changed) keepScenePair(out, prev, inc);
      if (changed) patch.extras = out;
    }
  }
  return Object.keys(patch).length > 0
    ? { kind: "update", patch }
    : { kind: "skip", reason: "nothing" };
}

// --- 大きさの上限 ------------------------------------------------------------

/**
 * 画面から届く解説（extras）の大きさの上限。今の一番大きいカード（全項目・追加例文・型の
 * 入れ替え候補つき）の数倍に置く。超えた物は**断る**（黙って切ると半端な解説が残る）。
 */
export const EXTRAS_LIMITS = {
  /** 1つの文字列の長さ。 */
  maxStringChars: 4_000,
  /** 1つの配列の長さ。 */
  maxArrayItems: 100,
  /** 1つの入れ物の鍵の数。 */
  maxObjectKeys: 120,
  /** 入れ子の深さ（extras → 追加例文 → 型 → 部品 → 入れ替え候補 で 8）。 */
  maxDepth: 10,
  /** 全体を JSON にした長さ。 */
  maxTotalChars: 100_000,
} as const;

export type JsonLimits = { [K in keyof typeof EXTRAS_LIMITS]: number };

/** 上限を超えた所の説明。収まっていれば null。 */
export function jsonBoundsProblem(
  value: unknown,
  limits: JsonLimits = EXTRAS_LIMITS,
): string | null {
  const walk = (v: unknown, depth: number, path: string): string | null => {
    if (depth > limits.maxDepth) return `${path}: too deep`;
    if (typeof v === "string") {
      return v.length > limits.maxStringChars ? `${path}: string too long` : null;
    }
    if (Array.isArray(v)) {
      if (v.length > limits.maxArrayItems) return `${path}: too many items`;
      for (let i = 0; i < v.length; i++) {
        const p = walk(v[i], depth + 1, `${path}[${i}]`);
        if (p) return p;
      }
      return null;
    }
    if (v && typeof v === "object") {
      const entries = Object.entries(v as Record<string, unknown>);
      if (entries.length > limits.maxObjectKeys) return `${path}: too many keys`;
      for (const [k, child] of entries) {
        if (k.length > 100) return `${path}: key too long`;
        const p = walk(child, depth + 1, `${path}.${k}`);
        if (p) return p;
      }
      return null;
    }
    return null;
  };
  const shape = walk(value, 0, "extras");
  if (shape) return shape;
  let total = 0;
  try {
    total = JSON.stringify(value ?? null)?.length ?? 0;
  } catch {
    return "extras: not serialisable";
  }
  return total > limits.maxTotalChars ? "extras: too large" : null;
}

/** 大きさを確かめてから、いつもの extras の形に直す。 */
export const BoundedExtrasSchema = z
  .unknown()
  .superRefine((v, ctx) => {
    const problem = jsonBoundsProblem(v);
    if (problem) ctx.addIssue({ code: "custom", message: problem });
  })
  .pipe(ExtrasSchema);

// --- 語の入力の形（保存の道で共有）-------------------------------------------

/**
 * 文字列の上限。画面で作る値の数倍に置く — キャッチの保存は止めてはいけない道なので、
 * 普通の値が引っかかる幅にはしない（巨大な値で共有の行を膨らませないための蓋）。
 */
export const WORD_TEXT_LIMITS = {
  headword: 100,
  reading: 500,
  meaning: 1_000,
  partOfSpeech: 100,
  level: 60,
  categoryKey: 64,
  example: 2_000,
  language: 16,
} as const;

/** 写真のキャッチ・文字や声のキャッチが送る語（`upsertWord` に渡る形）。 */
export const WordInputSchema = z.object({
  headword: z.string().min(1).max(WORD_TEXT_LIMITS.headword),
  reading_zhuyin: z.string().max(WORD_TEXT_LIMITS.reading).optional().default(""),
  pinyin: z.string().max(WORD_TEXT_LIMITS.reading).optional().default(""),
  meaning_ja: z.string().min(1).max(WORD_TEXT_LIMITS.meaning),
  part_of_speech: z.string().max(WORD_TEXT_LIMITS.partOfSpeech).optional().default("名詞"),
  level: z.string().max(WORD_TEXT_LIMITS.level).optional().default("TOCFL-2"),
  category_key: z.string().min(1).max(WORD_TEXT_LIMITS.categoryKey),
  example_sentence: z.string().max(WORD_TEXT_LIMITS.example).optional().default(""),
  example_translation: z.string().max(WORD_TEXT_LIMITS.example).optional().default(""),
  extras: BoundedExtrasSchema.optional(),
});

/** 写真の置き場所（`<uid>/<時刻>-object.jpg` など）の長さ。 */
export const STORAGE_PATH_MAX = 512;
/** 地名の長さ。 */
export const LOCATION_NAME_MAX = 300;

/** 学習言語（`zh-TW` / `en` …）。 */
export const LanguageCodeSchema = z
  .string()
  .max(WORD_TEXT_LIMITS.language)
  .default(DEFAULT_TARGET_LANGUAGE);

/** `updateWordExtras` の `patch`（共有の列。空の列を埋めるときだけ使われる）。 */
export const SharedColumnsPatchSchema = z.object({
  reading_zhuyin: z.string().max(WORD_TEXT_LIMITS.reading).optional(),
  pinyin: z.string().max(WORD_TEXT_LIMITS.reading).optional(),
  part_of_speech: z.string().max(WORD_TEXT_LIMITS.partOfSpeech).optional(),
  level: z.string().max(WORD_TEXT_LIMITS.level).optional(),
  example_sentence: z.string().max(WORD_TEXT_LIMITS.example).optional(),
  example_translation: z.string().max(WORD_TEXT_LIMITS.example).optional(),
  meaning_ja: z.string().max(WORD_TEXT_LIMITS.meaning).optional(),
});

/**
 * 解説の行の鍵（`explain_lang` / `explain_l1`）として受け付ける形。言語の符号だけ
 * （`ja` / `en` / `zh-TW` / `ko` …）。それ以外の値で行を作らせない。
 */
export function isExplanationLangCode(v: unknown): boolean {
  return typeof v === "string" && (v === "" || /^[a-z]{2,3}(-[A-Za-z]{2,4})?$/.test(v));
}
