import { logAppEvent } from "@/lib/metrics.functions";
import { reportLovableError } from "@/lib/lovable-error-reporting";

/**
 * **裏で動く処理の失敗を、開発者の記録に残す**（2026-10-01）。
 *
 * 発音（TTS）・写真の上げ直し・復習の採点は、失敗しても画面を止めない作りになっている
 * （端末の声に落ちる・切り抜きなしで保存する・次の札へ進む）。それ自体は正しいが、
 * 失敗を `catch {}` で捨てていたので、**利用者にも管理画面にも何も見えなかった**。
 * `save-failure.ts` と同じ2か所に残す:
 * - 利用者ごとの画面（`/admin/users` → その人 → 「裏の処理の失敗」）の回数。`usage_events`。
 * - Lovable のエラー記録（中身・どこで落ちたか）。
 *
 * 同じ種類は1分に1回だけ数える（音が出ない語を続けて押すと、押した数だけ行が増えるため）。
 * 記録の通信が落ちても利用者は止めない。
 */
export type BackgroundFailureArea =
  | "tts"
  | "photo_upload"
  | "thumb_upload"
  | "review_grade"
  // 読む人の言語の意味・解説を裏で作る（2026-10-02。図鑑と復習。失敗しても意味が出ないだけ）。
  | "reader_meaning"
  | "reader_explain"
  // チュートリアルの写真の分析・カード（2026-10-03。画面は「もう一度試す」を出す）。
  | "first_catch_ai"
  // 札を消した後の写真の掃除（2026-10-03。札は消えている。写真が残るだけ）。
  | "sticker_storage"
  // 古いメインの例文に札を付ける裏の仕事（2026-10-16。サーバで動く — `background-failure.server.ts`）。
  | "scene_label";

const lastLogged = new Map<BackgroundFailureArea, number>();
const THROTTLE_MS = 60_000;

export function reportBackgroundFailure(
  area: BackgroundFailureArea,
  error: unknown,
  context: Record<string, unknown> = {},
): void {
  try {
    reportLovableError(error, { boundary: "background_failure", where: area, ...context });
  } catch {
    // 記録のための処理で利用者を止めない
  }
  const now = Date.now();
  const last = lastLogged.get(area) ?? 0;
  if (now - last < THROTTLE_MS) return;
  lastLogged.set(area, now);
  void logAppEvent({ data: { kind: `bg_failed_${area}` } }).catch(() => {});
}

/** 試験用。 */
export function resetBackgroundFailureForTest(): void {
  lastLogged.clear();
}
