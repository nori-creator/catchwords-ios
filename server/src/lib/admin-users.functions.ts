import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import {
  aiCostEstimate,
  dailyActivity,
  dailyCounts,
  dueSchedule,
  latestIso,
  median,
  memoryLevelCounts,
  percentileRank,
  retention,
  sessionLengthBuckets,
  sessionMinutes,
  sessionSpans,
  streaks,
  weekdayCounts,
  weeklyReviews,
} from "@/lib/admin-user-stats";
import { taipeiDay } from "./taipei-day";
import { readAllPages } from "./pagination";

/**
 * **開発者だけ: 利用者ごとの詳しい情報**（オーナー指示 2026-09-27）。
 *
 * ## 見せる物・見せない物（法律とセキュリティの線）
 * 見せる: 設定、撮った数と日時、市区町村までの場所の名前、続けた日、スキャンから
 * 図鑑に入れるまでの速さ、復習の数と正答、滞在時間、離れる直前の画面、切り抜きと
 * 作り直しの回数、AI の呼び出し回数と費用の概算。
 * **見せない**: メールアドレス、正確な緯度経度、写真そのもの、日記や一言の本文
 * （本人の書いた文章）。サービスの改善に要らず、漏れた時の害が大きいため
 * （個人情報保護法の「利用目的の範囲」と「必要最小限」の考え方）。
 *
 * 呼べるのは `admin` の役を持つ人だけ（サーバで確かめる。画面の出し分けには頼らない）。
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

const dayKey = (iso: string) => taipeiDay(iso);

/**
 * 開発者の画面の読み込みの安全の上限（行）。ここまでは全部読む。超えたら
 * `warnIfTruncated` がログに残す（黙って切らない）。超えるほど育ったら集計用の表に移す。
 */
const ADMIN_READ = { maxRows: 1_000_000 };

function warnIfTruncated(where: string, reads: Record<string, { truncated: boolean }>) {
  for (const [name, r] of Object.entries(reads))
    if (r.truncated)
      console.warn(`[${where}] ${name}: 安全の上限で読むのを止めた（数が少なく出る）`);
}

export type AdminUserRow = {
  id: string;
  display_name: string | null;
  /** プロフィールの写真（公開 URL）。開発者の一覧で名前の横に出す（2026-10-15）。 */
  avatar_url: string | null;
  created_at: string;
  target_language: string | null;
  ui_language: string | null;
  plan: string | null;
  stickers: number;
  /**
   * 最後に使った時刻: アプリを開いた（`app_open` / `session_start`）・撮った・復習した、の
   * いちばん新しいもの。開いた記録は 2026-09 からしか無いので、それより前の人も撮った・
   * 復習した時刻で並ぶ。一覧はこの新しい順（`adminUserList`）。
   */
  last_active: string | null;
};

