import { describe, expect, it } from "vitest";
import {
  addDays,
  buildAnalytics,
  isTestEmail,
  percentile,
  placeArea,
  weekStart,
  type AnalyticsInput,
  type AnalyticsUserIn,
} from "./analytics";

// 2026-11-05 12:00 台湾 = 04:00 UTC（木曜）
const NOW = new Date("2026-11-05T04:00:00Z");
const at = (day: string, hh = "10") => `${day}T${hh}:00:00+08:00`;

function user(id: string, signup: string, extra: Partial<AnalyticsUserIn> = {}): AnalyticsUserIn {
  return {
    id,
    created_at: at(signup, "09"),
    email: `${id}@gmail.com`,
    is_anonymous: false,
    provider: "google",
    last_sign_in_at: null,
    display_name: id.toUpperCase(),
    avatar_url: null,
    ui_language: "ja",
    current_level: null,
    level_goal: "TOCFL-2",
    onboarded: true,
    ...extra,
  };
}

function input(over: Partial<AnalyticsInput> = {}): AnalyticsInput {
  return {
    now: NOW,
    range: 7,
    users: [],
    admins: [],
    flagged: [],
    catches: [],
    reviews: [],
    events: [],
    runs: [],
    costOf: () => 0,
    ...over,
  };
}

describe("dates", () => {
  it("adds days and finds the Monday of the week", () => {
    expect(addDays("2026-11-05", -6)).toBe("2026-10-30");
    expect(addDays("2026-02-28", 1)).toBe("2026-03-01");
    expect(weekStart("2026-11-05")).toBe("2026-11-02");
    expect(weekStart("2026-11-02")).toBe("2026-11-02");
    expect(weekStart("2026-11-08")).toBe("2026-11-02");
  });
});

