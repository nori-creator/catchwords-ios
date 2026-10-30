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
  candidateToChunk,
  CHUNKS_V2_MAX,
  describeChunkV2Gate,
  finishCandidate,
  readerIsTarget,
  frameKey,
  gateChunksV2,
  mergeByAgreement,
  poolCandidates,
  rankAndSelect,
  readJudgeRanks,
  UsageChunkV2Schema,
  type ChunkCandidate,
  type FinishItem,
  type RejectedCandidate,
  type SelectedCandidate,
  type UsageChunkV2,
} from "./chunks-v2";
import { chunksV2Prompt, finishV2Prompt, judgeV2Prompt } from "./chunks-v2.prompt";
import { claude5ThinkingOff } from "./claude-thinking";
import { normalizeTargetLanguage } from "./target-lang";

/**
 * **使い方チャンク v2 — AI と書庫に触る部分**（設計は `docs/chunk-rules.md` の v2 の節）。
 *
 * 流れ: 書庫に有る → そのまま（別の表示言語なら訳だけ小さく書かせる） / 無い → 2 社（Gemini・Claude）に同じ指示で
 * **独立に**書かせ（中国語だけ・軽い形）、形だけの門 → 照合（同じ型・含む関係・同じ中心の語 = 一致）→ 候補を全部
 * 2 社に見せて審査（自然か・よく言う順）→ 残った塊にだけ仕上げ（block・品詞・訳）→ 書庫へ。2 人目からは AI を呼ばない。
 * 片方の鍵が無ければ 1 社＋審査に落ちて記録する（一致の証拠は弱くなる）。
 *
 * 書庫の表（`chunk_library` / `chunk_library_text` / `chunk_runs`）が無い環境でも落ちない（書庫なしで作って返す）。
 */

// 締め切り。2026-10-30 の採点: 3 回目まで 1 社 27〜40 秒かかったのは、モデルが**既定で長く考えていた**ため。計測（mode=probe、
// 同じ指示文）: Gemini 3.8 Flash は既定 22 秒 → reasoning_effort low で 4.4 秒、Claude Haiku 5.5 は既定 25 秒（考えた分 5,000
// トークン）→ thinking disabled で 1.9 秒。5 回目の採点は書く段 p90 5.2 秒・審査 p90 2.9 秒・仕上げ p90 3.8 秒、1 語 p50 11 秒。
// 締め切りはその 2〜3 倍（遅い回は捨てて、次に開いた時に出す）。
/** 環境変数のミリ秒（空・数でない・0 以下なら既定。Actions は未設定の入力を空文字で渡す）。 */
function envMs(name: string, def: number): number {
  const n = Number(process.env[name]);
  return Number.isFinite(n) && n > 0 ? n : def;
}
const GEN_MS = envMs("AI_CHUNKS_V2_GEN_MS", 25_000);
const JUDGE_MS = envMs("AI_CHUNKS_V2_JUDGE_MS", 15_000);
const FINISH_MS = envMs("AI_CHUNKS_V2_FINISH_MS", 12_000);
/**
 * **書き手・審査のモデル**（2026-10-30 の比べ、60 語）: Claude は Sonnet 5.5（Haiku より基本的で頻度の高い塊 — 滑手機・去剪頭髮・
 * 買便當。速さは同じくらい、考える量は最小にする）。Gemini は**最新の Flash**（`latest-pro` = gemini-2.5-pro はこの鍵で呼び出しが
 * 時々断られ、黙って flash-lite に落ちていた — 参照の実行で 13 回。Flash 3.8 は 4 秒で安定）。費用は語ごとに 1 回だけ（書庫で共有）。
 * 仕上げ（区切り・品詞・訳）は速いモデル（`FINISH_MODEL`）。
 */
