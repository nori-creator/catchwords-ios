import { describe, expect, it } from "vitest";
import {
  activeDaysByUser,
  analysisReliability,
  computeBetaMetrics,
  costEstimate,
  DEFAULT_UNIT_COST_USD,
  normalizeUnitCosts,
  percentile,
  retentionCell,
  retentionTable,
  reviewSessions,
  signupFunnel,
  tutorialFunnel,
  unitCostOverrides,
  weeklyEngagement,
  type BetaRawData,
} from "./beta-metrics";
import { funnelKey } from "./funnel-events";

const TODAY = "2026-10-03";

/**
 * 見本の人（台湾の日付）:
 * - A: 9/20 登録。9/21・9/27・10/2 に使った → D1 ○、D7 ○、D30 はまだ。
 * - B: 9/20 登録。9/22 だけ → D1 ×（以降なら ○）、D7 ×。
 * - C: 10/2 登録 → D1 はまだ（10/3 は今日で途中）。
 * - D: 9/1 登録。10/1 に使った → D1 ×、D7 ×、D30 ○。
 * - admin・anon は数えない。
 */
const users = [
  { id: "A", signupDay: "2026-09-20" },
  { id: "B", signupDay: "2026-09-20" },
  { id: "C", signupDay: "2026-10-02" },
  { id: "D", signupDay: "2026-09-01" },
];
const activity = activeDaysByUser(
  [
    { user_id: "A", day: "2026-09-21" },
    { user_id: "A", day: "2026-09-27" },
    { user_id: "B", day: "2026-09-22" },
    { user_id: "D", day: "2026-10-01" },
  ],
  [{ user_id: "A", day: "2026-10-02" }],
  [],
);

