/**
 * **AI の速さと正確さの表の読み出し**（数え方は `ai-model-stats.ts`、口は `admin-ai.functions.ts` の
 * `adminGetAiStats`）。管理者だけ。
 *
 * 読む物: `ai_runs` の決まった loop（`AI_STATS_LOOPS`）の持ち主・種類・時刻・`meta` だけ。
 * どの loop の `meta` にも語・写真・文は入っていない（`ai_call` は機能・用途・モデル・時間・量、
 * `candidate_pick` は順位と数、ほかは各回の結果）。返すのは数だけ — 誰の行かは返さない。
 * `ai_runs` は本人の行しか読めない（RLS）ので、管理者と確かめてからサーバの鍵で読む。
 *
 * 「全員」の時は、登録前の人のチュートリアルの結果（`app_config` の `first-catch-run:` の行、
 * 中身は機能・成否・時間・試した AI の名前だけ）も読む。`ai_runs` に行を持てないため。
 *
 * 上限で切る時に**新しい行を残す**よう、新しい順に読む（数え方は並びに頼らない）。
 */
import { readAllPages } from "./pagination";
import {
  AI_STATS_DAYS,
  AI_STATS_LOOPS,
  computeAiModelStats,
  GUEST_FIRST_CATCH_LOOP,
  type AiModelStatsReport,
  type AiStatsDays,
  type AiStatsRow,
} from "./ai-model-stats";
import { GUEST_RUN_ROOT } from "./first-catch-guest.server";

/** 読む行の上限（30 日・全員でも足りる量。超えたら `truncated`）。 */
const MAX_ROWS = 60_000;
/** 登録前の人のチュートリアルの行の上限（全体の枠が 1 日 1000 回 × 残すのは 14 日）。 */
const MAX_GUEST_ROWS = 20_000;

/**
 * `first-catch-run:<日付>:<ok|fail>:<id>` の行を、表の行の形に。鍵の形が違う行・期間の外の行は
 * 捨てる。時刻は書いた時刻（`updated_at`、無ければ鍵の日付）。
 */
export function guestRunRows(
  rows: Array<{ key: string; value: unknown; updated_at?: string | null }>,
  since: string,
): AiStatsRow[] {
  const out: AiStatsRow[] = [];
  for (const r of rows) {
    const m = /^first-catch-run:(\d{4}-\d{2}-\d{2}):(?:ok|fail):/.exec(r.key);
    if (!m) continue;
    const created_at = r.updated_at || `${m[1]}T00:00:00.000Z`;
    if (created_at < since) continue;
    out.push({ user_id: "", loop: GUEST_FIRST_CATCH_LOOP, created_at, meta: r.value });
  }
  return out;
}

export type AiStatsInput = { days: AiStatsDays; mine: boolean };

export function parseAiStatsInput(raw: unknown): AiStatsInput {
  const v = (raw ?? {}) as { days?: unknown; mine?: unknown };
  const days = (AI_STATS_DAYS as readonly number[]).includes(Number(v.days))
    ? (Number(v.days) as AiStatsDays)
    : 7;
  return { days, mine: v.mine === true };
}

type RoleClient = {
  rpc: (
    fn: "has_role",
    args: { _user_id: string; _role: "admin" },
  ) => PromiseLike<{ data: unknown; error: { message: string } | null }>;
};

export async function loadAiModelStats(
  context: { supabase: unknown; userId: string },
  input: AiStatsInput,
  now: Date = new Date(),
): Promise<{ isAdmin: false } | ({ isAdmin: true; truncated: boolean } & AiModelStatsReport)> {
  const { data: isAdmin, error } = await (context.supabase as RoleClient).rpc("has_role", {
    _user_id: context.userId,
    _role: "admin",
  });
  if (error) throw new Error(error.message);
  if (!isAdmin) return { isAdmin: false };

  const since = new Date(now.getTime() - input.days * 86_400_000).toISOString();
  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
  const [runs, guests] = await Promise.all([
    readAllPages<AiStatsRow>(
      (a, b) => {
        let q = supabaseAdmin
          .from("ai_runs")
          .select("user_id, loop, created_at, meta")
          .in("loop", [...AI_STATS_LOOPS])
          .gte("created_at", since);
        if (input.mine) q = q.eq("user_id", context.userId);
        return q
          .order("created_at", { ascending: false })
          .order("id", { ascending: false })
          .range(a, b);
      },
      { maxRows: MAX_ROWS },
    ),
    input.mine
      ? Promise.resolve({ rows: [], truncated: false })
      : readAllPages<{ key: string; value: unknown; updated_at: string }>(
          (a, b) =>
            supabaseAdmin
              .from("app_config")
              .select("key, value, updated_at")
              .like("key", `${GUEST_RUN_ROOT}%`)
              .gte("key", `${GUEST_RUN_ROOT}${since.slice(0, 10)}`)
              .order("key", { ascending: false })
              .range(a, b),
          { maxRows: MAX_GUEST_ROWS },
        ),
  ]);
  const truncated = runs.truncated || guests.truncated;
  if (truncated)
    console.warn(
      `[ai-stats] read capped (${input.days} days): ai_runs ${runs.truncated}, guest ${guests.truncated}`,
    );
  const rows = [...runs.rows, ...guestRunRows(guests.rows, since)];
  return {
    isAdmin: true,
    truncated,
    ...computeAiModelStats(rows, { days: input.days, mine: input.mine, since }),
  };
}
