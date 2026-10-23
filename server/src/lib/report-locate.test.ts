import { describe, expect, it } from "vitest";
import { pickReportedItem, reportContext } from "./report-locate";

describe("報告から間違っている項目を決める", () => {
  const cands = ["pronunciation", "meaning", "example"] as const;
  it("画面に在る項目だけを採る", () => {
    expect(pickReportedItem({ item: "example" }, cands)).toBe("example");
    expect(pickReportedItem({ item: " meaning " }, cands)).toBe("meaning");
  });
  it("「なし」・画面に無い項目・壊れた答えは採らない", () => {
    expect(pickReportedItem({ item: "none" }, cands)).toBeNull();
    expect(pickReportedItem({ item: "etymology" }, cands)).toBeNull();
    expect(pickReportedItem("example", cands)).toBeNull();
    expect(pickReportedItem(null, cands)).toBeNull();
  });
  it("語の中身を項目ごとに短く並べる", () => {
    const text = reportContext(cands, {
      reading_zhuyin: "ㄋㄞˇ ㄔㄚˊ",
      meaning: "ミルクティー",
      extras: { example: "x".repeat(900) },
    });
    expect(text).toContain("[pronunciation] ㄋㄞˇ ㄔㄚˊ");
    expect(text).toContain("[meaning] ミルクティー");
    expect(text.split("\n")[2].length).toBeLessThan(520);
  });
});
