import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { ANALYTICS_RANGES, buildAnalytics, type AnalyticsReport, type AnalyticsUserIn } from "./analytics";
import { AI_PRICES_KEY, normalizePricesConfig, priceFor } from "./ai-costs";
import { readAllPages } from "./pagination";

/**
 * 開発者の「分析」の読み出し（数え方は `analytics.ts`）。管理者だけ（サーバで確かめる）。
 *
 * 返さない物: メールアドレス（試験用の判定にだけ使う）・正確な場所（市と区まで）・写真・本人の書いた文。
 * 読むのは新しいサーバー（iOS 1.0.4 から）だけ。古い Lovable のサーバーの数は混ぜない。
 */
async function requireAdmin(context: { supabase: unknown; userId: string }) {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data, error } = await (context.supabase as any).rpc("has_role", {
    _user_id: context.userId,
    _role: "admin",
  });
  if (error) throw new Error(error.message);
  if (!data) throw new Error("Forbidden: admin role required");
}

const READ = { maxRows: 1_000_000 };

type CatchRow = { user_id: string; created_at: string; location_name: string | null; location_custom: boolean | null };
/** 「数えない」の印を置く表（移行 `20261105120000_analytics_exclusions.sql`）。無い環境では誰も印なし。 */
const EXCLUSIONS = "analytics_exclusions";

const RangeInput = z.object({
  range: z
    .number()
    .int()
    .refine((v) => (ANALYTICS_RANGES as readonly number[]).includes(v))
    .default(30),
});

export const getAdminAnalytics = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => RangeInput.parse(input ?? {}))
  .handler(async ({ context, data }): Promise<AnalyticsReport> => {
    await requireAdmin(context);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const db = supabaseAdmin as any;
    const range = data.range as AnalyticsReport["range"];
    // AI の記録は前の期間の始まりから（品質は今の期間と前の期間しか見ない）。
    const runsSince = new Date(Date.now() - (2 * range + 2) * 86_400_000).toISOString();

    const authUsers: Array<{
      id: string;
      created_at: string;
      email?: string | null;
      is_anonymous?: boolean;
      last_sign_in_at?: string | null;
      app_metadata?: { provider?: string };
    }> = [];
    for (let page = 1; page < 100; page++) {
      const { data: got, error } = await supabaseAdmin.auth.admin.listUsers({ page, perPage: 1000 });
      if (error) throw new Error(error.message);
      authUsers.push(...got.users);
      if (got.users.length < 1000) break;
    }

    const [profiles, roles, stickers, encounters, reviews, events, runs, prices, flagged] = await Promise.all([
      readAllPages<{
        id: string;
        display_name: string | null;
        avatar_url: string | null;
        ui_language: string | null;
        current_level: string | null;
        level_goal: string | null;
        onboarded: boolean | null;
      }>((a, b) =>
        db
          .from("profiles")
          .select("id, display_name, avatar_url, ui_language, current_level, level_goal, onboarded")
          .order("id")
          .range(a, b),
      ),
      db.from("user_roles").select("user_id").eq("role", "admin"),
      readAllPages<CatchRow>(
        (a, b) =>
          db.from("stickers").select("user_id, created_at, location_name, location_custom").order("id").range(a, b),
        READ,
      ),
      readAllPages<CatchRow>(
        (a, b) =>
          db.from("encounters").select("user_id, created_at, location_name, location_custom").order("id").range(a, b),
        READ,
      ),
      readAllPages<{ user_id: string; reviewed_at: string; correct: boolean | null }>(
        (a, b) => db.from("review_history").select("user_id, reviewed_at, correct").order("id").range(a, b),
        READ,
      ),
      readAllPages<{ user_id: string; kind: string; created_at: string }>(
        (a, b) => db.from("usage_events").select("user_id, kind, created_at").order("id").range(a, b),
        READ,
      ),
      readAllPages<{ user_id: string | null; loop: string; created_at: string; meta: unknown }>(
        (a, b) =>
          db
            .from("ai_runs")
            .select("user_id, loop, created_at, meta")
            .in("loop", ["capture_suggest", "card_generate", "candidate_pick", "ai_call"])
            .gte("created_at", runsSince)
            .order("id")
            .range(a, b),
        READ,
      ),
      db.from("app_config").select("value").eq("key", AI_PRICES_KEY).maybeSingle(),
      db.from(EXCLUSIONS).select("user_id"),
    ]);
    for (const [name, r] of Object.entries({ stickers, encounters, reviews, events, runs }))
      if (r.truncated) console.warn(`[getAdminAnalytics] ${name}: 安全の上限で読むのを止めた`);
    if (roles.error) throw new Error(roles.error.message);

    const prof = new Map(profiles.rows.map((p) => [p.id, p]));
    const users: AnalyticsUserIn[] = authUsers.map((u) => {
      const p = prof.get(u.id);
      return {
        id: u.id,
        created_at: u.created_at,
        email: u.email ?? null,
        is_anonymous: !!u.is_anonymous,
        provider: u.app_metadata?.provider ?? null,
        last_sign_in_at: u.last_sign_in_at ?? null,
        display_name: p?.display_name ?? null,
        avatar_url: p?.avatar_url ?? null,
        ui_language: p?.ui_language ?? null,
        current_level: p?.current_level ?? null,
        level_goal: p?.level_goal ?? null,
        onboarded: p?.onboarded ?? null,
      };
    });
    const priceTable = normalizePricesConfig((prices.data as { value?: unknown } | null)?.value ?? null);

    return buildAnalytics({
      now: new Date(),
      range,
      users,
      admins: ((roles.data ?? []) as Array<{ user_id: string }>).map((r) => r.user_id),
      // 表がまだ無い環境（移行の前）は、誰にも印が無いとして続ける。
      flagged: flagged.error ? [] : ((flagged.data ?? []) as Array<{ user_id: string }>).map((r) => r.user_id),
      catches: [
        ...stickers.rows.map((r) => ({ ...r, kind: "new" as const })),
        ...encounters.rows.map((r) => ({ ...r, kind: "again" as const })),
      ],
      reviews: reviews.rows,
      events: events.rows,
      runs: runs.rows,
      costOf: (m) => {
        if (m.ok === false) return 0;
        const model = typeof m.model === "string" ? m.model : null;
        const tin = typeof m.in === "number" ? m.in : 0;
        const tout = typeof m.out === "number" ? m.out : 0;
        if (!model) return null;
        const p = priceFor(model, priceTable);
        return p ? (tin * p.inUsd + tout * p.outUsd) / 1_000_000 : null;
      },
    });
  });

const ExcludeInput = z.object({ userId: z.string().uuid(), excluded: z.boolean() });

/** 開発者が「この人を数えない」（試験用の自分の別アカウントなど）を付け外しする。管理者だけ。 */
export const setAnalyticsExcluded = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => ExcludeInput.parse(input))
  .handler(async ({ context, data }) => {
    await requireAdmin(context);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const db = supabaseAdmin as any;
    const { error } = data.excluded
      ? await db.from(EXCLUSIONS).upsert({ user_id: data.userId, reason: "admin" }, { onConflict: "user_id" })
      : await db.from(EXCLUSIONS).delete().eq("user_id", data.userId);
    if (error) throw new Error(error.message);
    return { ok: true, excluded: data.excluded };
  });
