import { describe, expect, it } from "vitest";
import { normalizeDetection, normalizeDetectItem } from "./scan-detect-parse";

describe("スキャンの返事を寛容に読む（オーナー報告 2026-09-23「検出に失敗と出る」）", () => {
  it("正しい形はそのまま", () => {
    const it0 = normalizeDetectItem({
      kind: "object",
      headword: "芒果",
      zhuyin: "ㄇㄤˊ ㄍㄨㄛˇ",
      pinyin: "mángguǒ",
      meaning_ja: "マンゴー",
      pos: "名詞",
      point: [512, 340],
      confidence: 0.93,
      alternatives: [],
    });
    expect(it0).toMatchObject({ headword: "芒果", point: [512, 340], confidence: 0.93 });
  });

  it("null・百分率・大文字・文字の座標・{x,y}・0〜1 の座標も読む", () => {
    const a = normalizeDetectItem({
      kind: "Text",
      headword: "吸管",
      zhuyin: null,
      pinyin: null,
      meaning_ja: null,
      pos: null,
      point: ["300", "700"],
      confidence: 93,
      alternatives: null,
    });
    expect(a).toMatchObject({ kind: "text", zhuyin: "", point: [300, 700], confidence: 0.93 });
    expect(normalizeDetectItem({ headword: "杯子", point: { x: 0.4, y: 0.5 } })?.point).toEqual([
      400, 500,
    ]);
  });

  it("語か座標が無い候補だけ捨て、残りは使う", () => {
    const r = normalizeDetection({
      items: [
        { headword: "", point: [1, 1] },
        { headword: "傘" },
        { headword: "碗", point: [10, 20] },
      ],
    });
    expect(r?.map((i) => i.headword)).toEqual(["碗"]);
  });

  it("同じ語は1つに。最大6つ。配列そのものでも読む", () => {
    const many = Array.from({ length: 9 }, (_, i) => ({ headword: `語${i % 8}`, point: [i, i] }));
    const r = normalizeDetection(many);
    expect(r).toHaveLength(6);
  });

  it("形の分からない返事だけ null（候補0個は失敗ではない）", () => {
    expect(normalizeDetection({ items: [] })).toEqual([]);
    expect(normalizeDetection("oops")).toBeNull();
    expect(normalizeDetection({ foo: 1 })).toBeNull();
  });
});
