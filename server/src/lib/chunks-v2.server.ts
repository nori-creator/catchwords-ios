import { generateText } from "ai";
import {
  explanationLanguageName,
  forFeature,
  getAi,
  measuredAi,
  parseJsonFromAiText,
  providerConfig,
  type AiConfig,
} from "./ai-provider.server";
import { withPartReadings } from "./chunk-readings.server";
import {
  AiChunksReplySchema,
  applyJudge,
  describeChunkV2Gate,
  finalChunks,
  frameKey,
  gateChunksV2,
  mergeByAgreement,
  readJudgeVerdicts,
  UsageChunkV2Schema,
  type UsageChunkV2,
} from "./chunks-v2";
import { chunksV2Prompt, judgeV2Prompt, translateV2Prompt } from "./chunks-v2.prompt";
import { normalizeTargetLanguage } from "./target-lang";

/**
 * **使い方チャンク v2 — AI と書庫に触る部分**（設計は `docs/chunk-rules.md` の v2 の節）。
 *
 * 流れ: 書庫に有る → そのまま（別の表示言語なら訳だけ小さく書かせる） / 無い → 2 社（Gemini・Claude）に同じ指示で
 * **独立に**書かせ、形だけの門 → 型の照合（一致 = 合格）→ 片方だけの型はもう片方の会社に審査 → 合格だけを書庫へ。
 * 2 人目からは AI を呼ばない。片方の鍵が無ければ 1 社＋審査に落ちて記録する（一致の証拠は弱くなる）。
 *
 * 書庫の表（`chunk_library` / `chunk_library_text` / `chunk_runs`）が無い環境でも落ちない（書庫なしで作って返す）。
 */

// 最初の採点（2026-10-30、8 語）は 9 秒で 2 社とも全部が時間切れだった: 6 文と塊・候補・訳をまとめて書く返事は
// 1,500〜2,500 トークンで、速いモデルでも 10〜25 秒かかる。書庫に無い 1 人目だけが待つ（画面は他の項目を先に出し、
// 塊は後から入る）ので、締め切りは長めに置く。
const GEN_MS = Number(process.env.AI_CHUNKS_V2_GEN_MS ?? 40_000);
const JUDGE_MS = Number(process.env.AI_CHUNKS_V2_JUDGE_MS ?? 15_000);
const TRANSLATE_MS = Number(process.env.AI_CHUNKS_V2_TRANSLATE_MS ?? 20_000);
/** Claude の書き手・審査のモデル（`ANTHROPIC_API_KEY` が要る）。 */
const CLAUDE_MODEL = process.env.AI_CHUNKS_V2_CLAUDE_MODEL ?? "claude-haiku-5-5";
/** 同じ語の作り中が、これより古ければ捨てて作り直す。 */
const RUN_STALE_MS = 45_000;

type LooseResult = { data: unknown; error: { message: string; code?: string } | null };
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Loose = any;

/** 書き手 1 社。`company` は記録と、審査を逆の会社に回すための名前。 */
export type ChunkWriter = { company: string; cfg: AiConfig; model: string };

export type ChunksV2Stats = {
  providers: string;
  a: { company: string; ms: number; kept: number; dropped: number; raw: number } | null;
  b: { company: string; ms: number; kept: number; dropped: number; raw: number } | null;
  agreed: number;
  judgedIn: number;
  judgedOut: number;
  judgeMs: number;
  totalMs: number;
};

export type ChunksV2PipelineResult = {
  chunks: UsageChunkV2[];
  rejected: UsageChunkV2[];
  stats: ChunksV2Stats;
};

/** 既定の書き手: A = Gemini（カードと同じ会社・丁寧な方のモデル）、B = Claude（鍵が無ければ null）。 */
export function defaultWriters(): { a: ChunkWriter | null; b: ChunkWriter | null } {
  const base = forFeature(getAi(), "card");
  const a: ChunkWriter | null = {
    company: base.name ?? base.provider,
    cfg: measuredAi(base, "card", "chunks"),
    model: base.modelRich,
  };
  const claude = providerConfig("anthropic", CLAUDE_MODEL);
  const b: ChunkWriter | null = claude
    ? { company: "anthropic", cfg: measuredAi(claude, "card", "chunks"), model: claude.modelRich }
    : null;
  // 既定の AI が Anthropic の時は、2 社にならない（同じ会社の 2 回は一致の証拠にならない）: B を外す。
  if (b && a && a.company === "anthropic") return { a, b: null };
  return { a, b };
}