export const listAdminUsers = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }): Promise<AdminUserRow[]> => {
    await requireAdmin(context);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    // 並びは「最後に使った順」（2026-10-02）。登録の新しい300人だけを読むと、前から使い
    // 続けている人が一覧から落ちるので、上限を上げた（読むのは短い列だけ）。
    // **`.limit(50000)` と書いても PostgREST は 1000 行で切る**（2026-10-03 監査）。札の数も
    // 最後に使った時刻も黙って少なくなっていたので、全部 `readAllPages` で 1000 行ずつ読む。
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const db = supabaseAdmin as any;
    const [profiles, stickers, events, reviewed] = await Promise.all([
      readAllPages<{
        id: string;
        display_name: string | null;
        avatar_url: string | null;
        created_at: string;
        target_language: string | null;
        ui_language: string | null;
        plan?: string | null;
      }>((a, b) =>
        db
          .from("profiles")
          .select("id, display_name, avatar_url, created_at, target_language, ui_language, plan")
          .order("created_at", { ascending: false })
          .order("id")
          .range(a, b),
      ),
      readAllPages<{ user_id: string; created_at: string }>(
        (a, b) => db.from("stickers").select("user_id, created_at").order("id").range(a, b),
        ADMIN_READ,
      ),
      readAllPages<{ user_id: string; created_at: string }>(
        (a, b) =>
          db
            .from("usage_events")
            .select("user_id, created_at")
            .in("kind", ["app_open", "session_start"])
            .order("id")
            .range(a, b),
        ADMIN_READ,
      ),
      readAllPages<{ user_id: string; reviewed_at: string }>(
        (a, b) => db.from("review_history").select("user_id, reviewed_at").order("id").range(a, b),
        ADMIN_READ,
      ),
    ]);
    warnIfTruncated("listAdminUsers", { profiles, stickers, events, reviewed });
    const count = new Map<string, number>();
    const last = new Map<string, string | null>();
    const bump = (uid: string, iso: string) => last.set(uid, latestIso(last.get(uid), iso));
    for (const s of stickers.rows) {
      count.set(s.user_id, (count.get(s.user_id) ?? 0) + 1);
      bump(s.user_id, s.created_at);
    }
    for (const e of events.rows) bump(e.user_id, e.created_at);
    for (const r of reviewed.rows) bump(r.user_id, r.reviewed_at);
    return profiles.rows.map((p) => ({
      id: p.id,
      display_name: p.display_name,
      avatar_url: p.avatar_url ?? null,
      created_at: p.created_at,
      target_language: p.target_language,
      ui_language: p.ui_language,
      plan: (p as { plan?: string | null }).plan ?? null,
      stickers: count.get(p.id) ?? 0,
      last_active: last.get(p.id) ?? null,
    }));
  });

export type CompareRow = {
  label: string;
  value: number;
  median: number | null;
  /** 全体の中での位置（0〜100）。 */
  pct: number | null;
};
export type AdminUserDetail = Awaited<ReturnType<typeof buildDetail>> & {
  compare?: CompareRow[];
  compareBase?: number;
};

