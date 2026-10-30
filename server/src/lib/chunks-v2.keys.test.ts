import { describe, expect, it } from "vitest";
import { sectionHasContent } from "./card-sections";
import { withChunkReadingsInExtras } from "./chunk-readings.server";
import { ExtrasSchema, normalizeExtras } from "./extras";
import { LEVEL_EXTRAS_KEYS, splitLevelExtras } from "./level-content";
import { scrubExtrasForReader } from "./note-language";

/**
 * **v2 の鍵がどこでも黙って落ちないこと**（`usage_chunks_v2` は `ExtrasSchema`・レベルの置き場・項目の中身の判定・
 * 読む人の言語の門・読みの 5 か所を通る。1 か所でも知らないと、画面に出ないか古い作りが v2 を上書きする）。
 */
const V2 = [
  {
    text: "把原子筆放進筆袋裡",
    blocks: [{ text: "把", pos: "Ptc" }, { text: "原子筆", pos: "N", slot: true, ja: "ボールペン", alts: [{ text: "鉛筆", ja: "鉛筆" }, { text: "橡皮擦", ja: "English gloss" }] }, { text: "放進", pos: "V" }, { text: "筆袋裡", pos: "N" }],
    head: { block: 3, start: 0, length: 2 },
    pattern: "action_ba",
    ja: "ボールペンをペンケースに入れる",
    note: "This note is English.",
    sentence: "我把原子筆放進筆袋裡了。",
    sentence_ja: "ボールペンをペンケースに入れたよ。",
    frequency: null,
    by: "agreement",
  },
];

describe("usage_chunks_v2 の鍵", () => {
  it("ExtrasSchema が v2 と pending の印を捨てない", () => {
    const parsed = ExtrasSchema.parse({ usage_chunks_v2: V2, usage_chunks_v2_pending: true });
    expect(parsed.usage_chunks_v2?.[0]?.text).toBe("把原子筆放進筆袋裡");
    expect(parsed.usage_chunks_v2?.[0]?.blocks[1]?.alts?.length).toBe(2);
    expect(parsed.usage_chunks_v2_pending).toBe(true);
    expect(normalizeExtras({ usage_chunks_v2: V2 })?.usage_chunks_v2).toHaveLength(1);
  });

  it("レベルで分ける鍵（帯の行に入り、言語の置き場には残らない）", () => {
    expect(LEVEL_EXTRAS_KEYS).toContain("usage_chunks_v2");
    const { level, rest } = splitLevelExtras({ usage_chunks_v2: V2, taiwan_note: "n" });
    expect(Object.keys(level)).toEqual(["usage_chunks_v2"]);
    expect(Object.keys(rest)).toEqual(["taiwan_note"]);
  });

  it("v2 が有れば「使い方」の項目は中身あり（古い作り直しが上書きしない）", () => {
    const base = { headword: "筆袋", language: "zh-TW", example_sentence: null, extras: { usage_chunks: [], usage_chunks_v2: V2 } };
    expect(sectionHasContent("usage_chunks", base as never)).toBe(true);
    expect(sectionHasContent("usage_chunks", { ...base, extras: { usage_chunks: [], usage_chunks_v2: [] } } as never)).toBe(false);
  });

  it("読む人の言語でない訳・解説だけを空にし、中国語の塊と文は触らない", () => {
    const out = scrubExtrasForReader({ usage_chunks_v2: V2 } as never, "ja") as { usage_chunks_v2: typeof V2 };
    const c = out.usage_chunks_v2[0];
    expect(c.text).toBe("把原子筆放進筆袋裡");
    expect(c.sentence).toBe("我把原子筆放進筆袋裡了。");
    expect(c.ja).toBe("ボールペンをペンケースに入れる");
    expect(c.note).toBe("");
    expect(c.blocks[1].alts?.[1].ja).toBe("");
    expect(c.blocks[1].alts?.[0].ja).toBe("鉛筆");
  });

  it("読む所で block と候補に辞書の読みが付く", () => {
    const out = withChunkReadingsInExtras({ usage_chunks_v2: V2 } as never, "zh-TW") as { usage_chunks_v2: typeof V2 & Array<{ blocks: Array<{ zhuyin?: string; pinyin?: string; alts?: Array<{ zhuyin?: string }> }> }> };
    const b = out.usage_chunks_v2[0].blocks;
    expect(b[3].zhuyin).toBeTruthy();
    expect(b[3].pinyin).toBeTruthy();
    expect(b[1].alts?.[0].zhuyin).toBeTruthy();
    // 無い欄は足さない。
    expect("usage_chunks" in (withChunkReadingsInExtras({ usage_chunks_v2: V2 } as never, "zh-TW") as object)).toBe(false);
  });
});
