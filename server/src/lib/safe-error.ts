/**
 * 内部の失敗理由（DB・ストレージのメッセージ）を呼ぶ側へ流さないための小道具。
 *
 * これまでは `throw new Error(error.message)` と書いていたので、Postgres や
 * ストレージの生のメッセージ（表名・列名・制約名・スキーマ）が、そのまま
 * 利用者の画面と通信の中身に出ていた。攻める側にとっては中の地図になる。
 *
 * 詳しい理由はサーバーの記録にだけ残し、呼ぶ側には「何ができなかったか」
 * だけを日本語で返す。
 */
export function internalFailure(scope: string, detail: unknown, userMessage: string): Error {
  const message =
    detail instanceof Error
      ? detail.message
      : typeof detail === "object" && detail !== null && "message" in detail
        ? String((detail as { message: unknown }).message)
        : String(detail);
  console.error(`[${scope}] ${message}`);
  return new Error(userMessage);
}