async function buildDetail(userId: string) {
  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
  const since = new Date(Date.now() - 180 * 86400 * 1000).toISOString();
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const db = supabaseAdmin as any;
  // 1人分でも記録は 1000 行を超えうる（PostgREST の既定の上限で黙って切られる）ので、
  // 札・スキャン・復習・利用・AI は全部 `readAllPages` で 1000 行ずつ読む（2026-10-03 監査）。
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const all = <T>(q: () => any) =>
    readAllPages<T>((from, to) => q().order("id").range(from, to), ADMIN_READ);
  const [profile, stickers, scans, history, reviews, usage, runs] = await Promise.all([
    db
      .from("profiles")
      .select(
        "id, display_name, avatar_url, created_at, native_language, ui_language, target_language, level_goal, current_level, pronunciation_strictness, review_mode, review_daily_limit, review_stage_focus, plan, album_bg, onboarded",
      )
      .eq("id", userId)
      .maybeSingle(),
    // 新しい順（st[0] が最新、最後が最初の札）。同じ時刻は id で並びを決める。
    readAllPages<unknown>(
      (from, to) =>
        db
          .from("stickers")
          .select(
            "id, created_at, capture_type, location_name, cutout_image_url, words(headword, language)",
          )
          .eq("user_id", userId)
          .order("created_at", { ascending: false })
          .order("id")
          .range(from, to),
      ADMIN_READ,
    ),
    all<unknown>(() =>
      db
        .from("scan_events")
        .select("created_at, detect_ms, tap_to_audio_ms, tapped, caught")
        .eq("user_id", userId)
        .gte("created_at", since),
    ),
    all<unknown>(() =>
      db
        .from("review_history")
        .select("reviewed_at, correct, response_ms")
        .eq("user_id", userId)
        .gte("reviewed_at", since),
    ),
    all<unknown>(() =>
      db
        .from("reviews")
        .select("due_at, interval_days, ease, last_reviewed_at, created_at")
        .eq("user_id", userId),
    ),
    all<unknown>(() =>
      db
        .from("usage_events")
        .select("kind, created_at")
        .eq("user_id", userId)
        .gte("created_at", since),
    ),
    all<unknown>(() => db.from("ai_runs").select("tokens_in, tokens_out").eq("user_id", userId)),
  ]);
  warnIfTruncated("buildDetail", { stickers, scans, history, reviews, usage, runs });
  if (!profile.data) throw new Error("User not found");

  type St = {
    id: string;
    created_at: string;
    capture_type: string | null;
    location_name: string | null;
    cutout_image_url: string | null;
    words: { headword: string; language: string | null } | null;
  };
  const st = stickers.rows as St[];
  const days = st.map((s) => dayKey(s.created_at));
  const byDay = new Map<string, number>();
  for (const d of days) byDay.set(d, (byDay.get(d) ?? 0) + 1);
  const places = new Map<string, number>();
  for (const s of st) {
    const p = (s.location_name ?? "").trim();
    if (p) places.set(p, (places.get(p) ?? 0) + 1);
  }
  const captureTypes: Record<string, number> = {};
  for (const s of st)
    captureTypes[s.capture_type ?? "photo"] = (captureTypes[s.capture_type ?? "photo"] ?? 0) + 1;

  // スキャンから図鑑に入れるまで: 捕まえたスキャンの後、10分以内に最初にできた札までの秒。
  type Sc = {
    created_at: string;
    detect_ms: number | null;
    tap_to_audio_ms: number | null;
    tapped: boolean;
    caught: boolean;
  };
  const sc = scans.rows as Sc[];
  const stTimes = st.map((s) => Date.parse(s.created_at)).sort((a, b) => a - b);
  const toDex = sc
    .filter((e) => e.caught)
    .map((e) => {
      const t = Date.parse(e.created_at);
      const hit = stTimes.find((x) => x >= t && x - t <= 10 * 60 * 1000);
      return hit ? (hit - t) / 1000 : null;
    });

  type Rh = { reviewed_at: string; correct: boolean | null; response_ms: number | null };
  const rh = history.rows as Rh[];
  const last30 = Date.now() - 30 * 86400 * 1000;
  type Rv = {
    due_at: string | null;
    interval_days: number | null;
    ease: number | null;
    last_reviewed_at: string | null;
    created_at: string | null;
  };
  const rv = reviews.rows as Rv[];
  const now = Date.now();

  type Ue = { kind: string; created_at: string };
  const ue = usage.rows as Ue[];
  const kinds: Record<string, number> = {};
  for (const e of ue) kinds[e.kind] = (kinds[e.kind] ?? 0) + 1;
  const leaves = Object.entries(kinds)
    .filter(([k]) => k.startsWith("leave_"))
    .map(([k, n]) => ({ screen: k.slice(6), count: n }))
    .sort((a, b) => b.count - a.count);
  const hours = Array.from({ length: 24 }, () => 0);
  for (const e of ue)
    if (e.kind === "session_start" || e.kind === "app_open")
      hours[
        Number(
          new Date(e.created_at).toLocaleString("en-US", {
            hour: "numeric",
            hour12: false,
            timeZone: "Asia/Taipei",
          }),
        ) % 24
      ]++;

  type Ar = { tokens_in: number | null; tokens_out: number | null };
  const ar = runs.rows as Ar[];

  // **グラフ用の細かい数**（2026-10-02「もっと詳しく、細かく、見やすく」）。どれも上で
  // 読んだ記録から作る（新しい問い合わせは足さない）。
  const today = dayKey(new Date().toISOString());
  const rhAt = rh.map((r) => ({
    at: r.reviewed_at,
    correct: r.correct,
    response_ms: r.response_ms,
  }));
  const spans = sessionSpans(ue);

  return {
    profile: profile.data as Record<string, string | number | boolean | null>,
    /** 最後に使った時刻（開いた・撮った・復習した、の新しい方。一覧の並びと同じ考え方）。 */
    // 記録は数万件になりうるので、関数の引数に広げず1件ずつ比べる。
    lastActive: [
      st[0]?.created_at,
      ...rh.map((r) => r.reviewed_at),
      ...ue.map((e) => e.created_at),
    ].reduce<string | null>((a, b) => latestIso(a, b), null),
    /** 日ごとの動き（90日、古い順）。画面で 14 / 30 / 90 日に切って出す。 */
    daily: dailyActivity({
      today,
      days: 90,
      dayOf: dayKey,
      catches: st.map((s) => s.created_at),
      reviews: rhAt,
      usage: ue,
    }),
    /** 週ごとの復習の正答率と答えるまでの秒（26週 = 読んでいる180日）。 */
    weekly: weeklyReviews(rhAt, today, 26, dayKey),
    memory: {
      /** 記憶の段0〜5の札の数（アプリの画面と同じ計算）。 */
      levels: memoryLevelCounts(rv, now),
      /** 期限切れと、これから14日の期限。 */
      schedule: dueSchedule(
        rv.map((r) => r.due_at),
        today,
        14,
        dayKey,
      ),
    },
    catches: {
      total: st.length,
      first: st.length ? st[st.length - 1].created_at : null,
      last: st.length ? st[0].created_at : null,
      last30: st.filter((s) => Date.parse(s.created_at) >= last30).length,
      byDay: [...byDay.entries()].sort((a, b) => (a[0] < b[0] ? 1 : -1)).slice(0, 30),
      topPlaces: [...places.entries()].sort((a, b) => b[1] - a[1]).slice(0, 8),
      captureTypes,
      cutouts: st.filter((s) => !!s.cutout_image_url).length,
      recentWords: st
        .slice(0, 12)
        .map((s) => ({ at: s.created_at, word: s.words?.headword ?? "" })),
    },
    streak: streaks(days, dayKey(new Date().toISOString())),
    speed: {
      scans: sc.length,
      detectMsMedian: median(sc.map((e) => e.detect_ms)),
      tapToAudioMsMedian: median(sc.map((e) => e.tap_to_audio_ms)),
      tapRate: sc.length ? Math.round((100 * sc.filter((e) => e.tapped).length) / sc.length) : null,
      scanToDexSecMedian: median(toDex),
    },
    review: {
      total180: rh.length,
      last30: rh.filter((r) => Date.parse(r.reviewed_at) >= last30).length,
      correctPct: rh.length
        ? Math.round((100 * rh.filter((r) => r.correct).length) / rh.length)
        : null,
      responseMsMedian: median(rh.map((r) => r.response_ms)),
      cards: rv.length,
      dueNow: rv.filter((r) => r.due_at && Date.parse(r.due_at) <= now).length,
      matured: rv.filter((r) => (r.interval_days ?? 0) >= 21).length,
      activeDays30: new Set(
        rh.filter((r) => Date.parse(r.reviewed_at) >= last30).map((r) => dayKey(r.reviewed_at)),
      ).size,
    },
    usage: {
      sessions: sessionMinutes(ue),
      /** 1回の滞在の長さの分布。 */
      sessionBuckets: sessionLengthBuckets(spans.map((s) => s.min)),
      /** 開いた曜日（月〜日、台湾時間）。 */
      weekdays: weekdayCounts(
        ue
          .filter((e) => e.kind === "session_start" || e.kind === "app_open")
          .map((e) => dayKey(e.created_at)),
      ),
      openDays: new Set(ue.filter((e) => e.kind === "app_open").map((e) => dayKey(e.created_at)))
        .size,
      hours,
      leaves,
      regenerations: kinds.card_regen ?? 0,
      reportFixes: kinds.report_fix ?? 0,
      removebg: kinds.removebg ?? 0,
      // 写真の保存に失敗した回数（`save-failure.ts`。記録は 2026-09-30 から）。
      saveFailures: {
        catch: kinds.save_failed_catch ?? 0,
        reencounter: kinds.save_failed_reencounter ?? 0,
        firstTransfer: kinds.save_failed_first_transfer ?? 0,
      },
      // 裏の処理の失敗（`background-failure.ts`。記録は 2026-10-01 から、同じ種類は1分に1回）。
      backgroundFailures: {
        tts: kinds.bg_failed_tts ?? 0,
        photoUpload: kinds.bg_failed_photo_upload ?? 0,
        thumbUpload: kinds.bg_failed_thumb_upload ?? 0,
        reviewGrade: kinds.bg_failed_review_grade ?? 0,
        firstCatchAi: kinds.bg_failed_first_catch_ai ?? 0,
        sceneLabel: kinds.bg_failed_scene_label ?? 0,
      },
    },
    ai: {
      ...aiCostEstimate(kinds),
      tokensIn: ar.reduce((s, r) => s + (r.tokens_in ?? 0), 0),
      tokensOut: ar.reduce((s, r) => s + (r.tokens_out ?? 0), 0),
    },
  };
}

