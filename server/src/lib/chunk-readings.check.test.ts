import { describe, expect, it } from "vitest";
import { withChunkReadingsInExtras } from "./chunk-readings.server";

// 点検 S11（2026-11-03）: 読みがそろったチャンクの誤った読みも直す。
describe("チャンクの読み", () => {
  it("雨傘 yǔ sān → yǔ sǎn", () => {
    const out = withChunkReadingsInExtras(
      {
        usage_chunks: [
          { parts: [{ text: "雨傘", role: "N", pinyin: "yǔ sān", zhuyin: "ㄩˇ ㄙㄢ" }] },
        ],
      } as never,
      "zh-TW",
    ) as { usage_chunks: Array<{ parts: Array<{ pinyin: string }> }> };
    expect(out.usage_chunks[0].parts[0].pinyin).toBe("yǔ sǎn");
  });
});