/** AI に 1 回聞いて JSON を読む（試験では差し替える）。 */
export type AskFn = (cfg: AiConfig, model: string, prompt: string, ms: number) => Promise<unknown>;

export const askJson: AskFn = async (cfg, model, prompt, ms) => {
  const result = await generateText({
    model: cfg.gateway(model),
    prompt,
    abortSignal: AbortSignal.timeout(ms),
    maxRetries: 0,
  });
  return parseJsonFromAiText(result.text);
};

/** 読む人の言語が学ぶ言語と同じ（繁體中文で台湾華語を読む）。 */
export function readerIsTargetLang(explainLang: string, language: string): boolean {
  const r = explainLang.toLowerCase();
  const t = normalizeTargetLanguage(language).toLowerCase();
  return r.startsWith("zh") ? t.startsWith("zh") : r === t;
}

/**
 * **作る（AI だけ。書庫に触らない）** — 採点もここを呼ぶ。
 */
export async function runChunksV2Pipeline(input: {
  headword: string;
  language: string;
  explainLang: string;
  meaning?: string | null;
  writers?: { a: ChunkWriter | null; b: ChunkWriter | null };
  genMs?: number;
  judgeMs?: number;
  ask?: AskFn;
}): Promise<ChunksV2PipelineResult> {
  const started = Date.now();
  const ask = input.ask ?? askJson;
  const { a, b } = input.writers ?? defaultWriters();
  const readerName = explanationLanguageName(input.explainLang);
  const readerIsTarget = readerIsTargetLang(input.explainLang, input.language);
  const prompt = chunksV2Prompt({ headword: input.headword, meaning: input.meaning, readerName, readerIsTarget });
  const gateCtx = { headword: input.headword, language: input.language, readerLang: input.explainLang };
  const genMs = input.genMs ?? GEN_MS;
  const judgeMs = input.judgeMs ?? JUDGE_MS;

  const write = async (w: ChunkWriter | null) => {
    if (!w) return null;
    const t0 = Date.now();
    try {
      const raw = await ask(w.cfg, w.model, prompt, genMs);
      const reply = AiChunksReplySchema.parse(raw);
      const gate = gateChunksV2(reply.chunks, gateCtx);
      console.info(`[chunks-v2] ${w.company} ${input.headword}: ${describeChunkV2Gate(gate)} ${Date.now() - t0}ms`);
      return { w, kept: gate.kept, raw: reply.chunks.length, dropped: gate.dropped.length, ms: Date.now() - t0 };
    } catch (e) {
      console.warn(`[chunks-v2] ${w.company} ${input.headword}: failed ${Date.now() - t0}ms`, (e as Error)?.name ?? e, (e as Error)?.message ?? "");
      return { w, kept: [] as UsageChunkV2[], raw: 0, dropped: 0, ms: Date.now() - t0, failed: true };
    }
  };
  const [ra, rb] = await Promise.all([write(a), write(b)]);

  // 照合: 両方が書けた時だけ一致を取る。片方だけの時は、全部を「片方だけ」として審査へ。
  const both = ra && rb && !ra.failed && !rb.failed;
  const merged = both
    ? mergeByAgreement(ra.kept, rb.kept)
    : { agreed: [] as UsageChunkV2[], onlyA: ra?.kept ?? [], onlyB: rb?.kept ?? [] };

  // 審査は、書いた方と逆の会社。逆が無ければ有る方（記録に残す）。
  const judgeWith = async (pending: UsageChunkV2[], judge: ChunkWriter | null) => {
    if (pending.length === 0 || !judge) return { approved: [] as UsageChunkV2[], ms: 0 };
    const t0 = Date.now();
    try {
      const cfg = measuredAi(judge.cfg, "card", "chunks_judge");
      const raw = await ask(cfg, judge.model, judgeV2Prompt(input.headword, pending), judgeMs);
      const verdicts = readJudgeVerdicts(raw, pending.length);
      return { approved: applyJudge(pending, verdicts), ms: Date.now() - t0 };
    } catch (e) {
      console.warn(`[chunks-v2] judge ${judge.company} ${input.headword}: failed`, (e as Error)?.name ?? e);
      return { approved: [] as UsageChunkV2[], ms: Date.now() - t0 };
    }
  };
  const judgeA = b ?? a;
  const judgeB = a ?? b;
  const [ja, jb] = await Promise.all([judgeWith(merged.onlyA, judgeA), judgeWith(merged.onlyB, judgeB)]);
  const judged = [...ja.approved, ...jb.approved].sort((x, y) => (y.frequency ?? 0) - (x.frequency ?? 0));
  const chunks = finalChunks(merged.agreed, judged);
  const keptKeys = new Set(chunks.map(frameKey));
  const rejected = [...merged.onlyA, ...merged.onlyB].filter((c) => !keptKeys.has(frameKey(c)));
  const providers = [a?.company, b?.company].filter(Boolean).join("+") || "none";

  return {
    chunks,
    rejected,
    stats: {
      providers,
      a: ra ? { company: ra.w.company, ms: ra.ms, kept: ra.kept.length, dropped: ra.dropped, raw: ra.raw } : null,
      b: rb ? { company: rb.w.company, ms: rb.ms, kept: rb.kept.length, dropped: rb.dropped, raw: rb.raw } : null,
      agreed: merged.agreed.length,
      judgedIn: judged.length,
      judgedOut: rejected.length,
      judgeMs: Math.max(ja.ms, jb.ms),
      totalMs: Date.now() - started,
    },
  };
}

