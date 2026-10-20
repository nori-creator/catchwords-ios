import { describe, expect, it } from "vitest";
import {
  FALLBACK_HEADWORDS,
  FALLBACK_HEADWORD_READINGS,
  FALLBACK_MEANINGS,
  buildChoices,
  pickDistractors,
  shuffle,
} from "./quiz-choices";

describe("pickDistractors", () => {
  it("池の順に取る(その学習者の頭で混ざる語を先に)", () => {
    expect(pickDistractors("A", [["B", "C"], ["D", "E"], FALLBACK_MEANINGS])).toEqual([
      "B",
      "C",
      "D",
    ]);
  });

  it("正解と同じ物は誤答にしない", () => {
    expect(pickDistractors("B", [["A", "B", "C", "D"]])).toEqual(["A", "C", "D"]);
  });

  it("同じ語を2回出さない(池をまたいでも)", () => {
    const got = pickDistractors("A", [
      ["B", "B"],
      ["B", "C", "D"],
    ]);
    expect(got).toEqual(["B", "C", "D"]);
    expect(new Set(got).size).toBe(got.length);
  });

  it("空文字は選ばない(意味が未入力の語が混ざっても穴が空かない)", () => {
    expect(pickDistractors("A", [["", "B", "", "C", "D"]])).toEqual(["B", "C", "D"]);
  });

  it("池が痩せていれば足りないまま返す(受け皿は呼ぶ側の責任)", () => {
    expect(pickDistractors("A", [["B"]])).toEqual(["B"]);
  });
});

describe("受け皿の大きさ", () => {
  // 3つしか無かった頃の不具合: 出題語が受け皿と一致すると誤答が2つになり、
  // 選択肢が3つの問題が出ていた。蘋果や公車を撮る学習者は普通にいる。
  it.each([
    ["意味", FALLBACK_MEANINGS],
    ["見出し語", FALLBACK_HEADWORDS],
  ])("%s の受け皿は want+1 個以上ある", (_name, pool) => {
    expect(pool.length).toBeGreaterThanOrEqual(4);
    expect(new Set(pool).size).toBe(pool.length);
  });

  it.each([...FALLBACK_HEADWORDS])("受け皿の語「%s」だけしか無くても4択になる", (word) => {
    // 撮った1語目が受け皿と同じ = 他の語がまだ1つも無い、最悪の場面。
    expect(buildChoices(word, [[], [], [], FALLBACK_HEADWORDS])).toHaveLength(4);
  });

  it.each([...FALLBACK_MEANINGS])("受け皿の意味「%s」だけしか無くても4択になる", (meaning) => {
    expect(buildChoices(meaning, [[], [], [], FALLBACK_MEANINGS])).toHaveLength(4);
  });

  it("見出し語の受け皿には全部の読みがある(注音欄が空にならない)", () => {
    for (const w of FALLBACK_HEADWORDS) {
      expect(FALLBACK_HEADWORD_READINGS[w]?.zhuyin).toBeTruthy();
      expect(FALLBACK_HEADWORD_READINGS[w]?.pinyin).toBeTruthy();
    }
  });
});

describe("buildChoices", () => {
  it("正解を必ず含み、重複が無い", () => {
    const got = buildChoices("A", [["B", "C", "D", "E"]]);
    expect(got).toContain("A");
    expect(new Set(got).size).toBe(4);
  });

  it("正解の位置が固定ではない(いつも同じ場所なら覚えられてしまう)", () => {
    const seen = new Set<number>();
    for (let i = 0; i < 200; i++) {
      seen.add(buildChoices("A", [["B", "C", "D"]]).indexOf("A"));
    }
    expect(seen.size).toBe(4);
  });
});

describe("shuffle", () => {
  it("元の配列を書き換えない", () => {
    const src = ["a", "b", "c"];
    shuffle(src);
    expect(src).toEqual(["a", "b", "c"]);
  });

  it("要素を落とさない・増やさない", () => {
    const src = Array.from({ length: 30 }, (_, i) => String(i));
    for (let i = 0; i < 50; i++) {
      expect([...shuffle(src)].sort()).toEqual([...src].sort());
    }
  });
});
