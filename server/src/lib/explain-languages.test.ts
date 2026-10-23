import { describe, expect, it } from "vitest";
import {
  EXPLAIN_LANGS,
  EXPLAIN_LANGUAGES,
  explainScript,
  isExplainLang,
  latinLanguageOf,
  normalizeExplainLang,
} from "./explain-languages";
import { UI_LANGS } from "./i18n";
import { explanationLanguageName } from "./ai-provider.server";
import { looksWrongForReader, scrubExtrasForReader } from "./note-language";
import { fitsReaderLanguage, quizMeaningLanguage } from "./meaning-language";
import { FALLBACK_MEANINGS_BY_LANG } from "./quiz-choices";
import { fitsReaderMeaning, fitsReaderNote } from "./first-catch-meaning";
import { basicLevelTable } from "./basic-level";
import { reconcileUiLanguage } from "./language-sync";
import { sceneMaxChars } from "./example-patterns";

/**
 * 解説の言語（読む人の言語）の門。2026-10-20 に iOS の表示言語へスペイン語・韓国語・ベトナム語を
 * 足した（オーナー指示「繁體字（台灣），スペイン語、韓国語、ベトナム語に対応させる」）。
 * 判定の例は iOS の `ios/LanguageRules/cases.json`（L-es-* / L-ko-* / L-vi-*）と同じ文。
 */
describe("解説の言語の一覧", () => {
  it("iOS の表示言語と同じ6つ、同じ順（先頭が既定）", () => {
    expect(EXPLAIN_LANGS).toEqual(["ja", "en", "zh-TW", "es", "ko", "vi"]);
  });

  it("**Web の画面の言語はその中**", () => {
    for (const ui of UI_LANGS) expect(isExplainLang(ui)).toBe(true);
  });

  it("知らない値は既定（日本語）に落とす", () => {
    for (const bad of [null, undefined, "", "fr", "es-MX", " ko "]) {
      expect(normalizeExplainLang(bad)).toBe(bad === " ko " ? "ko" : "ja");
    }
  });

  it("**どの言語にも、指示文での呼び名がある**（undefined を指示文に入れない）", () => {
    for (const code of EXPLAIN_LANGS) {
      const name = explanationLanguageName(code);
      expect(name, code).toBeTruthy();
      expect(name, code).not.toContain("undefined");
    }
    expect(explanationLanguageName("es")).toBe("スペイン語");
    expect(explanationLanguageName("xx")).toBe("日本語");
  });

  it("書く文字", () => {
    expect(EXPLAIN_LANGUAGES.map((l) => [l.code, explainScript(l.code)])).toEqual([
      ["ja", "kana"],
      ["en", "latin"],
      ["zh-TW", "han"],
      ["es", "latin"],
      ["ko", "hangul"],
      ["vi", "latin"],
    ]);
  });
});

describe("欧文の言語の見分け（latinLanguageOf）", () => {
  it("はっきりしている文は、その言語", () => {
    expect(latinLanguageOf("An umbrella used to keep off the rain")).toBe("en");
    expect(latinLanguageOf("Paraguas para protegerse de la lluvia")).toBe("es");
    expect(latinLanguageOf("cái ô dùng để che mưa")).toBe("vi");
    expect(latinLanguageOf("xe đạp")).toBe("vi");
  });

  it("**手がかりの無い短い語は分からない**（判定できない物は消さない）", () => {
    expect(latinLanguageOf("bus stop")).toBeNull();
    expect(latinLanguageOf("jalapeño pepper")).toBeNull();
    expect(latinLanguageOf("")).toBeNull();
  });
});

