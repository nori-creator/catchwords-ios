import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import fixture from "./__fixtures__/chunks-v2-eval.json";
import { frameKey, type UsageChunkV2 } from "./chunks-v2";
import { defaultWriters, runChunksV2Pipeline, type ChunkWriter, type ChunksV2Stats } from "./chunks-v2.server";
import { concreteModelId, measuredAi, providerConfig } from "./ai-provider.server";

/**
 * **使い方チャンク v2 の採点**（本物の AI を呼ぶ。普段の `npm test` では飛ばす）。
 *
 * 走らせ方（鍵が要る）:
 *   CHUNK_EVAL=1 GEMINI_API_KEY=… ANTHROPIC_API_KEY=… npx vitest run chunks-v2.eval
 * - `CHUNK_EVAL_REF=1` … 上位のモデル（Gemini latest-pro × Claude Sonnet）で同じ照合をして、**参照**
 *   （`__fixtures__/chunks-v2-eval.reference.json`）を書く。普段の採点は、この参照と比べる。
 * - `CHUNK_EVAL_LIMIT=10` … 最初の 10 語だけ。`CHUNK_EVAL_WORDS=筆袋,馬克杯` … その語だけ。
 * - `CHUNK_EVAL_LANG=ja` … 読む人の言語（既定 ja）。
 * 結果は `server/eval-out/chunks-v2-report.md`（人が読む）と `.json`（数字）に書く。GitHub Actions
 * （`.github/workflows/chunks-v2.yml`）は同じ物を成果物として残す。
 *
 * 見る数字（`docs/chunk-rules.md` の v2 の節）: 1 語あたりの塊の数、2 社の一致の割合、審査の不合格率、語ごとの時間の
 * p50 / p90、参照と比べた precision（出した塊のうち参照にも在る物）と ① の一致率。
 */

type FixtureWord = { headword: string; meaning_ja?: string; category?: number; source: string };
type Reference = Record<string, { frames: string[]; texts: string[] }>;

const ON = process.env.CHUNK_EVAL === "1";
const REF_MODE = process.env.CHUNK_EVAL_REF === "1";
const LANG = process.env.CHUNK_EVAL_LANG ?? "ja";
const OUT_DIR = resolve(__dirname, "../../eval-out");
const REF_PATH = resolve(__dirname, "__fixtures__/chunks-v2-eval.reference.json");

function pick(): FixtureWord[] {
  let words = (fixture as { words: FixtureWord[] }).words;
  const only = (process.env.CHUNK_EVAL_WORDS ?? "").split(",").map((s) => s.trim()).filter(Boolean);
  if (only.length) words = words.filter((w) => only.includes(w.headword));
  const limit = Number(process.env.CHUNK_EVAL_LIMIT ?? 0);
  if (limit > 0) words = words.slice(0, limit);
  return words;
}

function referenceWriters(): { a: ChunkWriter | null; b: ChunkWriter | null } {
  // 参照は上位のモデル。鍵が無い会社は null（その時の参照は 1 社＋審査になるので、記録に残す）。
  const g = providerConfig("google", process.env.CHUNK_EVAL_REF_GOOGLE ?? "latest-pro");
  const c = providerConfig("anthropic", process.env.CHUNK_EVAL_REF_CLAUDE ?? "claude-sonnet-5-5");
  return {
    a: g ? { company: "google", cfg: measuredAi(g, "card", "chunks"), model: g.modelRich } : null,
    b: c ? { company: "anthropic", cfg: measuredAi(c, "card", "chunks"), model: c.modelRich } : null,
  };
}

function percentile(xs: number[], p: number): number {
  if (xs.length === 0) return 0;
  const s = [...xs].sort((a, b) => a - b);
  return s[Math.min(s.length - 1, Math.floor((s.length - 1) * p))];
}

async function mapLimit<T, R>(items: T[], limit: number, fn: (t: T) => Promise<R>): Promise<R[]> {
  const out: R[] = new Array(items.length);
  let next = 0;
  await Promise.all(
    Array.from({ length: Math.min(limit, items.length) }, async () => {
      while (next < items.length) {
        const i = next++;
        out[i] = await fn(items[i]);
      }
    }),
  );
  return out;
}

