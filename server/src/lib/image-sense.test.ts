/**
 * 同じ名の別の物に当たる語の画像（オーナー報告 2026-10-08 ②「レンコンを文字検索したのに、
 * 蓮の花の画像しか出てこない」）。見本は `__fixtures__/image-search-ambiguous.json`
 * （と牛蒡の `image-search-burdock.json`）。ネットには出ない（fetch と AI は差し替える）。
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

import { searchImagesWith } from "./images.functions";
import {
  applyVerdict,
  cleanAvoidTerms,
  imageAvoidOf,
  imageSensePrompt,
  imageVerifyPrompt,
  needsSenseResolution,
  parseImageSense,
  parseVerifyVerdict,
  shouldVerify,
  SmallCache,
  type ImageSense,
} from "./image-sense";
import { isConfidentMatch, selectImageCandidates } from "./image-search-rank";
import type { ImageSenseDeps } from "./image-sense.server";
import { normalizeExtras, hasExtrasContent } from "./extras";

type Fixture = {
  lotusRoot: { unsplashFlowersOnly: unknown; unsplashMixed: unknown; commons: unknown };
  bambooShoot: { unsplash: unknown };
  peanut: { unsplash: unknown };
  mouse: { unsplash: unknown };
};
const fx = JSON.parse(
  fs.readFileSync(path.join(__dirname, "__fixtures__", "image-search-ambiguous.json"), "utf8"),
) as Fixture;
const burdock = JSON.parse(
  fs.readFileSync(path.join(__dirname, "__fixtures__", "image-search-burdock.json"), "utf8"),
) as { unsplash: unknown; commons: unknown };

const LOTUS_ROOT: ImageSense = {
  query: "lotus root",
  avoid: ["flower", "blossom", "pond", "petal"],
  sense: "Lotus root, the edible rhizome vegetable, raw or cooked.",
};

/**
 * fetch の差し替え: Unsplash とコモンズ（英語）にそれぞれの見本を返す。学習言語の出所
 * （コモンズの引用付きの検索・Wikipedia・Openverse）は何も見つからない。
 */
function routeFetch(fetchMock: ReturnType<typeof vi.fn>, unsplash: unknown, commons?: unknown) {
  fetchMock.mockImplementation(async (url: string) => {
    const u = String(url);
    if (u.includes("api.unsplash.com")) return new Response(JSON.stringify(unsplash));
    if (u.includes("commons.wikimedia.org")) {
      const learning = (new URL(u).searchParams.get("gsrsearch") ?? "").includes('"');
      return new Response(JSON.stringify(learning ? {} : (commons ?? { query: { pages: {} } })));
    }
    if (u.includes("wikipedia.org")) return new Response(JSON.stringify({ query: { pages: [] } }));
    if (u.includes("api.openverse.org")) return new Response(JSON.stringify({ results: [] }));
    throw new Error(`unexpected fetch ${u}`);
  });
}

/** 英語の出所（Unsplash）に投げた検索語。 */
function unsplashQuery(fetchMock: ReturnType<typeof vi.fn>): string | null {
  const call = fetchMock.mock.calls.find(([u]) => String(u).includes("api.unsplash.com"));
  return call ? new URL(String(call[0])).searchParams.get("query") : null;
}

function deps(over: Partial<ImageSenseDeps> = {}): ImageSenseDeps & {
  resolveSense: ReturnType<typeof vi.fn>;
  verify: ReturnType<typeof vi.fn>;
} {
  return {
    resolveSense: vi.fn(async () => LOTUS_ROOT),
    verify: vi.fn(async () => null),
    ...over,
  } as never;
}

describe("needsSenseResolution — 英語の検索語でなければ、探す前に意味を決める", () => {
  it("日本語・中国語は決める。英語は決めない", () => {
    expect(needsSenseResolution("レンコン")).toBe(true);
    expect(needsSenseResolution("蓮根")).toBe(true);
    expect(needsSenseResolution("蓮藕 lotus")).toBe(true);
    expect(needsSenseResolution("lotus root")).toBe(false);
    expect(needsSenseResolution("crème brûlée")).toBe(false);
    expect(needsSenseResolution("  ")).toBe(false);
  });
});