describe("読む人の言語の判定（looksWrongForReader）— iOS の cases.json と同じ文", () => {
  const cases: Array<[string, string, boolean, boolean?]> = [
    // [読む人, 文, 落とすか, 漢字だけの意味を許すか]
    ["es", "Paraguas para protegerse de la lluvia", false],
    ["es", "An umbrella used to keep off the rain", true],
    ["es", "雨傘", true, true],
    ["es", "cái ô dùng để che mưa", true],
    ["es", "bus stop", false],
    ["es", "Se dice 雨傘 en Taiwán; la palabra común es 雨傘.", false],
    ["vi", "Ô dùng để che mưa", false],
    ["vi", "Un paraguas para la lluvia", true],
    ["vi", "Ordinary stir-fried noodles. 鐵板麵 is served on an iron plate.", true],
    ["vi", "マッシュルームソースの鉄板焼きそば", true, true],
    ["en", "Paraguas para protegerse de la lluvia", true],
    ["en", "xe đạp", true],
    ["en", "jalapeño pepper", false],
    ["en", "Ordinary stir-fried noodles. 鐵板麵 is served on an iron plate.", false],
    ["ko", "비를 막는 우산", false],
    ["ko", "雨傘", true, true],
    ["ko", "An umbrella for the rain", true],
    ["ko", "‘芒果’는 망고라는 뜻이에요", false],
    ["ko", "かさ", true],
    ["ko", "這是一個很好吃的水果 망고", true],
    ["ko", "TV", false],
    ["ja", "マッシュルームソースの鉄板焼きそば", false, true],
  ];
  for (const [reader, text, wrong, hanOnlyOk] of cases) {
    it(`${reader}: ${text} → ${wrong ? "落とす" : "残す"}`, () => {
      expect(looksWrongForReader(text, reader, null, { hanOnlyOk })).toBe(wrong);
    });
  }
});

describe("意味・注記の言語（4択・候補・辞書）", () => {
  it("新しい3言語の意味を、その言語の読み手に通す", () => {
    expect(fitsReaderLanguage("paraguas", "es")).toBe(true);
    expect(fitsReaderLanguage("우산", "ko")).toBe(true);
    expect(fitsReaderLanguage("cái ô", "vi")).toBe(true);
    expect(fitsReaderMeaning("bánh mì", "vi")).toBe(true);
  });

  it("別の言語の意味は通さない", () => {
    expect(fitsReaderLanguage("傘", "es")).toBe(false);
    expect(fitsReaderLanguage("かさ", "ko")).toBe(false);
    expect(fitsReaderLanguage("우산", "en")).toBe(false);
    expect(fitsReaderLanguage("우산", "ja")).toBe(false);
    expect(fitsReaderLanguage("우산", "zh-TW")).toBe(false);
    expect(fitsReaderLanguage("An umbrella used to keep off the rain", "es")).toBe(false);
    expect(fitsReaderMeaning("親指", "es")).toBe(false);
  });

  it("注記: 韓国語の中で引いた見出し語は残し、中国語だけの文は落とす", () => {
    expect(fitsReaderNote("‘咖啡’는 커피예요", "ko", "zh-TW")).toBe(true);
    expect(fitsReaderNote("這是咖啡", "ko", "zh-TW")).toBe(false);
    expect(fitsReaderNote("Se usa con 咖啡 en Taiwán", "es", "zh-TW")).toBe(true);
  });

  it("**どの言語にも4択の受け皿が4つある**（無いと4択が組めない）", () => {
    for (const code of EXPLAIN_LANGS) {
      expect(FALLBACK_MEANINGS_BY_LANG[code], code).toHaveLength(4);
      for (const m of FALLBACK_MEANINGS_BY_LANG[code])
        expect(fitsReaderLanguage(m, code), `${code} ${m}`).toBe(true);
    }
  });

  it("4択を揃える言語は、正解が韓国語なら韓国語（受け皿がある言語）", () => {
    expect(quizMeaningLanguage("우산", "en")).toBe("ko");
    expect(quizMeaningLanguage("paraguas", "es")).toBe("es");
    expect(FALLBACK_MEANINGS_BY_LANG[quizMeaningLanguage("우산", "en")]).toBeDefined();
  });

  it("**基本の語の表は、どの言語にも名前がある**（無いと意味が空になる）", () => {
    for (const row of basicLevelTable("zh-TW")) {
      for (const code of EXPLAIN_LANGS)
        expect(row.label[code], `${row.headword} ${code}`).toBeTruthy();
    }
  });

  it("場面の札の長さ: 欧文の言語は英語と同じ、韓国語は韓国語の上限", () => {
    expect(sceneMaxChars("es")).toBe(sceneMaxChars("en"));
    expect(sceneMaxChars("vi")).toBe(sceneMaxChars("en"));
    expect(sceneMaxChars("ko")).toBeGreaterThan(sceneMaxChars("zh-TW"));
  });
});

