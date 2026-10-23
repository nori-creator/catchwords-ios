import { afterEach, describe, expect, it, vi } from "vitest";
import {
  explanationCacheKey,
  keepShownFields,
  readCachedExplanation,
  writeCachedExplanation,
} from "./explanation-cache";

/** 2026-09-28「開いたときに表示されたものが、ぱっと消えて新しいものが表示されるバグ」。 */
describe("単語の解説: 見えている物を差し替えない・端末に覚える", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("欠けた項目だけ新しい物で埋め、見えている項目はそのまま", () => {
    const shown: Record<string, unknown> = {
      usage_context: "コンビニで",
      related_words: [],
      mnemonic: "",
    };
    const fresh: Record<string, unknown> = {
      usage_context: "別の文",
      related_words: ["飲料"],
      mnemonic: "覚え方",
      explain_lang: "ja",
    };
    expect(keepShownFields(shown, fresh)).toEqual({
      usage_context: "コンビニで",
      related_words: ["飲料"],
      mnemonic: "覚え方",
      explain_lang: "ja",
    });
    expect(keepShownFields(null, fresh)).toBe(fresh);
  });

  it("解説（note）が1つも無い関連語は残さず、新しく作った物で埋める（2026-09-30 保溫瓶）", () => {
    const shown: Record<string, unknown> = {
      related_words: [{ word: "真空", kind: "rel", note: "" }],
    };
    const freshRel = [{ word: "真空", kind: "rel", note: "真空断熱の構造" }];
    expect(keepShownFields(shown, { related_words: freshRel }).related_words).toEqual(freshRel);
    // 解説の在る関連語はそのまま残す（開いている途中で差し替えない）。
    const withNote = [{ word: "水壺", kind: "syn", note: "水筒全般" }];
    expect(
      keepShownFields({ related_words: withNote }, { related_words: freshRel }).related_words,
    ).toEqual(withNote);
  });

  it("端末に覚えた解説を、同じ語・同じ言語・同じ母語の鍵で読み戻す", () => {
    const mem = new Map<string, string>();
    vi.stubGlobal("localStorage", {
      getItem: (k: string) => mem.get(k) ?? null,
      setItem: (k: string, v: string) => mem.set(k, v),
    });
    const k = explanationCacheKey("w1", "ja", "ja");
    expect(readCachedExplanation(k)).toBeUndefined();
    writeCachedExplanation(k, { picked: { meaning: "タピオカ" } });
    expect(readCachedExplanation(k)).toEqual({ picked: { meaning: "タピオカ" } });
    expect(readCachedExplanation(explanationCacheKey("w1", "en", "ja"))).toBeUndefined();
  });
});
