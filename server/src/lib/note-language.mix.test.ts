import { describe, expect, it } from "vitest";
import { looksLikeTargetNote, looksWrongForReader, readerMeaning } from "./note-language";
import { fitsReaderMeaning } from "./first-catch-meaning";

// 点検 T42・T43・T44（2026-11-03）。iOS の ios/LanguageRules/cases.json の L-mix-* と同じ文。
describe("英字の混じる中文の注記を、日本語の読者に出さない（T42）", () => {
  for (const t of ["很多人用LINE傳訊息給朋友", "在7-ELEVEN也買得到這種飲料", "台灣人喜歡點QQ的珍珠"]) {
    it(t, () => {
      expect(looksLikeTargetNote(t, "ja")).toBe(true);
      expect(looksWrongForReader(t, "ja")).toBe(true);
    });
  }
  it("英語の文は判定しない（英字が漢字以上）", () => {
    expect(looksLikeTargetNote("Use LINE to send 訊息", "ja")).toBe(false);
  });
  it("和文は残す", () => {
    expect(looksWrongForReader("LINEでメッセージを送る", "ja")).toBe(false);
  });
});

describe("漢字だけの正しい日本語の意味は残す（T43）", () => {
  for (const t of ["自動販売機", "空気清浄機", "携帯充電器", "台湾高速鉄道"]) {
    it(t, () => {
      expect(readerMeaning(t, "ja")).toBe(t);
      expect(fitsReaderMeaning(t, "ja")).toBe(true);
    });
  }
});

describe("中文・韓国語の意味を日本語の読者に出さない（T44）", () => {
  for (const t of ["一種台灣的手搖飲料", "台灣常見的熱帶水果"]) {
    it(t, () => {
      expect(readerMeaning(t, "ja")).toBe("");
      expect(fitsReaderMeaning(t, "ja")).toBe(false);
    });
  }
  it("망고", () => expect(fitsReaderMeaning("망고", "ja")).toBe(false));
});
