import { describe, expect, it } from "vitest";
import {
  chunkExamplesRule,
  chunksWithoutExample,
  coverChunks,
  type ExamplePattern,
} from "./example-patterns";

// オーナー報告 2026-10-27 紅茶拿鐵: 型が2つあるのに例文が1つ。
const chunks = [
  { parts: [{ text: "點" }, { text: "一杯" }, { text: "紅茶拿鐵" }] },
  { parts: [{ text: "紅茶拿鐵" }, { text: "去冰", alts: [{ text: "少冰" }, { text: "微糖" }] }] },
];
const pattern = (sentence: string, scene: string): ExamplePattern => ({
  situation: "",
  share: 50,
  sentence,
  translation: "訳",
  scene,
  chunks: [],
  scene_fits: true,
});
const base = { headword: "紅茶拿鐵", language: "zh-TW", readerLang: "ja", withExtra: true };
const card = (main: string, extra: string[] = []) => ({
  example_sentence: main,
  example_translation: "訳",
  extras: { examples_extra: extra.map((zh) => ({ zh, ja: "訳", scene: "場面", scene_for: zh })) },
});

describe("chunksWithoutExample", () => {
  it("例文に字のまま入っていない型の番号を返す", () => {
    expect(chunksWithoutExample(chunks, ["老闆，我想點一杯紅茶拿鐵。"])).toEqual([1]);
    // 入れ替えの候補に替えた形も、その型を含むとみなす。
    expect(chunksWithoutExample(chunks, ["我想點一杯紅茶拿鐵", "我的紅茶拿鐵少冰就好"])).toEqual([]);
  });
});

describe("coverChunks", () => {
  it("同じ返事の生のパターンから、例文の無い型の文を拾い直す（似た文型でも型が違えば残す）", () => {
    const { card: out, missing } = coverChunks(card("老闆，我想點一杯紅茶拿鐵。"), {
      ...base,
      chunks,
      patterns: [
        pattern("老闆，我想點一杯紅茶拿鐵。", "カフェで注文する時"),
        pattern("紅茶拿鐵去冰就好，謝謝！", "氷を抜いてほしい時"),
      ],
    });
    expect(missing).toEqual([]);
    expect(out.extras.examples_extra.map((e) => e.zh)).toEqual(["紅茶拿鐵去冰就好，謝謝！"]);
    expect(out.extras).toMatchObject({ example_pattern_count: 2 });
  });

  it("拾えない型は missing に残す（呼ぶ側が小さな呼び出しで書かせる）", () => {
    const { card: out, missing } = coverChunks(card("老闆，我想點一杯紅茶拿鐵。"), {
      ...base,
      chunks,
      patterns: [pattern("這杯紅茶拿鐵好香喔！", "飲んだ時")],
    });
    expect(missing).toEqual([1]);
    expect(out.extras.examples_extra).toEqual([]);
  });

  it("メインの例文が空なら、最初の型の文をメインにする", () => {
    const { card: out, missing } = coverChunks(card(""), {
      ...base,
      chunks,
      patterns: [
        pattern("紅茶拿鐵去冰就好，謝謝！", "氷を抜いてほしい時"),
        pattern("老闆，我想點一杯紅茶拿鐵。", "カフェで注文する時"),
      ],
    });
    expect(missing).toEqual([]);
    expect(out.example_sentence).toBe("老闆，我想點一杯紅茶拿鐵。");
    expect(out.extras.examples_extra.map((e) => (e as { zh: string }).zh)).toEqual([
      "紅茶拿鐵去冰就好，謝謝！",
    ]);
  });

  it("学習言語でない文・見出し語の無い文・自己点検が false の文は拾わない", () => {
    const { missing } = coverChunks(card("老闆，我想點一杯紅茶拿鐵。"), {
      ...base,
      chunks,
      patterns: [{ ...pattern("紅茶拿鐵去冰就好，謝謝！", "氷を抜いてほしい時"), scene_fits: false }],
    });
    expect(missing).toEqual([1]);
  });

  it("追加の例文を頼まない呼び出しでは、メインがあれば足さない", () => {
    const { card: out } = coverChunks(card("老闆，我想點一杯紅茶拿鐵。"), {
      ...base,
      withExtra: false,
      chunks,
      patterns: [pattern("紅茶拿鐵去冰就好，謝謝！", "氷を抜いてほしい時")],
    });
    expect(out.extras.examples_extra).toEqual([]);
  });
});

describe("chunkExamplesRule", () => {
  it("足りない型だけを、入れ替えの候補付きで並べる", () => {
    const rule = chunkExamplesRule({
      headword: "紅茶拿鐵",
      targetName: "台湾華語",
      nl: "日本語",
      chunks: [chunks[1]],
      levelRule: "",
      chunkRoles: "N / V",
    });
    expect(rule).toContain("1. 紅茶拿鐵[去冰/少冰/微糖]");
    expect(rule).not.toContain("點一杯");
    expect(rule).toContain('"example_patterns"');
  });
});
