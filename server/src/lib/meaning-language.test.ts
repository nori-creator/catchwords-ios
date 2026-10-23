import { describe, expect, it } from "vitest";
import { fitsReaderLanguage, keepReaderLanguage, quizMeaningLanguage } from "./meaning-language";
import { FALLBACK_MEANINGS_BY_LANG, pickDistractors } from "./quiz-choices";

describe("fitsReaderLanguage", () => {
  it("英語で読む人には、かな・漢字の入った意味を出さない", () => {
    expect(fitsReaderLanguage("tissue", "en")).toBe(true);
    expect(fitsReaderLanguage("ティッシュ", "en")).toBe(false);
    expect(fitsReaderLanguage("鶏肉", "en")).toBe(false);
  });

  it("日本語で読む人には、英語だけの意味と長い漢字だけの文を出さない", () => {
    expect(fitsReaderLanguage("ティッシュ", "ja")).toBe(true);
    expect(fitsReaderLanguage("鶏肉", "ja")).toBe(true); // 漢字だけの短い和語は通す
    expect(fitsReaderLanguage("Tシャツ", "ja")).toBe(true);
    expect(fitsReaderLanguage("tissue", "ja")).toBe(false);
    expect(fitsReaderLanguage("用來擦嘴巴的紙巾", "ja")).toBe(false);
  });

  it("繁體中文で読む人には、かなと英語だけの意味を出さない", () => {
    expect(fitsReaderLanguage("面紙", "zh-TW")).toBe(true);
    expect(fitsReaderLanguage("ティッシュ", "zh-TW")).toBe(false);
    expect(fitsReaderLanguage("tissue", "zh-TW")).toBe(false);
  });

  it("判定できない物（空・数字・記号）は落とさない", () => {
    for (const r of ["ja", "en", "zh-TW"] as const) {
      expect(fitsReaderLanguage("", r)).toBe(true);
      expect(fitsReaderLanguage("100", r)).toBe(true);
    }
  });
});

describe("quizMeaningLanguage", () => {
  it("正解が読み手の言語なら、読み手の言語で揃える", () => {
    expect(quizMeaningLanguage("tissue", "en")).toBe("en");
    expect(quizMeaningLanguage("ティッシュ", "ja")).toBe("ja");
  });

  it("正解が古い別の言語なら、正解の言語で揃える（1つだけ違う言語で当たらないように）", () => {
    expect(quizMeaningLanguage("ティッシュ", "en")).toBe("ja");
    expect(quizMeaningLanguage("tissue", "ja")).toBe("en");
  });
});

describe("4択の誤答が1つの言語に揃う", () => {
  it("英語の人: 日本語の誤答と日本語の受け皿を使わない", () => {
    const reader = "en" as const;
    const lang = quizMeaningLanguage("chicken", reader);
    const fit = (xs: string[]) => xs.filter((x) => fitsReaderLanguage(x, lang));
    const picked = pickDistractors("chicken", [
      fit(["ティッシュ", "remote control"]),
      fit(["鶏肉の皮"]),
      FALLBACK_MEANINGS_BY_LANG[lang],
    ]);
    expect(picked).toHaveLength(3);
    for (const p of picked) expect(fitsReaderLanguage(p, "en")).toBe(true);
  });

  it("受け皿はどの言語も4つあり、その言語の文字で書かれている", () => {
    for (const lang of ["ja", "en", "zh-TW"] as const) {
      expect(FALLBACK_MEANINGS_BY_LANG[lang]).toHaveLength(4);
      for (const m of FALLBACK_MEANINGS_BY_LANG[lang])
        expect(fitsReaderLanguage(m, lang)).toBe(true);
    }
  });
});

describe("keepReaderLanguage", () => {
  it("解説の注記が別の言語なら空にする", () => {
    expect(keepReaderLanguage("よく一緒に使う", "en")).toBe("");
    expect(keepReaderLanguage("often used together", "en")).toBe("often used together");
    expect(keepReaderLanguage(null, "ja")).toBe("");
  });
});
