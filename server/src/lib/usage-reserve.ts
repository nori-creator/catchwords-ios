/**
 * **その人の AI の回数を、数えると入れるを1回で確保する**（監査 2026-10-03 M1）。
 *
 * 前は「`usage_events` を数える → 1行入れる」の2回だったので、同時に何本も送ると
 * 全部が数える段を通り抜け、上限を超えて AI を呼べた。今は Postgres の関数
 * `reserve_usage_event`（`supabase/migrations/20261003130000_reserve_usage_event.sql`）が、
 * 同じ人・同じ種類を鍵（advisory lock）で1本ずつにして、数えて入れる。
 *
 * **関数がまだ無い（移行を流す前）時だけ**、前の2回のやり方で数える（動きを止めない）。
 * 関数があるのに失敗した時は投げる（**閉じる側に倒す**）。
 *
 * 管理者の鍵（service role）の物だけで呼ぶ。関数は service role にしか開けていない。
 */
export type UsageReserveDb = {
  rpc: (
    fn: "reserve_usage_event",
    args: { p_user_id: string; p_kind: string; p_limit: number; p_since: string },
  ) => PromiseLike<{ data: unknown; error: { code?: string; message?: string } | null }>;
  from: (table: "usage_events") => {
    select: (
      cols: string,
      opts: { count: "exact"; head: true },
    ) => {
      eq: (
        col: string,
        value: string,
      ) => {
        eq: (
          col: string,
          value: string,
        ) => {
          gte: (
            col: string,
            value: string,
          ) => PromiseLike<{ count: number | null; error: { message?: string } | null }>;
        };
      };
    };
    insert: (row: { user_id: string; kind: string }) => {
      select: (cols: string) => {
        single: () => PromiseLike<{
          data: { id: number } | null;
          error: { message?: string } | null;
        }>;
      };
    };
  };
};

/** 関数がまだ作られていない時の返事か（PostgREST の PGRST202 / Postgres の 42883）。 */
export function isMissingRpc(error: { code?: string; message?: string } | null): boolean {
  if (!error) return false;
  return (
    error.code === "PGRST202" ||
    error.code === "42883" ||
    /could not find the function/i.test(error.message ?? "")
  );
}

/**
 * 上限の内側なら1行入れてその番号を返す。上限なら `null`。数えられない・入れられない時は投げる。
 */
export async function reserveUsageRow(
  db: UsageReserveDb,
  userId: string,
  kind: string,
  limit: number,
  sinceIso: string,
): Promise<number | null> {
  const rpc = await db.rpc("reserve_usage_event", {
    p_user_id: userId,
    p_kind: kind,
    p_limit: limit,
    p_since: sinceIso,
  });
  if (!rpc.error) {
    if (rpc.data == null) return null;
    const id = Number(rpc.data);
    if (!Number.isFinite(id)) throw new Error("reserve_usage_event returned no id");
    return id;
  }
  if (!isMissingRpc(rpc.error)) throw new Error(rpc.error.message ?? "reserve_usage_event failed");

  // 移行を流すまでの間だけ: 前の2回のやり方（同時に来ると少し超えうる）。
  warnMissingOnce();
  const count = await db
    .from("usage_events")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("kind", kind)
    .gte("created_at", sinceIso);
  if (count.error || count.count == null) throw new Error(count.error?.message ?? "no count");
  if (count.count >= limit) return null;
  const inserted = await db
    .from("usage_events")
    .insert({ user_id: userId, kind })
    .select("id")
    .single();
  if (inserted.error || !inserted.data) throw new Error(inserted.error?.message ?? "no row");
  return inserted.data.id;
}

let warnedMissing = false;
function warnMissingOnce() {
  if (warnedMissing) return;
  warnedMissing = true;
  console.warn(
    "[usage] reserve_usage_event is missing — apply supabase/migrations/20261003130000_reserve_usage_event.sql",
  );
}
