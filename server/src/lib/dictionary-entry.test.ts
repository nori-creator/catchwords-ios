import { describe, it, expect } from "vitest";
import { DICTIONARY_SELECT, resolveDictionaryFields, usesLegacyColumns } from "./dictionary-entry";

/**
 * **辞書だけでカードを出す道**（AI を1回も呼ばない道）の入口。
 *
 * ここが壊れていると、辞書に在る語でも毎回 AI を待つことになる —
 * オーナーが「最大のペイン」と書いた「一瞬でも早く」の反対側。
 * しかも英語では**読みも意味も空**で返っていたので、道そのものが
 * 死んでいた。
 */

const ZH = {
  zhuyin: "ㄐㄧㄠˇ ㄊㄚˋ ㄔㄜ",
  pinyin: "jiǎo tà chē",
  meaning_ja: "自転車",
  tocfl_level: 2,
  reading_primary: "ㄐㄧㄠˇ ㄊㄚˋ ㄔㄜ",
  reading_alt: "jiǎo tà chē",
  meanings: { ja: "自転車" },
  level_step: 2,
};

/** 英語の行。**古い列は空**（`admin.functions.ts` がそう書く）。 */
const EN = {
  zhuyin: null,
  pinyin: null,
  meaning_ja: null,
  tocfl_level: null,
  reading_primary: "ˈbaɪsɪkəl",
  reading_alt: "ˈbaisikl",
  meanings: { "zh-TW": "腳踏車" },
  level_step: 2,
};

describe("resolveDictionaryFields", () => {
  it("**英語の行から読みと意味が出る**(前はどちらも空だった)", () => {
    const got = resolveDictionaryFields(EN, "zh-TW");
    expect(got.reading).toBe("ˈbaɪsɪkəl");
    expect(got.readingAlt).toBe("ˈbaisikl");
    expect(got.meaning).toBe("腳踏車");
    expect(got.levelStep).toBe(2);
  });

  it("台湾華語の行はこれまでどおり", () => {
    const got = resolveDictionaryFields(ZH, "ja");
    expect(got.reading).toBe("ㄐㄧㄠˇ ㄊㄚˋ ㄔㄜ");
    expect(got.meaning).toBe("自転車");
    expect(got.levelStep).toBe(2);
  });

  it("**古い列しか無い行も読める**(移行の前に入った行)", () => {
    const got = resolveDictionaryFields(
      { zhuyin: "ㄕㄡˇ", pinyin: "shǒu", meaning_ja: "手", tocfl_level: 1 },
      "ja",
    );
    expect(got.reading).toBe("ㄕㄡˇ");
    expect(got.readingAlt).toBe("shǒu");
    expect(got.meaning).toBe("手");
    expect(got.levelStep).toBe(1);
  });

  it("**合う言語が無ければ意味を返さない**(違う言語の語釈を出さない)", () => {
    // 日本語の人に中文の語釈を出すのは「無いよりまし」ではなく間違い。
    expect(resolveDictionaryFields(EN, "ja").meaning).toBe("");
    expect(resolveDictionaryFields(EN, "en").meaning).toBe("");
  });

  it("`meaning_ja` は**読む人が日本語のときだけ**の受け皿", () => {
    const row = { meaning_ja: "自転車", meanings: {} };
    expect(resolveDictionaryFields(row, "ja").meaning).toBe("自転車");
    expect(resolveDictionaryFields(row, "zh-TW").meaning).toBe("");
  });

  it("**級外は `null`**(0 を段として扱わない)", () => {
    for (const bad of [null, undefined, 0, 7, -1, 2.5, Number.NaN]) {
      const got = resolveDictionaryFields({ level_step: bad as never }, "ja");
      expect(got.levelStep, String(bad)).toBeNull();
    }
  });

  it("空白だけの値は無いものとして扱う", () => {
    const got = resolveDictionaryFields(
      { reading_primary: "   ", zhuyin: "ㄕㄡˇ", meanings: { ja: "  " }, meaning_ja: "手" },
      "ja",
    );
    expect(got.reading).toBe("ㄕㄡˇ");
    expect(got.meaning).toBe("手");
  });

  it("何も無い行で落ちない", () => {
    const got = resolveDictionaryFields({}, "ja");
    expect(got).toEqual({ reading: null, readingAlt: null, meaning: "", levelStep: null });
  });
});

describe("DICTIONARY_SELECT", () => {
  it("**新しい列が入っている**(ここを落とすと英語が丸ごと空で返る)", () => {
    for (const col of ["reading_primary", "reading_alt", "meanings", "level_step"]) {
      expect(DICTIONARY_SELECT.includes(col), col).toBe(true);
    }
  });

  it("古い列も残っている(移行の前に入った行のため)", () => {
    for (const col of ["zhuyin", "pinyin", "meaning_ja", "tocfl_level"]) {
      expect(DICTIONARY_SELECT.includes(col), col).toBe(true);
    }
  });
});

describe("usesLegacyColumns", () => {
  it("古い列に中身があるのは既定の言語だけ", () => {
    expect(usesLegacyColumns("zh-TW")).toBe(true);
    expect(usesLegacyColumns("en")).toBe(false);
  });
});
