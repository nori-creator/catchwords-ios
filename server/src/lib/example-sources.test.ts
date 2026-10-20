import { describe, it, expect } from "vitest";
import {
  hasPersonalMaterial,
  worldExampleRule,
  personalExampleRule,
  exampleSourceRule,
  DIARY_CHARS,
  DIARY_COUNT,
} from "./example-sources";

/**
 * 例文の出所の指示。**プロンプトの文字列そのものを試す**のは、
 * ここが空の引用符や「undefined」を含んだまま出ていっても、画面には
 * それらしい例文が出てしまい、誰も気づかないから。
 */

describe("hasPersonalMaterial", () => {
  it("何も無ければ false", () => {
    expect(hasPersonalMaterial({})).toBe(false);
    expect(hasPersonalMaterial({ caption: "", place: null, diaries: [] })).toBe(false);
    expect(hasPersonalMaterial({ diaries: ["", "   ", null, undefined] })).toBe(false);
  });

  it("1つでもあれば true", () => {
    expect(hasPersonalMaterial({ caption: "夜市で並んだ" })).toBe(true);
    expect(hasPersonalMaterial({ place: "士林夜市" })).toBe(true);
    expect(hasPersonalMaterial({ diaries: ["今日は雨だった"] })).toBe(true);
  });
});

describe("worldExampleRule", () => {
  it("実在のものから作らせ、検証が要る細部を禁じる", () => {
    const r = worldExampleRule("日本語");
    expect(r).toContain("実在の人物");
    expect(r).toContain("台湾");
    expect(r).toContain("事実を作らない");
    expect(r).toContain("日本語");
  });

  it("最重要はネイティブの自然さ。レベル・場面・生きた話題の順（2026-09-27）", () => {
    const r = worldExampleRule("日本語");
    const i1 = r.indexOf("最も自然");
    const i2 = r.indexOf("レベル");
    const i3 = r.indexOf("場面・状況・気持ち");
    const i4 = r.indexOf("生きた話題");
    expect(i1).toBeGreaterThan(-1);
    expect(i1).toBeLessThan(i2);
    expect(i2).toBeLessThan(i3);
    expect(i3).toBeLessThan(i4);
  });

  it("**固有名詞を無理に入れない**。いちばん大事なのは最も自然で頻繁に使う文（2026-09-28）", () => {
    const r = worldExampleRule("日本語");
    expect(r).toContain("最も頻繁に口にする一文");
    expect(r).toContain("固有名詞を無理に入れない");
    expect(r).toContain("自然に合う時だけ");
    // 生きた話題は「必ず現実から作る」ではなくなった。
    expect(r).not.toContain("例文は**現実から作る**");
  });

  it("英語を学ぶ人には台湾の話題を押し付けない。季節は今の月", () => {
    const r = worldExampleRule("日本語", "en", new Date(2026, 8, 27));
    expect(r).not.toContain("台湾");
    expect(r).toContain("2026年9月");
  });

  it("教科書的な無名の文を名指しで禁じる", () => {
    expect(worldExampleRule("日本語")).toContain("我是學生");
  });
});

describe("personalExampleRule", () => {
  it("材料が無ければ空文字（空の引用符を残さない）", () => {
    expect(personalExampleRule({}, "日本語")).toBe("");
    expect(personalExampleRule({ caption: "  " }, "日本語")).toBe("");
  });

  it("あるものだけを並べる", () => {
    const r = personalExampleRule({ caption: "並んで買った", place: "士林夜市" }, "日本語");
    expect(r).toContain("並んで買った");
    expect(r).toContain("士林夜市");
    // 渡していない項目の見出しは出さない。
    expect(r).not.toContain("最近の日記");
  });

  it("空白だけの日記は落とす", () => {
    const r = personalExampleRule({ diaries: ["", "  ", "雨で濡れた"] }, "日本語");
    expect(r).toContain("雨で濡れた");
    expect(r.match(/最近の日記/g)).toHaveLength(1);
  });

  it(`日記は${DIARY_COUNT}本まで`, () => {
    const r = personalExampleRule({ diaries: ["a", "b", "c", "d", "e"] }, "日本語");
    expect(r.match(/最近の日記/g)).toHaveLength(DIARY_COUNT);
    expect(r).not.toContain("「d」");
  });

  it(`長い日記は${DIARY_CHARS}字で切る`, () => {
    const long = "あ".repeat(DIARY_CHARS + 50);
    const r = personalExampleRule({ diaries: [long] }, "日本語");
    expect(r).toContain("…");
    expect(r).not.toContain(long);
    expect(r).toContain("あ".repeat(DIARY_CHARS));
  });

  it("改行や連続空白を1つに潰す（プロンプトが崩れない）", () => {
    const r = personalExampleRule({ caption: "夜市\n\nで   並んだ" }, "日本語");
    expect(r).toContain("夜市 で 並んだ");
  });

  it("undefined や null が文字列に漏れない", () => {
    const r = personalExampleRule(
      { caption: null, place: undefined, diaries: [null, "書いた"] },
      "日本語",
    );
    expect(r).not.toContain("undefined");
    expect(r).not.toContain("null");
  });
});

describe("exampleSourceRule", () => {
  it("材料が無ければ世界の側だけ", () => {
    const r = exampleSourceRule({}, "日本語");
    expect(r).toBe(worldExampleRule("日本語"));
  });

  it("材料があれば両方が入る", () => {
    const r = exampleSourceRule({ caption: "うれしかった" }, "日本語");
    expect(r).toContain("実在の人物");
    expect(r).toContain("うれしかった");
  });
});
