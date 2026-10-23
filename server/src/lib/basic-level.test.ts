import { describe, expect, it } from "vitest";
import { basicLevelOf, ensureBasicLevel, entryForLabel } from "./basic-level";
import { finishPhotoCandidates, type ReadingCheck } from "./photo-candidates";
import { BASIC_LEVEL_RULE, objectLabelRule } from "./candidate-register";
import type { UiLang } from "./i18n";

/** 読みの検めは素通し（辞書を読まない）。 */
const keepReading: ReadingCheck = (_lang, _head, item) => item;

const finish = (items: Parameters<typeof finishPhotoCandidates>[0], reader: UiLang = "ja") =>
  finishPhotoCandidates(items, reader, "zh-TW", keepReading).map((c) => ({
    headword: c.headword,
    register: c.register,
    meaning: c.meaning_ja,
    tag: c.object_label,
    category: c.category_key,
  }));

describe("写真のタグは基本の名詞・1つ目はタグと同じ物（オーナー指示 2026-10-15）", () => {
  it("#184 の不具合の返事そのまま: ケーキの物に 草莓蛋糕 が1つだけ → 蛋糕 を一般的な言い方として足す", () => {
    // 本番 2026-10-15 10:03:49。AI は物 0 に 草莓蛋糕 だけを返し、タグは「ケーキ」。前はその意味を「ケーキ」に
    // 書き換え、候補が1つなので画面は選ばせずに 草莓蛋糕 をキャッチした（「ショートケーキが草莓蛋糕だよね」）。
    const out = finish([
      {
        headword: "草莓蛋糕",
        reading_zhuyin: "ㄘㄠˇ ㄇㄟˊ ㄉㄢˋ ㄍㄠ",
        pinyin: "cǎoméi dàngāo",
        meaning_ja: "いちごのショートケーキ",
        register: "common",
        label: "ケーキ",
        category_key: "dessert",
        group: 0,
      },
    ]);
    expect(out).toEqual([
      {
        headword: "蛋糕",
        register: "common",
        meaning: "ケーキ",
        tag: "ケーキ",
        category: "dessert",
      },
      {
        headword: "草莓蛋糕",
        register: "specific",
        meaning: "いちごのショートケーキ",
        tag: "ケーキ",
        category: "dessert",
      },
    ]);
  });

  it("コスモスの花束: タグは「花」、1つ目は 花、波斯菊 はより詳しい言い方で意味はそのまま", () => {
    const out = finish([
      {
        headword: "波斯菊",
        meaning_ja: "コスモス",
        register: "common",
        label: "コスモス",
        category_key: "other",
        group: 0,
      },
      { headword: "花束", meaning_ja: "花束", register: "specific", group: 0 },
      { headword: "花瓶", meaning_ja: "花瓶", register: "common", category_key: "other", group: 1 },
    ]);
    expect(out).toEqual([
      { headword: "花", register: "common", meaning: "花", tag: "花", category: "flower" },
      {
        headword: "波斯菊",
        register: "specific",
        meaning: "コスモス",
        tag: "花",
        category: "flower",
      },
      { headword: "花束", register: "specific", meaning: "花束", tag: "花", category: "flower" },
      // 花の入れ物は花ではない（分類も「その他」から直る）。
      {
        headword: "花瓶",
        register: "common",
        meaning: "花瓶",
        tag: "花瓶",
        category: "decoration",
      },
    ]);
  });

  it("花 が後ろに在れば先頭へ移す（足さない）", () => {
    const out = finish([
      { headword: "玫瑰", meaning_ja: "バラ", register: "common", group: 0 },
      { headword: "花", meaning_ja: "花", register: "specific", group: 0 },
    ]);
    expect(out.map((c) => [c.headword, c.register, c.tag])).toEqual([
      ["花", "common", "花"],
      ["玫瑰", "specific", "花"],
    ]);
  });

  it("ボクサーパンツ: 內褲 の意味に細かい名前が書かれていたら表の「下着」（タグも下着）。細かい語の意味は変えない", () => {
    const out = finish([
      {
        headword: "內褲",
        meaning_ja: "ボクサーパンツ",
        register: "common",
        label: "下着",
        group: 0,
      },
      { headword: "平口褲", meaning_ja: "ボクサーパンツ", register: "specific", group: 0 },
      { headword: "四角褲", meaning_ja: "トランクス", register: "specific", group: 0 },
    ]);
    expect(out.map((c) => [c.headword, c.register, c.meaning, c.tag])).toEqual([
      ["內褲", "common", "下着", "下着"],
      ["平口褲", "specific", "ボクサーパンツ", "下着"],
      ["四角褲", "specific", "トランクス", "下着"],
    ]);
  });

  it("柴犬・柯基 → 狗（タグ「犬」）。英語で読む人は dog", () => {
    expect(
      finish([{ headword: "柴犬", meaning_ja: "柴犬", register: "common", group: 0 }]).map((c) => [
        c.headword,
        c.register,
        c.tag,
      ]),
    ).toEqual([
      ["狗", "common", "犬"],
      ["柴犬", "specific", "犬"],
    ]);
    expect(
      finish(
        [{ headword: "柯基", meaning_ja: "corgi", register: "common", label: "dog", group: 0 }],
        "en",
      ).map((c) => [c.headword, c.tag]),
    ).toEqual([
      ["狗", "dog"],
      ["柯基", "dog"],
    ]);
  });

  it("もう基本の語が1つ目なら何もしない（意味もそのまま）", () => {
    const out = finish([
      { headword: "蛋糕", meaning_ja: "ケーキ", register: "common", label: "ケーキ", group: 0 },
      { headword: "草莓蛋糕", meaning_ja: "いちごのケーキ", register: "specific", group: 0 },
    ]);
    expect(out.map((c) => [c.headword, c.register, c.meaning, c.tag])).toEqual([
      ["蛋糕", "common", "ケーキ", "ケーキ"],
      ["草莓蛋糕", "specific", "いちごのケーキ", "ケーキ"],
    ]);
  });

  it("タグからも基本の語を引く（分類が同じ時だけ — 花瓶に「花」と付いても 花 を足さない）", () => {
    expect(
      finish([
        {
          headword: "提拉米蘇",
          meaning_ja: "ティラミス",
          register: "common",
          label: "ケーキ",
          category_key: "dessert",
          group: 0,
        },
      ]).map((c) => [c.headword, c.register, c.tag]),
    ).toEqual([
      ["蛋糕", "common", "ケーキ"],
      ["提拉米蘇", "specific", "ケーキ"],
    ]);
    expect(
      finish([
        {
          headword: "花瓶",
          meaning_ja: "花瓶",
          register: "common",
          label: "花",
          category_key: "decoration",
          group: 0,
        },
      ]).map((c) => [c.headword, c.tag]),
    ).toEqual([["花瓶", "花瓶"]]);
  });

  it("細かい名前ではない物は上げない（熱狗・熊貓・招財貓・雞蛋糕・輪椅・豆花・爆米花・拉花）", () => {
    for (const h of [
      "熱狗",
      "熊貓",
      "招財貓",
      "雞蛋糕",
      "輪椅",
      "豆花",
      "爆米花",
      "拉花",
      "花瓶",
    ]) {
      expect([h, basicLevelOf(h, "zh-TW")?.headword ?? null]).toEqual([h, null]);
    }
    for (const [h, basic] of [
      ["草莓蛋糕", "蛋糕"],
      ["鮮奶油蛋糕", "蛋糕"],
      ["波斯菊", "花"],
      ["滿天星", "花"],
      ["花束", "花"],
      ["柯基犬", "狗"],
      ["警犬", "狗"],
      ["波斯貓", "貓"],
      ["四角褲", "內褲"],
      ["木椅", "椅子"],
      ["抹茶麵包", "麵包"],
    ]) {
      expect([h, basicLevelOf(h, "zh-TW")?.headword]).toEqual([h, basic]);
    }
  });

  it("タグの細かい名前から基本の語を引く（パンケーキ・ホットケーキはケーキにしない）", () => {
    expect(entryForLabel("ストロベリーケーキ", "ja", "zh-TW")?.headword).toBe("蛋糕");
    expect(entryForLabel("ショートケーキ", "ja", "zh-TW")?.headword).toBe("蛋糕");
    expect(entryForLabel("ボクサーパンツ", "ja", "zh-TW")?.headword).toBe("內褲");
    expect(entryForLabel("コスモス", "ja", "zh-TW")?.headword).toBe("花");
    expect(entryForLabel("strawberry cake", "en", "zh-TW")?.headword).toBe("蛋糕");
    expect(entryForLabel("パンケーキ", "ja", "zh-TW")).toBeNull();
    expect(entryForLabel("ホットケーキ", "ja", "zh-TW")).toBeNull();
    expect(entryForLabel("ホットドッグ", "ja", "zh-TW")).toBeNull();
    expect(entryForLabel("hot dog", "en", "zh-TW")).toBeNull();
  });

  it("打った語の候補（物の番号が無い）と、表の無い学習言語には何もしない", () => {
    const typed = [{ headword: "草莓蛋糕", meaning_ja: "いちごのケーキ", register: "common" }];
    expect(ensureBasicLevel(typed, "zh-TW", "ja")).toEqual(typed);
    const en = [
      { headword: "strawberry cake", meaning_ja: "ケーキ", register: "common", group: 0 },
    ];
    expect(ensureBasicLevel(en, "en", "ja")).toEqual(en);
  });

  it("指示文: 1つ目は基本の名詞、タグは子どもが最初に言う名前（例つき）", () => {
    expect(BASIC_LEVEL_RULE).toMatch(/子どもでも最初に言う基本の名詞/);
    expect(BASIC_LEVEL_RULE).toMatch(/花 → 波斯菊・花束/);
    expect(BASIC_LEVEL_RULE).toMatch(/蛋糕 → 草莓蛋糕・鮮奶油蛋糕/);
    const rule = objectLabelRule("日本語");
    expect(rule).toMatch(/「花」（「コスモス」「花束」にしない）/);
    expect(rule).toMatch(/「ケーキ」（「ストロベリーケーキ」/);
    expect(rule).toMatch(/蛋糕 ↔ ケーキ/);
  });
});
