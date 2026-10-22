import { describe, expect, it } from "vitest";
import { readSentence } from "./sentence-readings.server";

const pinyinOf = (s: string, known?: Array<{ text: string; pinyin: string }>) =>
  readSentence(s, known).map((u) => u.pinyin ?? "·");
const zhuyinOf = (s: string) => readSentence(s).map((u) => u.zhuyin ?? "·");

describe("readSentence（例文の字ごとの読み）", () => {
  it("every Han character gets a reading; punctuation, letters and digits none", () => {
    const units = readSentence("我買了T恤和3C產品。");
    expect(units.map((u) => u.char).join("")).toBe("我買了T恤和3C產品。");
    for (const u of units) {
      const han = /\p{Script=Han}/u.test(u.char);
      expect(!!u.pinyin).toBe(han);
      expect(!!u.zhuyin).toBe(han);
    }
  });

  it("reads polyphones by their neighbours", () => {
    expect(pinyinOf("我還沒吃飯")[1]).toBe("hái");
    expect(pinyinOf("他去銀行")[3]).toBe("háng");
  });

  it("uses Taiwan's readings", () => {
    expect(pinyinOf("把垃圾丟掉").slice(1, 3)).toEqual(["lè", "sè"]);
    expect(pinyinOf("星期天")[1]).toBe("qí");
  });

  it("writes zhuyin from the same syllables, the neutral tone first", () => {
    expect(zhuyinOf("小孩子用湯匙吃飯。")).toEqual([
      "ㄒㄧㄠˇ",
      "ㄏㄞˊ",
      "˙ㄗ",
      "ㄩㄥˋ",
      "ㄊㄤ",
      "ㄔˊ",
      "ㄔ",
      "ㄈㄢˋ",
      "·",
    ]);
  });

  it("the card's own readings win where the word stands in the sentence", () => {
    expect(pinyinOf("這個湯匙很好用", [{ text: "湯匙", pinyin: "tāng shi" }]).slice(2, 4)).toEqual([
      "tāng",
      "shi",
    ]);
  });

  it("an empty sentence has no units", () => {
    expect(readSentence("")).toEqual([]);
  });
});
