/**
 * **数に上限のある枠を、先に1つ確保する**（`app_config` の一意の鍵で数える）。
 *
 * ゲストの体験（`first-catch-guest.server.ts`）と、全利用者の1日の AI の上限
 * （`ai-provider.server.ts` の `assertWithinDailyCap`）が同じ物を使う。
 *
 * - `app_config` は**サーバ（管理者の鍵）しか書けない**表なので、利用者が枠を
 *   埋めて他の人を止めることはできない（`usage_events` は本人が自分の行を足せる）。
 * - 鍵は `<prefix><番号>`。番号は数えた数から順に試し、一意の制約（23505）で
 *   ぶつかったら次の番号へ — 同時に来ても上限より多くは確保できない。
 * - 値には写真・単語・IP・利用者の番号を入れない。
 *
 * 書き込みの形だけを受ける（試験で偽物を渡せるように）。
 */
export type BudgetDb = {
  from: (table: "app_config") => {
    select: (
      cols: string,
      opts: { count: "exact"; head: true },
    ) => {
      like: (col: string, pattern: string) => PromiseLike<{ count: number | null; error: unknown }>;
    };
    insert: (row: { key: string; value: Record<string, never> }) => PromiseLike<{
      error: { code?: string } | null;
    }>;
    delete: () => {
      like: (
        col: string,
        pattern: string,
      ) => {
        lt: (col: string, value: string) => PromiseLike<{ error: unknown }>;
      };
    };
  };
};

export type BudgetErrors = {
  /** 数えられない・書けない（**閉じる側に倒す**）。 */
  unavailable: string;
  /** 上限に達した。 */
  limit: string;
};

/**
 * 枠を1つ確保して、その番号を返す（0 始まり）。上限なら `errors.limit`、数えられない・
 * 書けないなら `errors.unavailable` を投げる。
 */
export async function reserveBudgetSlot(
  db: BudgetDb,
  prefix: string,
  limit: number,
  errors: BudgetErrors,
): Promise<number> {
  const count = await db
    .from("app_config")
    .select("key", { count: "exact", head: true })
    .like("key", `${prefix}%`);
  if (count.error || count.count == null) throw new Error(errors.unavailable);
  for (let slot = count.count; slot < limit; slot++) {
    const result = await db.from("app_config").insert({ key: `${prefix}${slot}`, value: {} });
    if (!result.error) return slot;
    if (result.error.code !== "23505") throw new Error(errors.unavailable);
  }
  throw new Error(errors.limit);
}

/** 古い枠の行を消すまでの日数。今日と昨日の行は残す。 */
export const BUDGET_KEEP_DAYS = 2;

/**
 * **古い日の枠の行を消す**（`app_config` が日ごとに増え続けないように）。
 * `root` で始まる鍵のうち、`updated_at`（行を作った時刻）が `keepDays` 日より前の物。
 * 失敗しても投げない — 掃除は確保のついでで、確保そのものを止める理由にならない。
 */
export async function pruneBudgetRows(
  db: BudgetDb,
  root: string,
  now: Date = new Date(),
  keepDays: number = BUDGET_KEEP_DAYS,
): Promise<boolean> {
  try {
    const before = new Date(now.getTime() - keepDays * 86_400_000).toISOString();
    const { error } = await db
      .from("app_config")
      .delete()
      .like("key", `${root}%`)
      .lt("updated_at", before);
    if (error) {
      console.warn("[budget] prune failed", root);
      return false;
    }
    return true;
  } catch {
    console.warn("[budget] prune failed", root);
    return false;
  }
}

/** 何回に1回掃除するか（毎回だと書き込みが倍になる）。番号 0（その日の最初）でも掃除する。 */
export const BUDGET_PRUNE_EVERY = 50;

export function shouldPruneAfter(slot: number): boolean {
  return slot % BUDGET_PRUNE_EVERY === 0;
}
