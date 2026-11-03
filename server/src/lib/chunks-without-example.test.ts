import { describe, expect, it } from "vitest";
import { chunksWithoutExample } from "./example-patterns";

// 点検 M-単1（2026-11-03）: 1つの文は1つの型だけが受け持つ。
describe("chunksWithoutExample", () => {
  const ch = (...texts: string[]) => ({ parts: texts.map((text) => ({ text })) });
  it("2つの型を含む文が1つだけなら、2つ目の型は例文が無い", () => {
    const chunks = [ch("點", "珍珠奶茶"), ch("珍珠奶茶", "半糖少冰")];
    expect(chunksWithoutExample(chunks as never, ["我要點珍珠奶茶半糖少冰。"])).toEqual([1]);
  });
  it("文が2つあれば両方に付く", () => {
    const chunks = [ch("點", "珍珠奶茶"), ch("珍珠奶茶", "半糖少冰")];
    expect(
      chunksWithoutExample(chunks as never, ["我要點珍珠奶茶。", "珍珠奶茶半糖少冰比較好喝。"]),
    ).toEqual([]);
  });
});
