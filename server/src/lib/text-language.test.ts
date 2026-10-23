import { describe, it, expect } from "vitest";
import { looksLikeTargetLanguage } from "./text-language";

/**
 * オーナー報告 2026-08-26（絵つき）
 * 「学習言語英語なのに単語の詳細の例文が台湾華語で表示される」。
 *
 * 届いた絵の実物:
 *   ceiling → 「這間咖啡廳的 ceiling 很高，感覺很舒服。」
 *   hand    → 「我今天要考 TOCFL，我的手很緊張。」
 *
 * どちらも英語の語を中国語の文に埋めたもので、英語の例文ではない。
 */

describe("looksLikeTargetLanguage", () => {
  it("**英語の文に漢字が混ざっていたら英語ではない**（報告の実物）", () => {
    expect(looksLikeTargetLanguage("這間咖啡廳的 ceiling 很高，感覺很舒服。", "en")).toBe(false);
    expect(looksLikeTargetLanguage("我今天要考 TOCFL，我的手很緊張。", "en")).toBe(false);
    expect(looksLikeTargetLanguage("不要看著 ceiling，看著老師。", "en")).toBe(false);
  });

  it("本物の英語の文は通る（固有名詞が入っていても）", () => {
    expect(looksLikeTargetLanguage("Jay Chou can play the piano with his hands.", "en")).toBe(true);
    expect(looksLikeTargetLanguage("The ceiling in this cafe is really high.", "en")).toBe(true);
  });

  it("台湾華語の文は台湾華語として通る", () => {
    expect(looksLikeTargetLanguage("這間咖啡廳的天花板很高。", "zh-TW")).toBe(true);
    expect(looksLikeTargetLanguage("我想把房間的燈關掉。", "zh-TW")).toBe(true);
  });

  it("**英語の文を台湾華語の例文として出さない**（逆向きも守る）", () => {
    expect(looksLikeTargetLanguage("The ceiling is high.", "zh-TW")).toBe(false);
  });

  it("**かなの文はどちらでもない**（日本語の訳が例文の欄に入った場合）", () => {
    expect(looksLikeTargetLanguage("この部屋の天井は高いです。", "zh-TW")).toBe(false);
    expect(looksLikeTargetLanguage("この部屋の天井は高いです。", "en")).toBe(false);
    // 漢字を含む日本語も、台湾華語としては通ってしまう。ここは
    // 文字だけでは割れないので**通す**（落とすには根拠が要る）。
    expect(looksLikeTargetLanguage("天井が高い", "zh-TW")).toBe(false);
  });

  it("**判定できないものは通す**（正しい中身まで消さない）", () => {
    for (const s of ["", "   ", "123", "!!!", "…", null, undefined]) {
      expect(looksLikeTargetLanguage(s, "en"), String(s)).toBe(true);
      expect(looksLikeTargetLanguage(s, "zh-TW"), String(s)).toBe(true);
    }
  });

  it("知らない言語は既定に均してから見る", () => {
    expect(looksLikeTargetLanguage("這是中文。", null)).toBe(true);
    expect(looksLikeTargetLanguage("This is English.", null)).toBe(false);
  });
});
