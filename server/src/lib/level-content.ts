import { LEVEL_BANDS, parseLevelStep, type LevelBand, type LevelIndex, type LevelScale } from "./level-scale";

/**
 * **例文とチャンクだけは、レベルの帯でも分ける**（オーナー決定 2026-10-25、`docs/sharing-rules.md` S1〜S8）。
 *
 * > 表示言語が同じで TOCFL のレベル（現状と目標）も同じくらいの場合、単語のすべての項目を共有して。
 * > ただ表示言語が同じで TOCFL のレベル1のユーザーとレベル5とかの人の例文、チャンク以外の項目は共有する。
 * > 表示言語が異なる場合は全く共有しない。完全に分ける。
 *
 * 「同じくらい」= 現状の帯と目標の帯が両方同じ（1・2級 A / 3・4級 B / 5・6級 C）。鍵は `"A>B"`。
 * ここは外の世界に触れない（DB は `level-content.server.ts`）。
 */

/** 札に書く「この決まりの前に保存した語」の印（S4・S5）。 */
export const LEGACY_BAND = "legacy" as const;

/** 帯の鍵（`"A>B"`）。`null` = 古い語（今までどおり読む・書く）。 */
export type LevelBandKey = string;

const BAND_KEY = /^[A-C]>[A-C]$/;

/** 帯の鍵の形か（DB の CHECK と同じ）。 */
export function isLevelBandKey(v: unknown): v is LevelBandKey {
  return typeof v === "string" && BAND_KEY.test(v);
}

/** 段 → 帯（1・2 = A、3・4 = B、5・6 = C）。 */
export function bandOf(index: LevelIndex): LevelBand {
  return LEVEL_BANDS[Math.floor((index - 1) / 2)] ?? "A";
}

function stepIndex(raw: string | null | undefined, fallback: LevelIndex): LevelIndex {
  const s = parseLevelStep(raw);
  return typeof s === "number" && s >= 1 && s <= 6 ? (s as LevelIndex) : fallback;
}

/**
 * その人の帯の鍵（S3）。現状の級が読めなければ目標の1つ下（`getUserLevels` と同じ）、目標が読めなければ2級。
 * 現状が目標より上でも、そのまま（`"C>A"`）— 設定どおりに分ける。
 */
export function levelBandKey(levels: { current?: string | null; goal?: string | null }): LevelBandKey {
  const goal = stepIndex(levels.goal, 2);
  const current = stepIndex(levels.current, Math.max(1, goal - 1) as LevelIndex);
  return `${bandOf(current)}>${bandOf(goal)}`;
}

/**
 * 帯の代表の級（S7）。現状 = 現状の帯の下の級（帯の誰でも読める）、目標 = 目標の帯の上の級。
 * 同じ帯の誰が作っても、例文・チャンクの指示が同じになる。
 */
export function bandLevels(key: LevelBandKey, scale: LevelScale): { current: string; goal: string } {
  const [c, g] = key.split(">") as [LevelBand, LevelBand];
  const lower = (b: LevelBand) => (LEVEL_BANDS.indexOf(b) * 2 + 1) as LevelIndex;
  const upper = (b: LevelBand) => (LEVEL_BANDS.indexOf(b) * 2 + 2) as LevelIndex;
  return { current: scale.toStored(lower(c)), goal: scale.toStored(upper(g)) };
}

/** 控え（`generated_cards`）の `gen.levels` に入れる形。古い形（`"TOCFL-2>TOCFL-3"`）と混ざらない。 */
export function bandGenLevels(key: LevelBandKey): string {
  return `band:${key}`;
}

/**
 * **レベルで分ける extras の鍵**（S2）: メインの例文の札・パーツ・目印、追加の例文、パターンの数、使い方チャンク
 * （と、まだ配っていない使い方パターン）。メインの例文と訳は列（`example_sentence` / `example_translation`）。
 */
export const LEVEL_EXTRAS_KEYS = [
  "example_scene",
  "example_scene_for",
  "example_chunks",
  "example_v",
  "example_pattern_count",
  "examples_extra",
  "usage_chunks",
  "usage_patterns",
  "usage_v",
] as const;

/** レベルで分ける節（作り直し・報告からの直しの節の名前）。 */
export const LEVEL_SECTIONS = ["example", "examples_extra", "usage_chunks"] as const;

