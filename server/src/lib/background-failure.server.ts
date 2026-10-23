import type { BackgroundFailureArea } from "./background-failure";

/**
 * **サーバで動く裏の仕事の失敗を、開発者の記録に残す**（`reportBackgroundFailure` のサーバ版。PR #189 の点検）。
 *
 * `reportBackgroundFailure` は画面から呼ぶ物で、記録の口（`logAppEvent`）は呼んだ人のログインの文脈で動き、
 * エラー記録（Lovable）はブラウザにしか無い。返事を返した後に動くサーバの仕事（古いメインの例文の札 —
 * `example-scene-label.server.ts`）にはそのどちらも無いので、同じ数え方をサーバの側でする:
 * - 利用者ごとの画面（`/admin/users` → その人 → 「裏の処理の失敗」）の回数: `usage_events` に
 *   `bg_failed_<area>` を service role で1行（画面の失敗と同じ種類・同じ数え方）
 * - サーバの記録（Workers のログ）に中身を残す
 *
 * 同じ人・同じ種類は1分に1回だけ数える（画面の版と同じ）。記録の失敗で仕事は止めない。**投げない。**
 */
const lastLogged = new Map<string, number>();
const THROTTLE_MS = 60_000;

export type ServerFailureDeps = {
  insert?: (row: { user_id: string; kind: string }) => Promise<void>;
  now?: () => number;
};

export async function reportServerBackgroundFailure(
  area: BackgroundFailureArea,
  userId: string,
  error: unknown,
  context: Record<string, unknown> = {},
  deps: ServerFailureDeps = {},
): Promise<void> {
  const message = error instanceof Error ? error.message : String(error);
  console.warn(`[background-failure] ${area}`, { ...context, message });
  const now = (deps.now ?? Date.now)();
  const key = `${area}:${userId}`;
  const last = lastLogged.get(key);
  if (last !== undefined && now - last < THROTTLE_MS) return;
  lastLogged.set(key, now);
  try {
    const insert =
      deps.insert ??
      (async (row: { user_id: string; kind: string }) => {
        const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
        const { error: e } = await supabaseAdmin.from("usage_events").insert(row as never);
        if (e) console.warn("[background-failure] could not record", e.message);
      });
    await insert({ user_id: userId, kind: `bg_failed_${area}` });
  } catch (e) {
    console.warn("[background-failure] could not record", e instanceof Error ? e.message : e);
  }
}

/** 試験用。 */
export function resetServerBackgroundFailureForTest(): void {
  lastLogged.clear();
}