const GEMINI_WRITER_MODEL = process.env.AI_CHUNKS_V2_GEMINI_MODEL ?? "latest-flash";
const CLAUDE_MODEL = process.env.AI_CHUNKS_V2_CLAUDE_MODEL ?? "claude-sonnet-5-5";
/** 仕上げ（区切り・品詞・訳）のモデル。`会社:モデル`。鍵が無ければ書き手の速い方。 */
const FINISH_MODEL = process.env.AI_CHUNKS_V2_FINISH_MODEL ?? "anthropic:claude-haiku-5-5";
/** Gemini の考える量（OpenAI 互換の口の `reasoning_effort`。Gemini 3 Flash は low が最小の確実な値 — minimal は版により 400）。 */
const GEMINI_EFFORT = process.env.AI_CHUNKS_V2_GEMINI_EFFORT ?? "low";
/** 同じ語の作り中が、これより古ければ捨てて作り直す。 */
const RUN_STALE_MS = 45_000;

type LooseResult = { data: unknown; error: { message: string; code?: string } | null };
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Loose = any;

/** 書き手 1 社。`company` は記録と、審査を逆の会社に回すための名前。 */
export type ChunkWriter = { company: string; cfg: AiConfig; model: string };

export type WriterStats = {
  company: string;
  ms: number;
  kept: number;
  dropped: number;
  raw: number;
  failed?: boolean;
  /** 形で落ちた物（字と理由。報告で AI の返事の癖を見る）。 */
  droppedTexts?: Array<{ text: string; reason: string }>;
  /** 書けた塊の字（報告用）。 */
  keptTexts?: string[];
};

export type ChunksV2Stats = {
  providers: string;
  a: WriterStats | null;
  b: WriterStats | null;
  /** 2 社が一致した塊の数（候補の中）。 */
  agreed: number;
  /** 候補の数（一致＋片方だけ）。 */
  pool: number;
  /** 選ばれた数（一致 / 審査で通った）。 */
  selectedAgreed: number;
  selectedJudged: number;
  /** 審査で「不自然」と落ちた数（重複・上限で省いた物は数えない）。 */
  rejected: number;
  judgeMs: number;
  /** 審査が答えた会社（a / b / both / none）。 */
  judgedBy: string;
  finishMs: number;
  totalMs: number;
};

export type ChunksV2PipelineResult = {
  /** 画面に出す塊（読む人の言語の訳つき）。訳が付けられなかった時は空（中国語だけの `selected` は書庫へ）。 */
  chunks: UsageChunkV2[];
  /** 2 社の照合と審査で残った塊（中国語だけ。仕上げが失敗しても block 1 つで残す）。 */
  selected: UsageChunkV2[];
  /** 落とした候補（理由つき: unnatural = 審査で不自然 / duplicate = 同じ言い方 / over_max = 上限）。 */
  rejected: RejectedCandidate[];
  stats: ChunksV2Stats;
};

/** 既定の書き手: A = Gemini（カードと同じ会社・丁寧な方のモデル）、B = Claude（鍵が無ければ null）。 */
export function defaultWriters(): { a: ChunkWriter | null; b: ChunkWriter | null } {
  const base = forFeature(getAi(), "card");
  // 既定の AI が Google なら、カードの Flash ではなく上位の Pro で書く（鍵は同じ）。
  const google = (base.name ?? base.provider) === "google" ? providerConfig("google", GEMINI_WRITER_MODEL) : null;
  const a: ChunkWriter | null = google
    ? { company: "google", cfg: measuredAi(google, "card", "chunks"), model: google.modelRich }
    : { company: base.name ?? base.provider, cfg: measuredAi(base, "card", "chunks"), model: base.modelRich };
  const claude = providerConfig("anthropic", CLAUDE_MODEL);
  const b: ChunkWriter | null = claude
    ? { company: "anthropic", cfg: measuredAi(claude, "card", "chunks"), model: claude.modelRich }
    : null;
  // 既定の AI が Anthropic の時は、2 社にならない（同じ会社の 2 回は一致の証拠にならない）: B を外す。
  if (b && a && a.company === "anthropic") return { a, b: null };
  return { a, b };
}

