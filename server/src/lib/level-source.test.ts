import { describe, it, expect } from "vitest";
import { isOutOfScale, resolveLevel } from "./level-source";
import { CEFR_SCALE, LEVEL_OUT, TOCFL_SCALE, parseLevelStep } from "./level-scale";

/**
 * オーナー指摘 2026-08-27 ⑭:
 * > 「これらの検定の単語以外の単語も勝手にレベルが表示されてる気がする。」
 *
 * 守るのは2点:
 *   ① 手元に答えが在るとき（辞書）は、AI の当て推量を採らない
 *   ② 分からないものに級を付けない（級外と言い切る）
 */

describe("辞書が正", () => {
  it("辞書に級が在れば、AI が別の級を言っても辞書を採る", () => {
    const r = resolveLevel({ scale: TOCFL_SCALE, dictStep: 2, aiLevel: "TOCFL-5" });
    expect(r).toEqual({ stored: "TOCFL-2", step: 2, source: "dictionary" });
  });

  it("英語も同じ（CEFR の綴りで保存する）", () => {
    const r = resolveLevel({ scale: CEFR_SCALE, dictStep: 3, aiLevel: "C2" });
    expect(r).toEqual({ stored: "B1", step: 3, source: "dictionary" });
  });

  it("**辞書に在るのに級が空なら級外**（検定の範囲外という意味）", () => {
    const r = resolveLevel({ scale: CEFR_SCALE, dictStep: null, aiLevel: "A2" });
    expect(r).toEqual({ stored: "CEFR-0", step: LEVEL_OUT, source: "dictionary-out" });
    expect(parseLevelStep(r.stored)).toBe(LEVEL_OUT);
  });
});

describe("辞書に無い語", () => {
  it("AI の級を読む", () => {
    expect(resolveLevel({ scale: TOCFL_SCALE, aiLevel: "TOCFL-4" })).toEqual({
      stored: "TOCFL-4",
      step: 4,
      source: "ai",
    });
  });

  it("AI が級外と答えたら級外", () => {
    const r = resolveLevel({ scale: TOCFL_SCALE, aiLevel: "TOCFL-0" });
    expect(r.source).toBe("ai-out");
    expect(isOutOfScale(r)).toBe(true);
  });

  it("**読めない答えは級外**（分からないものに級を付けない）", () => {
    for (const bad of [null, undefined, "", "  ", "不明", "unknown", "級外"]) {
      const r = resolveLevel({ scale: CEFR_SCALE, aiLevel: bad });
      expect([bad, r.source, r.stored]).toEqual([bad, "unknown-out", "CEFR-0"]);
    }
  });

  it("6段の外の数字も級外（`TOCFL-9` を9級にしない）", () => {
    expect(resolveLevel({ scale: TOCFL_SCALE, aiLevel: "TOCFL-9" }).source).toBe("ai-out");
  });
});

describe("「辞書に無い」と「辞書に在るが級が空」を混ぜない", () => {
  it("出所が別々に付く（直す所が違う）", () => {
    const notInDict = resolveLevel({ scale: CEFR_SCALE, aiLevel: "B2" });
    const inDictNoLevel = resolveLevel({ scale: CEFR_SCALE, dictStep: null, aiLevel: "B2" });
    expect(notInDict.source).toBe("ai");
    expect(inDictNoLevel.source).toBe("dictionary-out");
    expect(notInDict.stored).not.toBe(inDictNoLevel.stored);
  });
});
