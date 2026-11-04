import { describe, expect, it } from "vitest";
import { gateUsageChunks } from "./chunk-quality";

// 点検 S14（2026-11-03）: 目標 1・2 級でも、簡単な動詞の型は1つまで、程度の語の型（很＋好喝）は通さない。
describe("目標 1・2 級のチャンクの門", () => {
  const ctx = { headword: "珍珠奶茶", meaning: "タピオカミルクティー", language: "zh-TW", readerLang: "ja", allowSimplePartners: true };
  const c = (texts: string[], ja: string) => ({
    parts: texts.map((t) => ({ text: t, pos: t === "珍珠奶茶" ? "N" : t === "很" ? "Adv" : "V" })),
    ja,
    fits: true,
    why: "",
  });
  it("喝＋〜 は1つ目だけ残し、拿＋〜・很＋好喝 は落とす（強い型が2つ以上ある時）", () => {
    const g = gateUsageChunks(
      [
        c(["喝", "珍珠奶茶"], "タピオカミルクティーを飲む"),
        c(["珍珠奶茶", "半糖少冰"], "タピオカミルクティーを微糖・氷少なめで"),
        c(["拿", "珍珠奶茶"], "タピオカミルクティーを持つ"),
        c(["點", "珍珠奶茶"], "タピオカミルクティーを注文する"),
        c(["珍珠奶茶", "很", "好喝"], "タピオカミルクティーはとてもおいしい"),
      ],
      ctx,
    );
    const texts = g.kept.map((k) => k.parts.map((p) => p.text).join(""));
    expect(texts[0]).toBe("喝珍珠奶茶");
    expect(texts).not.toContain("拿珍珠奶茶");
    expect(texts).not.toContain("珍珠奶茶很好喝");
  });
});
