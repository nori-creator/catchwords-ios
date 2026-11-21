import { describe, expect, it } from "vitest";
import { gateUsageChunks } from "./chunk-quality";
import {
  chunksWithoutExample,
  coverChunks,
  examplePatternsRule,
  pickExamplePatterns,
  sentenceHoldsHeadword,
  type ExamplePattern,
} from "./example-patterns";
import { refineUsageChunks, type AiUsageChunk, type UsageChunk } from "./extras";
import { chunkHeadForm, chunkShortFormRule, usesShortForm, validShortForm } from "./short-form";

/**
 * **見出し語の短い形**（オーナー 2026-11-21「1.2 それでいい」）。台湾の人に、雨傘 の型「帶雨傘・撐雨傘・收雨傘」は
 * あまり見かけない、「帶傘・撐傘・收傘」が自然と言われた。見出し語の字の連続した一部の時だけ、型と例文で使ってよい。
 */

const p = (text: string, pos = "") => ({ text, pos });
const ai = (parts: { text: string; pos: string }[], ja: string, short?: string): AiUsageChunk =>
  ({ parts, ja, ...(short ? { short_form: short } : {}) }) as AiUsageChunk;
const ctx = { headword: "雨傘", language: "zh-TW", readerLang: "ja", meaning: "雨傘" };

describe("validShortForm", () => {
  it("見出し語の字の連続した一部だけを受け取る", () => {
    expect(validShortForm("雨傘", "傘", "zh-TW")).toBe("傘");
    expect(validShortForm("雨傘", " 傘 ", "zh-TW")).toBe("傘");
    expect(validShortForm("腳踏車", "踏車", "zh-TW")).toBe("踏車");
  });

  it("一部でない字・見出し語そのもの・空・漢字以外・台湾華語以外は受け取らない", () => {
    expect(validShortForm("雨傘", "陽傘", "zh-TW")).toBeNull();
    expect(validShortForm("雨傘", "雨傘", "zh-TW")).toBeNull();
    expect(validShortForm("雨傘", "", "zh-TW")).toBeNull();
    expect(validShortForm("雨傘", "傘子", "zh-TW")).toBeNull();
    expect(validShortForm("腳踏車", "腳車", "zh-TW")).toBeNull(); // 続いていない
    expect(validShortForm("雨傘", "umbrella", "zh-TW")).toBeNull();
    expect(validShortForm("umbrella", "brella", "en")).toBeNull();
  });
});

describe("chunkHeadForm", () => {
  it("見出し語が札なら見出し語、無ければ受け取れる短い形の札", () => {
    expect(chunkHeadForm({ parts: [p("帶"), p("雨傘")] }, "雨傘", "zh-TW")).toBe("雨傘");
    expect(chunkHeadForm({ parts: [p("帶"), p("傘")], short_form: "傘" }, "雨傘", "zh-TW")).toBe("傘");
    expect(usesShortForm({ parts: [p("帶"), p("傘")], short_form: "傘" }, "雨傘", "zh-TW")).toBe(true);
  });

  it("short_form を付けていない・札に無い・一部でない時は null", () => {
    expect(chunkHeadForm({ parts: [p("帶"), p("傘")] }, "雨傘", "zh-TW")).toBeNull();
    expect(chunkHeadForm({ parts: [p("帶傘")], short_form: "傘" }, "雨傘", "zh-TW")).toBeNull();
    expect(chunkHeadForm({ parts: [p("撐"), p("陽傘")], short_form: "陽傘" }, "雨傘", "zh-TW")).toBeNull();
  });
});

describe("門（gateUsageChunks）", () => {
  it("雨傘: 帶傘・撐傘・收傘 を通し、short_form を残す", () => {
    const g = gateUsageChunks(
      [
        ai([p("帶", "V"), p("傘", "N")], "傘を持っていく", "傘"),
        ai([p("撐", "V"), p("傘", "N")], "傘をさす", "傘"),
        ai([p("收", "V"), p("傘", "N")], "傘をたたむ", "傘"),
      ],
      ctx,
    );
    expect(g.dropped).toEqual([]);
    expect(g.kept.map((c) => c.parts.map((x) => x.text).join("＋"))).toEqual(["帶＋傘", "撐＋傘", "收＋傘"]);
    expect(g.kept.every((c) => c.short_form === "傘")).toBe(true);
  });

  it("見出し語のままの型には short_form を付けない（AI が付けてきても外す）", () => {
    const g = gateUsageChunks([ai([p("撐", "V"), p("雨傘", "N")], "傘をさす", "傘")], ctx);
    expect(g.kept).toHaveLength(1);
    expect(g.kept[0].short_form).toBeUndefined();
  });

  it("一部でない短い形は落とす（short_form）", () => {
    const g = gateUsageChunks([ai([p("撐", "V"), p("陽傘", "N")], "日傘をさす", "陽傘")], ctx);
    expect(g.kept).toEqual([]);
    expect(g.dropped.map((d) => d.reason)).toEqual(["short_form"]);
  });

  it("short_form の無い短い形は今までどおり落とす（headword_not_token）", () => {
    const g = gateUsageChunks([ai([p("帶", "V"), p("傘", "N")], "傘を持っていく")], ctx);
    expect(g.dropped.map((d) => d.reason)).toEqual(["headword_not_token"]);
  });

  it("短い形の札は入れ替えにしない（学ぶ語と同じ）", () => {
    const g = gateUsageChunks(
      [
        {
          parts: [
            { text: "撐", pos: "V" },
            { text: "傘", pos: "N", slot: true, alts: [{ text: "陽傘", ja: "日傘" }] },
          ],
          ja: "傘をさす",
          short_form: "傘",
        } as AiUsageChunk,
      ],
      ctx,
    );
    expect(g.kept[0].parts[1].slot).toBeUndefined();
    expect(g.kept[0].parts[1].alts).toBeUndefined();
  });

  it("台湾華語以外では short_form を見ない・残さない", () => {
    const g = gateUsageChunks([ai([p("put up", "V"), p("an umbrella", "N")], "傘をさす", "brella")], {
      headword: "umbrella",
      language: "en",
      readerLang: "ja",
    });
    expect(g.dropped).toEqual([]);
    expect(g.kept).toHaveLength(1);
    expect(g.kept[0].short_form).toBeUndefined();
  });
});