describe("Web が iOS だけの表示言語を書き換えない（reconcileUiLanguage）", () => {
  it("サーバがスペイン語なら、端末に英語・日本語が在ってもサーバが勝ち、書き戻さない", () => {
    for (const stored of [null, "en", "ja"]) {
      expect(reconcileUiLanguage({ stored, server: "es", fallback: "ja" })).toEqual({
        value: "es",
        pushToServer: false,
      });
    }
  });

  it("Web の言語どうしは今までどおり（端末が勝ち、違えば書き戻す）", () => {
    expect(reconcileUiLanguage({ stored: "en", server: "ja", fallback: "ja" })).toEqual({
      value: "en",
      pushToServer: true,
    });
    expect(reconcileUiLanguage({ stored: null, server: "zh-TW", fallback: "ja" })).toEqual({
      value: "zh-TW",
      pushToServer: false,
    });
  });
});

describe("解説のすべての欄を読む人の言語に揃える（scrubExtrasForReader、2026-10-20）", () => {
  const extras = {
    explain_lang: "es",
    usage_context: "通学のときに使う",
    taiwan_note: "En Taiwán se dice así.",
    example_scene: "朝ごはんのとき",
    region_scope: "台南",
    measure_words: [{ word: "支", note: "細長い物に" }],
    related_words: [{ word: "雨衣", kind: "rel", note: "impermeable" }],
    usage_chunks: [
      {
        ja: "abrir el paraguas",
        parts: [{ text: "打開", ja: "開く", alts: [{ text: "收起", ja: "cerrar" }] }],
      },
    ],
    countability: { kind: "countable", article: "", note: "数えられる" },
    kanji_breakdown: [{ kanji: "傘", meaning: "かさ" }],
    pitch_accent: "か↘さ＝頭高型",
    image_query: "umbrella",
  };

  it("スペイン語の読み手: 日本語の欄だけ空、スペイン語と学ぶ言語の部分は残す", () => {
    const out = scrubExtrasForReader(extras, "es") as typeof extras;
    expect(out.usage_context).toBe("");
    expect(out.taiwan_note).toBe("En Taiwán se dice así.");
    expect(out.example_scene).toBe("");
    expect(out.region_scope).toBe("");
    expect(out.measure_words[0]).toEqual({ word: "支", note: "" });
    expect(out.related_words[0].note).toBe("impermeable");
    expect(out.usage_chunks[0].ja).toBe("abrir el paraguas");
    expect(out.usage_chunks[0].parts[0].ja).toBe("");
    expect(out.usage_chunks[0].parts[0].alts[0]).toEqual({ text: "收起", ja: "cerrar" });
    expect(out.countability.note).toBe("");
    expect(out.kanji_breakdown[0]).toEqual({ kanji: "傘", meaning: "" });
    expect(out.pitch_accent).toBe("");
    // 画像の検索語は英語のまま（画面には出ない）。
    expect(out.image_query).toBe("umbrella");
  });

  it("日本語の読み手: 日本語の欄は残し、スペイン語の文を落とす", () => {
    const out = scrubExtrasForReader(extras, "ja") as typeof extras;
    expect(out.usage_context).toBe("通学のときに使う");
    expect(out.region_scope).toBe("台南");
    expect(out.measure_words[0].note).toBe("細長い物に");
    expect(out.pitch_accent).toBe("か↘さ＝頭高型");
    expect(out.taiwan_note).toBe("");
  });

  it("**日本語の読み手に、漢字だけの中文の注記・札・型の訳を出さない**（量詞の説明が台湾華語）。漢字だけの意味の語は残す", () => {
    const out = scrubExtrasForReader(
      {
        measure_words: [{ word: "支", note: "用於細長的東西" }],
        example_scene: "在夜市點餐時",
        usage_chunks: [{ ja: "打開這把雨傘吧", parts: [{ text: "雨傘", ja: "雨傘" }] }],
        kanji_breakdown: [{ kanji: "鐵", meaning: "鉄" }],
      },
      "ja",
    );
    expect(out.measure_words[0].note).toBe("");
    expect(out.example_scene).toBe("");
    expect(out.usage_chunks[0].ja).toBe("");
    expect(out.usage_chunks[0].parts[0].ja).toBe("雨傘");
    expect(out.kanji_breakdown[0].meaning).toBe("鉄");
  });

  it("韓国語の読み手: ハングルの無い欄は落とす", () => {
    const out = scrubExtrasForReader(
      { usage_context: "우산은 비 올 때 써요", taiwan_note: "台湾では傘をよく使う" },
      "ko",
    );
    expect(out).toEqual({ usage_context: "우산은 비 올 때 써요", taiwan_note: "" });
  });

  it("形の違う物はそのまま返す", () => {
    expect(scrubExtrasForReader(null, "es")).toBeNull();
    expect(scrubExtrasForReader([], "es")).toEqual([]);
  });
});
