import { readerText, scrubExtrasForReader } from "./note-language";
import {
  LEGACY_BAND,
  fillEmptyLevelContent,
  isLevelBandKey,
  levelBandKey,
  splitLevelExtras,
  type LevelBandKey,
  type LevelContentRow,
} from "./level-content";

/**
 * レベルの置き場（`word_level_content`）と札の帯（`stickers.level_band`）の読み書き（`docs/sharing-rules.md`）。
 *
 * **表・列がまだ無い環境では、全員を古い語（`null`）として扱う** — 移行の前にこの関数を配っても、今までどおり動く。
 * どれも投げない（読めなければ「無い」、書けなければ false）。
 */

type LooseResult = { data: unknown; error: { message: string; code?: string } | null };
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Loose = any;

const TABLE = "word_level_content";

/** 列・表が無い時の誤り（移行の前）。 */
function isMissing(error: { message?: string; code?: string } | null | undefined): boolean {
  if (!error) return false;
  const m = error.message ?? "";
  return (
    error.code === "42703" ||
    error.code === "42P01" ||
    error.code === "PGRST204" ||
    error.code === "PGRST205" ||
    /level_band|word_level_content/.test(m)
  );
}

let availableCache: { at: number; ok: boolean } | null = null;

/** 移行が当たっているか（1分覚える）。 */
export async function levelContentAvailable(admin: unknown): Promise<boolean> {
  const now = Date.now();
  if (availableCache && now - availableCache.at < 60_000) return availableCache.ok;
  let ok = false;
  try {
    const r = (await (admin as Loose).from("stickers").select("level_band").limit(1)) as LooseResult;
    ok = !r.error;
    if (r.error && !isMissing(r.error)) ok = false;
  } catch {
    ok = false;
  }
  availableCache = { at: now, ok };
  return ok;
}

/** 試験用: 覚えた結果を忘れる。 */
export function resetLevelContentAvailability(): void {
  availableCache = null;
}

/** その人の今の帯（プロフィールの現状と目標の級から）。 */
export async function profileLevelBand(userId: string): Promise<LevelBandKey> {
  const { getUserLevels } = await import("./ai-provider.server");
  return levelBandKey(await getUserLevels(userId));
}

/**
 * **この人がこの語で使う帯**（S4）。`null` = 古い語（今までどおり）。
 *
 * - その語の札があれば、最も古い札の帯。`legacy` なら null。まだ書いていなければ今の帯を書いて使う。
 * - 札が無ければ（保存の前）今の帯。
 * - 移行の前（列が無い）は null。
 */
export async function callerLevelBand(
  admin: unknown,
  userId: string,
  wordId: string | null | undefined,
): Promise<LevelBandKey | null> {
  if (!(await levelContentAvailable(admin))) return null;
  try {
    if (wordId) {
      const r = (await (admin as Loose)
        .from("stickers")
        .select("id, level_band, created_at")
        .eq("user_id", userId)
        .eq("word_id", wordId)
        .order("created_at", { ascending: true })
        .limit(1)) as LooseResult;
      if (r.error) return null;
      const row = (r.data as { level_band?: string | null }[] | null)?.[0];
      if (row) {
        const b = (row.level_band ?? "").trim();
        if (b === LEGACY_BAND) return null;
        if (isLevelBandKey(b)) return b;
        const now = await profileLevelBand(userId);
        await pinStickerBand(admin, userId, wordId, now);
        return now;
      }
    }
    return await profileLevelBand(userId);
  } catch (e) {
    console.warn("[level-content] 帯を決められない — 古い語として扱う", (e as Error)?.message);
    return null;
  }
}

/** その人のその語の札で、帯がまだ空の物に帯を書く（保存した時の帯で固定 — S4）。 */
export async function pinStickerBand(
  admin: unknown,
  userId: string,
  wordId: string,
  band: LevelBandKey,
  opts: { replace?: boolean } = {},
): Promise<boolean> {
  try {
    let q = (admin as Loose)
      .from("stickers")
      .update({ level_band: band })
      .eq("user_id", userId)
      .eq("word_id", wordId);
    // ↻ で今の帯に移す時（S5）は、古い語の印も書き換える。
    if (!opts.replace) q = q.is("level_band", null);
    const r = (await q) as LooseResult;
    if (r.error) {
      if (!isMissing(r.error)) console.warn("[level-content] 札に帯を書けない", r.error.message);
      return false;
    }
    return true;
  } catch {
    return false;
  }
}

function toRow(r: Record<string, unknown>): LevelContentRow {
  const ex = r.extras;
  return {
    level_band: String(r.level_band ?? ""),
    example_sentence: (r.example_sentence as string | null) ?? null,
    example_translation: (r.example_translation as string | null) ?? null,
    extras: ex && typeof ex === "object" && !Array.isArray(ex) ? (ex as Record<string, unknown>) : {},
  };
}

/**
 * その帯の行を引く。ぴったり（言語・母語・帯）を先に、無ければ同じ言語・同じ帯の行（`pickExplanation` と同じ —
 * 母語が違っても読める言語で書いてある）。別の言語・別の帯には落ちない。
 */
