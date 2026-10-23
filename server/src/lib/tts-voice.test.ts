import { describe, expect, it } from "vitest";
import { ttsVoiceFor, withVoiceOverride } from "./tts-voice";
import { DEFAULT_TARGET_LANGUAGE, TARGET_LANGUAGES } from "./target-lang";

/**
 * 守っているのは「**英語の語が台湾華語の声で読まれない**」こと。
 *
 * 読み上げは目で見えないので、絵の検査では捕まらない。しかも
 * `instructions` に「大陸の発音にするな」と書いてあるまま英語を流すと、
 * モデルは英語を中国語として読もうとする。
 */

describe("ttsVoiceFor", () => {
  it("**選べる学習言語には全部、声が用意されている**", () => {
    for (const lang of TARGET_LANGUAGES) {
      const v = ttsVoiceFor(lang);
      expect(v.googleLanguageCode, lang).toBeTruthy();
      expect(v.googleVoice, lang).toBeTruthy();
      expect(v.instructions.trim(), lang).not.toBe("");
    }
  });

  it("**言語ごとに違う声**(全部同じなら分ける意味が無い)", () => {
    const codes = TARGET_LANGUAGES.map((l) => ttsVoiceFor(l).googleLanguageCode);
    expect(new Set(codes).size).toBe(TARGET_LANGUAGES.length);
    const voices = TARGET_LANGUAGES.map((l) => ttsVoiceFor(l).googleVoice);
    expect(new Set(voices).size).toBe(TARGET_LANGUAGES.length);
  });

  it("台湾華語は `cmn-TW`(`zh-TW` では Google に通らない)", () => {
    expect(ttsVoiceFor(DEFAULT_TARGET_LANGUAGE).googleLanguageCode).toBe("cmn-TW");
  });

  it("英語はアメリカ英語(オーナー決定 2026-08-24)", () => {
    expect(ttsVoiceFor("en").googleLanguageCode).toBe("en-US");
    expect(ttsVoiceFor("en").instructions).toContain("American English");
  });

  it("**英語の指示に中国語の話が混ざっていない**", () => {
    const text = ttsVoiceFor("en").instructions;
    for (const word of ["Mandarin", "Taiwan", "zh-TW", "Chinese"]) {
      expect(text.includes(word), `英語の指示に「${word}」`).toBe(false);
    }
  });

  it("**台湾華語の指示に英語の話が混ざっていない**", () => {
    const text = ttsVoiceFor(DEFAULT_TARGET_LANGUAGE).instructions;
    expect(text.includes("American")).toBe(false);
  });

  it("知らない値は既定に落とす(未知のコードを合成に渡さない)", () => {
    // `"ja"` は 2026-10-01 から学習言語なので、知らない値の例は `"ko"` にした。
    for (const bad of [null, undefined, "", "  ", "kl-GL", "ko"]) {
      expect(ttsVoiceFor(bad), String(bad)).toEqual(ttsVoiceFor(DEFAULT_TARGET_LANGUAGE));
    }
  });
});

describe("withVoiceOverride — 環境変数の差し替え", () => {
  const zh = ttsVoiceFor(DEFAULT_TARGET_LANGUAGE);
  const en = ttsVoiceFor("en");

  it("既定の言語には効く", () => {
    expect(withVoiceOverride(zh, DEFAULT_TARGET_LANGUAGE, "cmn-TW-Wavenet-C").googleVoice).toBe(
      "cmn-TW-Wavenet-C",
    );
  });

  it("**他の言語には効かない**(台湾華語の声を変えたつもりで英語まで中国語にしない)", () => {
    expect(withVoiceOverride(en, "en", "cmn-TW-Wavenet-C").googleVoice).toBe(en.googleVoice);
  });

  it("差し替えが無ければそのまま", () => {
    expect(withVoiceOverride(zh, DEFAULT_TARGET_LANGUAGE, undefined)).toEqual(zh);
    expect(withVoiceOverride(zh, DEFAULT_TARGET_LANGUAGE, "")).toEqual(zh);
  });

  it("言語コードは差し替えない(声だけ)", () => {
    expect(withVoiceOverride(zh, DEFAULT_TARGET_LANGUAGE, "x").googleLanguageCode).toBe(
      zh.googleLanguageCode,
    );
  });
});
