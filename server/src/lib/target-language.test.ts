import { describe, expect, it } from "vitest";
import { isTargetHeadword, isZhHeadword } from "./target-language";

describe("isZhHeadword", () => {
  it.each(["文旦", "橡皮擦", "自動鉛筆", "珍珠奶茶", "捷運", "夜市"])(
    "漢字だけの %s は通す",
    (w) => {
      expect(isZhHeadword(w)).toBe(true);
    },
  );

  // 実際に図鑑へ入ってしまったもの。カタカナのまま見出しになり、
  // その下に注音が付いていた。
  it.each(["シャーペン", "けしごむ", "ティッシュ", "ボールペン", "メモちょう"])(
    "かなの %s は落とす",
    (w) => {
      expect(isZhHeadword(w)).toBe(false);
    },
  );

  it.each(["消しゴム", "シャー芯", "文旦ゼリー"])("かなが混ざる %s も落とす", (w) => {
    expect(isZhHeadword(w)).toBe(false);
  });

  it.each(["pencil", "MRT", "文旦juice"])("ラテン文字を含む %s は落とす", (w) => {
    expect(isZhHeadword(w)).toBe(false);
  });

  it.each(["", "   ", "、。", "!?", "123"])("中身が無い %s は落とす", (w) => {
    expect(isZhHeadword(w)).toBe(false);
  });

  it("飾りの約物は判定に影響しない", () => {
    expect(isZhHeadword("「文旦」")).toBe(true);
    expect(isZhHeadword(" 文旦 ")).toBe(true);
    expect(isZhHeadword("文旦。")).toBe(true);
  });

  it("約物を外した結果かなだけになるものは落とす", () => {
    expect(isZhHeadword("「シャーペン」")).toBe(false);
  });
});

describe("isTargetHeadword", () => {
  it("zh-TW は漢字の規則で見る", () => {
    expect(isTargetHeadword("文旦", "zh-TW")).toBe(true);
    expect(isTargetHeadword("シャーペン", "zh-TW")).toBe(false);
  });

  it("知らない言語は勝手に落とさない(根拠が無いため)", () => {
    expect(isTargetHeadword("Bleistift", "de-DE")).toBe(true);
    expect(isTargetHeadword("  ", "de-DE")).toBe(false);
  });
});
