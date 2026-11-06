/**
 * **開発者の「分析」**（オーナー 2026-11-04〜05「利用者の情報・KPI・ベータの指標を一から設計し直して…
 * プロのマーケターが使うような分析…そこから言える分析解説を書いて」。案 C を選び、A〜D は
 * 「古い方だけの1人を移す・iOS だけ作り直す・試験と匿名を外す・記録は 1.0.5 から」）。
 *
 * 3つの画面（利用者ごとの情報・KPIダッシュボード・ベータの指標）を1つにまとめる。ここは
 * **数えるだけの純粋な関数**（DB にも鍵にも触らない。試験で確かめる）。読み出しは
 * `analytics.functions.ts`。
 *
 * ## 一番大事な数 = 学習者
 * その期間に「1語以上撮った（新しい語・再会）」か「1問以上復習した」人。アプリを開いただけの人は
 * 数えない。日付は台湾時間（`taipeiDay`）。
 *
 * ## 数えない人（決定 C）
 * 匿名・管理者（オーナー）・試験用のメール（example.com / .invalid など）・開発者の画面で「数えない」に
 * した人（`analytics_exclusions`）。外した人は一覧の最後に理由と一緒に出す（黙って消さない）。
 *
 * ## 解説（1行）
 * 画面の各グラフの下の1行は、ここで決めた `code` と数（`values`）から画面が文にする（表示言語の
 * 表を通す）。数の判断（良い・注意・悪い）はここで決める。
 */
import { taipeiDay } from "./taipei-day";

export const ANALYTICS_RANGES = [7, 30, 90] as const;
export type AnalyticsRange = (typeof ANALYTICS_RANGES)[number];

/** 撮ってから候補が出るまでの目標（秒）。仕様の 2.5 秒。 */
export const SUGGEST_TARGET_S = 2.5;
/** 「人数が少ない」とみなす学習者の数（これ未満なら % が1人で大きく動くと添える）。 */
export const SMALL_SAMPLE = 10;

export type ExcludeReason = "anonymous" | "admin" | "test_email" | "flagged";

export type AnalyticsUserIn = {
  id: string;
  created_at: string;
  /** 試験用の判定にだけ使い、返さない。 */
  email: string | null;
  is_anonymous: boolean;
  provider: string | null;
  last_sign_in_at: string | null;
  display_name: string | null;
  avatar_url: string | null;
  ui_language: string | null;
  current_level: string | null;
  level_goal: string | null;
  onboarded: boolean | null;
};

export type AnalyticsInput = {
  now: Date;
  range: AnalyticsRange;
  users: AnalyticsUserIn[];
  admins: string[];
  flagged: string[];
  /** 新しい語（`stickers`）と再会（`encounters`）。 */
  catches: Array<{ user_id: string; created_at: string; location_name: string | null; kind: "new" | "again" }>;
  reviews: Array<{ user_id: string; reviewed_at: string; correct: boolean | null }>;
  /** 利用の記録（サーバの AI の記録も、1.0.5 からのアプリの記録も）。 */
  events: Array<{ user_id: string; kind: string; created_at: string }>;
  /** `ai_runs` の候補・カード・選んだ候補・AI の1回ずつ。 */
  runs: Array<{ user_id: string | null; loop: string; created_at: string; meta: unknown }>;
  /** AI の1回の費用（米ドル）。単価の分からない回は null。 */
  costOf: (meta: Record<string, unknown>) => number | null;
};

export type Tone = "good" | "warn" | "bad" | "info";
export type Insight = {
  /** どのグラフの下に出すか。 */
  chart: string;
  code: string;
  tone: Tone;
  values: Record<string, number | string>;
};

export type Metric = {
  value: number | null;
  prev: number | null;
  /** 割合の時の分母。 */
  n?: number;
  prev_n?: number;
  /** 押した時に出す人（id）。 */
  users?: string[];
};

export type UserStatus = "new" | "active" | "at_risk" | "lapsed" | "never";

