/**
 * **ネットの画像をサーバで取りに行く所の中身**（`fetchImageAsDataUrl` の本体）。
 *
 * ## なぜ切り出したか（オーナー報告 2026-10-07「画像をネットから探しています…」のまま）
 * 文字で足した語の見出しが「探しています…」のまま止まり、下の候補を押すと
 * 「画像の変更に失敗しました。」だけが出ていた。原因は取りに行く所にあった:
 *  - **名乗らずに取りに行っていた。** Cloudflare Workers の `fetch` は User-Agent を
 *    付けない。コモンズの置き場（`upload.wikimedia.org`）は名乗らない相手を 403 で
 *    弾く（Wikimedia の決まり）。検索の方は名乗っていたので、候補は出るのに保存できない。
 *  - **転送を一切受けなかった**（`redirect: "error"`）。置き場が別の URL へ回すと失敗する。
 *
 * サーバの奥（`createServerFn` の中）に埋めると試験から呼べないので、`fetch` を
 * 差し替えられる形でここに置く。
 *
 * ## SSRF 除けは保つ
 * 転送は自分で1段ずつ辿り、**行き先ごとに** https と許可リストを確かめ直す
 * （自動で辿らせると、許した置き場から内側の住所へ回されても気付けない）。
 */
import { MAX_PROXY_IMAGE_BYTES, readCappedBytes } from "./byte-cap";

// Allowlist of external image hosts we're willing to proxy. Keeps this
// endpoint from being abused as an SSRF gadget against internal/metadata
// endpoints (e.g. 169.254.169.254) or arbitrary internal services.
//
// **コモンズの置き場も許す**（2026-09-28 の点検で発見）。候補にコモンズの写真
// （`upload.wikimedia.org`）を出しているのに、ここで断っていたので**選んでも保存
// できなかった**。置き場は固定の1つなので、許可を1つ足すだけで SSRF 除けは保てる。
//
// **Openverse と Flickr も許す**（オーナー報告 2026-10-09「嘴邊肉の画像が英語で検索された画像」）。
// 学習言語で探す出所に Openverse（CC の写真の索引）を足した。候補の縮小版は
// `api.openverse.org/v1/images/<id>/thumb/`、Flickr の写真は `live.staticflickr.com`
// （古い形の `farmN.staticflickr.com` は live へ回される）。どれも固定の置き場で、
// 行き先は1段ずつ確かめ直すので SSRF 除けは保てる（API の JSON は画像の種類の確かめで断る）。
export const ALLOWED_IMAGE_HOSTS: ReadonlySet<string> = new Set<string>([
  "images.unsplash.com",
  "plus.unsplash.com",
  "upload.wikimedia.org",
  "api.openverse.org",
  "live.staticflickr.com",
  ...Array.from({ length: 9 }, (_, i) => `farm${i + 1}.staticflickr.com`),
]);

export const ALLOWED_IMAGE_MIME = /^image\/(jpeg|jpg|png|webp|gif|avif)$/i;

/**
 * 名乗り。Wikimedia の決まり（連絡先の分かる名前）に合わせる。
 * https://meta.wikimedia.org/wiki/User-Agent_policy
 */
export const IMAGE_FETCH_USER_AGENT = "CatchWords/1.0 (https://catchwords.lovable.app)";

/** 転送を辿る段の上限（回され続けて止まらないのを防ぐ）。 */
export const MAX_IMAGE_REDIRECTS = 3;

/** 行き先を確かめる。許さない物は理由付きで投げる。 */
export function assertAllowedImageUrl(raw: string): URL {
  let parsed: URL;
  try {
    parsed = new URL(raw);
  } catch {
    throw new Error("Invalid URL");
  }
  if (parsed.protocol !== "https:") {
    throw new Error("Only https URLs are permitted");
  }
  if (!ALLOWED_IMAGE_HOSTS.has(parsed.hostname.toLowerCase())) {
    throw new Error("URL host is not permitted");
  }
  return parsed;
}

type FetchLike = (url: string, init: RequestInit) => Promise<Response>;

/**
 * 許した置き場の画像を取り、data URL にして返す。
 *
 * 失敗の文は**日本語で、相手の答え（状態の番号）を添える** — 画面の
 * 「画像の変更に失敗しました」の後ろに理由として出す（`errors.ts`）。
 */
export async function fetchAllowedImage(
  raw: string,
  fetchImpl: FetchLike = fetch,
): Promise<{ dataUrl: string }> {
  let url = assertAllowedImageUrl(raw);
  let res: Response | null = null;
  for (let hop = 0; hop <= MAX_IMAGE_REDIRECTS; hop++) {
    res = await fetchImpl(url.toString(), {
      redirect: "manual",
      headers: { "User-Agent": IMAGE_FETCH_USER_AGENT, Accept: "image/*" },
      signal: AbortSignal.timeout(20_000),
    });
    if (res.status < 300 || res.status >= 400) break;
    const location = res.headers.get("location");
    await res.body?.cancel().catch(() => undefined);
    if (!location) throw new Error(`画像を取得できませんでした（${res.status}）`);
    if (hop === MAX_IMAGE_REDIRECTS) throw new Error("画像の転送が多すぎます");
    // 相対の転送先も、元の URL を基準に読んでから確かめ直す。
    url = assertAllowedImageUrl(new URL(location, url).toString());
  }
  if (!res) throw new Error("画像を取得できませんでした");
  if (!res.ok) {
    await res.body?.cancel().catch(() => undefined);
    throw new Error(`画像を取得できませんでした（${res.status}）`);
  }
  const ct = (res.headers.get("content-type") ?? "").split(";")[0].trim();
  if (!ALLOWED_IMAGE_MIME.test(ct)) {
    await res.body?.cancel().catch(() => undefined);
    throw new Error("Response is not a permitted image type");
  }
  // **大きさに上限**（監査 2026-10-03 L6）。許した置き場でも、とても大きい物を全部
  // 読むとサーバの記憶を食い潰す（`byte-cap.ts`）。
  const buf = await readCappedBytes(res, MAX_PROXY_IMAGE_BYTES);
  // base64 encode (Buffer is available in workers via nodejs_compat)
  const b64 = Buffer.from(buf).toString("base64");
  return { dataUrl: `data:${ct};base64,${b64}` };
}
