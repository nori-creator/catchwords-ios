import { describe, expect, it } from "vitest";
import { latestDiaryDay } from "./journal.functions";

// 日記を書ける最後の日: 台湾の今日の翌日まで（日本・韓国の端末は夜の1時間、台湾より1日先の日付になる）。
describe("latestDiaryDay", () => {
  it("is the day after Taipei's today", () => {
    // 2026-10-24 15:30 UTC = 2026-10-24 23:30 Taipei → tomorrow in Taipei is 2026-10-25.
    expect(latestDiaryDay(new Date("2026-10-24T15:30:00Z"))).toBe("2026-10-25");
    // 2026-10-24 16:30 UTC = 2026-10-25 00:30 Taipei → 2026-10-26.
    expect(latestDiaryDay(new Date("2026-10-24T16:30:00Z"))).toBe("2026-10-26");
  });
});
