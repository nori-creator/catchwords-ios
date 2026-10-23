import { describe, expect, it } from "vitest";
import {
  adminUserList,
  aiCostEstimate,
  dailyActivity,
  dailyCounts,
  dueSchedule,
  evenTicks,
  hasDisplayName,
  md,
  mdw,
  niceTicks,
  latestIso,
  median,
  memoryLevelCounts,
  percentileRank,
  retention,
  screenOf,
  sessionLengthBuckets,
  sessionMinutes,
  streaks,
  weekdayCounts,
  weeklyReviews,
} from "./admin-user-stats";

describe("開発者だけ: 利用者ごとの数字", () => {
  it("続けた日: 今日か昨日で終わっていれば続いている", () => {
    expect(streaks(["2026-09-25", "2026-09-26", "2026-09-27"], "2026-09-28")).toEqual({
      current: 3,
      best: 3,
    });
    expect(streaks(["2026-09-20", "2026-09-21", "2026-09-28"], "2026-09-28")).toEqual({
      current: 1,
      best: 2,
    });
    expect(streaks(["2026-09-20"], "2026-09-28").current).toBe(0);
    expect(streaks([], "2026-09-28")).toEqual({ current: 0, best: 0 });
  });

  it("真ん中の値", () => {
    expect(median([3, 1, 2])).toBe(2);
    expect(median([1, 2, 3, 4])).toBe(3);
    expect(median([null, undefined])).toBeNull();
  });

  it("画面の区分", () => {
    expect(screenOf("/review")).toBe("review");
    expect(screenOf("/dex/abc")).toBe("dex");
    expect(screenOf("/admin/users")).toBe("other");
  });

  it("滞在: 始まりと終わりを組にし、3時間を超える組は数えない", () => {
    const s = sessionMinutes([
      { kind: "session_start", created_at: "2026-09-28T09:00:00Z" },
      { kind: "session_end", created_at: "2026-09-28T09:06:00Z" },
      { kind: "session_start", created_at: "2026-09-28T12:00:00Z" },
      { kind: "session_end", created_at: "2026-09-28T12:10:00Z" },
      { kind: "session_start", created_at: "2026-09-28T13:00:00Z" },
      { kind: "session_end", created_at: "2026-09-28T18:00:00Z" },
    ]);
    expect(s.sessions).toBe(2);
    expect(s.medianMin).toBe(8);
    expect(s.totalMin).toBe(16);
  });

  it("AI の費用の概算は、単価の分かる種類だけ", () => {
    const c = aiCostEstimate({ card: 10, removebg: 1, app_open: 50 });
    expect(c.byKind.map((x) => x.kind)).toEqual(["card", "removebg"]);
    expect(c.usd).toBeCloseTo(0.06, 3);
  });
});

/** 2026-09-28「グラフや図チャート、ほかのユーザーとの比較、ユーザー全体の情報」。 */
describe("開発者だけ: 全体の数字と比較", () => {
  it("全体の中での位置（同じ値は半分と数える）", () => {
    expect(percentileRank([1, 2, 3, 4], 3)).toBe(63);
    expect(percentileRank([5, 5, 5, 5], 5)).toBe(50);
    expect(percentileRank([], 1)).toBeNull();
  });

  it("日ごとの数は古い順・無い日は0", () => {
    expect(dailyCounts(["2026-09-27", "2026-09-27", "2026-09-25"], "2026-09-28", 4)).toEqual([
      { day: "2026-09-25", n: 1 },
      { day: "2026-09-26", n: 0 },
      { day: "2026-09-27", n: 2 },
      { day: "2026-09-28", n: 0 },
    ]);
  });

  it("続けて使っている割合: まだ N 日経っていない人は数えない", () => {
    const users = [
      { signup: "2026-09-01", activeDays: ["2026-09-01", "2026-09-09"] },
      { signup: "2026-09-01", activeDays: ["2026-09-01"] },
      { signup: "2026-09-25", activeDays: ["2026-09-25"] },
    ];
    expect(retention(users, 7, "2026-09-28")).toEqual({ rate: 50, eligible: 2 });
    expect(retention(users, 30, "2026-09-28")).toEqual({ rate: null, eligible: 0 });
  });
});

/**
 * 2026-10-02「名前なしのユーザーは消して、ユーザーの名前一覧は最も最近利用した人順に
 * 並べて」「チャートやグラフをもっと詳しく、細かく、見やすく」。
 */