// ---------------------------------------------------------------------------------------------
// 書庫
// ---------------------------------------------------------------------------------------------

function isMissing(error: { message?: string; code?: string } | null | undefined): boolean {
  if (!error) return false;
  return (
    error.code === "42703" ||
    error.code === "42P01" ||
    error.code === "PGRST204" ||
    error.code === "PGRST205" ||
    /chunk_library|chunk_runs/.test(error.message ?? "")
  );
}

type LibraryRow = {
  id: string;
  zh: string;
  blocks: unknown;
  head: unknown;
  pattern: string | null;
  sentence: string | null;
  rank: number | null;
  frequency: number | null;
  decided_by: string | null;
};
type TextRow = { library_id: string; ja: string | null; sentence_ja: string | null; note: string | null; blocks_ja: unknown };

/** 中国語の block（訳を持たない形）に、その表示言語の意味を重ねる。 */
function assemble(row: LibraryRow, text: TextRow | null, language: string): UsageChunkV2 | null {
  const parsed = UsageChunkV2Schema.safeParse({
    text: row.zh,
    blocks: row.blocks,
    head: row.head,
    pattern: row.pattern ?? "",
    ja: text?.ja ?? "",
    note: text?.note || undefined,
    sentence: row.sentence ?? "",
    sentence_ja: text?.sentence_ja ?? "",
    frequency: row.frequency,
    by: row.decided_by ?? undefined,
  });
  if (!parsed.success) return null;
  const c = parsed.data;
  const blocksJa = Array.isArray(text?.blocks_ja) ? (text!.blocks_ja as Array<{ ja?: string; alts_ja?: string[] }>) : [];
  c.blocks = c.blocks.map((b, i) => {
    const bj = blocksJa[i];
    const next = { ...b };
    if (bj?.ja) next.ja = bj.ja;
    if (next.alts?.length) {
      next.alts = next.alts.map((al, j) => ({ ...al, ja: bj?.alts_ja?.[j] ?? al.ja ?? "" }));
    }
    return withPartReadings(next, language);
  });
  return c;
}

