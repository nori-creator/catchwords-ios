import { createServerFn } from "@tanstack/react-start";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { z } from "zod";
import { taipeiDay } from "./taipei-day";
import { readAllPages } from "./pagination";
import {
  FUNNEL_LATENCY_LOOP,
  LATENCY_EVENTS,
  MAX_FUNNEL_LATENCY_MS,
  MEMBER_FUNNEL_EVENTS,
} from "./funnel-events";

function dayKey(iso: string): string {
  return taipeiDay(iso);
}

/**
 * KPI events (roadmap §2/§3): funnel markers recorded into the existing
 * usage_events table — no new tables. The client dedupes (localStorage);
 * the server just accepts a whitelisted kind.
 */

export const APP_EVENTS = [
  "app_open",
  "onboarding_done",
  "first_scan",
  "first_catch",
  // 滞在時間と、離れる直前の画面（開発者だけの利用者ごとの画面で使う、`admin-user-stats.ts`）。
  "session_start",
  "session_end",
  "leave_home",
  "leave_dex",
  "leave_capture",
  "leave_scan",
  "leave_review",
  "leave_settings",
  "leave_other",
  // 保存の失敗（オーナー報告 2026-09-30「画像が保存されなかった。開発者の記録にも
  // 残っていない」）。利用者ごとの画面の「保存の失敗」に数が出る（`save-failure.ts`）。
  "save_failed_catch",
  "save_failed_reencounter",
  "save_failed_first_transfer",
  // 裏の処理の失敗（`background-failure.ts`。記録は 2026-10-01 から）。
  "bg_failed_tts",
  "bg_failed_photo_upload",
  "bg_failed_thumb_upload",
  "bg_failed_review_grade",
  "bg_failed_reader_meaning",
  "bg_failed_reader_explain",
  "bg_failed_first_catch_ai",
  "bg_failed_sticker_storage",
  "bg_failed_scene_label",
  // ベータの計測（2026-10-03、ロードマップ Phase 9.4）: 撮る・復習・課金の段
  // （`funnel-events.ts`）。種類と時刻だけで、写真・語・答えは送らない。
  ...MEMBER_FUNNEL_EVENTS,
] as const;
export type AppEventKind = (typeof APP_EVENTS)[number];

/**
 * 受け取る形。`ms`（待ち時間）は `LATENCY_EVENTS` の段だけが付けられる
 * （`candidates_shown` = シャッターから候補が並ぶまで）。
 */
export const AppEventInput = z
  .object({
    kind: z.enum(APP_EVENTS),
    ms: z.number().int().min(0).max(MAX_FUNNEL_LATENCY_MS).optional(),
  })
  .refine(
    (v) => v.ms === undefined || (LATENCY_EVENTS as readonly string[]).includes(v.kind),
    "ms is only accepted for latency events",
  );

export const logAppEvent = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => AppEventInput.parse(input))
  .handler(async ({ context, data }) => {
    const { supabase, userId } = context;
    await supabase.from("usage_events").insert({ user_id: userId, kind: data.kind });
    // 待ち時間は `usage_events` に列が無いので、本人の `ai_runs` に1行（表を足さない）。
    // 中身は段の名前と ms だけ。
    if (data.ms !== undefined)
      await supabase.from("ai_runs").insert({
        user_id: userId,
        loop: FUNNEL_LATENCY_LOOP,
        iterations: 0,
        accepted: 0,
        meta: { event: data.kind, ms: data.ms },
      });
    return { ok: true };
  });

/**
 * §7: median scan latencies over the caller's last 20 measured events,
 * shown in the settings developer panel against the spec targets
 * (detect ≤2.5s, tap→audio ≤1.0s).
 */
export const getMyScanMetrics = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const { supabase, userId } = context;
    const median = (xs: number[]): number | null => {
      if (xs.length === 0) return null;
      const s = [...xs].sort((a, b) => a - b);
      const m = Math.floor(s.length / 2);
      return s.length % 2 ? s[m] : Math.round((s[m - 1] + s[m]) / 2);
    };

    const { data: detectRows, error } = await supabase
      .from("scan_events")
      .select("detect_ms, tap_to_audio_ms, created_at")
      .eq("user_id", userId)
      .not("detect_ms", "is", null)
      .order("created_at", { ascending: false })
      .limit(60);
    if (error) {
      // Column not migrated yet — report empty rather than erroring settings.
      return { detect_ms_median: null, tap_to_audio_ms_median: null, samples: 0 };
    }
    // One scan inserts one row per detected item; collapse near-identical
    // detect_ms values (same scan) by taking distinct values in order.
    const detects: number[] = [];
    const audios: number[] = [];
    for (const r of detectRows ?? []) {
      if (
        typeof r.detect_ms === "number" &&
        (detects.length === 0 || detects[detects.length - 1] !== r.detect_ms)
      ) {
        detects.push(r.detect_ms);
      }
      if (typeof r.tap_to_audio_ms === "number") audios.push(r.tap_to_audio_ms);
    }
    return {
      detect_ms_median: median(detects.slice(0, 20)),
      tap_to_audio_ms_median: median(audios.slice(0, 20)),
      samples: Math.min(20, detects.length),
    };
  });

