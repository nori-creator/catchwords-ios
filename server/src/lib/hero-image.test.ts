import { describe, it, expect } from "vitest";
import fs from "node:fs";
import path from "node:path";
import {
  needsWebHero,
  shouldOfferWebCandidates,
  heroSearchQuery,
  cleanImageQuery,
  imageQueryOf,
  MAX_QUERY_CHARS,
  placeAutoHeroWith,
} from "./hero-image";

/**
 * オーナー指摘「単語の詳細の見出しの画像はネットからその単語を表す画像を
 * 添付して」の受け皿。
 *
 * ここで一番怖いのは**自分で撮った写真を押しのけること**なので、
 * 「あてがう」側より「触らない」側の試験を厚くする。
 */

describe("needsWebHero — あてがう", () => {
  it("**1枚も絵が無い札**にはあてがう(文字キャッチの札)", () => {
    expect(needsWebHero({})).toBe(true);
    expect(
      needsWebHero({ object_url: null, cutout_url: null, selfie_url: null, placeholder_url: null }),
    ).toBe(true);
  });
});

describe("needsWebHero — 触らない", () => {
  it("自分で撮った写真がある札には触らない", () => {
    expect(needsWebHero({ object_url: "o.jpg" })).toBe(false);
    expect(needsWebHero({ cutout_url: "c.png" })).toBe(false);
    // 原寸の掃除が済んで縮小版しか無い札も「撮った写真がある」
    expect(needsWebHero({ object_thumb_url: "o-s.jpg" })).toBe(false);
    expect(needsWebHero({ cutout_thumb_url: "c-s.png" })).toBe(false);
  });

  it("**自撮りだけの札にも触らない**(主役が入れ替わって見える)", () => {
    expect(needsWebHero({ selfie_url: "me.jpg" })).toBe(false);
  });

  it("すでに仮画像が入っている札には触らない(勝手に別の絵に変えない)", () => {
    expect(needsWebHero({ placeholder_url: "net.jpg" })).toBe(false);
  });

  it("札そのものが無いときは何もしない", () => {
    expect(needsWebHero(null)).toBe(false);
    expect(needsWebHero(undefined)).toBe(false);
  });
});

describe("shouldOfferWebCandidates", () => {
  it("**仮画像が入っていても候補は出す**(選び直せる)", () => {
    expect(shouldOfferWebCandidates({ placeholder_url: "net.jpg" })).toBe(true);
    expect(shouldOfferWebCandidates({ selfie_url: "me.jpg" })).toBe(true);
    expect(shouldOfferWebCandidates({})).toBe(true);
  });

  it("自分で撮った写真がある札には差し替えを勧めない", () => {
    expect(shouldOfferWebCandidates({ object_url: "o.jpg" })).toBe(false);
    expect(shouldOfferWebCandidates({ cutout_url: "c.png" })).toBe(false);
  });

  it("**`needsWebHero` より広い**(あてがう所は必ず候補も出る)", () => {
    const cases = [
      {},
      { placeholder_url: "n.jpg" },
      { selfie_url: "m.jpg" },
      { object_url: "o.jpg" },
      { cutout_url: "c.png" },
    ];
    for (const c of cases) {
      if (needsWebHero(c)) expect(shouldOfferWebCandidates(c)).toBe(true);
    }
  });
});

describe("heroSearchQuery", () => {
  it("意味をそのまま使う(語ではなく意味で探す)", () => {
    expect(heroSearchQuery({ headword: "腳踏車", meaning: "自転車" })).toBe("自転車");
  });

  it("**最初の語義だけに削る**(辞書の書き方を丸ごと投げない)", () => {
    expect(heroSearchQuery({ headword: "紙", meaning: "紙、書類、新聞" })).toBe("紙");
    expect(heroSearchQuery({ headword: "捷運", meaning: "MRT / 地下鉄" })).toBe("MRT");
    expect(heroSearchQuery({ headword: "雨傘", meaning: "傘・雨傘" })).toBe("傘");
  });

  it("括弧とその中身を落とす", () => {
    expect(heroSearchQuery({ headword: "腳踏車", meaning: "自転車（口語）" })).toBe("自転車");
    expect(heroSearchQuery({ headword: "跑", meaning: "走る《動》" })).toBe("走る");
    expect(heroSearchQuery({ headword: "書", meaning: "[名] 本" })).toBe("本");
  });

  it("**括弧の中の区切りで切らない**(片割れが残る)", () => {
    expect(heroSearchQuery({ headword: "腳踏車", meaning: "自転車（自転車、チャリ）" })).toBe(
      "自転車",
    );
  });

  it("穴埋めの記号を落とす", () => {
    expect(heroSearchQuery({ headword: "把", meaning: "〜を…する" })).toBe("を する");
  });

  it("**意味が無ければ見出し語で探す**(空の検索を投げない)", () => {
    expect(heroSearchQuery({ headword: "夜市", meaning: "" })).toBe("夜市");
    expect(heroSearchQuery({ headword: "夜市", meaning: null })).toBe("夜市");
    expect(heroSearchQuery({ headword: "夜市" })).toBe("夜市");
    // 括弧を落としたら何も残らない回も同じ
    expect(heroSearchQuery({ headword: "夜市", meaning: "（口語）" })).toBe("夜市");
  });

  it("どちらも無ければ空(呼ぶ側が投げないで済む)", () => {
    expect(heroSearchQuery({})).toBe("");
    expect(heroSearchQuery({ headword: null, meaning: null })).toBe("");
  });

  it(`長すぎる意味は ${MAX_QUERY_CHARS} 文字で切る`, () => {
    const long = "あ".repeat(120);
    expect(heroSearchQuery({ headword: "x", meaning: long })).toHaveLength(MAX_QUERY_CHARS);
  });

  it("前後の空白を残さない", () => {
    expect(heroSearchQuery({ headword: "書", meaning: "  本  、 書類 " })).toBe("本");
  });
});

