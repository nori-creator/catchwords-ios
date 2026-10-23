import { generateText } from "ai";
import type { UsageChunk } from "./extras";
import { getAiFor, parseJsonFromAiText } from "./ai-provider.server";
import { normalizeTargetLanguage } from "./target-lang";

/**
 * **チャンクを別の AI にもう一度見せる口（既定では閉じている）**（2026-10-15）。
 *
 * オーナーは 2026-10-14 に「別の AI で点検し直す呼び出しは置かない。カードの表示が遅くなる」と決めている。
 * 一方で 2026-10-15 の「チャンクのミスが多すぎる」を受けて、**1秒以内に収まるなら**という条件で
 * 安い点検を測った（`AI_CHUNK_VERIFY` 環境変数）:
 *
 * - `off`（既定）… 呼ばない。指示文の直しと `chunk-quality.ts` の門だけ。
 * - `inline` … カードを返す前に、いちばん速いモデル（Flash-Lite）に型だけを見せて true/false を答えさせる。
 *   **締め切り 1 秒**（`CHUNK_VERIFY_BUDGET_MS`）。間に合わなければ・失敗すれば門の結果をそのまま返す
 *   （点検で遅くなることはあっても、点検で壊れることは無い）。
 *
 * 実測（本番 `ai_runs`、2026-10 の 21 日間）: Flash-Lite の文字だけの呼び出しは、候補の語（出力 136 トークン）で
 * 中央値 1.1 秒・9割 1.4 秒、画像の意味（出力 76 トークン）で 1.0 秒・1.3 秒。型の点検は出力が 20 トークン
 * ほどなので 0.8〜1.2 秒の見込みで、**1 秒の予算をはみ出す回が半分近くある**。だから既定は `off` にし、
 * 開発者が試す時だけ `inline` にする（はみ出した回は門の結果のまま返すので、体感は最大 +1 秒）。
 */
export { chunkVerifyMode, type ChunkVerifyMode } from "./chunk-quality";

export const CHUNK_VERIFY_BUDGET_MS = 1000;

export type ChunkVerifyOutcome = {
  kept: UsageChunk[];
  dropped: number;
  ms: number;
  /** 締め切りに間に合わなかった・失敗した（門の結果をそのまま返した）。 */
  skipped: boolean;
};

/** 答えの形: 型ごとの true/false の配列。長さが合わなければ使わない。 */
export function readVerifyAnswer(raw: unknown, count: number): boolean[] | null {
  const ok = (raw as { ok?: unknown } | null)?.ok;
  if (!Array.isArray(ok) || ok.length !== count) return null;
  return ok.map((v) => v === true || (typeof v === "string" && /^(true|yes|ok)$/i.test(v)));
}

export function chunkVerifyPrompt(
  chunks: ReadonlyArray<UsageChunk>,
  ctx: { headword: string; meaning: string; language: string | null | undefined },
): string {
  const sep = normalizeTargetLanguage(ctx.language) === "en" ? " " : "＋";
  const lines = chunks
    .map((c, i) => `${i + 1}. ${c.parts.map((p) => p.text).join(sep)}${c.ja ? ` — ${c.ja}` : ""}`)
    .join("\n");
  return (
    `語「${ctx.headword}」（意味: ${ctx.meaning}）の「使い方の型」です。ネイティブがその語を**この意味の物として**、` +
    `そのまま口にする自然な句だけ true。別の物の動作に当てた物（刷子 に 刷牙）・語順が崩れた物・ネイティブが言わない物は false。\n` +
    `${lines}\n出力はJSONだけ: {"ok":[true,false,...]}（${chunks.length}個、順番どおり）`
  );
}

/**
 * 締め切りつきで点検する。**失敗しても投げない**（門の結果をそのまま返す）。
 */
export async function verifyChunksInline(
  chunks: ReadonlyArray<UsageChunk>,
  ctx: { headword: string; meaning: string; language: string | null | undefined },
  budgetMs = CHUNK_VERIFY_BUDGET_MS,
): Promise<ChunkVerifyOutcome> {
  const started = Date.now();
  const skip = (): ChunkVerifyOutcome => ({
    kept: [...chunks],
    dropped: 0,
    ms: Date.now() - started,
    skipped: true,
  });
  if (chunks.length === 0) return { ...skip(), skipped: false };
  try {
    const ai = await getAiFor("card", "chunk_verify");
    const result = await generateText({
      model: ai.gateway(ai.modelFast),
      prompt: chunkVerifyPrompt(chunks, ctx),
      abortSignal: AbortSignal.timeout(budgetMs),
      maxRetries: 0,
    });
    const answer = readVerifyAnswer(parseJsonFromAiText(result.text), chunks.length);
    if (!answer) return skip();
    const kept = chunks.filter((_, i) => answer[i]);
    return { kept, dropped: chunks.length - kept.length, ms: Date.now() - started, skipped: false };
  } catch (e) {
    console.info("chunk-verify: skipped", (e as Error)?.name ?? String(e));
    return skip();
  }
}