export function isLevelSection(section: string): boolean {
  return (LEVEL_SECTIONS as readonly string[]).includes(section);
}

const LEVEL_KEY_SET: ReadonlySet<string> = new Set(LEVEL_EXTRAS_KEYS);

/** extras を、レベルで分ける分（`level`）とそれ以外（`rest`）に分ける。 */
export function splitLevelExtras(extras: Record<string, unknown> | null | undefined): {
  level: Record<string, unknown>;
  rest: Record<string, unknown>;
} {
  const level: Record<string, unknown> = {};
  const rest: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(extras ?? {})) (LEVEL_KEY_SET.has(k) ? level : rest)[k] = v;
  return { level, rest };
}

/** レベルで分ける鍵を外した extras。 */
export function withoutLevelExtras<T extends Record<string, unknown> | null | undefined>(extras: T): T {
  if (!extras || typeof extras !== "object") return extras;
  return splitLevelExtras(extras).rest as T;
}

/** レベルの置き場の1行（必要な所だけ）。 */
export type LevelContentRow = {
  level_band: LevelBandKey;
  example_sentence: string | null;
  example_translation: string | null;
  extras: Record<string, unknown>;
};

/**
 * 読む人の解説に、その帯の例文・チャンクを重ねる（S6）。言語の置き場の例文・チャンクは**出さない**
 * （その帯の行が無ければ空 — 作りに行く）。
 */
export function overlayLevelContent<E extends Record<string, unknown> | null | undefined>(
  extras: E,
  row: LevelContentRow | null,
): Record<string, unknown> {
  return { ...splitLevelExtras(extras ?? {}).rest, ...(row ? splitLevelExtras(row.extras).level : {}) };
}

const filled = (v: unknown): boolean =>
  Array.isArray(v)
    ? v.length > 0
    : typeof v === "string"
      ? v.trim().length > 0
      : v != null && !(typeof v === "object" && Object.keys(v as object).length === 0);

/**
 * 帯の行に**空の所だけ**を埋める（共有の行と同じ約束 — 同じ帯の誰かがもう読んでいる中身を差し替えない）。
 * メインの例文は、文が空の時だけ文・訳・札・パーツを組で入れる（別の文の札を残さない）。
 * 書く物が無ければ null。
 */
export function fillEmptyLevelContent(
  current: LevelContentRow | null,
  next: { example_sentence?: string | null; example_translation?: string | null; extras?: Record<string, unknown> | null },
): { example_sentence?: string; example_translation?: string; extras: Record<string, unknown> } | null {
  const cur = current?.extras ?? {};
  const incoming = splitLevelExtras(next.extras ?? {}).level;
  const out: { example_sentence?: string; example_translation?: string; extras: Record<string, unknown> } = {
    extras: { ...splitLevelExtras(cur).level },
  };
  let changed = false;
  const mainKeys = new Set(["example_scene", "example_scene_for", "example_chunks", "example_v"]);
  const hasSentence = filled(current?.example_sentence);
  const nextSentence = (next.example_sentence ?? "").trim();
  // 送られた札・パーツ・訳が、いま在る文のための物か（別の文の札を残さない）。
  const sameSentence = hasSentence && nextSentence === (current?.example_sentence ?? "").trim();
  if (!hasSentence && nextSentence) {
    out.example_sentence = nextSentence;
    const tr = (next.example_translation ?? "").trim();
    if (tr) out.example_translation = tr;
    for (const k of mainKeys) {
      if (k in incoming) out.extras[k] = incoming[k];
      else delete out.extras[k];
    }
    changed = true;
  } else if (sameSentence) {
    // 文は在る: 同じ文のための訳・札・パーツの空きだけ入れる。
    const tr = (next.example_translation ?? "").trim();
    if (!filled(current?.example_translation) && tr) {
      out.example_translation = tr;
      changed = true;
    }
    for (const k of mainKeys) {
      if (filled(out.extras[k]) || !filled(incoming[k])) continue;
      out.extras[k] = incoming[k];
      changed = true;
    }
  }
  for (const [k, v] of Object.entries(incoming)) {
    if (mainKeys.has(k)) continue;
    if (filled(out.extras[k]) || !filled(v)) continue;
    out.extras[k] = v;
    changed = true;
  }
  return changed ? out : null;
}
