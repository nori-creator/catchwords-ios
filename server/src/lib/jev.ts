/**
 * **TypeSafe Jev**（2026-09-15 公開の「判断だけをする」モデル）の型と、
 * 外の世界に触れない計算。通信は `jev.server.ts`。
 *
 * ## Jev とは
 * 文章を作るAIではない。**状態（テキストや JSON）と、選択肢の決まった
 * 問い**を渡すと、各問いに**確率つきの答え**を返す。問いの形は3つ:
 *
 *   - `noul`   … はい／いいえ。「はい」の確率 0〜1 が返る
 *   - `choice` … 名前つきの選択肢から1つ。選択肢ごとの確率が返る
 *   - `score`  … 0 から始まる段階の尺度。期待値（間の値もとる）と
 *                段階ごとの確率が返る
 *
 * 複数の問いを**1回の呼び出しで並べて**聞ける。
 *
 * ## 仕様の出どころ（推測で書いていない）
 * 公式の JavaScript SDK `@typesafe-ai/sdk` 0.6.0（npm、保守者は
 * `@typesafe.ai` の2名。創業者 Diogo Almeida を含む）の型定義と実装から
 * 写した。依存を増やさないため（`package-lock.json` を触らない）、SDK は
 * 入れずに同じ HTTP を `fetch` で送る:
 *
 *   POST https://api.typesafe.ai/v1/systemone
 *   Authorization: Bearer <TYPESAFE_API_KEY>
 *   { "model": "jev-latest", "state": …, "questions": { "<名前>": { … } } }
 *
 * ## 使い方の約束（`ARCHITECTURE.md` / `PRODUCT.md`）
 * - **落ちても機能は止めない。** 呼ぶ側は必ず従来の処理に戻れること
 *   （公開から日の浅い early-access の製品で、判断そのものも誤りうる —
 *   TypeSafe 自身がそう書いている）。
 * - **記憶の予定（いつ復習するか）は動かさない。** 記憶の確率は
 *   「影の実行」— 予測を記録して実際の正誤と突き合わせるだけ
 *   （`PRODUCT.md`「test experimental predictors/models such as Jev in
 *   shadow mode before allowing them to control scheduling」）。
 */

/** 文字、JSON、または `null`。状態・問い・説明に使える形。 */
export type JevEntry = string | number | boolean | null | JevEntry[] | { [k: string]: JevEntry };

export type JevNoulQuestion = {
  type: "noul";
  instructions?: JevEntry;
  criteria?: { true?: JevEntry; false?: JevEntry } | null;
};
export type JevChoiceQuestion = {
  type: "choice";
  instructions?: JevEntry;
  /** 選択肢の名前 → その説明（`null` なら説明なし）。 */
  criteria: Record<string, JevEntry>;
};
export type JevScoreQuestion = {
  type: "score";
  instructions?: JevEntry;
  /** 0 から始まる段階の説明。**2つ以上。** */
  criteria: JevEntry[];
};
export type JevQuestion = JevNoulQuestion | JevChoiceQuestion | JevScoreQuestion;

export type JevNoulAnswer = { type: "noul"; noul: number };
export type JevChoiceAnswer = {
  type: "choice";
  choice: string;
  confidence: number;
  probabilities: Record<string, number>;
};
export type JevScoreAnswer = {
  type: "score";
  score: number;
  confidence: number;
  probabilities: Record<string, number>;
};
export type JevAnswer = JevNoulAnswer | JevChoiceAnswer | JevScoreAnswer;

export type JevResult = {
  model: string;
  answers: Record<string, JevAnswer>;
  usage?: { input_tokens: number; output_tokens: number };
};

/** 問いの作り方。SDK の `noul()` / `choice()` / `score()` と同じ形。 */
export const noul = (
  instructions: JevEntry,
  criteria?: JevNoulQuestion["criteria"],
): JevNoulQuestion => ({ type: "noul", instructions, ...(criteria ? { criteria } : {}) });

export const choice = (
  instructions: JevEntry,
  criteria: Record<string, JevEntry>,
): JevChoiceQuestion => ({ type: "choice", instructions, criteria });

export const score = (instructions: JevEntry, criteria: JevEntry[]): JevScoreQuestion => {
  if (criteria.length < 2) throw new Error("Jev の score には段階が2つ以上要る");
  return { type: "score", instructions, criteria };
};

const isProb = (v: unknown): v is number =>
  typeof v === "number" && Number.isFinite(v) && v >= 0 && v <= 1;

/**
 * 返ってきた答えを**確かめてから**使う形に直す。形が違う答えは捨てる
 * （捨てた問いは「答えが無い」として呼ぶ側が従来の処理に戻る）。
 *
 * 相手は公開から日の浅い API で、形が変わることもありうる。型だけ信じて
 * 読むと、`undefined` の確率で並べ替えて**黙って順番が壊れる**。
 */
export function parseJevAnswers(raw: unknown): Record<string, JevAnswer> {
  const out: Record<string, JevAnswer> = {};
  const answers = (raw as { answers?: unknown } | null)?.answers;
  if (!answers || typeof answers !== "object") return out;
  for (const [name, a] of Object.entries(answers as Record<string, unknown>)) {
    const v = a as Record<string, unknown> | null;
    if (!v || typeof v !== "object") continue;
    if (v.type === "noul" && isProb(v.noul)) {
      out[name] = { type: "noul", noul: v.noul };
    } else if (
      (v.type === "choice" || v.type === "score") &&
      v.probabilities &&
      typeof v.probabilities === "object"
    ) {
      const probs: Record<string, number> = {};
      for (const [k, p] of Object.entries(v.probabilities as Record<string, unknown>)) {
        if (isProb(p)) probs[k] = p;
      }
      if (Object.keys(probs).length === 0) continue;
      const conf = isProb(v.confidence) ? v.confidence : 0;
      if (v.type === "choice" && typeof v.choice === "string" && v.choice in probs) {
        out[name] = { type: "choice", choice: v.choice, confidence: conf, probabilities: probs };
      } else if (v.type === "score" && typeof v.score === "number" && Number.isFinite(v.score)) {
        out[name] = { type: "score", score: v.score, confidence: conf, probabilities: probs };
      }
    }
  }
  return out;
}

/** 選択肢の確率を取り出す（答えが無ければ `null`）。 */
export function choiceProb(a: JevAnswer | undefined, label: string): number | null {
  if (!a || a.type !== "choice") return null;
  const p = a.probabilities[label];
  return isProb(p) ? p : null;
}