export type AnalyticsUserRow = {
  id: string;
  name: string | null;
  avatar_url: string | null;
  created_at: string;
  provider: string | null;
  ui_language: string | null;
  level_now: string | null;
  level_goal: string | null;
  onboarded: boolean;
  status: UserStatus;
  /** 一度も撮っていない人がどこで止まったか。 */
  stopped_at: "onboarding" | "first_catch" | null;
  catches: number;
  catches_in_range: number;
  reviews: number;
  reviews_in_range: number;
  /** 復習の正答率（%）。復習が無ければ null。 */
  accuracy: number | null;
  learning_days: number;
  last_active: string | null;
  excluded: ExcludeReason | null;
};

export type AnalyticsReport = {
  generated_at: string;
  today: string;
  range: AnalyticsRange;
  window: { from: string; to: string; prev_from: string; prev_to: string };
  counted: number;
  excluded: number;
  /** アプリから届いた記録（開いた・画面など）の最初の日。1.0.5 より前は null。 */
  app_events_since: string | null;
  overview: {
    learners: Metric;
    new_users: Metric;
    catches: Metric;
    reviews: Metric;
    first_day_catch: Metric;
    week_return: Metric;
  };
  daily: Array<{ day: string; learners: string[]; catches: number; reviews: number; signups: string[] }>;
  funnel: { cohort: number; steps: Array<{ key: string; users: string[] }> };
  cohorts: Array<{ week: string; size: number; cells: Array<{ pct: number; users: string[] } | null> }>;
  users: AnalyticsUserRow[];
  quality: {
    suggest_s: { p50: number | null; p90: number | null; n: number; prev_p50: number | null };
    card_s: { p50: number | null; p90: number | null; n: number };
    first_pick: { pct: number | null; n: number };
    ai_errors: { pct: number | null; n: number };
    backup_refused: number;
    ai_cost_usd: { total: number; per_learner: number | null; unpriced: number };
    failures: number;
    places: Array<{ name: string; n: number }>;
  };
  ads: { limit_hit: number; offered: number; watched: number; failed: number };
  insights: Insight[];
};

/* ---------------------------------------------------------------- 日付 */

const DAY_MS = 86_400_000;
/** "YYYY-MM-DD" に n 日足す（台湾は夏時間が無いので正午で数えれば日がずれない）。 */
export function addDays(day: string, n: number): string {
  return new Date(Date.parse(`${day}T12:00:00Z`) + n * DAY_MS).toISOString().slice(0, 10);
}
export function daysBetween(a: string, b: string): number {
  return Math.round((Date.parse(`${b}T12:00:00Z`) - Date.parse(`${a}T12:00:00Z`)) / DAY_MS);
}
/** その日を含む週の月曜。 */
export function weekStart(day: string): string {
  const dow = new Date(`${day}T12:00:00Z`).getUTCDay(); // 0 = 日
  return addDays(day, -((dow + 6) % 7));
}

/* ---------------------------------------------------------------- 小さな道具 */

export function percentile(xs: number[], p: number): number | null {
  if (!xs.length) return null;
  const s = [...xs].sort((a, b) => a - b);
  const i = Math.min(s.length - 1, Math.max(0, Math.ceil((p / 100) * s.length) - 1));
  return s[i];
}
const pct = (a: number, b: number): number | null => (b > 0 ? Math.round((1000 * a) / b) / 10 : null);
const sec = (ms: number | null): number | null => (ms == null ? null : Math.round(ms / 100) / 10);
const obj = (v: unknown): Record<string, unknown> =>
  v && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, unknown>) : {};

/** 試験用のメール（RFC 2606 / 6761 の予約の名前）。 */
export function isTestEmail(email: string | null): boolean {
  if (!email) return false;
  const domain = email.toLowerCase().split("@")[1] ?? "";
  if (["example.com", "example.org", "example.net"].includes(domain)) return true;
  return /\.(invalid|test|example|localhost)$/.test(domain);
}

/**
 * 撮った場所の名前 → 市と区まで（番地は出さない）。
 * 「台北市 大安區 和平東路一段162號」→「台北市 大安區」。
 */
export function placeArea(name: string | null): string | null {
  const parts = (name ?? "").trim().split(/\s+/).filter(Boolean);
  if (!parts.length) return null;
  return parts.slice(0, 2).join(" ");
}