/** 仕上げの書き手（速いモデル）。鍵が無ければ null（呼ぶ側が書き手の速い方を使う）。 */
export function finishWriter(): ChunkWriter | null {
  const m = /^([a-z]+):(.+)$/i.exec(FINISH_MODEL.trim());
  if (!m) return null;
  const cfg = providerConfig(m[1], m[2]);
  return cfg ? { company: m[1], cfg: measuredAi(cfg, "card", "chunks_translate"), model: m[2] } : null;
}

/**
 * **考える量を最小にする**（速さの要）。OpenAI 互換の口は `providerOptions[会社名]` の中身を本文にそのまま足す。
 * - Anthropic: Messages API の `thinking`（Haiku 5.5 は disabled、Sonnet 5.5 は between_tools、Opus は切れない — `claude5ThinkingOff`）。
 * - Google: `reasoningEffort`（SDK の標準の欄。本文の `reasoning_effort` になり、Gemini 3 では thinking_level に写る）。
 *   **`reasoning_effort` と生で書くと SDK が自分の欄で上書きして消す**（4 回目の採点で Gemini だけ全部時間切れだった原因）。
 * ほかの会社には何も足さない。
 */
export type SpeedOptions = Record<string, Record<string, string | Record<string, string>>>;

export function speedOptions(cfg: Pick<AiConfig, "name">, model: string): SpeedOptions | undefined {
  const name = cfg.name ?? "";
  if (name === "anthropic") {
    const t = claude5ThinkingOff(`anthropic:${model}`);
    return t ? { anthropic: { thinking: t } } : undefined;
  }
  if (name === "google" && GEMINI_EFFORT && GEMINI_EFFORT !== "default") return { google: { reasoningEffort: GEMINI_EFFORT } };
  return undefined;
}

/** AI に 1 回聞いて JSON を読む（試験では差し替える）。 */
export type AskFn = (cfg: AiConfig, model: string, prompt: string, ms: number) => Promise<unknown>;

export const askJson: AskFn = async (cfg, model, prompt, ms) => {
  const providerOptions = speedOptions(cfg, model);
  const result = await generateText({
    model: cfg.gateway(model),
    prompt,
    abortSignal: AbortSignal.timeout(ms),
    maxRetries: 0,
    ...(providerOptions ? { providerOptions } : {}),
  });
  return parseJsonFromAiText(result.text);
};

/** 読む人の言語が学ぶ言語と同じ（繁體中文で台湾華語を読む）。知らない言語は「同じ」にしない（`readerIsTarget`）。 */
export function readerIsTargetLang(explainLang: string, language: string): boolean {
  return readerIsTarget(explainLang, language);
}

export type RunChunksV2Input = {
  headword: string;
  language: string;
  explainLang: string;
  meaning?: string | null;
  writers?: { a: ChunkWriter | null; b: ChunkWriter | null };
  /** 仕上げの書き手。省略 = 速いモデル（`finishWriter()`）、null = 書く段で速かった会社（試験は null）。 */
  finisher?: ChunkWriter | null;
  genMs?: number;
  judgeMs?: number;
  ask?: AskFn;
};

/**
 * **2 社に書かせ、照合し、審査し、残った塊を仕上げる**（書庫には触らない。試験はここを `ask` の偽物で回す）。
 */