describe("AI の答えを読む", () => {
  it("parseImageSense: 検索語・避ける語・説明を揃える。使えない物は null", () => {
    expect(
      parseImageSense({
        query: '"lotus root"',
        avoid: ["Flower", "pond", "蓮の花", 3, "pond", "a very long phrase of words"],
        sense: "  Lotus root,\n the vegetable ",
      }),
    ).toEqual({
      query: "lotus root",
      avoid: ["flower", "pond"],
      sense: "Lotus root, the vegetable",
    });
    expect(parseImageSense({ query: "", avoid: [] })).toBeNull();
    expect(parseImageSense({ query: "蓮藕" })).toBeNull();
    expect(parseImageSense(null)).toBeNull();
  });

  it("cleanAvoidTerms / imageAvoidOf: 英小文字の短い語だけ、上限まで", () => {
    expect(cleanAvoidTerms(["A", "flower", "Flower", "lotus flower", "x y z"])).toEqual([
      "flower",
      "lotus flower",
    ]);
    expect(cleanAvoidTerms("flower")).toEqual([]);
    expect(
      cleanAvoidTerms(Array.from({ length: 20 }, (_, i) => `w${"a".repeat(i + 1)}`)),
    ).toHaveLength(8);
    expect(imageAvoidOf({ image_avoid: ["pond"] })).toEqual(["pond"]);
    expect(imageAvoidOf({})).toEqual([]);
  });

  it("parseVerifyVerdict: 範囲内の番号だけ。形が違えば null（確かめなかった扱い）", () => {
    expect([...(parseVerifyVerdict({ match: [0, "2", 9, -1, 1.5] }, 3) ?? [])]).toEqual([0, 2]);
    expect(parseVerifyVerdict({ match: "0" }, 3)).toBeNull();
    expect(parseVerifyVerdict(null, 3)).toBeNull();
  });

  it("指示文に語・意味・避ける物が入る", () => {
    const p = imageSensePrompt({ headword: "蓮藕", meaning: "レンコン", language: "zh-TW" });
    expect(p).toContain("蓮藕");
    expect(p).toContain("レンコン");
    expect(p).toMatch(/lotus root, not the lotus flower/);
    const v = imageVerifyPrompt({
      headword: "蓮藕",
      meaning: "レンコン",
      sense: LOTUS_ROOT,
      count: 4,
    });
    expect(v).toContain("0 to 3");
    expect(v).toContain("flower, blossom, pond, petal");
    expect(v).toContain("edible rhizome");
  });
});

describe("確かめた答えで並べ直す", () => {
  it("合っていた物を先に、確かめていない物を後ろに、外れは捨てる", () => {
    expect(applyVerdict(["a", "b", "c", "d", "e"], [0, 1, 2], new Set([2]))).toEqual([
      "c",
      "d",
      "e",
    ]);
    // 1枚も合わなければ、確かめた物は全部捨てる（花を出すより出さない）。
    expect(applyVerdict(["a", "b"], [0, 1], new Set())).toEqual([]);
  });

  it("shouldVerify: 先頭が説明で確かな写真なら AI を呼ばない", () => {
    const ctx = { query: "lotus root", category: "vegetable", avoid: LOTUS_ROOT.avoid };
    expect(shouldVerify([{ text: "sliced lotus root", source: "unsplash" }], ctx)).toBe(false);
    expect(shouldVerify([{ text: "white lotus", source: "unsplash" }], ctx)).toBe(true);
    expect(shouldVerify([{ text: "", source: "unsplash" }], ctx)).toBe(true);
    expect(shouldVerify([{ source: "ai" }], ctx)).toBe(false);
    expect(shouldVerify([], ctx)).toBe(false);
  });

  it("SmallCache: 古い物から捨て、期限を過ぎた物は返さない", () => {
    const c = new SmallCache<number>(2, 1000);
    c.set("a", 1, 0);
    c.set("b", 2, 0);
    c.get("a", 1); // a を新しい側へ
    c.set("c", 3, 2);
    expect(c.get("b", 3)).toBeUndefined();
    expect(c.get("a", 3)).toBe(1);
    expect(c.get("c", 5000)).toBeUndefined();
  });
});