// --- Admin KPI dashboard (roadmap §3) ---------------------------------------

export type AdminDashboard = {
  days: Array<{
    day: string;
    scans: number;
    taps: number;
    catches: number;
    active_users: number;
    reviews: number;
  }>;
  funnel: {
    users_total: number;
    users_onboarded: number;
    users_first_scan: number;
    users_first_catch: number;
    d1_retention_pct: number | null;
  };
};

export const getAdminDashboard = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }): Promise<AdminDashboard> => {
    const { data: isAdmin, error: roleErr } = await context.supabase.rpc("has_role", {
      _user_id: context.userId,
      _role: "admin",
    });
    if (roleErr) throw new Error(roleErr.message);
    if (!isAdmin) throw new Error("Forbidden: admin role required");

    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const since = new Date(Date.now() - 14 * 86400 * 1000).toISOString();

    // `.limit(20000)` と書いても PostgREST は 1000 行で切る（2026-10-03 監査）。14日の数も
    // 漏斗の人数も黙って少なくなっていたので、全部 `readAllPages` で 1000 行ずつ読む。
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const db = supabaseAdmin as any;
    const big = { maxRows: 1_000_000 };
    const [usageRes, scanRes, stickerRes, profileCountRes, kpiRes] = await Promise.all([
      readAllPages<{ kind: string; user_id: string; created_at: string }>(
        (a, b) =>
          db
            .from("usage_events")
            .select("kind, user_id, created_at")
            .gte("created_at", since)
            .order("id")
            .range(a, b),
        big,
      ),
      readAllPages<{ created_at: string; tapped: boolean }>(
        (a, b) =>
          db
            .from("scan_events")
            .select("created_at, tapped")
            .gte("created_at", since)
            .order("id")
            .range(a, b),
        big,
      ),
      readAllPages<{ created_at: string }>(
        (a, b) =>
          db.from("stickers").select("created_at").gte("created_at", since).order("id").range(a, b),
        big,
      ),
      supabaseAdmin.from("profiles").select("id", { count: "exact", head: true }),
      readAllPages<{ kind: string; user_id: string; created_at: string }>(
        (a, b) =>
          db
            .from("usage_events")
            .select("kind, user_id, created_at")
            .in("kind", ["app_open", "onboarding_done", "first_scan", "first_catch"])
            .order("id")
            .range(a, b),
        big,
      ),
    ]);
    for (const [name, r] of Object.entries({ usageRes, scanRes, stickerRes, kpiRes }))
      if (r.truncated) console.warn(`[getAdminDashboard] ${name}: 安全の上限で読むのを止めた`);

    const byDay = new Map<
      string,
      { scans: number; taps: number; catches: number; users: Set<string>; reviews: number }
    >();
    const bucket = (day: string) => {
      if (!byDay.has(day))
        byDay.set(day, { scans: 0, taps: 0, catches: 0, users: new Set(), reviews: 0 });
      return byDay.get(day)!;
    };
    for (const e of usageRes.rows) {
      const b = bucket(dayKey(e.created_at));
      if (e.kind === "scan_detect") b.scans += 1;
      if (e.kind === "app_open") b.users.add(e.user_id);
      if (e.kind === "speaking_feedback") b.reviews += 1;
    }
    for (const e of scanRes.rows) {
      if (e.tapped) bucket(dayKey(e.created_at)).taps += 1;
    }
    for (const e of stickerRes.rows) {
      bucket(dayKey(e.created_at)).catches += 1;
    }

    const days = [...byDay.entries()]
      .sort((a, b) => (a[0] < b[0] ? 1 : -1))
      .slice(0, 14)
      .map(([day, v]) => ({
        day,
        scans: v.scans,
        taps: v.taps,
        catches: v.catches,
        active_users: v.users.size,
        reviews: v.reviews,
      }));

    // Funnel: distinct users per KPI marker + naive D1 (first open → opened next day).
    const usersBy = (kind: string) =>
      new Set(kpiRes.rows.filter((e) => e.kind === kind).map((e) => e.user_id));
    const opensByUser = new Map<string, Set<string>>();
    for (const e of kpiRes.rows) {
      if (e.kind !== "app_open") continue;
      if (!opensByUser.has(e.user_id)) opensByUser.set(e.user_id, new Set());
      opensByUser.get(e.user_id)!.add(dayKey(e.created_at));
    }
    let d1Yes = 0;
    let d1Eligible = 0;
    const today = dayKey(new Date().toISOString());
    for (const daysSet of opensByUser.values()) {
      const first = [...daysSet].sort()[0];
      if (!first || first === today) continue; // day-1 not observable yet
      d1Eligible += 1;
      const next = new Date(`${first}T12:00:00+08:00`);
      next.setDate(next.getDate() + 1);
      if (daysSet.has(taipeiDay(next))) d1Yes += 1;
    }

    return {
      days,
      funnel: {
        users_total: profileCountRes.count ?? 0,
        users_onboarded: usersBy("onboarding_done").size,
        users_first_scan: usersBy("first_scan").size,
        users_first_catch: usersBy("first_catch").size,
        d1_retention_pct: d1Eligible > 0 ? Math.round((100 * d1Yes) / d1Eligible) : null,
      },
    };
  });
