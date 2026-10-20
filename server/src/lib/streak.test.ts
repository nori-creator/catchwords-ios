import { describe, it, expect } from "vitest";
import { countStreak, previousDay } from "./streak";

describe("previousDay", () => {
  it("普通の日", () => {
    expect(previousDay("2026-08-19")).toBe("2026-08-18");
  });

  it("月をまたぐ", () => {
    expect(previousDay("2026-08-01")).toBe("2026-07-31");
    expect(previousDay("2026-03-01")).toBe("2026-02-28");
  });

  it("年をまたぐ", () => {
    expect(previousDay("2026-01-01")).toBe("2025-12-31");
  });

  it("うるう年の2月", () => {
    expect(previousDay("2028-03-01")).toBe("2028-02-29");
  });

  it("読めない日付は落とさずそのまま返す(表示が止まるより軽い)", () => {
    expect(previousDay("なにか")).toBe("なにか");
  });
});

describe("countStreak", () => {
  it("今日から続いている", () => {
    const days = ["2026-08-19", "2026-08-18", "2026-08-17"];
    expect(countStreak(days, "2026-08-19")).toBe(3);
  });

  it("**今日がまだ空でも、昨日から続いていれば途切れていない**", () => {
    // 朝いちばんに開いた人を 0 と言わない。
    const days = ["2026-08-18", "2026-08-17"];
    expect(countStreak(days, "2026-08-19")).toBe(2);
  });

  it("今日も昨日も無ければ 0", () => {
    expect(countStreak(["2026-08-10"], "2026-08-19")).toBe(0);
  });

  it("途中で1日抜けたらそこで止まる", () => {
    const days = ["2026-08-19", "2026-08-18", "2026-08-16", "2026-08-15"];
    expect(countStreak(days, "2026-08-19")).toBe(2);
  });

  it("同じ日が何度あっても1日と数える", () => {
    const days = ["2026-08-19", "2026-08-19", "2026-08-19", "2026-08-18"];
    expect(countStreak(days, "2026-08-19")).toBe(2);
  });

  it("月・年をまたいで続く", () => {
    const days = ["2026-01-01", "2025-12-31", "2025-12-30"];
    expect(countStreak(days, "2026-01-01")).toBe(3);
  });

  it("何も無ければ 0", () => {
    expect(countStreak([], "2026-08-19")).toBe(0);
  });

  it("止め木がある(全部埋まっていても回り続けない)", () => {
    // 400日ぶん連続で埋めて、上限で止まることを見る。
    const days: string[] = [];
    let d = "2026-08-19";
    for (let i = 0; i < 400; i++) {
      days.push(d);
      d = previousDay(d);
    }
    expect(countStreak(days, "2026-08-19", 30)).toBe(30);
  });
});