/** アプリが送る記録（サーバの AI の記録と分ける）。これが届き始めた日 = 「開いた記録」の始まり。 */
export const APP_SENT_KINDS = new Set([
  "app_open",
  "session_start",
  "session_end",
  "screen_view",
  "onboarding_step",
  "tutorial_step",
  "tutorial_skip",
  "notification_open",
  "widget_open",
]);
const FAILURE_PREFIXES = ["save_failed_", "bg_failed_"];

/* ---------------------------------------------------------------- 本体 */

export function buildAnalytics(input: AnalyticsInput): AnalyticsReport {
  const { range } = input;
  const today = taipeiDay(input.now);
  const from = addDays(today, -(range - 1));
  const prevTo = addDays(from, -1);
  const prevFrom = addDays(prevTo, -(range - 1));
  const inWin = (d: string) => d >= from && d <= today;
  const inPrev = (d: string) => d >= prevFrom && d <= prevTo;

  // 数えない人
  const admins = new Set(input.admins);
  const flagged = new Set(input.flagged);
  const reasonOf = (u: AnalyticsUserIn): ExcludeReason | null =>
    u.is_anonymous
      ? "anonymous"
      : admins.has(u.id)
        ? "admin"
        : isTestEmail(u.email)
          ? "test_email"
          : flagged.has(u.id)
            ? "flagged"
            : null;
  const reasons = new Map(input.users.map((u) => [u.id, reasonOf(u)]));
  const counted = input.users.filter((u) => reasons.get(u.id) == null);
  const countedIds = new Set(counted.map((u) => u.id));
  const signupDay = new Map(input.users.map((u) => [u.id, taipeiDay(u.created_at)]));

  // 1人ずつの学習した日・使った日
  const learnDays = new Map<string, Set<string>>();
  const seenDays = new Map<string, Set<string>>();
  const add = (m: Map<string, Set<string>>, id: string, d: string) => {
    if (!m.has(id)) m.set(id, new Set());
    m.get(id)!.add(d);
  };
  const catchesBy = new Map<string, string[]>();
  for (const c of input.catches) {
    const d = taipeiDay(c.created_at);
    add(learnDays, c.user_id, d);
    add(seenDays, c.user_id, d);
    if (!catchesBy.has(c.user_id)) catchesBy.set(c.user_id, []);
    catchesBy.get(c.user_id)!.push(d);
  }
  const reviewsBy = new Map<string, { days: string[]; correct: number; graded: number }>();
  for (const r of input.reviews) {
    const d = taipeiDay(r.reviewed_at);
    add(learnDays, r.user_id, d);
    add(seenDays, r.user_id, d);
    const x = reviewsBy.get(r.user_id) ?? { days: [], correct: 0, graded: 0 };
    x.days.push(d);
    if (r.correct != null) {
      x.graded += 1;
      if (r.correct) x.correct += 1;
    }
    reviewsBy.set(r.user_id, x);
  }
  let appEventsSince: string | null = null;
  const kindCount = (pred: (k: string) => boolean, inside: (d: string) => boolean) =>
    input.events.filter((e) => countedIds.has(e.user_id) && pred(e.kind) && inside(taipeiDay(e.created_at)))
      .length;
  for (const e of input.events) {
    const d = taipeiDay(e.created_at);
    add(seenDays, e.user_id, d);
    if (APP_SENT_KINDS.has(e.kind) && countedIds.has(e.user_id) && (!appEventsSince || d < appEventsSince))
      appEventsSince = d;
  }
  for (const u of input.users) {
    add(seenDays, u.id, signupDay.get(u.id)!);
    if (u.last_sign_in_at) add(seenDays, u.id, taipeiDay(u.last_sign_in_at));
  }

  const learnersIn = (inside: (d: string) => boolean) =>
    counted.filter((u) => [...(learnDays.get(u.id) ?? [])].some(inside)).map((u) => u.id);
  const signupsIn = (inside: (d: string) => boolean) =>
    counted.filter((u) => inside(signupDay.get(u.id)!)).map((u) => u.id);
  const countIn = (m: Map<string, string[]>, inside: (d: string) => boolean) =>
    counted.reduce((s, u) => s + (m.get(u.id) ?? []).filter(inside).length, 0);
  const reviewDays = new Map([...reviewsBy].map(([k, v]) => [k, v.days]));

  // 概要
  const learners = learnersIn(inWin);
  const learnersPrev = learnersIn(inPrev);
  const signups = signupsIn(inWin);
  const signupsPrev = signupsIn(inPrev);
  const caughtOnDay1 = (ids: string[]) =>
    ids.filter((id) => (catchesBy.get(id) ?? []).includes(signupDay.get(id)!));
  const firstDay = caughtOnDay1(signups);
  const firstDayPrev = caughtOnDay1(signupsPrev);
  // 7日以内に戻った: 登録の次の日〜7日後に学習した。登録から7日たった人だけで数える。
  const weekReturn = (lo: string, hi: string) => {
    const pool = counted
      .map((u) => u.id)
      .filter((id) => {
        const s = signupDay.get(id)!;
        return s >= lo && s <= hi && daysBetween(s, today) >= 7;
      });
    const back = pool.filter((id) => {
      const s = signupDay.get(id)!;
      return [...(learnDays.get(id) ?? [])].some((d) => {
        const k = daysBetween(s, d);
        return k >= 1 && k <= 7;
      });
    });
    return { pool, back };
  };
  const wr = weekReturn(addDays(from, -7), addDays(today, -7));
  const wrPrev = weekReturn(addDays(prevFrom, -7), addDays(prevTo, -7));

  const overview = {
    learners: { value: learners.length, prev: learnersPrev.length, users: learners },
    new_users: { value: signups.length, prev: signupsPrev.length, users: signups },
    catches: { value: countIn(catchesBy, inWin), prev: countIn(catchesBy, inPrev) },
    reviews: { value: countIn(reviewDays, inWin), prev: countIn(reviewDays, inPrev) },
    first_day_catch: {
      value: pct(firstDay.length, signups.length),
      prev: pct(firstDayPrev.length, signupsPrev.length),
      n: signups.length,
      prev_n: signupsPrev.length,
      users: firstDay,
    },
    week_return: {
      value: pct(wr.back.length, wr.pool.length),
      prev: pct(wrPrev.back.length, wrPrev.pool.length),
      n: wr.pool.length,
      prev_n: wrPrev.pool.length,
      users: wr.back,
    },
  } satisfies AnalyticsReport["overview"];

  // 日ごと
  const daily: AnalyticsReport["daily"] = [];
  for (let d = from; d <= today; d = addDays(d, 1)) {
    const on = (x: string) => x === d;
    daily.push({
      day: d,
      learners: learnersIn(on),
      catches: countIn(catchesBy, on),
      reviews: countIn(reviewDays, on),
      signups: signupsIn(on),
    });
  }

  // 最初の体験（この期間に登録した人の道のり。前の段を通った人だけを次の段で数える）
  const byId = new Map(input.users.map((u) => [u.id, u]));
  const s1 = signups;
  const s2 = s1.filter((id) => byId.get(id)?.onboarded);
  const s3 = s2.filter((id) => (catchesBy.get(id) ?? []).length > 0);
  const s4 = s3.filter((id) => (reviewsBy.get(id)?.days.length ?? 0) > 0);
  const s5 = s4.filter((id) => [...(seenDays.get(id) ?? [])].some((d) => d > signupDay.get(id)!));
  const funnel = {
    cohort: s1.length,
    steps: [
      { key: "signup", users: s1 },
      { key: "onboarded", users: s2 },
      { key: "first_catch", users: s3 },
      { key: "first_review", users: s4 },
      { key: "came_back", users: s5 },
    ],
  };

  // 登録した週ごとの続き方（週0 = 登録した週）
  const weeks = range === 90 ? 13 : 8;
  const thisWeek = weekStart(today);
  const cohorts: AnalyticsReport["cohorts"] = [];
  for (let w = weeks - 1; w >= 0; w--) {
    const ws = addDays(thisWeek, -7 * w);
    const members = counted.map((u) => u.id).filter((id) => weekStart(signupDay.get(id)!) === ws);
    const cells: Array<{ pct: number; users: string[] } | null> = [];
    for (let k = 0; k <= w; k++) {
      const a = addDays(ws, 7 * k);
      const b = addDays(a, 6);
      if (!members.length) {
        cells.push(null);
        continue;
      }
      const back = members.filter((id) => [...(learnDays.get(id) ?? [])].some((d) => d >= a && d <= b));
      cells.push({ pct: pct(back.length, members.length) ?? 0, users: back });
    }
    cohorts.push({ week: ws, size: members.length, cells });
  }

  // 利用者
  const statusOf = (u: AnalyticsUserIn, last: string | null): UserStatus => {
    const age = daysBetween(signupDay.get(u.id)!, today);
    const learned = (learnDays.get(u.id)?.size ?? 0) > 0;
    if (age < 7) return "new";
    if (!learned) return "never";
    const idle = last ? daysBetween(last, today) : Infinity;
    return idle <= 7 ? "active" : idle <= 21 ? "at_risk" : "lapsed";
  };
  const order: Record<UserStatus, number> = { new: 0, active: 1, at_risk: 2, lapsed: 3, never: 4 };
  const users: AnalyticsUserRow[] = input.users
    .map((u) => {
      const seen = [...(seenDays.get(u.id) ?? [])].sort();
      const last = seen.length ? seen[seen.length - 1] : null;
      const rv = reviewsBy.get(u.id);
      const cs = catchesBy.get(u.id) ?? [];
      const status = statusOf(u, last);
      return {
        id: u.id,
        name: u.display_name,
        avatar_url: u.avatar_url,
        created_at: u.created_at,
        provider: u.provider,
        ui_language: u.ui_language,
        level_now: u.current_level,
        level_goal: u.level_goal,
        onboarded: !!u.onboarded,
        status,
        stopped_at: cs.length || rv ? null : u.onboarded ? ("first_catch" as const) : ("onboarding" as const),
        catches: cs.length,
        catches_in_range: cs.filter(inWin).length,
        reviews: rv?.days.length ?? 0,
        reviews_in_range: (rv?.days ?? []).filter(inWin).length,
        accuracy: rv && rv.graded ? Math.round((100 * rv.correct) / rv.graded) : null,
        learning_days: learnDays.get(u.id)?.size ?? 0,
        last_active: last,
        excluded: reasons.get(u.id) ?? null,
      };
    })
    .sort(
      (a, b) =>
        Number(a.excluded != null) - Number(b.excluded != null) ||
        order[a.status] - order[b.status] ||
        (b.last_active ?? "").localeCompare(a.last_active ?? "") ||
        b.created_at.localeCompare(a.created_at),
    );

  // 品質（数える人の分だけ。AI の記録は持ち主の無い物も入れる — 待ち時間は人によらない）
  const runsIn = (loop: string, inside: (d: string) => boolean) =>
    input.runs.filter(
      (r) =>
        r.loop === loop && inside(taipeiDay(r.created_at)) && (r.user_id == null || countedIds.has(r.user_id)),
    );
  const msOf = (rs: typeof input.runs) =>
    rs
      .map((r) => obj(r.meta))
      .filter((m) => m.ok !== false && typeof m.ms === "number")
      .map((m) => m.ms as number);
  const suggest = msOf(runsIn("capture_suggest", inWin));
  const suggestPrev = msOf(runsIn("capture_suggest", inPrev));
  const cards = msOf(runsIn("card_generate", inWin));
  const picks = runsIn("candidate_pick", inWin).map((r) => obj(r.meta).rank);
  const calls = runsIn("ai_call", inWin).map((r) => obj(r.meta));
  let usd = 0;
  let unpriced = 0;
  for (const m of calls) {
    const c = input.costOf(m);
    if (c == null) {
      if (m.ok !== false) unpriced += 1;
    } else usd += c;
  }
  const backupRefused = [...runsIn("capture_suggest", inWin), ...runsIn("card_generate", inWin)].filter((r) => {
    const attempts = obj(r.meta).attempts;
    return Array.isArray(attempts) && attempts.some((a) => /http_40[23]/.test(String(obj(a).code ?? "")));
  }).length;
  const areas = new Map<string, number>();
  for (const c of input.catches) {
    if (!countedIds.has(c.user_id) || !inWin(taipeiDay(c.created_at))) continue;
    const a = placeArea(c.location_name);
    if (a) areas.set(a, (areas.get(a) ?? 0) + 1);
  }
  const quality = {
    suggest_s: {
      p50: sec(percentile(suggest, 50)),
      p90: sec(percentile(suggest, 90)),
      n: suggest.length,
      prev_p50: sec(percentile(suggestPrev, 50)),
    },
    card_s: { p50: sec(percentile(cards, 50)), p90: sec(percentile(cards, 90)), n: cards.length },
    first_pick: { pct: pct(picks.filter((r) => r === 1).length, picks.length), n: picks.length },
    ai_errors: { pct: pct(calls.filter((m) => m.ok === false).length, calls.length), n: calls.length },
    backup_refused: backupRefused,
    ai_cost_usd: {
      total: Math.round(usd * 1000) / 1000,
      per_learner: learners.length ? Math.round((usd / learners.length) * 1000) / 1000 : null,
      unpriced,
    },
    failures: kindCount((k) => FAILURE_PREFIXES.some((p) => k.startsWith(p)), inWin),
    places: [...areas]
      .map(([name, n]) => ({ name, n }))
      .sort((a, b) => b.n - a.n || a.name.localeCompare(b.name))
      .slice(0, 8),
  };
  const ads = {
    limit_hit: kindCount((k) => k === "limit_hit", inWin),
    offered: kindCount((k) => k === "ad_offered", inWin),
    watched: kindCount((k) => k === "ad_watched", inWin),
    failed: kindCount((k) => k === "ad_failed", inWin),
  };

  const report: Omit<AnalyticsReport, "insights"> = {
    generated_at: input.now.toISOString(),
    today,
    range,
    window: { from, to: today, prev_from: prevFrom, prev_to: prevTo },
    counted: counted.length,
    excluded: input.users.length - counted.length,
    app_events_since: appEventsSince,
    overview,
    daily,
    funnel,
    cohorts,
    users,
    quality,
    ads,
  };
  return { ...report, insights: insightsFor(report) };
}

