/**
 * **「固定の写真で試す」の関所と記録**（口は `ai.functions.ts` の `adminTestPhotoCandidates`、
 * 写真と正解は `ai-test-photos.ts`、数え方は `ai-model-stats.ts` の `computeAiTests`）。
 *
 * - 管理者だけ（`has_role`）。
 * - 1日（直近 24 時間）の試しは `AI_TEST_DAILY_LIMIT` 回まで。試しは利用者の1日の枠を使わない
 *   ので、画面の繰り返しの不具合などで止まらなくなった時の費用の歯止め。
 * - 結果は `ai_runs`（loop = `ai_test`）に1枚1行。中身はモデル・写真の名前・学習言語・成否・
 *   時間・正解の順位・使った量だけ（写真は決まった公開の物で、利用者の物は送らない）。
 */
import type { LanguageModelUsage } from "ai";
import type { Json } from "@/integrations/supabase/types";
import { AI_TEST_LOOP } from "./ai-model-stats";

export const AI_TEST_DAILY_LIMIT = 300;
export const ADMIN_TEST_FORBIDDEN = "Forbidden: 管理者だけが使えます";

type TestClient = {
  rpc: (
    fn: "has_role",
    args: { _user_id: string; _role: "admin" },
  ) => PromiseLike<{ data: unknown; error: { message: string } | null }>;
  from: (table: "ai_runs") => {
    select: (
      cols: string,
      opts: { count: "exact"; head: true },
    ) => {
      eq: (
        col: string,
        v: string,
      ) => {
        eq: (
          col: string,
          v: string,
        ) => {
          gte: (
            col: string,
            v: string,
          ) => PromiseLike<{ count: number | null; error: { message: string } | null }>;
        };
      };
    };
    insert: (row: Record<string, unknown>) => PromiseLike<{ error: { message: string } | null }>;
  };
};

type Ctx = { supabase: unknown; userId: string };

export async function assertAiTestAllowed(ctx: Ctx, now: Date = new Date()): Promise<void> {
  const sb = ctx.supabase as TestClient;
  const { data: isAdmin, error } = await sb.rpc("has_role", {
    _user_id: ctx.userId,
    _role: "admin",
  });
  if (error) throw new Error(error.message);
  if (!isAdmin) throw new Error(ADMIN_TEST_FORBIDDEN);
  const since = new Date(now.getTime() - 86_400_000).toISOString();
  const { count, error: countError } = await sb
    .from("ai_runs")
    .select("id", { count: "exact", head: true })
    .eq("user_id", ctx.userId)
    .eq("loop", AI_TEST_LOOP)
    .gte("created_at", since);
  if (countError) throw new Error(countError.message);
  if ((count ?? 0) >= AI_TEST_DAILY_LIMIT)
    throw new Error(`AI_TEST_DAILY_LIMIT: 試しは1日 ${AI_TEST_DAILY_LIMIT} 枚までです`);
}

export type AiTestRecord = {
  task: "photo_candidates";
  model: string;
  photo: string;
  kind: string;
  lang: string;
  ok: boolean;
  ms: number;
  rank: number | null;
  /** 返ってきた候補の数。 */
  n: number;
  code?: string;
  usage?: LanguageModelUsage;
  /** 呼び方の違い（`thinking-off` = Claude に考えさせない）。無ければ既定の呼び方。 */
  variant?: string;
};

export function aiTestRow(userId: string, r: AiTestRecord) {
  const meta: { [key: string]: Json } = {
    task: r.task,
    model: r.model.slice(0, 160),
    photo: r.photo,
    kind: r.kind,
    lang: r.lang,
    ok: r.ok,
    ms: Math.max(0, Math.round(r.ms)),
    n: r.n,
  };
  if (r.rank != null) meta.rank = r.rank;
  if (r.variant) meta.variant = r.variant.slice(0, 40);
  if (r.code) meta.code = r.code.slice(0, 60);
  const tin = r.usage?.inputTokens;
  const tout = r.usage?.outputTokens;
  const reasoning = r.usage?.outputTokenDetails?.reasoningTokens;
  if (typeof tin === "number") meta.in = tin;
  if (typeof tout === "number") meta.out = tout;
  if (typeof reasoning === "number") meta.reasoning = reasoning;
  return {
    user_id: userId,
    loop: AI_TEST_LOOP,
    iterations: 1,
    accepted: r.ok && r.rank === 1 ? 1 : 0,
    meta,
  };
}

/** 記録の失敗で試しの結果を捨てない（画面には返す）。 */
export async function recordAiTest(ctx: Ctx, r: AiTestRecord): Promise<void> {
  const { error } = await (ctx.supabase as TestClient)
    .from("ai_runs")
    .insert(aiTestRow(ctx.userId, r));
  if (error) console.warn("[ai-test] ai_runs insert failed", error.message);
}