describe("small helpers", () => {
  it("treats reserved domains as test accounts only", () => {
    expect(isTestEmail("e2e-test@catchwords.invalid")).toBe(true);
    expect(isTestEmail("a@example.com")).toBe(true);
    expect(isTestEmail("a@gmail.com")).toBe(false);
    expect(isTestEmail("x@privaterelay.appleid.com")).toBe(false);
    expect(isTestEmail(null)).toBe(false);
  });
  it("keeps only the city and district of a place", () => {
    expect(placeArea("台北市 大安區 和平東路一段162號")).toBe("台北市 大安區");
    expect(placeArea("京都市 下京区")).toBe("京都市 下京区");
    expect(placeArea("Taipei City, Da'an District, 162 Heping East Road")).toBe("Taipei City, Da'an District");
    // 区の無い所: 2つ目は通りなので市だけ
    expect(placeArea("Seattle, 123 Main Street")).toBe("Seattle");
    expect(placeArea("Seattle, Main Street")).toBe("Seattle");
    expect(placeArea("台北市 和平東路一段")).toBe("台北市");
    expect(placeArea("서울특별시 강남구 테헤란로 152")).toBe("서울특별시 강남구");
    // 番地から始まる名前は出さない
    expect(placeArea("162 Heping East Road")).toBeNull();
    expect(placeArea("  ")).toBeNull();
    expect(placeArea(null)).toBeNull();
  });
  it("takes the nearest-rank percentile", () => {
    expect(percentile([], 50)).toBeNull();
    expect(percentile([3000, 1000, 2000], 50)).toBe(2000);
    expect(percentile([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 90)).toBe(9);
  });
});

describe("buildAnalytics", () => {
  it("leaves out anonymous, admin, test and flagged accounts but still lists them last", () => {
    const r = buildAnalytics(
      input({
        users: [
          user("real", "2026-10-01"),
          user("anon", "2026-10-01", { is_anonymous: true }),
          user("owner", "2026-06-22"),
          user("e2e", "2026-10-01", { email: "e2e-test@catchwords.invalid" }),
          user("alt", "2026-10-25"),
        ],
        admins: ["owner"],
        flagged: ["alt"],
        catches: [{ user_id: "owner", created_at: at("2026-11-04"), location_name: null, kind: "new" }],
      }),
    );
    expect(r.counted).toBe(1);
    expect(r.excluded).toBe(4);
    expect(r.overview.learners.value).toBe(0); // the owner's catch is not counted
    expect(r.users[0].id).toBe("real");
    expect(Object.fromEntries(r.users.map((u) => [u.id, u.excluded]))).toEqual({
      real: null,
      anon: "anonymous",
      owner: "admin",
      e2e: "test_email",
      alt: "flagged",
    });
  });

  it("counts learners (caught or reviewed) in this and the previous window, by Taipei day", () => {
    const r = buildAnalytics(
      input({
        users: [user("a", "2026-09-01"), user("b", "2026-09-01"), user("c", "2026-09-01")],
        catches: [
          // 2026-10-30 00:30 Taipei is still 2026-10-29 16:30 UTC — counts as 10/30 (in the window)
          { user_id: "a", created_at: "2026-10-29T16:30:00Z", location_name: null, kind: "new" },
          { user_id: "c", created_at: at("2026-10-25"), location_name: null, kind: "again" },
        ],
        reviews: [
          { user_id: "b", reviewed_at: at("2026-11-05"), correct: true },
          { user_id: "b", reviewed_at: at("2026-10-24"), correct: false },
        ],
        // opening the app is not learning
        events: [{ user_id: "c", kind: "session_start", created_at: at("2026-11-04") }],
      }),
    );
    expect(r.window).toEqual({ from: "2026-10-30", to: "2026-11-05", prev_from: "2026-10-23", prev_to: "2026-10-29" });
    expect(r.overview.learners.value).toBe(2);
    expect(r.overview.learners.users?.sort()).toEqual(["a", "b"]);
    expect(r.overview.learners.prev).toBe(2); // b (10/24) and c (10/25)
    expect(r.overview.catches.value).toBe(1);
    expect(r.overview.reviews.value).toBe(1);
    expect(r.daily).toHaveLength(7);
    expect(r.daily.find((d) => d.day === "2026-10-30")?.learners).toEqual(["a"]);
    expect(r.app_events_since).toBe("2026-11-04");
    const learners = r.insights.find((i) => i.chart === "learners");
    expect(learners).toMatchObject({ code: "learners_flat", tone: "info" });
  });

  it("walks new sign-ups through the first steps, each step only from the one before", () => {
    const r = buildAnalytics(
      input({
        users: [
          user("n1", "2026-11-01"),
          user("n2", "2026-11-02"),
          user("n3", "2026-11-03", { onboarded: false }),
          user("old", "2026-09-01"),
        ],
        catches: [
          { user_id: "n1", created_at: at("2026-11-01"), location_name: "台北市 大安區 和平東路", kind: "new" },
          { user_id: "n2", created_at: at("2026-11-03"), location_name: null, kind: "new" },
        ],
        reviews: [{ user_id: "n1", reviewed_at: at("2026-11-02"), correct: true }],
      }),
    );
    expect(r.funnel.cohort).toBe(3);
    expect(r.funnel.steps.map((s) => [s.key, s.users.length])).toEqual([
      ["signup", 3],
      ["onboarded", 2],
      ["first_catch", 2],
      ["first_review", 1],
      ["came_back", 1],
    ]);
    expect(r.overview.first_day_catch).toMatchObject({ value: 33.3, n: 3, users: ["n1"] });
    const drop = r.insights.find((i) => i.chart === "funnel");
    expect(drop?.code).toBe("funnel_drop");
    expect(drop?.values).toMatchObject({ lost: 1, of: 3 }); // the first drop of the biggest size wins
    expect(r.quality.places).toEqual([{ name: "台北市 大安區", n: 1 }]);
    expect(r.users.find((u) => u.id === "n3")).toMatchObject({ status: "new", stopped_at: "onboarding" });
  });

  it("gives each user a status from the last day they were seen", () => {
    const r = buildAnalytics(
      input({
        users: [
          user("active", "2026-09-01"),
          user("risk", "2026-09-01"),
          user("gone", "2026-09-01"),
          user("never", "2026-09-01"),
        ],
        catches: [
          { user_id: "active", created_at: at("2026-11-01"), location_name: null, kind: "new" },
          { user_id: "risk", created_at: at("2026-10-20"), location_name: null, kind: "new" },
          { user_id: "gone", created_at: at("2026-09-10"), location_name: null, kind: "new" },
        ],
      }),
    );
    const s = Object.fromEntries(r.users.map((u) => [u.id, [u.status, u.stopped_at]]));
    expect(s).toEqual({
      active: ["active", null],
      risk: ["at_risk", null],
      gone: ["lapsed", null],
      never: ["never", "first_catch"],
    });
    expect(r.users.map((u) => u.id)).toEqual(["active", "risk", "gone", "never"]);
    expect(r.insights.filter((i) => i.chart === "users").map((i) => i.code)).toEqual([
      "users_at_risk",
      "users_never",
    ]);
  });

  it("builds weekly cohorts with week 0 as the sign-up week", () => {
    const r = buildAnalytics(
      input({
        users: [user("w1", "2026-10-20"), user("w2", "2026-10-21")], // both in the week of 10/19
        catches: [
          { user_id: "w1", created_at: at("2026-10-20"), location_name: null, kind: "new" },
          { user_id: "w1", created_at: at("2026-10-27"), location_name: null, kind: "new" },
          { user_id: "w2", created_at: at("2026-11-03"), location_name: null, kind: "new" },
        ],
      }),
    );
    expect(r.cohorts).toHaveLength(8);
    const c = r.cohorts.find((x) => x.week === "2026-10-19")!;
    expect(c.size).toBe(2);
    expect(c.cells.map((x) => x?.pct)).toEqual([50, 50, 50]);
    expect(r.cohorts[r.cohorts.length - 1]).toMatchObject({ week: "2026-11-02", size: 0, cells: [null] });
    expect(r.insights.find((i) => i.chart === "cohorts")).toMatchObject({ code: "cohort_week1", values: { pct: 50 } });
  });

  it("leaves a cohort whose week 1 has not ended out of the reading", () => {
    // 11/1（日）に登録 → 週1 は 11/2〜11/8。11/5 にはまだ途中なので、戻っていなくても 0% として数えない。
    const r = buildAnalytics(
      input({
        users: [user("w1", "2026-10-20"), user("late", "2026-11-01")],
        catches: [
          { user_id: "w1", created_at: at("2026-10-20"), location_name: null, kind: "new" },
          { user_id: "w1", created_at: at("2026-10-27"), location_name: null, kind: "new" },
          { user_id: "late", created_at: at("2026-11-01"), location_name: null, kind: "new" },
        ],
      }),
    );
    expect(r.cohorts.find((x) => x.week === "2026-10-26")!.cells.map((x) => x?.pct)).toEqual([100, 0]);
    expect(r.insights.find((i) => i.chart === "cohorts")).toMatchObject({ code: "cohort_week1", values: { pct: 100, n: 1 } });
  });

  it("leaves names the learner wrote out of the places", () => {
    const r = buildAnalytics(
      input({
        users: [user("a", "2026-09-01")],
        catches: [
          { user_id: "a", created_at: at("2026-11-04"), location_name: "台北市 大安區 和平東路一段162號", kind: "new" },
          { user_id: "a", created_at: at("2026-11-04"), location_name: "My home", location_custom: true, kind: "again" },
        ],
      }),
    );
    expect(r.quality.places).toEqual([{ name: "台北市 大安區", n: 1 }]);
  });

  it("measures the wait, the first-pick rate, AI errors, cost and a refusing backup", () => {
    const run = (loop: string, meta: unknown, day = "2026-11-04") => ({
      user_id: "a",
      loop,
      created_at: at(day),
      meta,
    });
    const r = buildAnalytics(
      input({
        users: [user("a", "2026-09-01")],
        catches: [{ user_id: "a", created_at: at("2026-11-04"), location_name: null, kind: "new" }],
        runs: [
          run("capture_suggest", { ok: true, ms: 2000 }),
          run("capture_suggest", { ok: true, ms: 4000 }),
          run("capture_suggest", { ok: false, ms: 9000 }),
          run("capture_suggest", { ok: true, ms: 1000 }, "2026-10-25"),
          run("card_generate", {
            ok: true,
            ms: 30000,
            attempts: [{ outcome: "error", code: "http_402" }],
          }),
          run("candidate_pick", { via: "photo", rank: 1 }),
          run("candidate_pick", { via: "photo", rank: 3 }),
          // 候補を捨てて検索した1番目は外れとして数え、打ち込み・スキャンは数えない（beta-metrics と同じ）
          run("candidate_pick", { via: "native_search", rank: 1 }),
          run("candidate_pick", { via: "typed", rank: 1 }),
          run("ai_call", { ok: true, model: "google:x", in: 1000, out: 100 }),
          run("ai_call", { ok: false, model: "google:x" }),
          run("ai_call", { ok: true, model: "lovable:y", in: 10, out: 10 }),
        ],
        costOf: (m) => (m.model === "google:x" ? 0.01 : null),
      }),
    );
    expect(r.quality.suggest_s).toEqual({ p50: 2, p90: 4, n: 2, prev_p50: 1 });
    expect(r.quality.card_s).toMatchObject({ p50: 30, n: 1 });
    expect(r.quality.first_pick).toEqual({ pct: 33.3, n: 3 });
    expect(r.quality.ai_errors).toEqual({ pct: 33.3, n: 3 });
    expect(r.quality.ai_cost_usd).toEqual({ total: 0.02, per_learner: 0.02, unpriced: 1 });
    expect(r.quality.backup_refused).toBe(1);
    expect(r.insights.find((i) => i.chart === "speed")).toMatchObject({ code: "speed_ok", tone: "good" });
    expect(r.insights.find((i) => i.chart === "ai")).toMatchObject({ code: "ai_backup_refused", tone: "bad" });
  });

  it("says there is nothing yet instead of showing zeros as a result", () => {
    const r = buildAnalytics(input({ users: [user("a", "2026-09-01")] }));
    const codes = Object.fromEntries(r.insights.map((i) => [i.chart, i.code]));
    expect(codes).toMatchObject({
      learners: "learners_none",
      kpis: "no_signups",
      funnel: "funnel_empty",
      cohorts: "cohort_wait",
      speed: "speed_none",
      ads: "ads_no_data",
    });
    expect(r.overview.week_return.value).toBeNull();
    expect(r.app_events_since).toBeNull();
  });
});
