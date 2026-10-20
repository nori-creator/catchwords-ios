import { describe, expect, it } from "vitest";
import { readerL1 } from "./reader-language";
import { L1_ORDER, l1ChoicesFor } from "./l1";
import { TARGET_LANGUAGES } from "./target-lang";
import { UI_LANGS } from "./i18n";

describe("readerL1 — 母語と表示言語の統合", () => {
  it("表示言語が学習言語と違うなら、それがそのまま母語", () => {
    // これが普通の場合。設定は1つで足りる。
    expect(readerL1({ uiLanguage: "zh-TW", targetLanguage: "en" })).toBe("zh-TW");
    expect(readerL1({ uiLanguage: "ja", targetLanguage: "en" })).toBe("ja");
    expect(readerL1({ uiLanguage: "en", targetLanguage: "zh-TW" })).toBe("en");
    expect(readerL1({ uiLanguage: "ja", targetLanguage: "zh-TW" })).toBe("ja");
  });

  it("表示言語=学習言語のときは、母語として採らない", () => {
    // 「英語話者が英語のここで転ぶ」は成り立たない指示。
    expect(readerL1({ uiLanguage: "en", targetLanguage: "en" })).not.toBe("en");
    expect(readerL1({ uiLanguage: "zh-TW", targetLanguage: "zh-TW" })).not.toBe("zh-TW");
  });

  it("そのときは前に保存されていた母語を使う", () => {
    expect(readerL1({ uiLanguage: "en", nativeLanguage: "zh-TW", targetLanguage: "en" })).toBe(
      "zh-TW",
    );
    expect(readerL1({ uiLanguage: "en", nativeLanguage: "ja", targetLanguage: "en" })).toBe("ja");
  });

  it("保存されていた母語も使えないときは、選べる先頭に落とす", () => {
    const first = l1ChoicesFor("en")[0];
    expect(readerL1({ uiLanguage: "en", nativeLanguage: "en", targetLanguage: "en" })).toBe(first);
    expect(readerL1({ uiLanguage: "en", nativeLanguage: "ko", targetLanguage: "en" })).toBe(first);
    expect(readerL1({ uiLanguage: null, nativeLanguage: null, targetLanguage: "en" })).toBe(first);
  });

  it("**必ず学習言語と違う値を返す**(どの組み合わせでも)", () => {
    for (const target of TARGET_LANGUAGES) {
      for (const ui of UI_LANGS) {
        for (const native of [...L1_ORDER, null, "ko", ""]) {
          const got = readerL1({ uiLanguage: ui, nativeLanguage: native, targetLanguage: target });
          expect(got, `${target}/${ui}/${native}`).not.toBe(target);
          expect(L1_ORDER, `${target}/${ui}/${native}`).toContain(got);
        }
      }
    }
  });

  it("統合できる前提が崩れていない — 2つの一覧が同じ3つ", () => {
    // ここがずれたら統合そのものが成り立たない。足したときに気づけるように。
    expect([...L1_ORDER].sort()).toEqual([...UI_LANGS].sort());
  });
});
