import { describe, it, expect } from "vitest";
import { commonsCandidates, commonsSearchUrl, type CommonsResponse } from "./commons-images";

/**
 * ネットの画像が出ない（オーナー報告 2026-08-27 ④）。
 *
 * 原因は出所が2つとも鍵か残高を要ることだった。ここで守るのは
 * 「**鍵の要らない出所が、返ってきた形の揺れに耐えて候補を出す**」の一点。
 */

const page = (over: Record<string, unknown> = {}) => ({
  title: "File:Map of Taipei.jpg",
  imageinfo: [
    {
      url: "https://upload.wikimedia.org/x/Map_of_Taipei.jpg",
      thumburl: "https://upload.wikimedia.org/thumb/x/Map_of_Taipei.jpg/960px-Map_of_Taipei.jpg",
      descriptionurl: "https://commons.wikimedia.org/wiki/File:Map_of_Taipei.jpg",
      extmetadata: {
        Artist: { value: '<a href="/wiki/User:Someone">Someone</a>' },
        LicenseShortName: { value: "CC BY-SA 4.0" },
      },
      ...over,
    },
  ],
});

describe("commonsCandidates", () => {
  it("鍵の付いたオブジェクトでも配列でも同じ物を返す", () => {
    const asObject: CommonsResponse = { query: { pages: { "123": page() } } };
    const asArray: CommonsResponse = { query: { pages: [page()] } };
    expect(commonsCandidates(asObject)).toEqual(commonsCandidates(asArray));
    expect(commonsCandidates(asObject)).toHaveLength(1);
  });

  it("帰属は HTML を落として、免許と一緒に持つ", () => {
    const [c] = commonsCandidates({ query: { pages: [page()] } });
    expect(c.credit.name).toBe("Someone / CC BY-SA 4.0");
    expect(c.credit.link).toContain("commons.wikimedia.org");
  });

  it("**作者が読めない画像は落とす**(出せない帰属を付けて出さない)", () => {
    const noArtist = page({ extmetadata: { LicenseShortName: { value: "CC0" } } });
    expect(commonsCandidates({ query: { pages: [noArtist] } })).toEqual([]);
  });

  it("写真でないファイル(SVG・音声・PDF)は落とす", () => {
    const svg = page({ url: "https://upload.wikimedia.org/x/Map.svg" });
    const ogg = page({ url: "https://upload.wikimedia.org/x/Map.ogg" });
    expect(commonsCandidates({ query: { pages: [svg, ogg] } })).toEqual([]);
  });

  it("縮小版が無ければ原寸を使う(1枚も落とさない)", () => {
    const [c] = commonsCandidates({ query: { pages: [page({ thumburl: undefined })] } });
    expect(c.thumb).toBe(c.url);
  });

  it("**保存に使う URL も縮小版**(原寸は大きさの上限で断られる。2026-10-07)", () => {
    const [c] = commonsCandidates({ query: { pages: [page()] } });
    expect(c.url).toBe(
      "https://upload.wikimedia.org/thumb/x/Map_of_Taipei.jpg/960px-Map_of_Taipei.jpg",
    );
    // 一覧の絵は決まった幅の小さい方。
    expect(c.thumb).toBe(
      "https://upload.wikimedia.org/thumb/x/Map_of_Taipei.jpg/500px-Map_of_Taipei.jpg",
    );
  });

  it("同じ URL は1度だけ", () => {
    expect(commonsCandidates({ query: { pages: [page(), page()] } })).toHaveLength(1);
  });

  it("空・壊れた答えでも落ちない", () => {
    expect(commonsCandidates({})).toEqual([]);
    expect(commonsCandidates({ query: {} })).toEqual([]);
    expect(commonsCandidates({ query: { pages: {} } })).toEqual([]);
    expect(commonsCandidates({ query: { pages: [{}] } })).toEqual([]);
  });

  it("上限を超えて返さない", () => {
    const many = Array.from({ length: 12 }, (_, i) =>
      page({ url: `https://upload.wikimedia.org/x/${i}.jpg` }),
    );
    expect(commonsCandidates({ query: { pages: many } }, 3)).toHaveLength(3);
  });
});

describe("commonsSearchUrl", () => {
  it("**鍵を1つも付けない**(この出所の要点)", () => {
    expect(commonsSearchUrl("地図")).not.toMatch(/key=|token=|client[-_]?id/i);
  });

  it("ファイル空間の画像だけを探す", () => {
    const u = new URL(commonsSearchUrl("map"));
    expect(u.searchParams.get("gsrnamespace")).toBe("6");
    expect(u.searchParams.get("gsrsearch")).toContain("filetype:bitmap");
    expect(u.searchParams.get("iiurlwidth")).toBe("960");
  });

  it("検索語をそのまま繋がない(記号で URL が壊れない)", () => {
    const u = commonsSearchUrl("a&b=c d");
    expect(() => new URL(u)).not.toThrow();
    expect(new URL(u).searchParams.get("gsrsearch")).toBe("filetype:bitmap a&b=c d");
  });
});