/**
 * 自動の1枚と、人の差し替え・AI の絵が重なった時（Codex 指摘 2026-10-07）。
 * 遅れて届いた自動の1枚で、人が選んだ絵を塗り替えない。
 */
describe("placeAutoHeroWith — 人の操作を上書きしない", () => {
  const run = (supersededAt: "never" | "before" | "afterUpload") => {
    const log: string[] = [];
    let manual = supersededAt === "before";
    const result = placeAutoHeroWith({
      superseded: () => manual,
      upload: async () => {
        log.push("upload");
        if (supersededAt === "afterUpload") manual = true;
        return "u/1-placeholder.jpg";
      },
      save: async (p) => {
        log.push(`save:${p}`);
      },
      discard: async (p) => {
        log.push(`discard:${p}`);
      },
    });
    return { result, log };
  };

  it("誰も触っていなければ、写して仮画像にする", async () => {
    const { result, log } = run("never");
    await expect(result).resolves.toBe("saved");
    expect(log).toEqual(["upload", "save:u/1-placeholder.jpg"]);
  });

  it("**写す前に差し替え・AI の絵が始まっていたら、写しもしない**", async () => {
    const { result, log } = run("before");
    await expect(result).resolves.toBe("superseded");
    expect(log).toEqual([]);
  });

  it("**写している間に始まったら、仮画像にせず写しを消す**（置き去りにしない）", async () => {
    const { result, log } = run("afterUpload");
    await expect(result).resolves.toBe("superseded");
    expect(log).toEqual(["upload", "discard:u/1-placeholder.jpg"]);
  });

  it("消すのに失敗しても、上書きはしない", async () => {
    await expect(
      placeAutoHeroWith({
        superseded: (() => {
          let n = 0;
          return () => n++ > 0;
        })(),
        upload: async () => "p",
        save: async () => {
          throw new Error("上書きしてはいけない");
        },
        discard: async () => {
          throw new Error("消せない");
        },
      }),
    ).resolves.toBe("superseded");
  });

});

describe("heroSearchQuery — 画像検索用の英語（オーナー報告 2026-10-08「牛蒡で花の写真しか出ない」）", () => {
  it("AI が返した image_query が在れば、意味の欄より先に使う", () => {
    expect(
      heroSearchQuery({ headword: "牛蒡", meaning: "ゴボウ", imageQuery: "burdock root" }),
    ).toBe("burdock root");
  });

  it("無い・空・形が違う時は今までどおり意味の欄（古いカード）", () => {
    expect(heroSearchQuery({ headword: "牛蒡", meaning: "ゴボウ" })).toBe("ゴボウ");
    expect(heroSearchQuery({ headword: "牛蒡", meaning: "ゴボウ", imageQuery: "  " })).toBe(
      "ゴボウ",
    );
    expect(heroSearchQuery({ headword: "牛蒡", meaning: "ゴボウ", imageQuery: null })).toBe(
      "ゴボウ",
    );
  });

  it("cleanImageQuery: 引用符・括弧・末尾の句点を落とし、文は使わない", () => {
    expect(cleanImageQuery('"burdock root"')).toBe("burdock root");
    expect(cleanImageQuery("burdock root (vegetable).")).toBe("burdock root");
    expect(cleanImageQuery("This is a photo of a root! Really?")).toBe("");
    expect(cleanImageQuery("a b c d e f g")).toBe("");
    expect(cleanImageQuery(undefined)).toBe("");
    const long = cleanImageQuery("supercalifragilistic expialidocious vegetable root");
    expect(long.length).toBeLessThanOrEqual(MAX_QUERY_CHARS);
    expect(long.endsWith(" ")).toBe(false);
  });

  it("imageQueryOf: 札の extras から読む（無い・形が違えば空）", () => {
    expect(imageQueryOf({ image_query: "mango fruit" })).toBe("mango fruit");
    expect(imageQueryOf({ image_query: 3 })).toBe("");
    expect(imageQueryOf(null)).toBe("");
  });
});
