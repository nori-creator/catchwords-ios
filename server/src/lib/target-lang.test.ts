import { describe, it, expect } from "vitest";
import fs from "node:fs";
import path from "node:path";
import {
  TARGET_LANGUAGES,
  DEFAULT_TARGET_LANGUAGE,
  normalizeTargetLanguage,
  speechLangOf,
  MAP_DISPLAY_LANGUAGE,
} from "./target-lang";

describe("normalizeTargetLanguage", () => {
  it("知っている言語はそのまま", () => {
    for (const l of TARGET_LANGUAGES) expect(normalizeTargetLanguage(l)).toBe(l);
  });

  it("**知らない値は既定に落とす**(未知の言語で黙って動かさない)", () => {
    expect(normalizeTargetLanguage("en-US")).toBe(DEFAULT_TARGET_LANGUAGE);
    expect(normalizeTargetLanguage("zh-CN")).toBe(DEFAULT_TARGET_LANGUAGE);
    expect(normalizeTargetLanguage("")).toBe(DEFAULT_TARGET_LANGUAGE);
    expect(normalizeTargetLanguage(null)).toBe(DEFAULT_TARGET_LANGUAGE);
    expect(normalizeTargetLanguage(undefined)).toBe(DEFAULT_TARGET_LANGUAGE);
  });

  it("前後の空白は落とす", () => {
    expect(normalizeTargetLanguage("  zh-TW ")).toBe("zh-TW");
  });

  it("既定は必ず一覧の中にある", () => {
    expect(TARGET_LANGUAGES).toContain(DEFAULT_TARGET_LANGUAGE);
  });
});

describe("speechLangOf", () => {
  it("引数なしでも既定を返す", () => {
    expect(speechLangOf()).toBe(DEFAULT_TARGET_LANGUAGE);
  });

  it("壊れた値でも読み上げが止まらない", () => {
    expect(speechLangOf("こわれた")).toBe(DEFAULT_TARGET_LANGUAGE);
  });
});

describe("MAP_DISPLAY_LANGUAGE", () => {
  /**
   * **学習言語と別に持つことが要点。** 同じ定数にまとめてしまうと、
   * 英語版を足したときに「士林夜市」が "Shilin Night Market" に化ける。
   * 地名はその場所の名前なので、学ぶ言語に付いていってはいけない。
   */
  it("地図の言語は台湾の地名が返る言語で固定", () => {
    expect(MAP_DISPLAY_LANGUAGE).toBe("zh-TW");
  });
});