describe("並べ替え・捨てる（語ごとの表を持たずに）", () => {
  it("蓮藕: 花・池・ただの蓮は確かではなく、根の写真だけが確か", () => {
    const ctx = { query: "lotus root", category: "vegetable", avoid: LOTUS_ROOT.avoid };
    expect(isConfidentMatch("sliced lotus root on a cutting board", ctx)).toBe(true);
    expect(isConfidentMatch("stir fried lotus roots", ctx)).toBe(true);
    expect(isConfidentMatch("pink lotus flower in bloom", ctx)).toBe(false);
    expect(isConfidentMatch("white lotus", ctx)).toBe(false);
    expect(isConfidentMatch("lotus root and lotus flower", ctx)).toBe(false);
    // 説明の飾り（sliced / vegetable）は写真に無くても確か。
    expect(
      isConfidentMatch("lotus root", {
        query: "lotus root vegetable sliced",
        category: "vegetable",
      }),
    ).toBe(true);
  });

  it("竹筍: 竹林・パンダは捨て、筍を先に", () => {
    const list = (
      fx.bambooShoot.unsplash as { results: Array<{ alt_description: string }> }
    ).results.map((r) => ({ text: r.alt_description }));
    const out = selectImageCandidates(list, {
      query: "bamboo shoot",
      category: "vegetable",
      avoid: ["forest", "grove", "panda"],
    }).map((c) => c.text);
    expect(out).toEqual(["fresh bamboo shoots at the market", "boiled bamboo shoot salad"]);
    // 避ける語が無い（古いカード）でも、食べ物の語で竹林は捨てる。
    const noAvoid = selectImageCandidates(list, { query: "bamboo shoot", category: "vegetable" });
    expect(noAvoid.map((c) => c.text)).not.toContain("bamboo forest in Kyoto");
  });

  it("落花生: 畑の株・花は捨て、食べる豆を先に", () => {
    const list = (
      fx.peanut.unsplash as { results: Array<{ alt_description: string }> }
    ).results.map((r) => ({ text: r.alt_description }));
    const out = selectImageCandidates(list, { query: "peanuts", category: "food" }).map(
      (c) => c.text,
    );
    expect(out[0]).toBe("roasted peanuts in a bowl");
    expect(out).not.toContain("peanut plant growing in a field");
    expect(out).not.toContain("yellow peanut flower");
  });

  it("マウス（機械）: 動物の写真は捨てる。動物のマウスでは機械を捨てられる", () => {
    const list = (
      fx.mouse.unsplash as {
        results: Array<{ alt_description: string; tags: Array<{ title: string }> }>;
      }
    ).results.map((r) => ({ text: [r.alt_description, ...r.tags.map((t) => t.title)].join(" ") }));
    const device = selectImageCandidates(list, { query: "computer mouse", category: "tech" });
    expect(device[0].text).toMatch(/wireless computer mouse/);
    expect(device.some((c) => /rodent|pet/.test(c.text))).toBe(false);
    const animal = selectImageCandidates(list, {
      query: "mouse",
      category: "animal",
      avoid: ["computer", "keyboard", "device"],
    });
    expect(animal.some((c) => /computer|keyboard/.test(c.text))).toBe(false);
    expect(animal[0].text).toMatch(/brown mouse/);
  });

  it("花を探している語は花を落とさない（蓮の花の語 → flower の棚）", () => {
    const out = selectImageCandidates([{ text: "pink lotus flower in bloom" }], {
      query: "lotus flower",
      category: "flower",
    });
    expect(out).toHaveLength(1);
  });
});