export async function readLevelContent(
  admin: unknown,
  wordId: string,
  key: { explainLang: string; l1: string },
  band: LevelBandKey,
  opts: { exact?: boolean } = {},
): Promise<LevelContentRow | null> {
  try {
    const r = (await (admin as Loose)
      .from(TABLE)
      .select("l1, level_band, example_sentence, example_translation, extras")
      .eq("word_id", wordId)
      .eq("explain_lang", key.explainLang)
      .eq("level_band", band)) as LooseResult;
    if (r.error) {
      if (!isMissing(r.error)) console.warn("[level-content] 読めない", r.error.message);
      return null;
    }
    const rows = (r.data as Record<string, unknown>[] | null) ?? [];
    const exact = rows.find((x) => x.l1 === key.l1);
    if (exact) return toRow(exact);
    return !opts.exact && rows[0] ? toRow(rows[0]) : null;
  } catch {
    return null;
  }
}

async function upsertRow(
  admin: unknown,
  wordId: string,
  key: { explainLang: string; l1: string },
  band: LevelBandKey,
  row: { example_sentence?: string | null; example_translation?: string | null; extras: Record<string, unknown> },
): Promise<boolean> {
  try {
    const r = (await (admin as Loose).from(TABLE).upsert(
      {
        word_id: wordId,
        explain_lang: key.explainLang,
        l1: key.l1,
        level_band: band,
        ...("example_sentence" in row ? { example_sentence: row.example_sentence } : {}),
        ...("example_translation" in row ? { example_translation: row.example_translation } : {}),
        extras: row.extras,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "word_id,explain_lang,l1,level_band" },
    )) as LooseResult;
    if (r.error) {
      if (!isMissing(r.error)) console.warn("[level-content] 書けない", r.error.message);
      return false;
    }
    return true;
  } catch {
    return false;
  }
}

/**
 * サーバが作ったカードの例文・チャンクで、その帯の行の**空の所だけ**を埋める（`applyWordExtrasUpdate`）。
 * 読む人の言語でない訳・札は入れない。
 */
export async function fillLevelContent(
  admin: unknown,
  wordId: string,
  key: { explainLang: string; l1: string },
  band: LevelBandKey,
  card: { example_sentence?: string | null; example_translation?: string | null; extras?: Record<string, unknown> | null },
): Promise<boolean> {
  const current = await readLevelContent(admin, wordId, key, band, { exact: true });
  const extras = scrubExtrasForReader(
    splitLevelExtras(card.extras ?? {}).level as never,
    key.explainLang,
  ) as Record<string, unknown>;
  const translation = readerText(card.example_translation ?? null, key.explainLang, card.example_sentence ?? null);
  const next = fillEmptyLevelContent(current, {
    example_sentence: card.example_sentence ?? null,
    example_translation: translation || null,
    extras,
  });
  if (!next) return true;
  return upsertRow(admin, wordId, key, band, {
    ...(current ? {} : { example_sentence: null, example_translation: null }),
    ...next,
  });
}

/**
 * 作り直した1項目を、その帯の行に**重ねて**書く（`runSectionRegen` / 報告からの直し）。値の在る鍵は入れ替え、
 * `replaceKeys` は空でも入れ替える。メインの例文を作り直した時は文と訳も。行が無ければ作る。
 */
export async function mergeIntoLevelContent(
  admin: unknown,
  wordId: string,
  key: { explainLang: string; l1: string },
  band: LevelBandKey,
  patch: {
    extras: Record<string, unknown>;
    replaceKeys?: readonly string[];
    example_sentence?: string | null;
    example_translation?: string | null;
  },
): Promise<boolean> {
  const current = await readLevelContent(admin, wordId, key, band, { exact: true });
  const incoming = splitLevelExtras(
    scrubExtrasForReader(patch.extras as never, key.explainLang) as Record<string, unknown>,
  ).level;
  const extras: Record<string, unknown> = { ...splitLevelExtras(current?.extras ?? {}).level };
  for (const [k, v] of Object.entries(incoming)) {
    const filled = Array.isArray(v) ? v.length > 0 : typeof v === "string" ? v.trim().length > 0 : v != null;
    if (filled || (patch.replaceKeys ?? []).includes(k)) extras[k] = v;
  }
  const row: { example_sentence?: string | null; example_translation?: string | null; extras: Record<string, unknown> } = {
    extras,
  };
  const sentence = (patch.example_sentence ?? "").trim();
  if (sentence) {
    row.example_sentence = sentence;
    row.example_translation = readerText(patch.example_translation ?? null, key.explainLang, sentence) || null;
  } else if (!current) {
    row.example_sentence = null;
    row.example_translation = null;
  }
  return upsertRow(admin, wordId, key, band, row);
}

/**
 * 見出し語から、この人の帯と語の行を決める（`generateCard` は見出し語で呼ばれる）。語の行がまだ無ければ今の帯。
 */
export async function callerBandForHeadword(
  admin: unknown,
  userId: string,
  language: string,
  headword: string,
): Promise<{ band: LevelBandKey | null; wordId: string | null }> {
  if (!(await levelContentAvailable(admin))) return { band: null, wordId: null };
  let wordId: string | null = null;
  try {
    const r = (await (admin as Loose)
      .from("words")
      .select("id")
      .eq("language", language)
      .eq("headword", headword)
      .limit(1)) as LooseResult;
    wordId = ((r.data as { id?: string }[] | null)?.[0]?.id as string | undefined) ?? null;
  } catch {
    wordId = null;
  }
  return { band: await callerLevelBand(admin, userId, wordId), wordId };
}
