import { describe, it, expect } from "vitest";
import { hasOwnPhoto, pickStickerPhoto, stickerPhotoUrl, type PhotoSources } from "./sticker-photo";
import { photoCandidates } from "./sticker-photo";

/**
 * ここが7通りに散らばっていたせいで、同じ札が画面をまたぐと
 * 別の写真で出ていた。**画面ごとの意図は残しつつ、落ち方は共通**にする。
 */

const ALL: PhotoSources = {
  object_url: "obj.jpg",
  object_thumb_url: "obj.thumb.webp",
  cutout_url: "cut.png",
  cutout_thumb_url: "cut.thumb.webp",
  selfie_url: "me.jpg",
  placeholder_url: "net.jpg",
};

describe("pickStickerPhoto — 既定の落ち方", () => {
  it("何も言わなければ元写真", () => {
    expect(pickStickerPhoto(ALL)?.role).toBe("object");
  });

  it("元写真が無ければ切り抜き、次に自撮り、最後にネット画像", () => {
    expect(pickStickerPhoto({ ...ALL, object_url: null, object_thumb_url: null })?.role).toBe(
      "cutout",
    );
    expect(pickStickerPhoto({ selfie_url: "me.jpg", placeholder_url: "net.jpg" })?.role).toBe(
      "selfie",
    );
    expect(pickStickerPhoto({ placeholder_url: "net.jpg" })?.role).toBe("placeholder");
  });

  it("1枚も無ければ null", () => {
    expect(pickStickerPhoto({})).toBeNull();
    expect(pickStickerPhoto(null)).toBeNull();
    expect(pickStickerPhoto(undefined)).toBeNull();
    expect(stickerPhotoUrl({})).toBeNull();
  });

  it("空文字は「在る」と数えない", () => {
    expect(pickStickerPhoto({ object_url: "", cutout_url: "cut.png" })?.role).toBe("cutout");
  });
});

describe("pickStickerPhoto — 画面ごとの意図", () => {
  it("棚は切り抜きを先に見る(立てるため)", () => {
    const p = pickStickerPhoto(ALL, { prefer: "cutout", thumb: true });
    expect(p).toEqual({ url: "cut.thumb.webp", role: "cutout", thumb: true });
  });

  it("アルバムは自撮りを先に見る", () => {
    expect(pickStickerPhoto(ALL, { prefer: "selfie" })?.role).toBe("selfie");
  });

  it("先に見たい役が無ければ、既定の順に落ちる", () => {
    const noCutout = { ...ALL, cutout_url: null, cutout_thumb_url: null };
    expect(pickStickerPhoto(noCutout, { prefer: "cutout" })?.role).toBe("object");
  });

  /**
   * **設定やDBから来た文字列をそのまま渡せること。**
   * ここで投げると、値が古いだけで画面が真っ白になる。
   */
  it.each([null, undefined, "", "CUTOUT", "写真", 3, true, {}])(
    "知らない好み %p は既定の順に落ちるだけ",
    (bad) => {
      expect(pickStickerPhoto(ALL, { prefer: bad as never })?.role).toBe("object");
    },
  );
});

describe("pickStickerPhoto — 縮小版", () => {
  it("小さく出す所では縮小版を使う", () => {
    expect(pickStickerPhoto(ALL, { thumb: true })).toEqual({
      url: "obj.thumb.webp",
      role: "object",
      thumb: true,
    });
  });

  it("縮小版が無ければ原寸に落ちる", () => {
    const p = pickStickerPhoto({ object_url: "obj.jpg" }, { thumb: true });
    expect(p).toEqual({ url: "obj.jpg", role: "object", thumb: false });
  });

  /** 原寸の掃除が済んで縮小版しか無い札を**取りこぼさない**。 */
  it("縮小版しか無くても出す", () => {
    const p = pickStickerPhoto({ object_thumb_url: "obj.thumb.webp" });
    expect(p).toEqual({ url: "obj.thumb.webp", role: "object", thumb: true });
  });

  it("大きく出す所では原寸を使う", () => {
    expect(pickStickerPhoto(ALL, { thumb: false })?.url).toBe("obj.jpg");
  });
});

describe("hasOwnPhoto", () => {
  it("自分で撮った絵があるか", () => {
    expect(hasOwnPhoto({ object_url: "o.jpg" })).toBe(true);
    expect(hasOwnPhoto({ cutout_thumb_url: "c.webp" })).toBe(true);
    expect(hasOwnPhoto({ selfie_url: "me.jpg" })).toBe(true);
  });

  /** ネット画像しか無い札を「撮った」と数えない。 */
  it("ネット画像だけなら false", () => {
    expect(hasOwnPhoto({ placeholder_url: "net.jpg" })).toBe(false);
    expect(hasOwnPhoto({})).toBe(false);
    expect(hasOwnPhoto(null)).toBe(false);
  });
});

/**
 * オーナー指摘 2026-08-21:
 * > 「文字入力した単語はホームのアルバムに**単語の文字だけ**書いて。」
 *
 * アルバムはネットの絵を貼らない。詳細では逆にそれが見出しになるので、
 * 「持っていない」ことにはせず、**画面ごとに外す**。
 */
describe("exclude — 画面ごとに外す役", () => {
  it("外した役は選ばれない", () => {
    expect(pickStickerPhoto({ placeholder_url: "net.jpg" }, { exclude: ["placeholder"] })).toBe(
      null,
    );
  });

  it("外しても、残りの役からは普通に選ぶ", () => {
    const got = pickStickerPhoto(
      { object_url: "o.jpg", placeholder_url: "net.jpg" },
      { exclude: ["placeholder"] },
    );
    expect(got?.role).toBe("object");
  });

  it("**外す役は `prefer` より強い**(好みで押し戻せない)", () => {
    expect(
      pickStickerPhoto(
        { placeholder_url: "net.jpg" },
        { prefer: "placeholder", exclude: ["placeholder"] },
      ),
    ).toBe(null);
    // 好みが外した役でも、残りからは選ぶ
    expect(
      pickStickerPhoto(
        { selfie_url: "me.jpg", placeholder_url: "net.jpg" },
        { prefer: "placeholder", exclude: ["placeholder"] },
      )?.role,
    ).toBe("selfie");
  });

  it("複数まとめて外せる", () => {
    expect(
      pickStickerPhoto(
        { selfie_url: "me.jpg", placeholder_url: "net.jpg" },
        { exclude: ["selfie", "placeholder"] },
      ),
    ).toBe(null);
  });

  it("**外さないときは今までどおり**(既定の振る舞いを変えない)", () => {
    expect(pickStickerPhoto({ placeholder_url: "net.jpg" })?.role).toBe("placeholder");
    expect(pickStickerPhoto({ placeholder_url: "net.jpg" }, { exclude: [] })?.role).toBe(
      "placeholder",
    );
  });

  it("`stickerPhotoUrl` からも外せる", () => {
    expect(stickerPhotoUrl({ placeholder_url: "net.jpg" }, { exclude: ["placeholder"] })).toBe(
      null,
    );
  });
});

describe("photoCandidates（地図のピン: 読めなければ次へ）", () => {
  it("縮小版 → 原寸 → 別の役。重複なし", () => {
    const c = photoCandidates({
      object_thumb_url: "o.thumb",
      object_url: "o",
      cutout_url: "c",
      placeholder_url: "p",
    });
    expect(c).toEqual(["o.thumb", "o", "c", "p"]);
  });
  it("何も無ければ空", () => {
    expect(photoCandidates(null)).toEqual([]);
    expect(photoCandidates({})).toEqual([]);
  });
});