export const getAdminUserDetail = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => z.object({ userId: z.string().uuid() }).parse(input))
  .handler(async ({ context, data }) => {
    await requireAdmin(context);
    const [detail, pop] = await Promise.all([buildDetail(data.userId), population()]);
    // **ほかの利用者との比較**（2026-09-28）。数字だけを比べる（ほかの人の中身は見せない）。
    const me = pop.perUser.get(data.userId) ?? {
      catches: 0,
      catches30: 0,
      reviews30: 0,
      open30: 0,
    };
    const all = [...pop.perUser.values()];
    const row = (label: string, k: keyof typeof me) => {
      const xs = all.map((u) => u[k]);
      return { label, value: me[k], median: median(xs), pct: percentileRank(xs, me[k]) };
    };
    return {
      ...detail,
      compare: [
        row("撮った語（合計）", "catches"),
        row("撮った語（30日）", "catches30"),
        row("復習（30日）", "reviews30"),
        row("開いた日（30日）", "open30"),
      ],
      compareBase: all.length,
    };
  });

/**
 * **全体の数字を集めるための読み込み**（利用者ごとの数だけを作る。中身は読まない）。
 * 大きくなったら集計用の表（夜に1回まとめる）に移す。いまは上限つきで直接数える。
 */
async function population() {
  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const db = supabaseAdmin as any;
  const since30 = new Date(Date.now() - 31 * 86400 * 1000).toISOString();
  // `.limit(100000)` と書いても PostgREST は 1000 行で切る（2026-10-03 監査）。全体の札の数・
  // 比べる中央値が黙って小さくなっていたので、全部 `readAllPages` で 1000 行ずつ読む。
  const [profiles, stickers, history, opens] = await Promise.all([
    readAllPages<unknown>((a, b) =>
      db
        .from("profiles")
        .select("id, created_at, plan, target_language")
        .order("created_at", { ascending: false })
        .order("id")
        .range(a, b),
    ),
    readAllPages<unknown>(
      (a, b) => db.from("stickers").select("user_id, created_at").order("id").range(a, b),
      ADMIN_READ,
    ),
    readAllPages<unknown>(
      (a, b) =>
        db
          .from("review_history")
          .select("user_id, reviewed_at")
          .gte("reviewed_at", since30)
          .order("id")
          .range(a, b),
      ADMIN_READ,
    ),
    readAllPages<unknown>(
      (a, b) =>
        db
          .from("usage_events")
          .select("user_id, created_at")
          .in("kind", ["app_open", "session_start"])
          .gte("created_at", new Date(Date.now() - 400 * 86400 * 1000).toISOString())
          .order("id")
          .range(a, b),
      ADMIN_READ,
    ),
  ]);
  warnIfTruncated("population", { profiles, stickers, history, opens });
  type P = { id: string; created_at: string; plan: string | null; target_language: string | null };
  const ps = profiles.rows as P[];
  const st = stickers.rows as Array<{ user_id: string; created_at: string }>;
  const rh = history.rows as Array<{ user_id: string; reviewed_at: string }>;
  const op = opens.rows as Array<{ user_id: string; created_at: string }>;
  const t30 = Date.parse(since30);
  const perUser = new Map<
    string,
    { catches: number; catches30: number; reviews30: number; open30: number }
  >();
  for (const p of ps) perUser.set(p.id, { catches: 0, catches30: 0, reviews30: 0, open30: 0 });
  for (const s of st) {
    const u = perUser.get(s.user_id);
    if (!u) continue;
    u.catches++;
    if (Date.parse(s.created_at) >= t30) u.catches30++;
  }
  for (const r of rh) {
    const u = perUser.get(r.user_id);
    if (u) u.reviews30++;
  }
  const activeDays = new Map<string, Set<string>>();
  const mark = (uid: string, iso: string) => {
    if (!activeDays.has(uid)) activeDays.set(uid, new Set());
    activeDays.get(uid)!.add(dayKey(iso));
  };
  for (const o of op) mark(o.user_id, o.created_at);
  for (const s of st) mark(s.user_id, s.created_at);
  for (const [uid, days] of activeDays) {
    const u = perUser.get(uid);
    if (!u) continue;
    u.open30 = [...days].filter((d) => Date.parse(`${d}T12:00:00Z`) >= t30).length;
  }
  return { ps, st, op, rh, perUser, activeDays };
}

