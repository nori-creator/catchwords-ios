import { describe, expect, it } from "vitest";
import { reportMayRegenerate } from "./plan-limits";

/** オーナー決定 2026-09-28「無料は1日3つまで」「作り直しはプロユーザーのみ」。 */
describe("無料と Pro の境目", () => {
  it("無料の人の報告は記録だけ（作り直しの裏道にしない）。辞書で照らす所は全員", () => {
    expect(reportMayRegenerate({ isPro: false, item: "example" })).toBe("record_only");
    expect(reportMayRegenerate({ isPro: false, item: "auto" })).toBe("record_only");
    expect(reportMayRegenerate({ isPro: true, item: "example" })).toBe("ai");
    expect(reportMayRegenerate({ isPro: false, item: "pronunciation" })).toBe("dictionary");
    expect(reportMayRegenerate({ isPro: false, item: "pos" })).toBe("dictionary");
  });
});