/** 書庫の塊（承認済み・順）とその表示言語の訳。表が無ければ null。 */
export async function readChunkLibrary(
  admin: unknown,
  language: string,
  headword: string,
  explainLang: string,
): Promise<{ chunks: UsageChunkV2[]; missingText: UsageChunkV2[]; rows: LibraryRow[] } | null> {
  try {
    const r = (await (admin as Loose)
      .from("chunk_library")
      .select("id, zh, blocks, head, pattern, sentence, rank, frequency, decided_by")
      .eq("language", language)
      .eq("headword", headword)
      .eq("status", "approved")
      .order("rank", { ascending: true })) as LooseResult;
    if (r.error) {
      if (!isMissing(r.error)) console.warn("[chunks-v2] library read", r.error.message);
      return null;
    }
    const rows = (r.data as LibraryRow[] | null) ?? [];
    if (rows.length === 0) return { chunks: [], missingText: [], rows };
    const needText = !readerIsTargetLang(explainLang, language);
    let texts: TextRow[] = [];
    if (needText) {
      const t = (await (admin as Loose)
        .from("chunk_library_text")
        .select("library_id, ja, sentence_ja, note, blocks_ja")
        .in("library_id", rows.map((x) => x.id))
        .eq("explain_lang", explainLang)) as LooseResult;
      if (!t.error) texts = (t.data as TextRow[] | null) ?? [];
    }
    const byId = new Map(texts.map((t) => [t.library_id, t]));
    const chunks: UsageChunkV2[] = [];
    const missingText: UsageChunkV2[] = [];
    for (const row of rows) {
      const text = byId.get(row.id) ?? null;
      const c = assemble(row, text, language);
      if (!c) continue;
      if (needText && !text?.ja) missingText.push(c);
      else chunks.push(c);
    }
    return { chunks, missingText, rows };
  } catch {
    return null;
  }
}

function textRowFor(c: UsageChunkV2) {
  return {
    ja: c.ja,
    sentence_ja: c.sentence_ja,
    note: c.note ?? "",
    blocks_ja: c.blocks.map((b) => ({ ja: b.ja ?? "", alts_ja: (b.alts ?? []).map((a) => a.ja ?? "") })),
  };
}

/** 中国語だけの block（書庫の形。訳は別の表）。 */
function zhBlocks(c: UsageChunkV2) {
  return c.blocks.map((b) => ({
    text: b.text,
    pos: b.pos,
    ...(b.slot ? { slot: true, alts: (b.alts ?? []).map((a) => ({ text: a.text })) } : {}),
  }));
}

/** 作った物を書庫へ（承認・不合格の両方）。訳はその表示言語の行に。投げない。 */
export async function writeChunkLibrary(
  admin: unknown,
  input: { language: string; headword: string; explainLang: string; providers: string },
  approved: ReadonlyArray<UsageChunkV2>,
  rejected: ReadonlyArray<UsageChunkV2> = [],
): Promise<boolean> {
  const now = new Date().toISOString();
  const rows = [
    ...approved.map((c, i) => ({ c, status: "approved", rank: i })),
    ...rejected.map((c, i) => ({ c, status: "rejected", rank: 100 + i })),
  ].map(({ c, status, rank }) => ({
    language: input.language,
    headword: input.headword,
    zh: c.text,
    frame: frameKey(c),
    blocks: zhBlocks(c),
    head: c.head,
    pattern: c.pattern,
    sentence: c.sentence,
    rank,
    frequency: c.frequency,
    decided_by: c.by ?? null,
    status,
    providers: input.providers,
    updated_at: now,
  }));
  if (rows.length === 0) return true;
  try {
    const r = (await (admin as Loose)
      .from("chunk_library")
      .upsert(rows, { onConflict: "language,headword,zh" })
      .select("id, zh")) as LooseResult;
    if (r.error) {
      if (!isMissing(r.error)) console.warn("[chunks-v2] library write", r.error.message);
      return false;
    }
    if (readerIsTargetLang(input.explainLang, input.language)) return true;
    const ids = new Map(((r.data as Array<{ id: string; zh: string }> | null) ?? []).map((x) => [x.zh, x.id]));
    const textRows = approved
      .filter((c) => ids.has(c.text) && c.ja)
      .map((c) => ({ library_id: ids.get(c.text), explain_lang: input.explainLang, ...textRowFor(c) }));
    if (textRows.length === 0) return true;
    const t = (await (admin as Loose)
      .from("chunk_library_text")
      .upsert(textRows, { onConflict: "library_id,explain_lang" })) as LooseResult;
    if (t.error) console.warn("[chunks-v2] library text write", t.error.message);
    return !t.error;
  } catch (e) {
    console.warn("[chunks-v2] library write threw", (e as Error)?.message);
    return false;
  }
}

