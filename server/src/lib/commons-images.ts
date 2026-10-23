/**
 * ウィキメディア・コモンズの検索結果を、札の絵の候補に読み替える。
 *
 * ## なぜ足したか（オーナー報告 2026-08-27 ④）
 * > 「単語の詳細のネットの画像がよく表示されない不具合を直して。」
 *
 * 絵の出所はこれまで2つしか無く、**どちらも鍵か残高を要る**:
 *   1. Unsplash … `UNSPLASH_ACCESS_KEY` が要る
 *   2. AI の生成 … `LOVABLE_API_KEY` と残高が要る
 *
 * どちらかが切れると候補は 0 件になり、画面には「画像がありません」だけが
 * 残る。**鍵の要らない出所が1つも無い**のが「よく表示されない」の形。
 *
 * コモンズは鍵が要らず、素性のはっきりした自由利用の画像が
 * 数千万枚ある。街で見かける具体的な物（地図・靴下・駅）は特に強い。
 *
 * ## ここは純粋な物
 * 取りに行くのは `images.functions.ts`。ここは**返ってきた JSON を
 * 候補に直すだけ**なので、試験から素の値を渡して確かめられる。
 * この app が何度も踏んだ「server の奥に判断が埋まっていて誰も見ていない」
 * を避ける。
 */

/** コモンズの `imageinfo` の、こちらが見る所だけ。 */
export type CommonsPage = {
  title?: string;
  imageinfo?: Array<{
    url?: string;
    thumburl?: string;
    descriptionurl?: string;
    extmetadata?: Record<string, { value?: unknown } | undefined>;
  }>;
};

export type CommonsResponse = {
  query?: { pages?: Record<string, CommonsPage> | CommonsPage[] };
};

export type CommonsCandidate = {
  url: string;
  thumb: string;
  credit: { name: string; link: string };
  /**
   * 題・説明・分類をつないだ字（並べ直しの手がかり。`image-search-rank.ts`）。
   * 画面には出さない — 候補を返す前に `images.functions.ts` が落とす。
   */
  text: string;
};

/**
 * 絵として使えない拡張子。
 *
 * コモンズの検索は音声・動画・PDF・SVG も返す。SVG を外すのは、
 * 図版（地図記号や国旗の作図）が「その語を表す写真」の代わりにならない
 * ことが多いため — 札の主役に据えると、何の絵なのか読めない。
 */
const NOT_A_PHOTO = /\.(svg|ogv|ogg|oga|webm|mid|flac|wav|pdf|djvu|tif|tiff)$/i;

/** `extmetadata` の値は HTML が入っていることがある。字だけにする。 */
function plainText(raw: unknown): string {
  if (typeof raw !== "string") return "";
  return raw
    .replace(/<[^>]*>/g, " ")
    .replace(/&[a-z]+;/gi, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function metaValue(page: CommonsPage, key: string): string {
  const info = page.imageinfo?.[0];
  return plainText(info?.extmetadata?.[key]?.value);
}

/**
 * コモンズの答えを候補の並びに直す。
 *
 * **順番を保つ。** コモンズは関連の高い順に返すので、こちらで並べ替えない。
 * `pages` はオブジェクト（鍵が page id）で返ることも配列で返ることもある
 * ので、どちらも受ける。
 *
 * 帰属は必須（コモンズの多くは CC BY / CC BY-SA）。作者が読めない画像は
 * **落とす** — 出せない帰属を付けて出すより、その1枚を諦めるほうがいい。
 */
export function commonsCandidates(json: CommonsResponse, limit = 6): CommonsCandidate[] {
  const raw = json.query?.pages;
  const pages: CommonsPage[] = Array.isArray(raw) ? raw : Object.values(raw ?? {});
  const out: CommonsCandidate[] = [];
  const seen = new Set<string>();
  for (const page of pages) {
    const info = page.imageinfo?.[0];
    const url = info?.url;
    if (!url || seen.has(url)) continue;
    if (NOT_A_PHOTO.test(url)) continue;
    const artist = metaValue(page, "Artist");
    const license = metaValue(page, "LicenseShortName");
    if (!artist) continue;
    seen.add(url);
    // **保存に使うのも縮小版**（オーナー報告 2026-10-07「画像の変更に失敗」）。
    // 原寸は数十 MB の写真もあり、サーバの大きさの上限（`byte-cap.ts`）で断られる。
    // 縮小版が無い（原寸が小さい）時だけ原寸を使う。
    const full = info?.thumburl || url;
    out.push({
      url: full,
      // 一覧の小さな絵は、決まった幅の小さい縮小版にする（無ければ同じ物）。
      thumb: smallerThumb(full),
      credit: {
        name: license ? `${artist} / ${license}` : artist,
        link: info?.descriptionurl || url,
      },
      text: [
        (page.title ?? "").replace(/^File:/i, "").replace(/\.[a-z0-9]+$/i, ""),
        metaValue(page, "ObjectName"),
        metaValue(page, "ImageDescription"),
        metaValue(page, "Categories"),
      ]
        .filter(Boolean)
        .join(" ")
        .replace(/[_|]/g, " ")
        .slice(0, 600),
    });
    if (out.length >= limit) break;
  }
  return out;
}

/**
 * 縮小版を頼む幅。**Wikimedia が決めている幅だけ**を使う（決まった幅以外は
 * その場で作らせることになり、断られたり遅くなったりする）。
 * https://www.mediawiki.org/wiki/Common_thumbnail_sizes
 */
export const COMMONS_IMAGE_WIDTH = 960;
export const COMMONS_THUMB_WIDTH = 500;

/** `.../960px-名前.jpg` を一覧用の幅に置き換える。形が違えばそのまま。 */
function smallerThumb(url: string): string {
  return url.replace(`/${COMMONS_IMAGE_WIDTH}px-`, `/${COMMONS_THUMB_WIDTH}px-`);
}

/**
 * 検索の URL。**鍵を付けない**（付ける鍵が無いのがこの出所の要点）。
 *
 * `gsrnamespace=6` はファイル空間。`iiurlwidth` を付けると縮小版の URL が
 * 一緒に返るので、一覧に並べるぶんの帯域を丸ごと節約できる。
 */
export function commonsSearchUrl(query: string, limit = 6): string {
  const u = new URL("https://commons.wikimedia.org/w/api.php");
  u.searchParams.set("action", "query");
  u.searchParams.set("format", "json");
  u.searchParams.set("generator", "search");
  u.searchParams.set("gsrsearch", `filetype:bitmap ${query}`);
  u.searchParams.set("gsrnamespace", "6");
  u.searchParams.set("gsrlimit", String(limit));
  u.searchParams.set("prop", "imageinfo");
  u.searchParams.set("iiprop", "url|extmetadata");
  u.searchParams.set("iiurlwidth", String(COMMONS_IMAGE_WIDTH));
  return u.toString();
}