describe("searchImagesWith — レンコン（蓮藕）を文字で調べた時", () => {
  const fetchMock = vi.fn();
  beforeEach(() => {
    fetchMock.mockReset();
    vi.stubGlobal("fetch", fetchMock);
    vi.stubEnv("IMAGE_PROVIDER", "off");
    vi.stubEnv("UNSPLASH_ACCESS_KEY", "test-only");
    vi.spyOn(console, "warn").mockImplementation(() => undefined);
  });
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.unstubAllEnvs();
    vi.restoreAllMocks();
  });

  it("**前の動き（根本の原因）**: 意味の欄の日本語で探すと、出所が返す蓮の花がそのまま先頭だった", async () => {
    // カードの AI が答える前（`image_query` がまだ無い）・意味を決める AI が無い時。
    routeFetch(fetchMock, fx.lotusRoot.unsplashFlowersOnly);
    const out = await searchImagesWith(
      { query: "レンコン", language: "zh-TW", purpose: "candidates", category: "vegetable" },
      async () => undefined,
    );
    const asked = new URL(String(fetchMock.mock.calls[0][0]));
    expect(asked.searchParams.get("query")).toBe("レンコン");
    // 花・池は捨てるが、「ただの蓮」は説明だけでは外れと言えず残る — だから意味を決めて確かめる。
    expect(out.candidates.map((c) => c.url)).toEqual(["https://images.unsplash.com/lotus-3"]);
  });

  it("見出し語と意味があれば、探す前に意味を決めて英語で探す。花・池は1枚も出さない", async () => {
    routeFetch(fetchMock, fx.lotusRoot.unsplashMixed, fx.lotusRoot.commons);
    const d = deps();
    const out = await searchImagesWith(
      {
        query: "レンコン",
        language: "zh-TW",
        purpose: "candidates",
        category: "vegetable",
        headword: "蓮藕",
        meaning: "レンコン",
      },
      async () => undefined,
      d,
    );
    expect(d.resolveSense).toHaveBeenCalledWith({
      headword: "蓮藕",
      meaning: "レンコン",
      language: "zh-TW",
    });
    expect(unsplashQuery(fetchMock)).toBe("lotus root");
    const urls = out.candidates.map((c) => c.url);
    expect(urls[0]).toBe("https://images.unsplash.com/renkon-3");
    expect(urls).toContain("https://images.unsplash.com/renkon-dish-5");
    expect(urls.some((u) => /flower|pond|Nelumbo/i.test(u))).toBe(false);
    // 2026-10-09: 食べ物の棚は英語の題を信じず、学習言語の写真が無ければ絵を確かめる。
    // 確かめられない（ここでは null）時は、説明で確かな物だけ残る。
    expect(d.verify).toHaveBeenCalledTimes(1);
    // 学習言語（蓮藕）でも探している。
    expect(fetchMock.mock.calls.some(([u]) => String(u).includes("api.openverse.org"))).toBe(true);
  });

  it("Unsplash が花しか返さなければコモンズも探し、根の写真を先頭に", async () => {
    routeFetch(fetchMock, fx.lotusRoot.unsplashFlowersOnly, fx.lotusRoot.commons);
    const d = deps();
    const out = await searchImagesWith(
      {
        query: "lotus root",
        language: "zh-TW",
        purpose: "candidates",
        category: "vegetable",
        avoid: LOTUS_ROOT.avoid,
      },
      async () => undefined,
      d,
    );
    const urls = out.candidates.map((c) => c.url);
    expect(out.candidates[0].source).toBe("commons");
    expect(urls[0]).toContain("Renkon_lotus_root");
    expect(urls[1]).toContain("Lotus_root_slices");
    expect(urls.some((u) => /flower|pond|Nelumbo/i.test(u))).toBe(false);
    // 英語の検索語が在るので、意味は決め直さない。見出し語が無い（古い呼び出し）ので確かめない。
    expect(d.resolveSense).not.toHaveBeenCalled();
    expect(d.verify).not.toHaveBeenCalled();
  });

  it("説明で言い切れない時は絵を確かめ、外れと言われた物を捨てる", async () => {
    routeFetch(fetchMock, fx.lotusRoot.unsplashFlowersOnly);
    const d = deps({
      // 「ただの蓮」（lotus-3）は花だった、と答える。
      verify: vi.fn(async ({ images }) => ({
        checked: images.map((_: unknown, i: number) => i),
        matched: new Set<number>(),
      })),
    });
    const out = await searchImagesWith(
      {
        query: "レンコン",
        language: "zh-TW",
        purpose: "candidates",
        category: "vegetable",
        headword: "蓮藕",
        meaning: "レンコン",
      },
      async () => undefined,
      d,
    );
    expect(d.verify).toHaveBeenCalledTimes(1);
    const arg = d.verify.mock.calls[0][0] as {
      sense: ImageSense;
      images: Array<{ thumb: string }>;
    };
    expect(arg.sense.query).toBe("lotus root");
    // AI に見せるのは小さい絵（幅 256）。
    expect(arg.images[0].thumb).toContain("w=256");
    expect(out.candidates).toEqual([]);
  });

  it("確かめに失敗したら（時間切れなど）、食べ物の棚では説明で確かでない写真は出さない", async () => {
    routeFetch(fetchMock, fx.lotusRoot.unsplashFlowersOnly);
    const d = deps({ verify: vi.fn(async () => null) });
    const out = await searchImagesWith(
      {
        query: "lotus root",
        language: "zh-TW",
        purpose: "candidates",
        category: "vegetable",
        headword: "蓮藕",
        meaning: "レンコン",
        avoid: LOTUS_ROOT.avoid,
      },
      async () => undefined,
      d,
    );
    expect(d.verify).toHaveBeenCalledTimes(1);
    // 前は「ただの蓮」（lotus-3）を残していた。外れの写真より語の札（2026-10-09 オーナー報告）。
    expect(out.candidates).toEqual([]);
  });

  it("確かめに失敗しても、食べ物でない棚は説明の順のまま返す", async () => {
    routeFetch(fetchMock, fx.mouse.unsplash);
    const d = deps({
      resolveSense: vi.fn(async () => ({ query: "computer mouse", avoid: [] })),
      verify: vi.fn(async () => null),
    });
    const out = await searchImagesWith(
      {
        query: "computer mouse",
        language: "zh-TW",
        purpose: "candidates",
        category: "tech",
        headword: "滑鼠",
        meaning: "マウス",
      },
      async () => undefined,
      d,
    );
    expect(out.candidates.length).toBeGreaterThan(0);
    expect(out.candidates.every((c) => !/rodent|pet/.test(c.url))).toBe(true);
  });

  it("意味を決められなければ（同意・枠・失敗）今までどおり日本語で探す", async () => {
    routeFetch(fetchMock, fx.lotusRoot.unsplashMixed);
    const d = deps({ resolveSense: vi.fn(async () => null) });
    await searchImagesWith(
      { query: "レンコン", language: "zh-TW", purpose: "candidates", headword: "蓮藕" },
      async () => undefined,
      d,
    );
    expect(unsplashQuery(fetchMock)).toBe("レンコン");
  });

  it("牛蒡の見本も同じ道で: 花は出さず、根を先頭に", async () => {
    routeFetch(fetchMock, burdock.unsplash, burdock.commons);
    const out = await searchImagesWith(
      {
        query: "burdock root",
        language: "zh-TW",
        purpose: "candidates",
        category: "vegetable",
        avoid: ["flower", "thistle"],
      },
      async () => undefined,
      deps(),
    );
    const urls = out.candidates.map((c) => c.url);
    expect(urls[0]).toBe("https://images.unsplash.com/root-3");
    expect(urls.some((u) => /flower|wild/.test(u))).toBe(false);
  });
});

describe("カードの extras（image_avoid）", () => {
  it("読めて、「中身がある」には数えない", () => {
    expect(normalizeExtras({ image_avoid: ["flower", "pond"] })?.image_avoid).toEqual([
      "flower",
      "pond",
    ]);
    expect(normalizeExtras({ image_avoid: "flower" })?.image_avoid).toEqual([]);
    expect(hasExtrasContent({ image_avoid: ["flower"] })).toBe(false);
  });
});