type RunRow = { status: string; started_at: string; finished_at: string | null; approved: number };

async function readRun(admin: unknown, language: string, headword: string): Promise<RunRow | null> {
  try {
    const r = (await (admin as Loose)
      .from("chunk_runs")
      .select("status, started_at, finished_at, approved")
      .eq("language", language)
      .eq("headword", headword)
      .maybeSingle()) as LooseResult;
    if (r.error) return null;
    return (r.data as RunRow | null) ?? null;
  } catch {
    return null;
  }
}

async function writeRun(
  admin: unknown,
  language: string,
  headword: string,
  patch: { status: "pending" | "done" | "failed"; providers?: string; approved?: number; error?: string | null },
): Promise<void> {
  try {
    const row = {
      language,
      headword,
      status: patch.status,
      providers: patch.providers ?? null,
      approved: patch.approved ?? 0,
      error: patch.error ?? null,
      ...(patch.status === "pending"
        ? { started_at: new Date().toISOString(), finished_at: null }
        : { finished_at: new Date().toISOString() }),
    };
    const r = (await (admin as Loose).from("chunk_runs").upsert(row, { onConflict: "language,headword" })) as LooseResult;
    if (r.error && !isMissing(r.error)) console.warn("[chunks-v2] run write", r.error.message);
  } catch {
    /* 記録できなくても作る方は進む */
  }
}

/** 書庫に有る塊に、別の表示言語の訳・解説を付ける（小さな呼び出し）。失敗すれば []。 */
async function translateForReader(
  headword: string,
  language: string,
  chunks: ReadonlyArray<UsageChunkV2>,
  explainLang: string,
  writer: ChunkWriter | null,
  ask: AskFn = askJson,
): Promise<UsageChunkV2[]> {
  if (!writer || chunks.length === 0) return [];
  try {
    const cfg = measuredAi(writer.cfg, "card", "chunks_translate");
    const raw = (await ask(cfg, writer.model, translateV2Prompt(headword, chunks, explanationLanguageName(explainLang)), TRANSLATE_MS)) as {
      items?: unknown;
    };
    const items = Array.isArray(raw?.items) ? (raw.items as Array<Record<string, unknown>>) : [];
    const gateCtx = { headword, language, readerLang: explainLang };
    const out: UsageChunkV2[] = [];
    chunks.forEach((c, at) => {
      const it = items.find((x) => Number(x?.i) === at + 1) ?? items[at];
      if (!it) return;
      const slotAt = c.blocks.findIndex((b) => b.slot);
      const altsJa = Array.isArray(it.alts_ja) ? (it.alts_ja as unknown[]).map((v) => (typeof v === "string" ? v : "")) : [];
      const blocks = c.blocks.map((b, i) =>
        i === slotAt
          ? { ...b, ja: typeof it.slot_ja === "string" ? it.slot_ja : "", alts: (b.alts ?? []).map((a, j) => ({ ...a, ja: altsJa[j] ?? "" })) }
          : b,
      );
      const candidate = { ...c, blocks, ja: String(it.ja ?? ""), sentence_ja: String(it.sentence_ja ?? ""), note: String(it.note ?? "") };
      // 言語の混ざりは門で落とす（形だけ）。
      const gate = gateChunksV2(
        [{ sentence: candidate.sentence, sentence_ja: candidate.sentence_ja, text: candidate.text, blocks: candidate.blocks, pattern: candidate.pattern, ja: candidate.ja, note: candidate.note }],
        gateCtx,
      );
      if (gate.kept[0]) out.push({ ...gate.kept[0], frequency: c.frequency, by: c.by });
    });
    return out;
  } catch (e) {
    console.warn("[chunks-v2] translate failed", (e as Error)?.name ?? e);
    return [];
  }
}

