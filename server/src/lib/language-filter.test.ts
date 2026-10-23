import { describe, expect, it } from "vitest";
import { wordLanguageFilter, matchesTargetLanguage } from "./language-filter";
import { DEFAULT_TARGET_LANGUAGE, TARGET_LANGUAGES } from "./target-lang";

describe("wordLanguageFilter", () => {
  it("既定の言語では、空の行も一緒に見える", () => {
    // 既存の150語は `language` が空の可能性がある。ここを外すと
    // 台湾華語を学んでいる人の図鑑が丸ごと消える。
    expect(wordLanguageFilter("zh-TW")).toBe("language.eq.zh-TW,language.is.null");
  });

  it("英語では空の行を**入れない**(混ぜない)", () => {
    expect(wordLanguageFilter("en")).toBe("language.eq.en");
    expect(wordLanguageFilter("en")).not.toContain("is.null");
  });

  it("知らない値は既定に落とす", () => {
    expect(wordLanguageFilter("zh-CN")).toBe(wordLanguageFilter(DEFAULT_TARGET_LANGUAGE));
    expect(wordLanguageFilter(null)).toBe(wordLanguageFilter(DEFAULT_TARGET_LANGUAGE));
    expect(wordLanguageFilter(undefined)).toBe(wordLanguageFilter(DEFAULT_TARGET_LANGUAGE));
    expect(wordLanguageFilter("")).toBe(wordLanguageFilter(DEFAULT_TARGET_LANGUAGE));
  });

  it("どの学習言語でも壊れた条件を作らない", () => {
    for (const lang of TARGET_LANGUAGES) {
      const f = wordLanguageFilter(lang);
      // `or` の項は「列.演算子.値」の形。項の数だけ確かめる。
      for (const part of f.split(",")) {
        expect(part, `${lang}: ${part}`).toMatch(/^language\.(eq\.[\w-]+|is\.null)$/);
      }
    }
  });
});

describe("matchesTargetLanguage", () => {
  it("DB の条件と同じ答えを出す — 既定の言語", () => {
    expect(matchesTargetLanguage("zh-TW", "zh-TW")).toBe(true);
    expect(matchesTargetLanguage(null, "zh-TW")).toBe(true);
    expect(matchesTargetLanguage("", "zh-TW")).toBe(true);
    expect(matchesTargetLanguage("  ", "zh-TW")).toBe(true);
    expect(matchesTargetLanguage("en", "zh-TW")).toBe(false);
  });

  it("DB の条件と同じ答えを出す — 英語", () => {
    expect(matchesTargetLanguage("en", "en")).toBe(true);
    expect(matchesTargetLanguage("zh-TW", "en")).toBe(false);
    // **空を英語として数えない。** ここが DB 側の `is.null` を
    // 入れていないことと対になっている。
    expect(matchesTargetLanguage(null, "en")).toBe(false);
    expect(matchesTargetLanguage("", "en")).toBe(false);
  });

  it("2つの規則が食い違っていない", () => {
    // 「DB の条件に `is.null` が在る ⇔ 空の行を通す」が
    // どの言語でも一致していること。片方だけ直る事故を潰す。
    for (const lang of TARGET_LANGUAGES) {
      const dbAllowsNull = wordLanguageFilter(lang).includes("language.is.null");
      expect(matchesTargetLanguage(null, lang), lang).toBe(dbAllowsNull);
    }
  });
});
