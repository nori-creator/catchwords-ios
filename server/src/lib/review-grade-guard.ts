/**
 * もう採点済みの札か（2026-10-01「同じ答えが2回届くと進捗が2回進む」）。
 *
 * 復習に出す札は期限が来た物だけ（`getDueReviews` の `due_at <= 今`）。採点すると期限が
 * 先へ動くので、期限がまだ先の札への採点は「もう採点済み」— 通信のやり直し・二重送信・
 * 別の端末で先に済ませた札。期限の無い札は採点できる。数秒の時計のずれで、いま期限が
 * 来た札を弾かないよう1分の余裕を見る。
 */
export function isAlreadyGraded(dueAt: string | null | undefined, nowMs: number): boolean {
  if (!dueAt) return false;
  const due = new Date(dueAt).getTime();
  return Number.isFinite(due) && due > nowMs + 60_000;
}

/**
 * 採点を保存できなかった**理由**（日本語）。iOS は自分の文「採点を保存できませんでした。もう一度答えてください。」の
 * 次の行にこれを出す（日本語の画面だけ。ほかの言語では iOS の「サーバーエラー（503）」）ので、同じことを繰り返さない。
 */
export const GRADE_SAVE_FAILED_MESSAGE =
  "一時的に保存先（データベース）につながりませんでした。少し待つと直ります。";

/**
 * **採点を保存できなかった**（DB に届かない・書けない。2026-10-15）。`native-fn.ts` の `statusForError` が
 * **503** にする — 前は PostgREST の英語の失敗をそのまま投げて 500 になり、iOS は「サーバーエラー（500）」としか
 * 出せなかった。もう一度答えれば保存される種類の失敗（iOS は札を回の最後に戻す）。中身の理由はサーバの記録に残す。
 */
export class GradeSaveError extends Error {
  override name = "ServiceUnavailableError";
  constructor(message: string = GRADE_SAVE_FAILED_MESSAGE) {
    super(message);
  }
}

/** `review_history.response_ms` は integer。開いたまま放っておいた札（何日も）で記録が落ちないよう頭を打つ。 */
export const MAX_RESPONSE_MS = 2_147_483_647;
