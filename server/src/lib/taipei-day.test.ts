import { describe, expect, it } from "vitest";
import { taipeiDay } from "./taipei-day";

describe("taipeiDay", () => {
  it("台湾時間の0時で日付が変わる", () => {
    expect(taipeiDay(new Date("2026-09-28T15:59:00Z"))).toBe("2026-09-28");
    expect(taipeiDay(new Date("2026-09-28T16:00:00Z"))).toBe("2026-09-29");
  });
  it("ISO 文字列も受け取る", () => {
    expect(taipeiDay("2026-01-01T00:00:00+08:00")).toBe("2026-01-01");
  });
});
