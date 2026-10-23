import { describe, expect, it } from "vitest";
import {
  fitCardToReader,
  fitLessonToReader,
  fitSuggestionsToReader,
  fitsReaderMeaning,
  fitsReaderNote,
  misfitHeadwords,
  readerMeaning,
} from "./first-catch-meaning";

describe("first-catch meanings in the display language", () => {
  it("zh-TW UI × en target: Japanese meanings are replaced from the dictionary or blanked", () => {
    // 実物確認 2026-10-03（run 37105477674、WebKit）で出た「flower 花。植物の生殖器官。」。
    const items = [
      { headword: "flower", meaning_ja: "花。植物の生殖器官。", distinction: "" },
      { headword: "latte", meaning_ja: "拿鐵（一種咖啡飲料）", distinction: "" },
      { headword: "cup", meaning_ja: "カップ", distinction: "取っ手のある器" },
    ];
    expect(misfitHeadwords(items, "zh-TW")).toEqual(["flower", "cup"]);
    const fitted = fitSuggestionsToReader(items, "zh-TW", "en", new Map([["flower", "花"]]));
    expect(fitted.map((s) => s.meaning_ja)).toEqual(["花", "拿鐵（一種咖啡飲料）", ""]);
    expect(fitted[2].distinction).toBe("");
  });

  it("never substitutes a dictionary meaning that is itself in another language", () => {
    expect(readerMeaning("はな", "zh-TW", "はな（花）")).toBe("");
    expect(readerMeaning("flower", "ja", "flower")).toBe("");
  });

  it("does not blank Japanese kanji-only meanings for a Japanese reader", () => {
    expect(fitsReaderMeaning("自動販売機", "ja")).toBe(true);
    expect(fitsReaderMeaning("coffee", "ja")).toBe(false);
    expect(fitsReaderMeaning("拿鐵", "en")).toBe(false);
    expect(fitsReaderMeaning("coffee", "en")).toBe(true);
  });

  it("notes may quote the target word, but a whole note in another language is dropped", () => {
    expect(fitsReaderNote("Say 咖啡 when ordering.", "en", "zh-TW")).toBe(true);
    expect(fitsReaderNote("注文する時に使う", "en", "zh-TW")).toBe(false);
    expect(fitsReaderNote("點餐時說 latte", "zh-TW", "en")).toBe(true);
    expect(fitsReaderNote("注文する時に使う", "zh-TW", "en")).toBe(false);
  });

  it("card: meaning, translation and usage-chunk translations follow the reader", () => {
    const card = fitCardToReader(
      {
        headword_zh: "flower",
        meaning_ja: "はな",
        example_translation: "彼女は花を摘んだ。",
        extras: { usage_chunks: [{ parts: [], ja: "一輪の花を" }], examples_extra: [] },
      },
      "zh-TW",
      "en",
      "花",
    );
    expect(card.meaning_ja).toBe("花");
    expect(card.example_translation).toBe("");
    expect((card.extras as { usage_chunks: Array<{ ja: string }> }).usage_chunks[0].ja).toBe("");
  });

  it("lesson: Japanese senses are dropped; none left → null", () => {
    const jp = {
      senses: [{ meaning: "植物の花", note: "" }],
      examples: [{ sentence: "A flower.", translation: "花です", situation: "", explanation: "" }],
    };
    expect(fitLessonToReader(jp, "zh-TW", "en")).toBeNull();
    const ok = fitLessonToReader(
      { ...jp, senses: [{ meaning: "植物的花", note: "" }, ...jp.senses] },
      "zh-TW",
      "en",
    );
    expect(ok?.senses).toEqual([{ meaning: "植物的花", note: "" }]);
    expect(ok?.examples[0].translation).toBe("");
  });
});
