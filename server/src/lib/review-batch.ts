/**
 * 復習の**束が尽きたとき**に何と言うかを決める。
 *
 * ## なぜ純粋な関数として切り出すか
 * オーナー報告:
 * >「復習の枚数を変更しても、適応されてない。無限にしたのに、
 * >  今日の復習の枚数は終わったとでて復習できない。」
 *
 * 調べたら、**枚数の設定は正しく保存されていた**(本番の profiles は
 * `review_daily_limit: 0` = 無制限)。`getDueReviews` も `0` を無制限として
 * 正しく扱っている。壊れていたのはその先だった:
 *
 * - `getDueReviews` は**1回に最大10枚**しか返さない(体感の軽さのため)。
 * - 画面は `idx >= cards.length` になった瞬間に `DoneState` を出す。
 * - `DoneState` の見出しは「**今日の復習、終わりました**」で固定。
 *
 * つまり **10枚やるたびに、期限切れが何百枚あろうと「今日は終わり」と
 * 言い切っていた。** 上限を無制限にしても10枚で同じ文面が出るので、
 * 「設定が効いていない」としか見えない。
 *
 * 「あと何枚出せるか」は**サーバにしか分からない**(端末は10枚の窓しか
 * 見ていない)。だから判定そのものをここに置いて、
 * `getReviewCapState` が返す数だけを入れる。画面にも server にも
 * 同じ判断を書かない — この作業場で何度も起きている
 * 「片方だけ直る」事故はいつもそこから来ている。
 */

/** `getReviewCapState` が返すもののうち、言い方を決めるのに要る分だけ。 */
export type ReviewBatchState = {
  /** 1日の上限。**0 は無制限**(設定の「無制限」)。 */
  limit: number;
  /** 今日すでに答えた枚数。 */
  doneToday: number;
  /** いま期限が来ていて、**まだ出していない**語の数。 */
  dueRemaining: number;
};

/**
 * - `more`   … まだ出せる語がある。**続けられる**ので「終わり」と言わない。
 * - `capped` … 自分で決めた上限に当たった。上限を上げる導線を出す。
 * - `done`   … 本当に出せる語が無い。ここでだけ祝う。
 */
export type BatchEndKind = "more" | "capped" | "done";

export function batchEndKind(state: ReviewBatchState): BatchEndKind {
  const remaining = Math.max(0, Math.floor(state.dueRemaining));
  // 出せる語が無いなら、上限に当たっていようがいまいが「終わり」。
  // **上限のせいで止まったと言うには「まだ待っている語がある」ことが要る** —
  // ちょうど全部やり終えた人に「上限を上げましょう」と言うと、
  // 上げたのに1枚も出てこない。
  if (remaining === 0) return "done";
  // 0 以下は無制限。ここを `limit > 0` で守らないと、無制限の人が
  // `doneToday >= 0` で必ず capped になる(元の不具合と同じ形)。
  if (state.limit > 0 && state.doneToday >= state.limit) return "capped";
  return "more";
}