describe.skipIf(!ON)("使い方チャンク v2 の採点（本物の AI）", () => {
  it("採点して報告を書く", { timeout: 60 * 60 * 1000 }, async () => {
    const words = pick();
    const writers = REF_MODE ? referenceWriters() : defaultWriters();
    expect(writers.a || writers.b, "鍵が 1 つも無い").toBeTruthy();
    let reference: Reference = {};
    try {
      reference = JSON.parse(readFileSync(REF_PATH, "utf8")) as Reference;
    } catch {
      /* 参照がまだ無い */
    }

    const modelNames = await Promise.all(
      [writers.a, writers.b].map(async (w) => (w ? `${w.company}:${await concreteModelId({ name: w.company }, w.model)}` : null)),
    );
    const rows = await mapLimit(words, Number(process.env.CHUNK_EVAL_CONCURRENCY ?? 3), async (w) => {
      const r = await runChunksV2Pipeline({ headword: w.headword, language: "zh-TW", explainLang: LANG, meaning: w.meaning_ja, writers });
      const shown = new Set(r.chunks.map((c) => c.text));
      return { word: w, chunks: r.chunks, rejected: r.rejected, stats: r.stats, untranslated: r.selected.filter((c) => !shown.has(c.text)).map((c) => c.text) };
    });

    // 数字
    const totalMs = rows.map((r) => r.stats.totalMs);
    const nChunks = rows.map((r) => r.chunks.length);
    const agreed = rows.reduce((n, r) => n + r.stats.agreed, 0);
    const judgedIn = rows.reduce((n, r) => n + r.stats.selectedJudged, 0);
    const judgedOut = rows.reduce((n, r) => n + r.stats.rejected, 0);
    const agreedShown = rows.reduce((n, r) => n + r.stats.selectedAgreed, 0);
    const shown = agreedShown + judgedIn;
    const patterns = new Map<string, number>();
    for (const r of rows) for (const c of r.chunks) patterns.set(c.pattern || "?", (patterns.get(c.pattern || "?") ?? 0) + 1);
    let refWords = 0;
    let precisionHit = 0;
    let precisionAll = 0;
    let top1 = 0;
    let recallHit = 0;
    let recallAll = 0;
    for (const r of rows) {
      const ref = reference[r.word.headword];
      if (!ref) continue;
      refWords++;
      const refFrames = new Set(ref.frames);
      for (const c of r.chunks) {
        precisionAll++;
        if (refFrames.has(frameKey(c))) precisionHit++;
      }
      if (r.chunks[0] && ref.frames[0] && frameKey(r.chunks[0]) === ref.frames[0]) top1++;
      const mine = new Set(r.chunks.map(frameKey));
      for (const f of ref.frames.slice(0, 3)) {
        recallAll++;
        if (mine.has(f)) recallHit++;
      }
    }
    const summary = {
      mode: REF_MODE ? "reference" : "eval",
      providers: rows[0]?.stats.providers ?? "",
      words: rows.length,
      chunksPerWord: Number((nChunks.reduce((a, b) => a + b, 0) / Math.max(1, rows.length)).toFixed(2)),
      wordsWithNone: nChunks.filter((n) => n === 0).length,
      agreementShare: shown ? Number((agreedShown / shown).toFixed(3)) : 0,
      agreedCandidates: agreed,
      judgeRejectRate: judgedIn + judgedOut ? Number((judgedOut / (judgedIn + judgedOut)).toFixed(3)) : 0,
      p50Ms: percentile(totalMs, 0.5),
      p90Ms: percentile(totalMs, 0.9),
      patterns: Object.fromEntries([...patterns.entries()].sort((a, b) => b[1] - a[1])),
      vsReference: refWords
        ? { words: refWords, precision: Number((precisionHit / Math.max(1, precisionAll)).toFixed(3)), top1: Number((top1 / refWords).toFixed(3)), recallTop3: Number((recallHit / Math.max(1, recallAll)).toFixed(3)) }
        : null,
    };

    mkdirSync(OUT_DIR, { recursive: true });
    const line = (c: UsageChunkV2) => {
      const slot = c.blocks.find((b) => b.slot);
      return `${c.text}（${c.by === "agreement" ? "一致" : "審査"} / ${c.pattern || "?"}${slot ? ` / 入替 ${slot.text}→${(slot.alts ?? []).map((a) => a.text).join("·")}` : ""}）`;
    };
    const ms = (r: (typeof rows)[number]) => {
      const st = r.stats;
      const w = (x: ChunksV2Stats["a"]) => (x ? `${x.company[0]}${x.failed ? "✗" : ""}${Math.round(x.ms / 100) / 10}` : "-");
      return `${Math.round(st.totalMs / 100) / 10}s（書 ${w(st.a)}/${w(st.b)} 審 ${Math.round(st.judgeMs / 100) / 10}(${st.judgedBy}) 仕 ${Math.round(st.finishMs / 100) / 10}）`;
    };
    const timings = rows.map((r) => r.stats);
    const writeMs = timings.flatMap((s) => [s.a, s.b]).filter((x): x is NonNullable<typeof x> => !!x && !x.failed).map((x) => x.ms);
    const failedWrites = timings.flatMap((s) => [s.a, s.b]).filter((x) => x?.failed).length;
    const md = [
      `# 使い方チャンク v2 の採点 — ${summary.mode}（${new Date().toISOString()}）`,
      ``,
      `- 書き手: ${summary.providers}（${modelNames.filter(Boolean).join(" / ")}）、読む人の言語: ${LANG}、語: ${summary.words}`,
      `- 1 語あたりの塊: ${summary.chunksPerWord}、塊が 0 の語: ${summary.wordsWithNone}、訳が付かず出せなかった塊: ${rows.reduce((n, r) => n + r.untranslated.length, 0)}`,
      `- 2 社の一致の割合（出した塊のうち）: ${summary.agreementShare}（候補の一致 ${summary.agreedCandidates}）、候補のうち落ちた割合: ${summary.judgeRejectRate}`,
      `- 1 語の時間: p50 ${summary.p50Ms} ms / p90 ${summary.p90Ms} ms（書く段 1 回: p50 ${percentile(writeMs, 0.5)} ms / p90 ${percentile(writeMs, 0.9)} ms、時間切れ ${failedWrites} 回、審査 p90 ${percentile(timings.map((s) => s.judgeMs), 0.9)} ms、仕上げ p90 ${percentile(timings.map((s) => s.finishMs), 0.9)} ms）`,
      `- 型の内訳: ${Object.entries(summary.patterns).map(([k, v]) => `${k} ${v}`).join("、")}`,
      summary.vsReference
        ? `- 参照（上位モデル）との比べ: precision ${summary.vsReference.precision}、① の一致 ${summary.vsReference.top1}、参照の上位 3 の再現 ${summary.vsReference.recallTop3}（${summary.vsReference.words} 語）`
        : `- 参照なし（CHUNK_EVAL_REF=1 で作る）`,
      ``,
      `| 語 | 塊（決まり方 / 型） | 文 | 不自然と落ちた | 省いた（重複・上限） | 訳が付かなかった | 時間 |`,
      `|---|---|---|---|---|---|---|`,
      ...rows.map((r) =>
        `| ${r.word.headword} | ${r.chunks.map(line).join("<br>") || "—"} | ${r.chunks.map((c) => c.sentence).join("<br>")} | ${r.rejected.filter((c) => c.reason === "unnatural").map((c) => c.text).join("<br>")} | ${r.rejected.filter((c) => c.reason !== "unnatural").map((c) => c.text).join("<br>")} | ${r.untranslated.join("<br>")} | ${ms(r)} |`,
      ),
      ``,
      `## 書く段の返事（会社ごと: 通った塊 / 形で落ちた物）`,
      ``,
      `| 語 | 会社 | 通った | 形で落ちた（理由） |`,
      `|---|---|---|---|`,
      ...rows.flatMap((r) =>
        [r.stats.a, r.stats.b]
          .filter((w): w is NonNullable<typeof w> => !!w)
          .map((w) => `| ${r.word.headword} | ${w.company}${w.failed ? "（時間切れ）" : ""} | ${(w.keptTexts ?? []).join("<br>")} | ${(w.droppedTexts ?? []).map((d) => `${d.text}（${d.reason}）`).join("<br>")} |`),
      ),
    ].join("\n");
    writeFileSync(resolve(OUT_DIR, "chunks-v2-report.md"), md);
    writeFileSync(
      resolve(OUT_DIR, "chunks-v2-report.json"),
      JSON.stringify({ summary, rows: rows.map((r) => ({ headword: r.word.headword, chunks: r.chunks, rejected: r.rejected.map((c) => ({ text: c.text, reason: c.reason })), stats: r.stats as ChunksV2Stats })) }, null, 2),
    );
    if (REF_MODE) {
      const ref: Reference = {};
      for (const r of rows) ref[r.word.headword] = { frames: r.chunks.map(frameKey), texts: r.chunks.map((c) => c.text) };
      writeFileSync(REF_PATH, JSON.stringify(ref, null, 2));
    }
    console.info(md);
    expect(rows.length).toBe(words.length);
  });
});
