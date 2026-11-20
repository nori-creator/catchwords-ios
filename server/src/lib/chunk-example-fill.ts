/**
 * **型（チャンク）の数だけ例文を出す — 足りない型の例文を足す**（オーナー報告 2026-11-20 雨傘:
 * 「チャンクに対して例文が2つしか出ない…チャンクと例文の数が合わないミスが多い」）。
 *
 * 2026-10-27 に入れた「足りない型だけ小さな呼び出しで書かせる」は、本番で **28 回のうち 27 回が時間切れ**だった
 * （締め切り 8 秒。同じモデルの小さな呼び出しは中央値 9.2 秒・90% が 13 秒以内 — `ai_runs`、2026-11-01〜20）。
 * つまり足す道はほぼ一度も働いていなかった。さらに、型と例文を**別々に**書く道が2つあった:
 * - 「使い方」だけを作る（カードに型が1つも残らなかった時の自動の穴埋め・↻）→ 新しい型に例文が無い。
 * - 「例文」だけを作り直す（↻）→ 指示文に今の型が書かれておらず、型を含まない例文になる。
 *
 * ここは3つの道（カードの生成・使い方の作り直し・例文の作り直し）が同じ物を使う1つの段:
 * 1. 手元の文（同じ返事の生のパターン）から拾う（`coverChunks`。AI は呼ばない）。
 * 2. それでも例文の無い型だけ、1回の小さな呼び出しで書かせる（締め切りは実測に合わせる）。
 * 書けなかった時はカードをそのまま返す（型も例文も捨てない）。
 */
import { z } from "zod";
import {
  ExamplePatternSchema,
  coverChunks,
  type ExamplePattern,
} from "./example-patterns";

/**
 * 小さな呼び出しの締め切り。実測（上）の 90% が 13 秒以内・最大 15.6 秒なので 15 秒。8 秒では半分も返らない。
 */
export const CHUNK_EXAMPLES_TIMEOUT_MS = 15_000;
/** これより短い残り時間では呼ばない（返ってこない呼び出しに回数だけ使う）。 */
export const CHUNK_EXAMPLES_MIN_MS = 6_000;

/**
 * 残り時間から締め切りを決める。iOS はカードの生成・項目の作り直しを 60 秒で切る（`AIService.generateCard` /
 * `DexStore.fillSection`）ので、要求が始まってから `budgetMs` までに答える。残りが足りなければ 0（呼ばない）。
 */
export function chunkExamplesTimeout(elapsedMs: number, budgetMs = 52_000): number {
  const left = Math.min(CHUNK_EXAMPLES_TIMEOUT_MS, budgetMs - Math.max(0, elapsedMs));
  return left >= CHUNK_EXAMPLES_MIN_MS ? left : 0;
}

type CoverOpts = Parameters<typeof coverChunks>[1];
type Chunk = NonNullable<CoverOpts["chunks"]>[number];

export type ChunkExampleFill<T> = {
  card: T;
  /** 小さな呼び出しで頼んだ型の数（0 = 呼んでいない）。 */
  asked: number;
  /** それでも例文の無い型の番号。 */
  missing: number[];
  ms: number;
  /** 呼び出しが落ちた理由（時間切れなど）。 */
  error?: string;
};

export async function fillChunkExamples<
  T extends { example_sentence?: string; example_translation?: string; extras?: Record<string, unknown> | null },
>(
  card: T,
  opts: Omit<CoverOpts, "patterns"> & {
    /** 同じ返事の生のパターン（在れば先にここから拾う）。 */
    patterns?: readonly ExamplePattern[] | null;
    /** 例文の無い型だけを渡すと、その型の例文を書かせる指示文を返す（`chunkExamplesRule`）。 */
    rule: (missing: Chunk[]) => string;
    generate: (prompt: string, signal: AbortSignal) => Promise<{ text?: string | null }>;
    parse: (text: string) => unknown;
    /** 0 以下なら呼ばない（手元の文から拾うだけ）。 */
    timeoutMs: number;
  },
): Promise<ChunkExampleFill<T>> {
  const started = Date.now();
  const { patterns, rule, generate, parse, timeoutMs, ...cover } = opts;
  const chunks = cover.chunks ?? [];
  const first = coverChunks(card, { ...cover, patterns: patterns ?? [] });
  if (first.missing.length === 0 || !cover.withExtra || timeoutMs <= 0) {
    return { card: first.card, asked: 0, missing: first.missing, ms: Date.now() - started };
  }
  const asked = first.missing.map((i) => chunks[i]);
  try {
    const reply = await generate(rule(asked), AbortSignal.timeout(timeoutMs));
    const parsed = z
      .object({ example_patterns: z.array(ExamplePatternSchema).catch([]) })
      .catch({ example_patterns: [] })
      .parse(parse(reply.text ?? ""));
    const again = coverChunks(first.card, { ...cover, patterns: parsed.example_patterns });
    return { card: again.card, asked: asked.length, missing: again.missing, ms: Date.now() - started };
  } catch (e) {
    return {
      card: first.card,
      asked: asked.length,
      missing: first.missing,
      ms: Date.now() - started,
      error: e instanceof Error ? e.message.slice(0, 120) : "failed",
    };
  }
}