describe("保存済みの型を数える側（refineUsageChunks）", () => {
  it("短い形の型を空と数えない（空と数えると開くたびに作り直しに来る）", () => {
    const chunks: UsageChunk[] = [
      { parts: [p("帶", "V"), p("傘", "N")], ja: "傘を持っていく", short_form: "傘" },
      { parts: [p("帶", "V"), p("傘", "N")], ja: "x" }, // short_form 無し: 今までどおり出さない
    ];
    const out = refineUsageChunks(chunks, [{ word: "一把" }], "雨傘", "zh-TW");
    expect(out).toHaveLength(1);
    expect(out[0].short_form).toBe("傘");
  });
});

describe("例文", () => {
  const take: UsageChunk = { parts: [p("帶", "V"), p("傘", "N")], ja: "傘を持っていく", short_form: "傘" };
  const close: UsageChunk = { parts: [p("收", "V"), p("傘", "N")], ja: "傘をたたむ", short_form: "傘" };
  const pattern = (sentence: string): ExamplePattern =>
    ({ situation: "", share: 50, sentence, translation: "訳", scene: "雨の日に", chunks: [], scene_fits: true }) as ExamplePattern;

  it("短い形の型が文に出ていれば、見出し語の代わりに短い形でよい", () => {
    expect(sentenceHoldsHeadword("外面在下雨，出門記得帶傘喔！", "雨傘", [take], "zh-TW")).toBe(true);
    expect(sentenceHoldsHeadword("外面在下雨，出門記得帶傘喔！", "雨傘", [], "zh-TW")).toBe(false);
    // 傘 は入っているが、型（收＋傘）が文に無い — 見出し語の例文とは数えない。
    expect(sentenceHoldsHeadword("這把傘是我的。", "雨傘", [close], "zh-TW")).toBe(false);
    expect(sentenceHoldsHeadword("我的雨傘不見了。", "雨傘", [], "zh-TW")).toBe(true);
  });

  it("pickExamplePatterns が短い形の例文を通す", () => {
    const picked = pickExamplePatterns([pattern("外面在下雨，出門記得帶傘喔！"), pattern("這把傘是我的耶。")], {
      headword: "雨傘",
      language: "zh-TW",
      readerLang: "ja",
      chunks: [take],
    });
    expect(picked.map((e) => e.sentence)).toEqual(["外面在下雨，出門記得帶傘喔！"]);
  });

  it("coverChunks が短い形の型ごとに例文を拾う", () => {
    const card = { example_sentence: "", example_translation: "", extras: {} };
    const out = coverChunks(card, {
      chunks: [take, close],
      patterns: [pattern("外面在下雨，出門記得帶傘喔！"), pattern("進去之前先收傘，不要滴到地上。")],
      headword: "雨傘",
      language: "zh-TW",
      readerLang: "ja",
      withExtra: true,
    });
    expect(out.missing).toEqual([]);
    expect(
      chunksWithoutExample([take, close], [
        out.card.example_sentence ?? "",
        ...((out.card.extras as { examples_extra?: { zh: string }[] }).examples_extra ?? []).map((e) => e.zh),
      ]),
    ).toEqual([]);
  });

  it("例文を対にする指示に、短い形を使う型だと書く", () => {
    const rule = examplePatternsRule({
      headword: "雨傘",
      targetName: "台湾華語",
      nl: "日本語",
      max: 3,
      levelRule: "",
      sourceRule: "",
      chunkRoles: "V / N",
      pairChunks: [take],
    });
    expect(rule).toContain("見出し語の短い形「傘」を使う型");
    expect(rule).toContain("short_form");
  });
});

describe("指示文", () => {
  it("台湾華語だけに、禁止の例と自分で確かめる一文を入れる", () => {
    const rule = chunkShortFormRule("雨傘", "zh-TW");
    expect(rule).toContain("short_form");
    expect(rule).toContain("腳踏車 → 車");
    expect(rule).toContain("自分で確かめる");
    expect(chunkShortFormRule("umbrella", "en")).toBe("");
    expect(chunkShortFormRule("傘", "zh-TW")).toBe("");
  });
});