describe("開発者だけ: 一覧の並びとグラフの数", () => {
  const row = (name: string | null, last: string | null, created = "2026-09-01T00:00:00Z") => ({
    display_name: name,
    last_active: last,
    created_at: created,
  });
  const day = (iso: string) => iso.slice(0, 10);

  it("名前なし（null・空・空白だけ）は一覧に出さないが、外した数は返す", () => {
    expect(hasDisplayName("のり")).toBe(true);
    expect(hasDisplayName(" a ")).toBe(true);
    expect(hasDisplayName(null)).toBe(false);
    expect(hasDisplayName("")).toBe(false);
    expect(hasDisplayName("　 ")).toBe(false);
    const r = adminUserList([row("A", null), row(null, "2026-10-01T00:00:00Z"), row("  ", null)]);
    expect(r.rows.map((x) => x.display_name)).toEqual(["A"]);
    expect(r.hiddenNoName).toBe(2);
  });

  it("最後に使った新しい順。記録の無い人は最後（その中は登録の新しい順）", () => {
    const r = adminUserList([
      row("古い", "2026-09-20T00:00:00Z"),
      row("無し・古い登録", null, "2026-08-01T00:00:00Z"),
      row("新しい", "2026-10-01T23:00:00Z"),
      row("無し・新しい登録", null, "2026-09-30T00:00:00Z"),
      row("中", "2026-09-28T00:00:00Z"),
    ]);
    expect(r.rows.map((x) => x.display_name)).toEqual([
      "新しい",
      "中",
      "古い",
      "無し・新しい登録",
      "無し・古い登録",
    ]);
  });

  it("いちばん新しい時刻（無い物・壊れた物は飛ばす）", () => {
    expect(latestIso(null, "2026-09-01T00:00:00Z", undefined, "2026-09-02T00:00:00Z")).toBe(
      "2026-09-02T00:00:00Z",
    );
    expect(latestIso("x", null)).toBeNull();
    expect(latestIso()).toBeNull();
  });

  it("日ごとの動き: 無い日も0で並び、撮った・復習・開いた・滞在・AI を日に分ける", () => {
    const d = dailyActivity({
      today: "2026-10-02",
      days: 3,
      dayOf: day,
      catches: ["2026-10-02T01:00:00Z", "2026-10-02T02:00:00Z", "2026-09-01T00:00:00Z"],
      reviews: [
        { at: "2026-09-30T01:00:00Z", correct: true },
        { at: "2026-09-30T02:00:00Z", correct: false },
      ],
      usage: [
        { kind: "app_open", created_at: "2026-10-01T09:00:00Z" },
        { kind: "session_start", created_at: "2026-10-01T09:00:00Z" },
        { kind: "session_end", created_at: "2026-10-01T09:07:30Z" },
        { kind: "card", created_at: "2026-10-01T09:01:00Z" },
        { kind: "tts", created_at: "2026-10-01T09:02:00Z" },
      ],
    });
    expect(d.map((x) => x.day)).toEqual(["2026-09-30", "2026-10-01", "2026-10-02"]);
    expect(d[0]).toMatchObject({ reviews: 2, correct: 1, catches: 0 });
    expect(d[1]).toMatchObject({ opens: 1, minutes: 7.5, aiCalls: 2 });
    expect(d[1].aiUsd).toBeCloseTo(0.0055, 4);
    expect(d[2].catches).toBe(2);
  });

  it("週ごとの復習: 最後の週は今日で終わる7日。復習の無い週の正答率は null", () => {
    const w = weeklyReviews(
      [
        { at: "2026-10-02T00:00:00Z", correct: true, response_ms: 2000 },
        { at: "2026-09-27T00:00:00Z", correct: true, response_ms: null },
        { at: "2026-09-25T00:00:00Z", correct: false, response_ms: 4000 },
      ],
      "2026-10-02",
      3,
      day,
    );
    expect(w.map((x) => [x.from, x.to])).toEqual([
      ["2026-09-12", "2026-09-18"],
      ["2026-09-19", "2026-09-25"],
      ["2026-09-26", "2026-10-02"],
    ]);
    expect(w[0].accuracy).toBeNull();
    expect(w[1]).toMatchObject({ reviews: 1, accuracy: 0, responseSec: 4 });
    expect(w[2]).toMatchObject({ reviews: 2, correct: 2, accuracy: 100, responseSec: 2 });
  });

  it("復習の予定: 期限切れと、今日から N 日（その先と期限なしは数えない）", () => {
    const s = dueSchedule(
      [
        "2026-09-30T00:00:00Z",
        "2026-10-02T05:00:00Z",
        "2026-10-03T00:00:00Z",
        "2026-12-01T00:00:00Z",
        null,
      ],
      "2026-10-02",
      2,
      day,
    );
    expect(s.overdue).toBe(1);
    expect(s.byDay).toEqual([
      { day: "2026-10-02", n: 1 },
      { day: "2026-10-03", n: 1 },
    ]);
  });

  it("滞在の長さの分布と曜日（月曜始まり）", () => {
    expect(sessionLengthBuckets([0.5, 2, 2.9, 7, 45]).map((b) => b.n)).toEqual([
      1, 2, 0, 1, 0, 0, 1,
    ]);
    // 2026-09-28 は月曜、2026-10-04 は日曜。
    expect(weekdayCounts(["2026-09-28", "2026-09-28", "2026-10-04"])).toEqual([
      2, 0, 0, 0, 0, 0, 1,
    ]);
  });

  it("グラフの目盛り: 縦は切りのよい間隔、横は今日を必ず含む", () => {
    expect(niceTicks(41)).toEqual([0, 20, 40, 60]);
    expect(niceTicks(6)).toEqual([0, 2, 4, 6]);
    expect(niceTicks(2)).toEqual([0, 1, 2]);
    expect(niceTicks(0)).toEqual([0, 1]);
    const xs = Array.from({ length: 30 }, (_, i) => String(i));
    const t = evenTicks(xs);
    expect(t[t.length - 1]).toBe("29");
    expect(t.length).toBeLessThanOrEqual(5);
    expect(md("2026-09-07")).toBe("9/7");
    expect(mdw("2026-09-27")).toBe("9/27(日)");
  });

  it("記憶の段: 復習した直後は「はっきり」、一度も復習していない札は 0% の「忘れかけ」", () => {
    const now = Date.parse("2026-10-02T00:00:00Z");
    const c = memoryLevelCounts(
      [
        { interval_days: 3, ease: 2.5, last_reviewed_at: "2026-10-02T00:00:00Z", created_at: null },
        { interval_days: 1, ease: 1.3, last_reviewed_at: null, created_at: "2026-06-01T00:00:00Z" },
      ],
      now,
    );
    expect(c).toEqual([1, 0, 0, 0, 0, 1]);
  });
});