export async function runChunksV2Pipeline(input: RunChunksV2Input): Promise<ChunksV2PipelineResult> {
  const started = Date.now();
  const ask = input.ask ?? askJson;
  const { a, b } = input.writers ?? defaultWriters();
  const prompt = chunksV2Prompt({ headword: input.headword, meaning: input.meaning });
  const gateCtx = { headword: input.headword, language: input.language };
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
      return { w, kept: gate.kept, raw: reply.chunks.length, dropped: gate.dropped.length, droppedTexts: gate.dropped, ms: Date.now() - t0, failed: false };
    } catch (e) {
      console.warn(`[chunks-v2] ${w.company} ${input.headword}: failed ${Date.now() - t0}ms`, (e as Error)?.name ?? e, (e as Error)?.message ?? "");
      return { w, kept: [] as ChunkCandidate[], raw: 0, dropped: 0, droppedTexts: [], ms: Date.now() - t0, failed: true };
    }
  };
  const [ra, rb] = await Promise.all([write(a), write(b)]);

  // 照合: 両方が書けた時だけ一致を取る。片方だけの時は、全部を「片方だけ」として審査へ。
  const both = ra && rb && !ra.failed && !rb.failed;
  const merged = both
    ? mergeByAgreement(ra.kept, rb.kept)
    : { agreed: [] as ChunkCandidate[], onlyA: ra?.kept ?? [], onlyB: rb?.kept ?? [] };
  const pool = poolCandidates(merged);

  // 審査と並べ替え: 候補を全部まとめて 2 社に見せる。合否は書いた方でない会社の「自然」、順位は 2 社の平均。
  const judgeWith = async (judge: ChunkWriter | null) => {
    if (pool.length === 0 || !judge) return { ranks: null as ReturnType<typeof readJudgeRanks> | null, ms: 0 };
    const t0 = Date.now();
    try {
      const cfg = measuredAi(judge.cfg, "card", "chunks_judge");
      const raw = await ask(cfg, judge.model, judgeV2Prompt(input.headword, pool.map((p) => p.chunk)), judgeMs);
      const ranks = readJudgeRanks(raw, pool.length);
      return { ranks: ranks.length > 0 ? ranks : null, ms: Date.now() - t0 };
    } catch (e) {
      console.warn(`[chunks-v2] judge ${judge.company} ${input.headword}: failed ${Date.now() - t0}ms`, (e as Error)?.name ?? e);
      return { ranks: null, ms: Date.now() - t0 };
    }
  };
  const [ja, jb] = await Promise.all([judgeWith(a && !ra?.failed ? a : null), judgeWith(b && !rb?.failed ? b : null)]);
  const { selected, rejected } = rankAndSelect(pool, ja.ranks, jb.ranks, CHUNKS_V2_MAX);

  // 仕上げ: 残った塊にだけ block・品詞と、読む人の言語の訳・解説（繁體中文で読む人は訳なし）。
  const t1 = Date.now();
  const readerName = readerIsTargetLang(input.explainLang, input.language) ? null : explanationLanguageName(input.explainLang);
  // 仕上げは速いモデルに。無ければ、書く段で速く答えた会社に（答えられなかった会社には頼まない）。
  const okWriters = [ra, rb].filter((r): r is NonNullable<typeof r> => !!r && !r.failed).sort((x, y) => x.ms - y.ms);
  const fallback = okWriters[0]?.w ?? a ?? b;
  const finisher = input.finisher === undefined ? (finishWriter() ?? fallback) : (input.finisher ?? fallback);
  const finished = await finishChunks(input.headword, input.language, selected, readerName, input.explainLang, finisher, ask);
  const chunks = readerName ? finished.filter((c) => c.ja) : finished;
  const providers = [a?.company, b?.company].filter(Boolean).join("+") || "none";

  return {
    chunks,
    selected: finished,
    rejected,
    stats: {
      providers,
      a: ra ? { company: ra.w.company, ms: ra.ms, kept: ra.kept.length, dropped: ra.dropped, raw: ra.raw, failed: ra.failed, droppedTexts: ra.droppedTexts, keptTexts: ra.kept.map((c) => c.text) } : null,
      b: rb ? { company: rb.w.company, ms: rb.ms, kept: rb.kept.length, dropped: rb.dropped, raw: rb.raw, failed: rb.failed, droppedTexts: rb.droppedTexts, keptTexts: rb.kept.map((c) => c.text) } : null,
      agreed: merged.agreed.length,
      pool: pool.length,
      selectedAgreed: finished.filter((c) => c.by === "agreement").length,
      selectedJudged: finished.filter((c) => c.by === "judge").length,
      rejected: rejected.filter((r) => r.reason === "unnatural").length,
      judgeMs: Math.max(ja.ms, jb.ms),
      judgedBy: ja.ranks && jb.ranks ? "both" : ja.ranks ? "a" : jb.ranks ? "b" : "none",
      finishMs: Date.now() - t1,
      totalMs: Date.now() - started,
    },
  };
}

