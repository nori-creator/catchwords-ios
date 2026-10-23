/**
 * **1回の費用の目安に使う単価**（米ドル / 100 万トークン、入力・出力）。開発者の「AI の設定」の
 * 速さと正確さの表（`ai-model-stats.ts`）が、呼んだ1回の使った量に掛けて出す。
 *
 * - 公式の料金表で確かめた物だけを書く（確かめた日つき）。載っていないモデルは費用を出さない
 *   （使った量だけ出す）。
 * - **有料枠の単価**。Google の無料枠で動いている間の実際の請求は 0 円（その代わり、無料枠では
 *   送った中身が Google の改善に使われ得る）。
 * - 出力の量には考えた分（reasoning）も入る（各社とも出力として請求する）。
 * - Lovable・OpenRouter の口を通した呼び出しは単価が違うので出さない。
 */
export type ModelPrice = {
  /** `会社:モデル`（`ai-call-log.ts` の記録の形）に当てる。 */
  match: RegExp;
  inUsd: number;
  outUsd: number;
  /** 確かめた所と日付。 */
  source: string;
};

export const AI_MODEL_PRICES: readonly ModelPrice[] = [
  {
    // 2026-10: 入力 $0.30 / 出力 $2.50（画像も入力として数える）。
    match: /^google:gemini-3\.5-flash-lite(?:-[\w.]+)?$/,
    inUsd: 0.3,
    outUsd: 2.5,
    source: "ai.google.dev/gemini-api/docs/pricing (checked 2026-10-11)",
  },
  {
    // 導入価格（2026-12-31 まで）: 入力 $0.75 / 出力 $3.75。2027-01-01 から $1.50 / $7.50。
    match: /^google:gemini-3\.8-flash(?:-preview[\w.-]*)?$/,
    inUsd: 0.75,
    outUsd: 3.75,
    source:
      "ai.google.dev/gemini-api/docs/pricing (checked 2026-10-11, introductory until 2026-12-31)",
  },
  {
    // 送る文が 10 万トークン以下の時の単価（それより長い依頼はこの画面の用途に無い）。
    match: /^anthropic:claude-haiku-5-5(?:-\d{8})?$/,
    inUsd: 0.1,
    outUsd: 0.5,
    source: "Anthropic models overview (checked 2026-10-11)",
  },
  {
    match: /^anthropic:claude-sonnet-5-5(?:-\d{8})?$/,
    inUsd: 2,
    outUsd: 10,
    source: "Anthropic models overview (checked 2026-10-11)",
  },
  {
    match: /^anthropic:claude-opus-5-5(?:-\d{8})?$/,
    inUsd: 4,
    outUsd: 20,
    source: "Anthropic models overview (checked 2026-10-14)",
  },
  {
    match: /^anthropic:claude-fable-5-1(?:-\d{8})?$/,
    inUsd: 10,
    outUsd: 50,
    source: "Anthropic models overview (checked 2026-10-14)",
  },
];

export function priceOf(model: string): ModelPrice | null {
  return AI_MODEL_PRICES.find((p) => p.match.test(model)) ?? null;
}

/** 1回の費用（米ドル）。単価が分からない・量が分からない時は null。 */
export function callCostUsd(
  model: string,
  tokensIn: number | undefined,
  tokensOut: number | undefined,
): number | null {
  const p = priceOf(model);
  if (!p || tokensIn == null || tokensOut == null) return null;
  return (tokensIn * p.inUsd + tokensOut * p.outUsd) / 1_000_000;
}
