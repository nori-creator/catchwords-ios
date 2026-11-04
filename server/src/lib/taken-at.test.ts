import { describe, expect, it } from "vitest";
import { acceptedTakenAt } from "./stickers.functions";

// 点検 B1・T35（2026-11-03）: 後で保存した写真は撮った時の日に置く。使えない値は今の時刻。
describe("acceptedTakenAt", () => {
  const now = Date.parse("2026-11-03T10:00:00Z");
  it("90日以内の過去はそのまま", () => {
    expect(acceptedTakenAt("2026-11-01T08:00:00Z", now)).toBe("2026-11-01T08:00:00.000Z");
  });
  it("先の時刻・古すぎる・読めない値は使わない", () => {
    expect(acceptedTakenAt("2026-11-04T10:00:00Z", now)).toBeNull();
    expect(acceptedTakenAt("2026-01-01T00:00:00Z", now)).toBeNull();
    expect(acceptedTakenAt("きのう", now)).toBeNull();
    expect(acceptedTakenAt(null, now)).toBeNull();
  });
});