export type AdminOverview = Awaited<ReturnType<typeof buildOverview>>;

async function buildOverview() {
  const { ps, st, op, rh, perUser, activeDays } = await population();
  const today = dayKey(new Date().toISOString());
  const dayUsers = new Map<string, Set<string>>();
  for (const o of op) {
    const d = dayKey(o.created_at);
    if (!dayUsers.has(d)) dayUsers.set(d, new Set());
    dayUsers.get(d)!.add(o.user_id);
  }
  const active = (n: number) => {
    const from = dailyCounts([], today, n).map((x) => x.day);
    const set = new Set<string>();
    for (const d of from) for (const u of dayUsers.get(d) ?? []) set.add(u);
    return set.size;
  };
  const count = <T extends string>(xs: T[]) => {
    const m: Record<string, number> = {};
    for (const x of xs) m[x] = (m[x] ?? 0) + 1;
    return Object.entries(m).sort((a, b) => b[1] - a[1]);
  };
  const users = ps.map((p) => ({
    signup: dayKey(p.created_at),
    activeDays: [...(activeDays.get(p.id) ?? [])],
  }));
  const catchesPerUser = [...perUser.values()].map((u) => u.catches);
  const bucket = (n: number) =>
    n === 0 ? "0" : n < 10 ? "1–9" : n < 50 ? "10–49" : n < 200 ? "50–199" : "200+";
  return {
    totals: {
      users: ps.length,
      pro: ps.filter((p) => p.plan === "pro").length,
      new7: ps.filter((p) => Date.now() - Date.parse(p.created_at) < 7 * 86400 * 1000).length,
      active1: active(1),
      active7: active(7),
      active30: active(30),
      catches: st.length,
      reviews30: rh.length,
    },
    series: {
      signups: dailyCounts(
        ps.map((p) => dayKey(p.created_at)),
        today,
        30,
      ),
      active: dailyCounts([], today, 30).map((x) => ({
        day: x.day,
        n: dayUsers.get(x.day)?.size ?? 0,
      })),
      catches: dailyCounts(
        st.map((s) => dayKey(s.created_at)),
        today,
        30,
      ),
    },
    retention: {
      d1: retention(users, 1, today),
      d7: retention(users, 7, today),
      d30: retention(users, 30, today),
    },
    languages: count(ps.map((p) => p.target_language ?? "—")),
    plans: count(ps.map((p) => p.plan ?? "free")),
    catchesBuckets: ["0", "1–9", "10–49", "50–199", "200+"].map((b) => ({
      bucket: b,
      n: catchesPerUser.filter((n) => bucket(n) === b).length,
    })),
    medians: {
      catches: median(catchesPerUser),
      reviews30: median([...perUser.values()].map((u) => u.reviews30)),
      open30: median([...perUser.values()].map((u) => u.open30)),
    },
  };
}

/** **全体の数字**（オーナー指示 2026-09-28「ユーザー全体の情報など、もっと分析しやすいように」）。 */
export const getAdminOverview = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    await requireAdmin(context);
    return buildOverview();
  });
