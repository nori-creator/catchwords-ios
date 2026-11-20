import { describe, expect, it } from "vitest";
import {
  chunkExamplesRule,
  chunksWithoutExample,
  coverChunks,
  examplePatternsRule,
  showsChunk,
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

// オーナー報告 2026-11-20 雨傘: 型が3つ（帶＋雨傘 / 撐＋雨傘 / 收＋雨傘）で例文が2つ。
describe("showsChunk — 画面が例文を型の下に出す決まり（iOS ChunkRules.chunkPlace と同じ）", () => {
  const c = (...texts: string[]) => ({ parts: texts.map((text) => ({ text })) });
  it("続けて入っている・部品が離れていても順のまま4字以内なら出る", () => {
    expect(showsChunk("出門記得帶雨傘喔！", c("帶", "雨傘"))).toBe(true);
    expect(showsChunk("我們一起撐這把雨傘走吧。", c("撐", "雨傘"))).toBe(true);
    expect(showsChunk("小籠包一定要配薑絲", c("小籠包", "配", "薑絲"))).toBe(true);
    expect(showsChunk("先用刨刀把馬鈴薯削皮喔", c("用", "刨刀", "削皮"))).toBe(true);
  });
  it("順が逆・部品が無い・間が5字以上なら出ない", () => {
    expect(showsChunk("我先把這件襯衫燙平再出門。", c("燙", "襯衫"))).toBe(false);
    expect(showsChunk("你的雨傘還在滴水，先放在門口吧。", c("收", "雨傘"))).toBe(false);
    expect(showsChunk("先用刨刀把那些馬鈴薯削皮喔", c("用", "刨刀", "削皮"))).toBe(false);
    expect(showsChunk("雨傘", c("雨傘"))).toBe(false);
  });
  it("入れ替えの候補に替えた形も（1か所ずつ）", () => {
    const swap = { parts: [{ text: "漢堡" }, { text: "加" }, { text: "蛋", alts: [{ text: "起司" }] }] };
    expect(showsChunk("我的漢堡要加起司喔", swap)).toBe(true);
    expect(showsChunk("我的漢堡要加培根喔", swap)).toBe(false);
  });
});

describe("chunksWithoutExample — 画面と同じ数え方", () => {
  const umbrella = [
    { parts: [{ text: "帶" }, { text: "雨傘" }] },
    { parts: [{ text: "撐" }, { text: "雨傘" }] },
    { parts: [{ text: "收" }, { text: "雨傘" }] },
  ];
  it("雨傘: 離れて入っている「撐…雨傘」は在る、「收＋雨傘」だけが無い", () => {
    expect(
      chunksWithoutExample(umbrella, [
        "外面快要下雨了，出門記得帶雨傘喔！",
        "雨越下越大了，我們一起撐這把雨傘走吧。",
        "你的雨傘還在滴水，先放在門口雨傘架上吧。",
      ]),
    ).toEqual([2]);
  });
});

describe("coverChunks — 続けて入っている文を先に取る", () => {
  it("同じ型に2つの文がある時、離れて入っている文より続けて入っている文", () => {
    const umbrella = [{ parts: [{ text: "撐" }, { text: "雨傘" }] }];
    const { card: out, missing } = coverChunks(
      { example_sentence: "出門記得帶雨傘喔！", example_translation: "訳", extras: { examples_extra: [] } },
      {
        headword: "雨傘",
        language: "zh-TW",
        readerLang: "ja",
        withExtra: true,
        chunks: umbrella,
        patterns: [
          pattern("雨越下越大了，我們一起撐這把雨傘走吧。", "友だちと歩く時"),
          pattern("雨變大了，我們趕快撐雨傘吧。", "雨が強くなった時"),
        ],
      },
    );
    expect(missing).toEqual([]);
    expect((out.extras.examples_extra as Array<{ zh: string }>).map((e) => e.zh)).toEqual([
      "雨變大了，我們趕快撐雨傘吧。",
    ]);
  });
});

describe("examplePatternsRule — 例文を型と対にする指示", () => {
  const ruleBase = {
    headword: "雨傘",
    targetName: "台湾華語",
    nl: "日本語",
    levelRule: "",
    sourceRule: "",
    chunkRoles: "N / V",
  };
  it("同じ返事に型を書く時: 数と順を型に合わせる（「数を合わせるために場面を作らない」は型が空の時だけ）", () => {
    const rule = examplePatternsRule({ ...ruleBase, max: 4, pairChunks: "same_reply" });
    expect(rule).toContain("例文の数は、同じ返事の usage_chunks（使い方の型）の数と同じにする");
    expect(rule).toContain("i 番目の例文は i 番目の型を使う");
    expect(rule).toContain("usage_chunks が空の時だけ");
  });
  it("今の型に合わせて例文だけを作り直す時: 型を番号付きで書く", () => {
    const rule = examplePatternsRule({
      ...ruleBase,
      max: 4,
      pairChunks: [
        { parts: [{ text: "帶" }, { text: "雨傘" }] },
        { parts: [{ text: "收" }, { text: "雨傘" }] },
      ],
    });
    expect(rule).toContain("1. 帶雨傘");
    expect(rule).toContain("2. 收雨傘");
    expect(rule).toContain("次の使い方の型（画面の①②③…）の数と同じにする");
    expect(rule).not.toContain("数を合わせるために場面を作らない");
  });
  it("型と対にしない呼び出し（型を頼まない・1つだけ）は今までの指示のまま", () => {
    expect(examplePatternsRule({ ...ruleBase, max: 4 })).toContain("数を合わせるために場面を作らない");
    expect(examplePatternsRule({ ...ruleBase, max: 1, pairChunks: "same_reply" })).toContain(
      "いちばんよく使うパターン1つだけ",
    );
  });
});
