/**
 * ネットの画像の候補の並べ直し（オーナー報告 2026-10-08「牛蒡を検索すると花の写真しか出ない」）。
 * 見本は `__fixtures__/image-search-burdock.json`（Unsplash とコモンズの返事の形）。
 */
import fs from "node:fs";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("@/integrations/supabase/auth-middleware", () => ({ requireSupabaseAuth: {} }));
vi.mock("@/integrations/supabase/client.server", () => ({
  supabaseAdmin: {
    from: () => ({
      select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: null }) }) }),
    }),
  },
}));

import { imageRelevance, rankImageCandidates } from "./image-search-rank";
import { commonsCandidates, type CommonsResponse } from "./commons-images";
import { searchImagesWith } from "./images.functions";

const fixture = JSON.parse(
  fs.readFileSync(path.join(__dirname, "__fixtures__", "image-search-burdock.json"), "utf8"),
) as { unsplash: unknown; commons: CommonsResponse };

describe("imageRelevance（探した物に合う写真を前へ、外れを後ろへ）", () => {
  const ctx = { query: "burdock root", category: "vegetable" };

  it("探した語が説明に出てくる写真ほど高い", () => {
    expect(imageRelevance("fresh burdock roots on a table", ctx)).toBeGreaterThan(
      imageRelevance("a wooden table", ctx),
    );
  });

  it("花・植物を探していない語では、花の写真を下げる", () => {
    expect(imageRelevance("purple thistle flowers in bloom", ctx)).toBeLessThan(0);
    expect(imageRelevance("ゴボウの花", { query: "ゴボウ", category: null })).toBeLessThan(
      imageRelevance("ゴボウ", { query: "ゴボウ", category: null }),
    );
  });

  it("花を探している語（棚が flower・語に flower/花）では花を下げない", () => {
    expect(imageRelevance("cherry blossom in spring", { query: "桜", category: "flower" })).toBe(0);
    expect(
      imageRelevance("cauliflower florets", { query: "cauliflower", category: null }),
    ).toBeGreaterThan(0);
    expect(imageRelevance("fireworks 花火", { query: "花火", category: "sky" })).toBeGreaterThan(0);
  });

  it("標本・挿絵は写真より後ろ", () => {
    expect(imageRelevance("herbarium specimen of burdock", ctx)).toBeLessThan(
      imageRelevance("burdock", ctx),
    );
  });

  it("説明の無い候補は 0 点（AI の絵など）", () => {
    expect(imageRelevance(undefined, ctx)).toBe(0);
    expect(imageRelevance("", ctx)).toBe(0);
  });
});

describe("rankImageCandidates", () => {
  it("同じ点なら元の順を保つ（出所の関連順を崩さない）", () => {
    const list = [{ text: "a" }, { text: "b" }, { text: "c" }];
    expect(rankImageCandidates(list, { query: "zzz" })).toEqual(list);
  });

  it("コモンズの見本: 根の写真が先頭、花・標本が後ろ", () => {
    const found = commonsCandidates(fixture.commons, 12);
    expect(found.map((c) => c.url)[0]).toContain("arctium-flower");
    const ranked = rankImageCandidates(found, { query: "burdock root", category: "vegetable" });
    expect(ranked[0].url).toContain("gobo-root");
    expect(ranked[ranked.length - 1].url).not.toContain("gobo-root");
  });

  it("古いカード（意味の欄の日本語で探す）でも、花の写真は根の写真より後ろ", () => {
    const found = commonsCandidates(fixture.commons, 12);
    const ranked = rankImageCandidates(found, { query: "ゴボウ", category: "vegetable" });
    expect(ranked[0].url).toContain("gobo-root");
  });
});

describe("searchImagesWith — 並べ直して返す", () => {
  const fetchMock = vi.fn();
  beforeEach(() => {
    fetchMock.mockReset();
    vi.stubGlobal("fetch", fetchMock);
    vi.stubEnv("IMAGE_PROVIDER", "off");
    vi.spyOn(console, "warn").mockImplementation(() => undefined);
  });
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.unstubAllEnvs();
    vi.restoreAllMocks();
  });

  it("Unsplash: 根の写真・料理だけを返す（花・野草は捨てる）。説明の字は返さない", async () => {
    vi.stubEnv("UNSPLASH_ACCESS_KEY", "test-only");
    fetchMock.mockImplementation(async () => new Response(JSON.stringify(fixture.unsplash)));
    const out = await searchImagesWith(
      { query: "burdock root", language: "zh-TW", purpose: "candidates", category: "vegetable" },
      async () => undefined,
    );
    const asked = new URL(String(fetchMock.mock.calls[0][0]));
    expect(asked.searchParams.get("query")).toBe("burdock root");
    expect(asked.searchParams.get("per_page")).toBe("12");
    // オーナー報告 2026-10-08 ②: 後ろへ回すだけでは、出所が花しか返さない語で花が先頭になる。
    // 外れと分かる物は捨てる。根の写真が在るのでコモンズは探さない（1回だけ取りに行く）。
    expect(out.candidates.map((c) => c.url)).toEqual([
      "https://images.unsplash.com/root-3",
      "https://images.unsplash.com/dish-4",
    ]);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(out.candidates.every((c) => !("text" in c))).toBe(true);
  });

  it("コモンズ（鍵の要らない出所）も並べ直す", async () => {
    vi.stubEnv("UNSPLASH_ACCESS_KEY", "");
    fetchMock.mockImplementation(async () => new Response(JSON.stringify(fixture.commons)));
    const out = await searchImagesWith(
      { query: "burdock root", language: "zh-TW", purpose: "candidates" },
      async () => undefined,
    );
    expect(out.candidates[0].url).toContain("gobo-root");
    expect(out.candidates[0].source).toBe("commons");
    expect(out.candidates.every((c) => !("text" in c))).toBe(true);
  });
});
