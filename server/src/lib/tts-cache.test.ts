import { describe, expect, it } from "vitest";
import { ttsObjectPath } from "./tts-cache";

/**
 * Characterization tests for the existing shared TTS cache.
 *
 * These intentionally describe CURRENT behavior before the speech-router
 * refactor. They are a safety net: provider/model/version and pronunciation
 * disambiguation will later become part of the cache identity, but we first
 * freeze what callers rely on today.
 */
describe("ttsObjectPath characterization", () => {
  it("is deterministic for the same language, voice and text", async () => {
    const a = await ttsObjectPath("zh-TW", "alloy", "蘋果");
    const b = await ttsObjectPath("zh-TW", "alloy", "蘋果");
    expect(a).toBe(b);
    expect(a).toMatch(/^zh-TW\/alloy\/[a-f0-9]{64}\.mp3$/);
  });

  it("separates learning languages even when the text is identical", async () => {
    const zh = await ttsObjectPath("zh-TW", "alloy", "OK");
    const en = await ttsObjectPath("en", "alloy", "OK");
    expect(zh).not.toBe(en);
  });

  it("separates voice/speed cache keys", async () => {
    const normal = await ttsObjectPath("en", "alloy", "apple");
    const slower = await ttsObjectPath("en", "alloy@0.9", "apple");
    expect(normal).not.toBe(slower);
  });

  it("separates different text", async () => {
    const apple = await ttsObjectPath("en", "alloy", "apple");
    const orange = await ttsObjectPath("en", "alloy", "orange");
    expect(apple).not.toBe(orange);
  });
});
