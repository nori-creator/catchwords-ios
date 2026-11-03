import { describe, expect, it } from "vitest";
import { measureWordReading, withChunkReadingsInExtras } from "./chunk-readings.server";

// 決定 10B（2026-11-03）・点検 T24・M36: 量詞の「一」は辞書の形 yī、読みは辞書で検める。
describe("量詞の読み", () => {
  it("一張: AI の yí zhàng（声調の誤り）→ yī zhāng / ㄧ ㄓㄤ", () => {
    expect(measureWordReading("一張", "yí zhàng", "ㄧˋ ㄓㄤ")).toEqual({ pinyin: "yī zhāng", zhuyin: "ㄧ ㄓㄤ" });
  });
  it("一個・一杯・一台 も yī", () => {
    expect(measureWordReading("一個", "yí gè", "ㄧˊ ㄍㄜˋ").pinyin).toBe("yī gè");
    expect(measureWordReading("一杯", "yì bēi", "ㄧˋ ㄅㄟ").pinyin).toBe("yī bēi");
    expect(measureWordReading("一台", "yì tái", "ㄧˋ ㄊㄞˊ")).toEqual({ pinyin: "yī tái", zhuyin: "ㄧ ㄊㄞˊ" });
  });
  it("カードの量詞の欄に効く", () => {
    const out = withChunkReadingsInExtras(
      { measure_words: [{ word: "一張", zhuyin: "ㄧˋ ㄓㄤ", pinyin: "yí zhàng", note: "平らな物に" }] },
      "zh-TW",
    );
    expect(out.measure_words?.[0]).toMatchObject({ pinyin: "yī zhāng", zhuyin: "ㄧ ㄓㄤ", note: "平らな物に" });
  });
});