/** 仕上げの返事から、候補の番号 → 返事の 1 つ。 */
function pickItems(raw: unknown, count: number): Array<FinishItem | null> {
  const items = Array.isArray((raw as { items?: unknown } | null)?.items) ? ((raw as { items: unknown[] }).items as Array<Record<string, unknown>>) : [];
  return Array.from({ length: count }, (_, at) => (items.find((x) => Number(x?.i) === at + 1) ?? items[at] ?? null) as FinishItem | null);
}

/**
 * 残った候補に block・品詞と訳を付ける（1 回の小さな呼び出し）。呼び出しが失敗したら block 1 つ・訳なしで返す
 * （中国語は書庫に残り、訳は次に開いた時に付く）。
 */
async function finishChunks(
  headword: string,
  language: string,
  selected: ReadonlyArray<SelectedCandidate>,
  readerName: string | null,
  explainLang: string,
  writer: ChunkWriter | null,
  ask: AskFn,
): Promise<UsageChunkV2[]> {
  if (selected.length === 0) return [];
  const ctx = { headword, language, readerLang: readerName ? explainLang : null };
  if (!writer) return selected.map((c) => candidateToChunk(c, headword, language));
  try {
    const cfg = measuredAi(writer.cfg, "card", "chunks_translate");
    const raw = await ask(cfg, writer.model, finishV2Prompt(headword, selected, readerName), FINISH_MS);
    const items = pickItems(raw, selected.length);
    return selected.map((c, at) => finishCandidate(c, items[at], ctx));
  } catch (e) {
    console.warn(`[chunks-v2] finish ${headword}: failed`, (e as Error)?.name ?? e);
    return selected.map((c) => candidateToChunk(c, headword, language));
  }
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

/** 書庫に有る塊に、別の表示言語の訳・解説を付ける（小さな呼び出し。block は書庫の物をそのまま使う）。失敗すれば []。 */
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
    const raw = await ask(cfg, writer.model, finishV2Prompt(headword, chunks, explanationLanguageName(explainLang), { blocks: false }), FINISH_MS);
    const items = pickItems(raw, chunks.length);
    const out: UsageChunkV2[] = [];
    chunks.forEach((c, at) => {
      const it = items[at];
      if (!it) return;
      const slot = c.blocks.find((b) => b.slot);
      const cand = { text: c.text, sentence: c.sentence, key: "", pattern: c.pattern, slot: slot?.text ?? null, alts: (slot?.alts ?? []).map((a) => a.text), by: c.by };
      // block は書庫の物（区切りは聞いていない）。訳だけを重ねる。
      const done = finishCandidate(cand, { ...it, blocks: c.blocks.map((b) => ({ text: b.text, pos: b.pos })) }, { headword, language, readerLang: explainLang });
      if (done.ja) out.push({ ...done, frequency: c.frequency, head: c.head ?? done.head });
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
        const translated = await translateForReader(headword, language, lib.missingText, input.explainLang, (input.ask ? null : finishWriter()) ?? writers.a ?? writers.b, input.ask);
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
    // 試験（ask の偽物）では仕上げも偽の書き手に（環境の鍵で速いモデルを探さない）。
    const result = await runChunksV2Pipeline({ headword, language, explainLang: input.explainLang, meaning: input.meaning, writers, ask: input.ask, ...(input.ask ? { finisher: null } : {}) });
    // 書庫には中国語（selected）を入れ、訳が付いた物（chunks）だけ訳の行も。訳が付かなかった塊は次に開いた時に訳だけ付く。
    const byText = new Map(result.chunks.map((c) => [c.text, c]));
    const forLibrary = result.selected.map((c) => byText.get(c.text) ?? c);
    const rejectedRows = result.rejected.filter((r) => r.reason === "unnatural").map((r) => candidateToChunk(r, headword, language));
    await writeChunkLibrary(admin, { language, headword, explainLang: input.explainLang, providers: result.stats.providers }, forLibrary, rejectedRows);
    await writeRun(admin, language, headword, { status: "done", providers: result.stats.providers, approved: result.selected.length });
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