export type ChunksV2JobResult = {
  status: "ready" | "none" | "pending";
  chunks: UsageChunkV2[];
  fromLibrary: boolean;
  stats?: ChunksV2Stats;
};

/**
 * **その語のチャンクを用意する**: 書庫 → 無ければ作って書庫へ。同じ語の作り中が他に居れば `pending`（呼ぶ側が待って
 * 読み直す）。`force` は ↻（書庫を無視して作り直し、書庫を置き換える）。
 */
export async function startChunksV2Job(
  admin: unknown,
  input: {
    language: string;
    headword: string;
    explainLang: string;
    meaning?: string | null;
    force?: boolean;
    /** 試験用: 書き手と AI の呼び方の差し替え。 */
    writers?: { a: ChunkWriter | null; b: ChunkWriter | null };
    ask?: AskFn;
  },
): Promise<ChunksV2JobResult> {
  const language = normalizeTargetLanguage(input.language);
  const headword = input.headword.trim();
  const writers = input.writers ?? defaultWriters();
  if (!input.force) {
    const lib = await readChunkLibrary(admin, language, headword, input.explainLang);
    if (lib && lib.rows.length > 0) {
      if (lib.missingText.length > 0) {
        const translated = await translateForReader(headword, language, lib.missingText, input.explainLang, writers.a ?? writers.b, input.ask);
        if (translated.length > 0) {
          await writeChunkLibrary(admin, { language, headword, explainLang: input.explainLang, providers: "translate" }, translated);
        }
        const all = [...lib.chunks, ...translated].sort((x, y) => rankOf(lib.rows, x) - rankOf(lib.rows, y));
        return { status: all.length > 0 ? "ready" : "none", chunks: all, fromLibrary: true };
      }
      return { status: "ready", chunks: lib.chunks, fromLibrary: true };
    }
    const run = await readRun(admin, language, headword);
    if (run) {
      const age = Date.now() - Date.parse(run.started_at);
      if (run.status === "pending" && age < RUN_STALE_MS) return { status: "pending", chunks: [], fromLibrary: false };
      // 作ったが 1 つも合格しなかった語: 1 日は作り直さない（毎回 AI を呼ばない）。
      if (run.status === "done" && run.approved === 0 && run.finished_at && Date.now() - Date.parse(run.finished_at) < 86_400_000) {
        return { status: "none", chunks: [], fromLibrary: true };
      }
    }
  }
  await writeRun(admin, language, headword, { status: "pending" });
  try {
    const result = await runChunksV2Pipeline({ headword, language, explainLang: input.explainLang, meaning: input.meaning, writers, ask: input.ask });
    await writeChunkLibrary(admin, { language, headword, explainLang: input.explainLang, providers: result.stats.providers }, result.chunks, result.rejected);
    await writeRun(admin, language, headword, { status: "done", providers: result.stats.providers, approved: result.chunks.length });
    return { status: result.chunks.length > 0 ? "ready" : "none", chunks: result.chunks, fromLibrary: false, stats: result.stats };
  } catch (e) {
    await writeRun(admin, language, headword, { status: "failed", error: String((e as Error)?.message ?? e).slice(0, 300) });
    return { status: "none", chunks: [], fromLibrary: false };
  }
}

function rankOf(rows: ReadonlyArray<LibraryRow>, c: UsageChunkV2): number {
  return rows.find((r) => r.zh === c.text)?.rank ?? 999;
}

/**
 * 作り中の語を待つ（500 ms ごとに書庫を読む）。`pending` のまま時間切れなら `pending` を返す。
 */
export async function awaitChunksV2(
  admin: unknown,
  input: Parameters<typeof startChunksV2Job>[1],
  waitMs: number,
): Promise<ChunksV2JobResult> {
  const deadline = Date.now() + waitMs;
  let r = await startChunksV2Job(admin, input);
  while (r.status === "pending" && Date.now() < deadline) {
    await new Promise((res) => setTimeout(res, 500));
    r = await startChunksV2Job(admin, input);
  }
  return r;
}
