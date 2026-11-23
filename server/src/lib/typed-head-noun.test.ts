import { describe, expect, it } from "vitest";
import {
  dropLeadingSyllables,
  headNounOf,
  measureRepeatsHeadword,
  toHeadNoun,
  TYPED_HEAD_NOUN_RULE,
} from "./typed-head-noun";

describe("headNounOf — 句の頭の数・量詞を外す（2026-11-23 一杯のコーヒー）", () => {
  it.each([
    ["一杯咖啡", "咖啡", "一杯"],
    ["兩顆蘋果", "蘋果", "兩顆"],
    ["這杯咖啡", "咖啡", "這杯"],
    ["那三瓶可樂", "可樂", "那三瓶"],
    ["一杯的咖啡", "咖啡", "一杯的"],
    ["半顆西瓜", "西瓜", "半顆"],
    ["十個饅頭", "饅頭", "十個"],
  ])("%s → %s", (input, head, stripped) => {
    expect(headNounOf(input)).toEqual({ headword: head, stripped });
  });

  it.each([
    "咖啡",
    "珍珠奶茶",
    "雨傘",
    "滾筒黏毛器",
    "三明治", // 明 は量詞でない
    "五花肉",
    "九層塔",
    "四季豆",
    "八寶粥",
    "十字路口",
    "千層麵", // 千 は数に入れない
    "百香果",
    "一杯", // 外すと何も残らない
    "一本書", // 残りが1字 — 書 は AI の指示に任せる
    "杯子", // 数が無い
    "杯墊",
    "這咖啡", // 量詞が無い
    "一般", // 量詞が無い
  ])("%s は割らない", (w) => {
    expect(headNounOf(w)).toEqual({ headword: w, stripped: "" });
  });
});

describe("toHeadNoun — 読みも外した字数ぶん外す", () => {
  it("本番の 一杯咖啡 の候補（読みは AI の返事のまま）", () => {
    const c = toHeadNoun({
      headword: "一杯咖啡",
      reading_zhuyin: "ㄧ ㄅㄟ ㄎㄚ ㄈㄟ",
      pinyin: "yī bēi kāfēi",
      meaning_ja: "a cup of coffee",
    });
    expect(c.headword).toBe("咖啡");
    expect(c.reading_zhuyin).toBe("ㄎㄚ ㄈㄟ");
    expect(c.pinyin).toBe("kāfēi");
    expect(c.meaning_ja).toBe("a cup of coffee"); // 意味はここでは触らない（行の意味の確かめが後で整える）
  });

  it("「的」も1音（一杯的咖啡 → 3音外す）", () => {
    const c = toHeadNoun({ headword: "一杯的咖啡", reading_zhuyin: "ㄧ ㄅㄟ ˙ㄉㄜ ㄎㄚ ㄈㄟ", pinyin: "yī bēi de kāfēi" });
    expect(c.headword).toBe("咖啡");
    expect(c.reading_zhuyin).toBe("ㄎㄚ ㄈㄟ");
    expect(c.pinyin).toBe("kāfēi");
  });

  it("割らない語はそのまま（同じ物を返す）", () => {
    const c = { headword: "珍珠奶茶", reading_zhuyin: "ㄓㄣ ㄓㄨ ㄋㄞˇ ㄔㄚˊ", pinyin: "zhēnzhū nǎichá" };
    expect(toHeadNoun(c)).toBe(c);
  });

  it("音が足りない時は空（後で埋める）", () => {
    expect(dropLeadingSyllables("yībēi", 2)).toBe("");
    expect(dropLeadingSyllables("yī bēi kāfēi", 0)).toBe("yī bēi kāfēi");
  });
});

describe("量詞の欄で量を二重にしない（オーナー 2026-11-23「一杯 杯咖啡」）", () => {
  it("物の名前を見出し語にすれば、量詞の欄は 一杯 + 咖啡 で一杯咖啡", () => {
    const head = toHeadNoun({ headword: "一杯咖啡", reading_zhuyin: "", pinyin: "" }).headword;
    const measure = "一杯";
    expect(measure + head).toBe("一杯咖啡");
    expect(measureRepeatsHeadword(measure, head)).toBe(false);
  });

  it("古い語（見出し語が 一杯咖啡 のまま）は量が重なると分かる", () => {
    expect(measureRepeatsHeadword("一杯", "一杯咖啡")).toBe(true);
    expect(measureRepeatsHeadword("杯", "一杯咖啡")).toBe(true);
    expect(measureRepeatsHeadword("一壺", "一杯咖啡")).toBe(false);
    expect(measureRepeatsHeadword("一杯", "咖啡")).toBe(false);
  });
});

describe("指示文", () => {
  it("句を見出し語にしないことと、定着した語を割らないことを書く", () => {
    expect(TYPED_HEAD_NOUN_RULE).toContain("一杯のコーヒー");
    expect(TYPED_HEAD_NOUN_RULE).toContain("咖啡");
    expect(TYPED_HEAD_NOUN_RULE).toContain("珍珠奶茶");
  });
});