/* ---------------------------------------------------------------- 解説 */

/**
 * 各グラフの下の1行。数から「何が言えるか」を決める（文は画面の表示言語の表）。
 * 1つのグラフに1行。数が足りなくて言えない時も、言えないことを1行で言う。
 */
export function insightsFor(r: Omit<AnalyticsReport, "insights">): Insight[] {
  const out: Insight[] = [];
  const o = r.overview;
  const L = o.learners.value ?? 0;
  const P = o.learners.prev ?? 0;

  // 学習者の推移
  if (L === 0 && P === 0) out.push({ chart: "learners", code: "learners_none", tone: "bad", values: { days: r.range } });
  else
    out.push({
      chart: "learners",
      code: L > P ? "learners_up" : L < P ? "learners_down" : "learners_flat",
      tone: L > P ? "good" : L < P ? "bad" : "info",
      values: { now: L, prev: P, diff: Math.abs(L - P), days: r.range },
    });

  // 4つの数
  if ((o.new_users.value ?? 0) === 0)
    out.push({ chart: "kpis", code: "no_signups", tone: "warn", values: { days: r.range } });
  else if (o.first_day_catch.value != null)
    out.push({
      chart: "kpis",
      code: "first_day_catch",
      tone: o.first_day_catch.value >= 60 ? "good" : o.first_day_catch.value >= 40 ? "warn" : "bad",
      values: { pct: o.first_day_catch.value, n: o.first_day_catch.n ?? 0 },
    });
  if (r.counted > 0 && L < SMALL_SAMPLE)
    out.push({ chart: "sample", code: "small_sample", tone: "info", values: { n: L } });

  // 最初の体験
  const steps = r.funnel.steps;
  if (r.funnel.cohort === 0)
    out.push({ chart: "funnel", code: "funnel_empty", tone: "info", values: { days: r.range } });
  else {
    let worst = { i: 1, lost: -1 };
    for (let i = 1; i < steps.length; i++) {
      const lost = steps[i - 1].users.length - steps[i].users.length;
      if (lost > worst.lost) worst = { i, lost };
    }
    const before = steps[worst.i - 1].users.length;
    out.push({
      chart: "funnel",
      code: worst.lost === 0 ? "funnel_no_drop" : "funnel_drop",
      tone: worst.lost === 0 ? "good" : before && worst.lost / before >= 0.4 ? "bad" : "warn",
      values: {
        from: steps[worst.i - 1].key,
        to: steps[worst.i].key,
        lost: worst.lost,
        of: before,
        pct: before ? Math.round((100 * worst.lost) / before) : 0,
      },
    });
  }

  // 続ける（週1に戻った割合を、週1が見える組だけで平均）
  let size = 0;
  let back = 0;
  for (const c of r.cohorts)
    if (c.size && c.cells.length > 1 && c.cells[1]) {
      size += c.size;
      back += c.cells[1]!.users.length;
    }
  if (!size) out.push({ chart: "cohorts", code: "cohort_wait", tone: "info", values: {} });
  else {
    const p = Math.round((100 * back) / size);
    out.push({
      chart: "cohorts",
      code: "cohort_week1",
      tone: p >= 40 ? "good" : p >= 20 ? "warn" : "bad",
      values: { pct: p, n: size },
    });
  }

  // 利用者
  const counted = r.users.filter((u) => !u.excluded);
  const atRisk = counted.filter((u) => u.status === "at_risk").length;
  const never = counted.filter((u) => u.status === "never");
  const neverFirst = never.filter((u) => u.stopped_at === "first_catch").length;
  if (atRisk)
    out.push({ chart: "users", code: "users_at_risk", tone: "warn", values: { n: atRisk } });
  if (never.length)
    out.push({
      chart: "users",
      code: "users_never",
      tone: "bad",
      values: { n: never.length, first: neverFirst, onboarding: never.length - neverFirst },
    });
  if (!atRisk && !never.length)
    out.push({ chart: "users", code: "users_ok", tone: "good", values: { n: counted.length } });

  // 品質
  const q = r.quality;
  if (q.suggest_s.p50 == null)
    out.push({ chart: "speed", code: "speed_none", tone: "info", values: { days: r.range } });
  else
    out.push({
      chart: "speed",
      code: q.suggest_s.p50 <= SUGGEST_TARGET_S ? "speed_ok" : "speed_slow",
      tone: q.suggest_s.p50 <= SUGGEST_TARGET_S ? "good" : q.suggest_s.p50 <= SUGGEST_TARGET_S * 1.6 ? "warn" : "bad",
      values: {
        p50: q.suggest_s.p50,
        p90: q.suggest_s.p90 ?? q.suggest_s.p50,
        target: SUGGEST_TARGET_S,
        n: q.suggest_s.n,
      },
    });
  if (q.backup_refused > 0)
    out.push({ chart: "ai", code: "ai_backup_refused", tone: "bad", values: { n: q.backup_refused } });
  else if (q.ai_errors.pct != null && q.ai_errors.pct > 5)
    out.push({ chart: "ai", code: "ai_errors", tone: "warn", values: { pct: q.ai_errors.pct, n: q.ai_errors.n } });
  else if (q.ai_errors.n)
    out.push({
      chart: "ai",
      code: "ai_ok",
      tone: "good",
      values: { pct: q.ai_errors.pct ?? 0, usd: q.ai_cost_usd.total, n: q.ai_errors.n },
    });
  if (q.first_pick.pct != null)
    out.push({
      chart: "pick",
      code: "first_pick",
      tone: q.first_pick.pct >= 60 ? "good" : q.first_pick.pct >= 40 ? "warn" : "bad",
      values: { pct: q.first_pick.pct, n: q.first_pick.n },
    });
  if (q.places.length)
    out.push({
      chart: "places",
      code: "places_top",
      tone: "info",
      values: { name: q.places[0].name, n: q.places[0].n, areas: q.places.length },
    });

  // 広告
  const a = r.ads;
  if (!a.limit_hit && !a.offered && !a.watched && !a.failed)
    out.push({ chart: "ads", code: "ads_no_data", tone: "info", values: {} });
  else
    out.push({
      chart: "ads",
      code: "ads_watch_rate",
      tone: a.offered && a.watched / a.offered >= 0.5 ? "good" : "warn",
      values: { watched: a.watched, offered: a.offered, pct: a.offered ? Math.round((100 * a.watched) / a.offered) : 0 },
    });
  return out;
}
