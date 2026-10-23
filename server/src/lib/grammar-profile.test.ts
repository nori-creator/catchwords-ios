import { describe, it, expect } from "vitest";
import {
  GRAMMAR_ITEMS,
  grammarAbove,
  grammarAtOrBelow,
  grammarCountByStep,
  grammarStepOf,
} from "./grammar-profile";
import { LEVEL_INDEXES } from "./level-scale";

/**
 * 英語の文法項目と級の門（CEFR-J Grammar Profile）。
 *
 * ここで一番怖いのは**級の取り違え**。文法の級は「この人にこの例文を
 * 出してよいか」の判断そのものなので、1つずれると B2 の型が A2 の人に出る。
 * 語彙のときに `alarm clock` を取りこぼしたのと同じ形の事故が起きうる。
 */

describe("grammarStepOf — CEFR-J の級を段に読む", () => {
  it("細かい級を段に丸める", () => {
    expect(grammarStepOf("A1.1")).toBe(1);
    expect(grammarStepOf("A1.3")).toBe(1);
    expect(grammarStepOf("A2.1")).toBe(2);
    expect(grammarStepOf("B1.2")).toBe(3);
    expect(grammarStepOf("B2.2")).toBe(4);
  });

  it("**範囲はやさしいほうを採る**(難しいほうだと範囲から外れて出てこない)", () => {
    expect(grammarStepOf("A1.1-A1.2")).toBe(1);
    expect(grammarStepOf("A1.1-B2.2")).toBe(1);
    expect(grammarStepOf("A2.2-B1.1")).toBe(2);
    expect(grammarStepOf("B1.1-B2.2")).toBe(3);
  });

  it("読めない書き方は null(でっち上げない)", () => {
    for (const bad of ["", "  ", "C1.1", "X1", "1", "A3.1", null, undefined]) {
      expect([bad, grammarStepOf(bad)]).toEqual([bad, null]);
    }
  });

  it("小文字でも読む", () => {
    expect(grammarStepOf("b1.1")).toBe(3);
  });
});

describe("表そのもの", () => {
  it("256項目ある(取りこぼしていない)", () => {
    expect(GRAMMAR_ITEMS).toHaveLength(256);
  });

  it("**空の欄を持たない**(名前の無い項目を画面に出さない)", () => {
    for (const g of GRAMMAR_ITEMS) {
      expect(g.id.trim()).toBeTruthy();
      expect(g.ja.trim()).toBeTruthy();
      expect(g.en.trim()).toBeTruthy();
    }
  });

  it("id が重複していない(出典と1対1で突き合わせられる)", () => {
    expect(new Set(GRAMMAR_ITEMS.map((g) => g.id)).size).toBe(GRAMMAR_ITEMS.length);
  });

  it("**段は 1〜4 だけ**(CEFR-J は A1〜B2 しか扱わない)", () => {
    for (const g of GRAMMAR_ITEMS) {
      expect(g.step).toBeGreaterThanOrEqual(1);
      expect(g.step).toBeLessThanOrEqual(4);
    }
  });

  it("やさしい順に並んでいる", () => {
    for (let i = 1; i < GRAMMAR_ITEMS.length; i++) {
      expect(GRAMMAR_ITEMS[i].step).toBeGreaterThanOrEqual(GRAMMAR_ITEMS[i - 1].step);
    }
  });

  it("どの段にも項目がある(空の級を作らない)", () => {
    const counts = grammarCountByStep();
    for (const s of [1, 2, 3, 4]) expect(counts[s]).toBeGreaterThan(0);
  });

  it("**C1/C2 は空**(CEFR-J の対象外。数え間違いではない)", () => {
    const counts = grammarCountByStep();
    expect(counts[5]).toBe(0);
    expect(counts[6]).toBe(0);
    // 段の一覧そのものは6つのままであること(級の目盛りと食い違わせない)。
    expect(Object.keys(counts).map(Number).sort()).toEqual([...LEVEL_INDEXES]);
  });
});

describe("本物の項目が正しい級に居る", () => {
  const find = (en: string) => GRAMMAR_ITEMS.find((g) => g.en === en);

  it("**冠詞は A1**(中国語話者の最大の誤りが最初に来る)", () => {
    expect(find("INDEFINITE ARTICLES")?.step).toBe(1);
    expect(find("DEFINITE ARTICLES")?.step).toBe(1);
  });

  it("難しい型は B2", () => {
    expect(find("having been+PAST PARTICIPLE")?.step).toBe(4);
  });

  it("中くらいの型は B1", () => {
    expect(find("too ADJ/ADV to+INFINITIVE")?.step).toBe(3);
  });
});

describe("級で絞る", () => {
  it("その級までの項目だけ返る", () => {
    for (const s of [1, 2, 3, 4]) {
      for (const g of grammarAtOrBelow(s)) expect(g.step).toBeLessThanOrEqual(s);
    }
  });

  it("**A1 の人に B2 の型を渡さない**", () => {
    const a1 = grammarAtOrBelow(1);
    expect(a1.every((g) => g.step === 1)).toBe(true);
    expect(a1.some((g) => g.en === "having been+PAST PARTICIPLE")).toBe(false);
  });

  it("上の級の項目が取れる(背伸びしている所を認めるため)", () => {
    for (const g of grammarAbove(2)) expect(g.step).toBeGreaterThan(2);
    expect(grammarAbove(1).length).toBeGreaterThan(0);
  });

  it("**上と下で全部を覆い、重ならない**", () => {
    for (const s of [1, 2, 3, 4]) {
      expect(grammarAtOrBelow(s).length + grammarAbove(s).length).toBe(GRAMMAR_ITEMS.length);
    }
  });

  it("B2 より上は空(CEFR-J の上限)", () => {
    expect(grammarAbove(4)).toEqual([]);
  });

  it("段の外を渡しても落ちない", () => {
    expect(grammarAtOrBelow(0)).toEqual([]);
    expect(grammarAtOrBelow(6)).toHaveLength(GRAMMAR_ITEMS.length);
    expect(grammarAbove(6)).toEqual([]);
  });
});
