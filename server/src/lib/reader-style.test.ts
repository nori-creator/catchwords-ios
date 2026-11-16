import { describe, expect, it } from "vitest";
import { EXPLAIN_LANGUAGES } from "./explain-languages";
import { meaningRule, MEANING_LENGTH_RULE_EN } from "./meaning-rule";
import { readerStyleRule } from "./reader-style";
import { chunkExamplesRule } from "./example-patterns";

/**
 * 訳と解説の自然さの指示（オーナー 2026-11-16「直訳ではなくて最も自然な訳を表示したい」）。
 * 指示の文そのものは変えてよいが、言語ごとに要る決まりが落ちないことを見る。
 */
const zh = (explainLang: string) =>
  readerStyleRule({ explainLang, targetCode: "zh-TW", targetName: "台湾華語", nl: "X" });

describe("readerStyleRule", () => {
  it("どの表示言語にも、その言語の書き方の決まりがある", () => {
    for (const l of EXPLAIN_LANGUAGES) {
      expect(l.contentStyle.trim(), l.code).not.toBe("");
      expect(zh(l.code), l.code).toContain(l.contentStyle);
    }
  });

  it("欧文・ハングルの読者の決まりに、かなを入れない（例につられて日本語で返さない）", () => {
    for (const l of EXPLAIN_LANGUAGES.filter((x) => x.code !== "ja")) {
      expect(l.contentStyle, l.code).not.toMatch(/[ぁ-ゖァ-ヺ]/u);
    }
  });

  it("共通: 直訳・混ぜ書き・訳語の揺れ・誇張・返す前の文法の確かめ", () => {
    const r = zh("es");
    expect(r).toContain("直訳しない");
    expect(r).toContain("混ぜない");
    expect(r).toContain("同じ訳語");
    expect(r).toContain("誇張しない");
    expect(r).toContain("我的橡皮擦不見了");
    expect(r).toContain("語順を写していないか");
  });

  it("言語ごとの決まり", () => {
    expect(zh("ja")).toContain("です・ます");
    expect(zh("ja")).toContain("辞書形");
    expect(zh("en")).toContain("US English");
    expect(zh("es")).toContain("bueno para la salud");
    expect(zh("es")).toContain("habla más bajo");
    expect(zh("ko")).toContain("해요체");
    expect(zh("vi")).toContain("làm ơn");
    expect(zh("zh-TW")).toContain("防曬乳");
  });

  it("中文で読む人だけ、例文と型の訳を空にさせる", () => {
    expect(zh("zh-TW")).toContain("空文字");
    for (const code of ["ja", "en", "es", "ko", "vi"]) expect(zh(code), code).not.toContain("空文字");
  });

  it("学習言語が中国語でなければ、中国語の例を出さない", () => {
    const r = readerStyleRule({ explainLang: "ja", targetCode: "en", targetName: "英語", nl: "日本語" });
    expect(r).not.toContain("橡皮擦");
    expect(r).not.toContain("小聲一點");
    expect(r).toContain("ネイティブがふだん言う自然な言い方か");
  });

  it("型の例文を足す呼び出しにも渡せる（渡さなければ今までどおり）", () => {
    const base = {
      headword: "雨傘",
      targetName: "台湾華語",
      nl: "日本語",
      chunks: [],
      levelRule: "",
      chunkRoles: "",
    };
    const style = zh("ja");
    expect(chunkExamplesRule({ ...base, styleRule: style })).toContain(style);
    expect(chunkExamplesRule(base)).not.toContain("訳と解説の自然さ");
  });
});

describe("意味は見出しの呼び名だけ（同格を付けない）", () => {
  it("meaningRule と英語の指示の両方", () => {
    expect(meaningRule("台湾華語", "英語")).toContain("MRT, the metro");
    expect(meaningRule("台湾華語", "英語")).toContain("同格");
    expect(MEANING_LENGTH_RULE_EN).toContain("no appositions");
  });
});