describe("percentile", () => {
  it("uses nearest rank and ignores non-finite values", () => {
    expect(percentile([], 50)).toBeNull();
    expect(percentile([5], 90)).toBe(5);
    expect(percentile([4, 1, 3, 2], 50)).toBe(2);
    expect(percentile([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 90)).toBe(9);
    expect(percentile([1, NaN, 3], 50)).toBe(1);
  });
});

describe("retention（登録日ごとの継続）", () => {
  it("counts exact-day retention only for users whose day has finished", () => {
    expect(retentionCell(users, activity, 1, TODAY, "exact")).toEqual({
      kept: 1, // A
      eligible: 3, // A, B, D（C は 10/3 が今日なので入れない）
      pct: 33,
    });
    expect(retentionCell(users, activity, 1, TODAY, "onOrAfter")).toEqual({
      kept: 3,
      eligible: 3,
      pct: 100,
    });
    expect(retentionCell(users, activity, 7, TODAY, "exact")).toEqual({
      kept: 1,
      eligible: 3,
      pct: 33,
    });
    expect(retentionCell(users, activity, 30, TODAY, "exact")).toEqual({
      kept: 1, // D（9/1 + 30 = 10/1）
      eligible: 1,
      pct: 100,
    });
  });

  it("groups cohorts by signup day, newest first", () => {
    const t = retentionTable(users, activity, TODAY);
    expect(t.cohorts.map((c) => [c.day, c.users])).toEqual([
      ["2026-10-02", 1],
      ["2026-09-20", 2],
      ["2026-09-01", 1],
    ]);
    const sep20 = t.cohorts[1];
    expect(sep20.d1).toEqual({ kept: 1, eligible: 2, pct: 50 });
    expect(sep20.d7).toEqual({ kept: 1, eligible: 2, pct: 50 });
    expect(sep20.d30).toEqual({ kept: 0, eligible: 0, pct: null });
    expect(t.cohorts[0].d1.pct).toBeNull();
  });
});

describe("funnels", () => {
  it("counts tutorial sessions per step in the last 7 and 30 days", () => {
    const keys = [
      funnelKey("2026-10-03", "welcome_view", "a1"),
      funnelKey("2026-10-03", "welcome_view", "a2"),
      funnelKey("2026-09-27", "welcome_view", "a3"), // 7日の端（含む）
      funnelKey("2026-09-26", "welcome_view", "a4"), // 7日の外・30日の中
      funnelKey("2026-09-03", "welcome_view", "a5"), // 30日の外
      funnelKey("2026-10-03", "signup_done", "a1"),
      "funnel:2026-10-03:not_a_step:ab",
      "first-catch-run:2026-10-03:ok:x",
    ];
    const f = tutorialFunnel(keys, TODAY);
    expect(f[0]).toEqual({ step: "welcome_view", sessions: { 7: 3, 30: 4 } });
    expect(f.find((r) => r.step === "signup_done")?.sessions).toEqual({ 7: 1, 30: 1 });
    expect(f.find((r) => r.step === "photo_taken")?.sessions).toEqual({ 7: 0, 30: 0 });
  });

  it("signup → first catch → first review within the signup window", () => {
    const s = signupFunnel(
      users,
      [{ user_id: "A" }, { user_id: "C" }, { user_id: "D" }],
      [{ user_id: "A" }],
      TODAY,
    );
    expect(s).toEqual([
      { stage: "signup", users: { 7: 1, 30: 3 } },
      { stage: "first_catch", users: { 7: 1, 30: 2 } },
      { stage: "first_review", users: { 7: 0, 30: 1 } },
    ]);
  });
});

describe("reviewSessions / weeklyEngagement", () => {
  it("splits sessions on gaps longer than 10 minutes", () => {
    const s = reviewSessions([
      { user_id: "A", at: "2026-10-02T01:00:00Z" },
      { user_id: "A", at: "2026-10-02T01:02:00Z" },
      { user_id: "A", at: "2026-10-02T01:05:00Z" },
      { user_id: "A", at: "2026-10-02T03:00:00Z" },
      { user_id: "B", at: "2026-10-01T15:59:00Z" }, // 台湾では 10/1 23:59
    ]);
    expect(s).toEqual([
      { user_id: "A", day: "2026-10-02", minutes: 5, answers: 3 },
      { user_id: "A", day: "2026-10-02", minutes: 0, answers: 1 },
      { user_id: "B", day: "2026-10-01", minutes: 0, answers: 1 },
    ]);
  });

  it("computes catches and reviews per active user per week", () => {
    const ids = new Set(["A", "B"]);
    const act = activeDaysByUser(
      [
        { user_id: "A", day: "2026-10-01" },
        { user_id: "B", day: "2026-10-02" },
        { user_id: "B", day: "2026-09-25" },
      ],
      [],
      [],
    );
    const weeks = weeklyEngagement(
      ids,
      act,
      [
        { user_id: "A", day: "2026-10-01" },
        { user_id: "A", day: "2026-10-01" },
        { user_id: "B", day: "2026-10-02" },
        { user_id: "ADMIN", day: "2026-10-02" },
      ],
      [
        { user_id: "A", at: "2026-10-01T01:00:00Z" },
        { user_id: "A", at: "2026-10-01T01:04:00Z" },
        { user_id: "ADMIN", at: "2026-10-01T01:00:00Z" },
      ],
      TODAY,
      2,
    );
    expect(weeks[0]).toEqual({
      from: "2026-09-27",
      to: "2026-10-03",
      activeUsers: 2,
      catches: 3,
      reviews: 2,
      catchesPerActive: 1.5,
      reviewsPerActive: 1,
      reviewSessions: 1,
      medianReviewSessionMin: 4,
    });
    expect(weeks[1]).toMatchObject({ from: "2026-09-20", activeUsers: 1, catches: 0 });
  });
});

describe("cost estimate", () => {
  const raw = (over: Partial<BetaRawData> = {}): BetaRawData => ({
    today: TODAY,
    users,
    anonIds: ["ANON"],
    usage: [],
    catches: [],
    reviews: [],
    funnelKeys: [],
    latencies: [],
    runs: [],
    aiRuns: [],
    unitCosts: normalizeUnitCosts(null),
    ...over,
  });

  it("multiplies calls by unit cost, splits member / pre-signup and excludes admins", () => {
    const c = costEstimate(
      raw({
        usage: [
          { user_id: "A", kind: "card", day: "2026-10-03" },
          { user_id: "A", kind: "card", day: "2026-10-02" },
          { user_id: "B", kind: "tts", day: "2026-10-02" },
          { user_id: "A", kind: "camera_open", day: "2026-10-02" }, // 費用のない種類
          { user_id: "ANON", kind: "first_catch_ai", day: "2026-10-01" },
          { user_id: "ADMIN", kind: "card", day: "2026-10-02" },
          { user_id: "A", kind: "card", day: "2026-09-01" }, // 30日の外
        ],
        aiRuns: [{ user_id: "B", loop: "review_distractor_pregen", day: "2026-10-01" }],
        runs: [
          { source: "guest", day: "2026-10-01", ok: true, ms: 9000, action: "candidates" },
          {
            source: "guest",
            day: "2026-10-01",
            ok: false,
            ms: 20000,
            action: "candidates",
            refunded: true,
          },
        ],
      }),
      2,
    );
    const u = DEFAULT_UNIT_COST_USD;
    expect(c.memberUsd).toBeCloseTo(2 * u.card + u.tts + u["run:review_distractor_pregen"], 6);
    expect(c.guestUsd).toBeCloseTo(u.first_catch_ai + u["guest:first_catch_ai"], 6);
    expect(c.excludedUsd).toBeCloseTo(u.card, 6);
    expect(c.totalUsd).toBeCloseTo(c.memberUsd + c.guestUsd, 6);
    expect(c.perActiveUserMonthUsd).toBeCloseTo(c.totalUsd / 2, 4);
    expect(c.byKind.find((k) => k.key === "card")).toMatchObject({ calls: 2, unit: u.card });
    expect(c.days).toHaveLength(30);
    expect(c.days.at(-1)).toMatchObject({ day: TODAY, calls: 1 });
  });

  it("has no per-user figure without active users", () => {
    expect(costEstimate(raw(), 0).perActiveUserMonthUsd).toBeNull();
  });

  it("validates admin-edited unit costs", () => {
    const n = normalizeUnitCosts({ card: 0.01, tts: -1, bogus: 3, scan_detect: "x" });
    expect(n.card).toBe(0.01);
    expect(n.tts).toBe(DEFAULT_UNIT_COST_USD.tts);
    expect("bogus" in n).toBe(false);
    expect(unitCostOverrides({ ...DEFAULT_UNIT_COST_USD, card: 0.01 })).toEqual({ card: 0.01 });
  });
});

describe("analysisReliability（最初のキャッチの解析）", () => {
  it("reports success rate and p50/p90 latency by source and action", () => {
    const rows = analysisReliability(
      [
        { source: "member", user_id: "A", day: TODAY, ok: true, ms: 4000, action: "candidates" },
        { source: "member", user_id: "A", day: TODAY, ok: true, ms: 6000, action: "card" },
        { source: "guest", day: TODAY, ok: false, ms: 20000, action: "candidates" },
        { source: "guest", day: "2026-09-20", ok: true, ms: 5000, action: "candidates" },
        { source: "member", user_id: "ADMIN", day: TODAY, ok: false, ms: 1, action: "card" },
      ],
      TODAY,
      new Set(["ADMIN"]),
    );
    const get = (w: number, source: string, action = "all") =>
      rows.find((r) => r.window === w && r.source === source && r.action === action);
    expect(get(7, "all")).toEqual({
      window: 7,
      source: "all",
      action: "all",
      n: 3,
      ok: 2,
      pct: 67,
      p50: 6000,
      p90: 20000,
    });
    expect(get(30, "guest")).toMatchObject({ n: 2, ok: 1, pct: 50 });
    expect(get(7, "all", "candidates")).toMatchObject({ n: 2, ok: 1 });
    expect(get(7, "member")).toMatchObject({ n: 2, ok: 2, pct: 100 });
  });
});

describe("computeBetaMetrics", () => {
  it("excludes admins and anonymous accounts from user metrics", () => {
    const m = computeBetaMetrics({
      today: TODAY,
      users,
      anonIds: ["ANON"],
      usage: [
        { user_id: "A", kind: "camera_open", day: "2026-10-02" },
        { user_id: "A", kind: "camera_open", day: "2026-10-03" },
        { user_id: "ADMIN", kind: "camera_open", day: "2026-10-03" },
        { user_id: "ANON", kind: "camera_open", day: "2026-10-03" },
        { user_id: "B", kind: "candidates_shown", day: "2026-10-03" },
      ],
      catches: [{ user_id: "ADMIN", day: "2026-10-03" }],
      reviews: [],
      funnelKeys: [],
      latencies: [
        { user_id: "B", day: TODAY, ms: 3000 },
        { user_id: "ADMIN", day: TODAY, ms: 99999 },
      ],
      runs: [],
      aiRuns: [],
      unitCosts: normalizeUnitCosts(null),
    });
    expect(m.memberEvents.find((e) => e.kind === "camera_open")).toEqual({
      kind: "camera_open",
      users: { 7: 1, 30: 1 },
      events: { 7: 2, 30: 2 },
    });
    expect(m.candidateLatency[7]).toEqual({ n: 1, p50: 3000, p90: 3000, p99: 3000 });
    expect(m.cost.activeUsers30).toBe(2); // A と B（D は 10/1 の記録が無いこの例では数えない）
    expect(m.engagement[0].catches).toBe(0);
    expect(m.truncated).toBe(false);
  });
});
