import { describe, expect, it } from "vitest";
import { checkTaiwanReading } from "./tw-reading.server";
import { readSentence } from "./sentence-readings.server";

// 点検 S4（2026-11-03）: 台湾の読みを辞書が大陸の読みに書き換えていた語。AI が台湾の読みを書いたら、そのまま残す。
const KEEP: Array<[string, string]> = [
  ["阿嬤", "ā mà"],
  ["夕陽", "xì yáng"],
  ["研究", "yán jiù"],
  ["廣播", "guǎng bò"],
  ["叔叔", "shú shu"],
  ["成績", "chéng jī"],
  ["突然", "tú rán"],
  ["可惜", "kě xí"],
  ["傍晚", "bāng wǎn"],
  ["和", "hàn"],
  ["咖哩", "gā lǐ"],
  ["乾麵", "gān miàn"],
  ["消息", "xiāo xí"],
  ["古蹟", "gǔ jī"],
];

describe("台湾の読みを大陸の読みに書き換えない", () => {
  for (const [word, py] of KEEP) {
    it(`${word} ${py}`, () => {
      const r = checkTaiwanReading(word, py, "");
      expect(r.pinyin).toBe(py);
      expect(r.fixed).not.toContain("pinyin");
    });
  }
});

describe("AI が大陸の読みを書いたら台湾の読みに直す", () => {
  const CASES: Array<[string, string, string]> = [
    ["夕陽", "xī yáng", "xì yáng"],
    ["研究", "yán jiū", "yán jiù"],
    ["廣播", "guǎng bō", "guǎng bò"],
    ["成績", "chéng jì", "chéng jī"],
    ["突然", "tū rán", "tú rán"],
    ["可惜", "kě xī", "kě xí"],
    ["阿嬤", "ā mó", "ā mà"],
    ["傍晚", "bàng wǎn", "bāng wǎn"],
    ["乾麵", "gàn miàn", "gān miàn"],
  ];
  for (const [word, ai, want] of CASES) {
    it(`${word}: ${ai} → ${want}`, () => {
      expect(checkTaiwanReading(word, ai, "").pinyin).toBe(want);
    });
  }
});

describe("例文の読みも台湾の読み", () => {
  const read = (s: string) => readSentence(s).map((u) => u.pinyin ?? "").join(" ").trim();
  it("研究・廣播・成績・夕陽", () => {
    expect(read("我在研究")).toContain("jiù");
    expect(read("廣播說")).toContain("bò");
    expect(read("成績很好")).toContain("jī");
    expect(read("夕陽很美")).toContain("xì");
  });
  it("乾麵 は gān", () => {
    expect(readSentence("我要乾麵")[2].pinyin).toBe("gān");
  });
});

describe("軽声は残す", () => {
  it("叔叔 の2字目", () => {
    expect(readSentence("我叔叔")[2].pinyin).toBe("shu");
  });
});

describe("例文の読みの直し（点検 S10・S5・M35、決定 10B）", () => {
  const p = (s: string, known?: Array<{ text: string; pinyin: string }>) =>
    readSentence(s, known).map((u) => u.pinyin ?? "·").join(" ");
  const CASES: Array<[string, string]> = [
    ["他長得很高", "tā zhǎng de hěn gāo"],
    ["我要包子", "wǒ yào bāo zi"],
    ["這雙鞋子", "zhè shuāng xié zi"],
    ["我睡不著", "wǒ shuì bù zháo"],
    ["慢慢地走", "màn màn de zǒu"],
    ["我買洗髮精", "wǒ mǎi xǐ fǎ jīng"],
    ["你幹嘛", "nǐ gàn má"],
    ["好啦", "hǎo la"],
    ["我得去上班", "wǒ děi qù shàng bān"],
    ["他得到獎", "tā dé dào jiǎng"],
    ["還書", "huán shū"],
    ["我還沒吃", "wǒ hái méi chī"],
    ["一個人", "yī gè rén"],
    ["不要", "bù yào"],
    ["頭髮", "tóu fǎ"],
    ["了解", "liǎo jiě"],
  ];
  for (const [s, want] of CASES) it(s, () => expect(p(s)).toBe(want));
  it("1字の見出しの読みを、読みが複数ある字には当てない", () => {
    expect(p("我還沒吃", [{ text: "還", pinyin: "huán" }])).toBe("wǒ hái méi chī");
    expect(p("了解", [{ text: "了", pinyin: "le" }])).toBe("liǎo jiě");
  });
});
