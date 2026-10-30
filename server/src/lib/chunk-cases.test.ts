import { describe, expect, it } from "vitest";
import { CHUNK_CASES, chunkCasesRule, parseCaseChunk } from "./chunk-cases";
import { gateUsageChunks, splitHeadwordLocative } from "./chunk-quality";

/** 台帳の型を、門に渡す形に（訳は読む人を渡さないので要らない）。 */
function asChunk(text: string) {
  return { parts: parseCaseChunk(text).map((p) => ({ text: p.text, pos: p.pos })), ja: "", fits: true };
}

describe("間違いの台帳（chunk-cases.ts）", () => {
  for (const c of CHUNK_CASES) {
    const ctx = { headword: c.headword, language: "zh-TW", allowSimplePartners: true };
    it(`${c.headword}: ○ の型は門で落ちない`, () => {
      for (const g of c.good) {
        const res = gateUsageChunks([asChunk(g)], ctx);
        expect(res.dropped.map((d) => `${d.text}: ${d.reason}`)).toEqual([]);
      }
    });
    it(`${c.headword}: ✗ の型は門で必ず落ちる`, () => {
      for (const b of c.bad) {
        expect(gateUsageChunks([asChunk(b)], ctx).kept).toEqual([]);
      }
    });
  }

  it("指示文には教訓と、その語の過去の ✗ が入る", () => {
    const rule = chunkCasesRule("筆袋");
    expect(rule).toContain("✗ 裝進＋筆袋");
    expect(rule).toContain("長さの上限に収めるために自然な句を削らない");
    expect(chunkCasesRule("電風扇")).not.toContain("「筆袋」で過去");
  });
});

describe("把 と方位の語は長さに数えない（筆袋 2026-10-30）", () => {
  it("把＋原子筆＋放進＋筆袋＋裡 は通る", () => {
    const res = gateUsageChunks([asChunk("把/Ptc＋原子筆/N＋放進/V＋筆袋/N＋裡/Ncd")], {
      headword: "筆袋",
      language: "zh-TW",
    });
    expect(res.kept).toHaveLength(1);
  });

  it("中身が5つの型は今までどおり落ちる", () => {
    const res = gateUsageChunks([asChunk("跟/Prep＋朋友/N＋一起/Adv＋去/V＋筆袋/N")], {
      headword: "筆袋",
      language: "zh-TW",
    });
    expect(res.dropped[0]?.reason).toBe("too_many_parts");
  });

  it("「筆袋裡」は 筆袋 ＋ 裡 に分けて通す（読みも分ける）", () => {
    const parts = splitHeadwordLocative(
      [
        { text: "放在", pos: "V" },
        { text: "筆袋裡", pos: "N", pinyin: "bǐ dài lǐ", zhuyin: "ㄅㄧˇ ㄉㄞˋ ㄌㄧˇ" },
      ],
      "筆袋",
    );
    expect(parts.map((p) => p.text)).toEqual(["放在", "筆袋", "裡"]);
    expect(parts[1].pinyin).toBe("bǐ dài");
    expect(parts[2].zhuyin).toBe("ㄌㄧˇ");
    const res = gateUsageChunks([{ parts: [{ text: "放在", pos: "V" }, { text: "筆袋裡", pos: "N" }], ja: "", fits: true }], {
      headword: "筆袋",
      language: "zh-TW",
    });
    expect(res.kept[0]?.parts.map((p) => p.text)).toEqual(["放在", "筆袋", "裡"]);
  });
});
