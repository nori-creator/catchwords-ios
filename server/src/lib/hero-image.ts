/**
 * 「この札の見出しに、ネットの画像を1枚あてがうか」を決める唯一の場所。
 *
 * オーナー指摘 2026-08-21:
 * > 「文字入力した単語はホームのアルバムに単語の文字だけ書いて。またその
 * >  単語をタップすると、単語の詳細が開くようにして。**単語の詳細の見出しの
 * >  画像はネットからその単語を表す画像を添付して。**」
 *
 * ## なぜ集約するか — 片方の詳細にしか付いていなかった
 * 詳細は**2つある**。ホームやアルバムから開く `StickerSheet` と、
 * 図鑑から開く `/dex/$stickerId` のページ。ネット画像の自動添付は
 * **`StickerSheet` にしか無く**、`/dex/$stickerId` は
 * `placeholder_url` を**描くだけ**で取りに行かない。だから図鑑から開いた
 * 文字キャッチの語は、いつまでも見出しが空のままだった。
 *
 * この app が何度も踏んでいる「兄弟の取りこぼし」
 * (声・場所・写真の選び方・演出) と同じ形なので、**判断をここに1つ置いて**
 * 両方の詳細から同じ物を呼ぶ。
 *
 * ## 探す言葉は「意味」であって「語」ではない
 * 画像検索に `腳踏車` を渡すと、中国語の通販の写真や字が写った画像が返る。
 * 母語の意味(`自転車`)を渡したほうが**その語を表す絵**に近い。
 * ただし意味の欄は辞書の書き方をそのまま持っていて
 * (`自転車、チャリ（口語）`)、丸ごと渡すと検索が壊れる。
 * **最初の1語だけに削ってから**渡す。
 *
 * 外の世界に触れるものをここに入れないこと。
 */

import { hasOwnPhoto, type PhotoSources } from "./sticker-photo";

/** 検索語の上限。長い文を投げると画像検索は当たらなくなる。 */
export const MAX_QUERY_CHARS = 40;

/** 意味の欄で語義を区切っている記号。 */
const SENSE_SEPARATORS = /[、,，;；/・|]/;

/** 括弧とその中身(`（口語）` `《動》` `[名]`)。絵の手がかりにならない。 */
const BRACKETED = /[（(【〈《[「][^）)】〉》\]」]*[）)】〉》\]」]/g;

/** 見出し語の穴埋め記号(`〜` `～` `…`)。検索語に残すと当たらない。 */
const PLACEHOLDERS = /[〜～……]/g;

/**
 * その札は、ネットの画像を**新しく1枚**あてがう必要があるか。
 *
 * **自分の絵があるものには触らない。** 自撮りだけの札も触らない —
 * 自撮りがその札の主役で、ネット画像を足すと主役が入れ替わって見える。
 * すでに仮画像が入っているものも触らない(勝手に別の絵に変えない)。
 */
export function needsWebHero(sources: PhotoSources | null | undefined): boolean {
  if (!sources) return false;
  return !hasOwnPhoto(sources) && !sources.placeholder_url;
}

/**
 * 「別の画像に変える」候補を並べてよいか。
 *
 * `needsWebHero` より**広い** — すでに仮画像が入っていても、気に入らな
 * ければ選び直せるように候補は出す。自分で撮った写真がある札だけは、
 * 差し替えを勧めない(撮った物がその札の答えなので)。
 */
export function shouldOfferWebCandidates(sources: PhotoSources | null | undefined): boolean {
  if (!sources) return false;
  return !sources.object_url && !sources.cutout_url;
}

/**
 * 画像検索に投げる言葉を作る。
 *
 * 1. カードを作る時に AI が返した**画像検索用の英語**（`extras.image_query`）が在れば
 *    それを使う（オーナー報告 2026-10-08「牛蒡を検索すると花の写真しか出ない」 —
 *    意味の欄の `ゴボウ` で探すと植物のゴボウの花に当たる。`burdock root` なら食べる根）
 * 2. 無ければ（古いカード）意味の欄を**最初の語義だけ**に削り、括弧と穴埋め記号を落とす
 * 3. 何も残らなければ見出し語そのものに落ちる(空の検索を投げない)
 */
export function heroSearchQuery(word: {
  headword?: string | null;
  meaning?: string | null;
  imageQuery?: string | null;
}): string {
  const head = (word.headword ?? "").trim();
  const preferred = cleanImageQuery(word.imageQuery);
  if (preferred) return preferred;
  const cleaned = firstSense(word.meaning ?? "");
  return (cleaned || head).slice(0, MAX_QUERY_CHARS);
}

/**
 * `extras.image_query` を検索語に使える形にする。引用符・括弧を落とし、空白を詰め、
 * 長すぎる物は語の切れ目で切る。文になっている物（句点入り・語が多すぎる）は使わない。
 */
export function cleanImageQuery(raw: string | null | undefined): string {
  if (typeof raw !== "string") return "";
  const t = raw
    .replace(BRACKETED, " ")
    .replace(/["'“”‘’「」『』]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .replace(/[。.]+$/, "")
    .trim();
  if (!t || /[。!?！？]/.test(t)) return "";
  const words = t.split(" ");
  if (words.length > 6) return "";
  let out = "";
  for (const w of words) {
    const next = out ? `${out} ${w}` : w;
    if (next.length > MAX_QUERY_CHARS) break;
    out = next;
  }
  return out;
}

/** 札の語から、画像検索の手がかり（`extras.image_query`）を読む。形が違えば空。 */
export function imageQueryOf(extras: unknown): string {
  if (!extras || typeof extras !== "object") return "";
  const v = (extras as { image_query?: unknown }).image_query;
  return typeof v === "string" ? v : "";
}

function firstSense(raw: string): string {
  // 括弧を先に落とす。`自転車（口語では腳踏車）` の中の「、」で
  // 切ってしまうと、括弧の片割れだけが残る。
  const noBrackets = raw.replace(BRACKETED, " ");
  const first = noBrackets.split(SENSE_SEPARATORS)[0] ?? "";
  return first.replace(PLACEHOLDERS, " ").replace(/\s+/g, " ").trim();
}

/**
 * **自動の1枚を入れる手順**（`useAutoHero`）。人が「別の画像」を選んだ・AI で絵を作り始めた
 * 後は、遅れて届いた自動の1枚で**上書きしない**（Codex 指摘 2026-10-07: 自動の検索・保存が
 * 遅いと、先に入った AI の絵を自動の絵が塗り替えていた）。
 *
 * - 写す前に人の操作が始まっていたら、何もしない（写しもしない）。
 * - 写した後に始まっていたら、写した物を消して仮画像にはしない（置き去りの画像を残さない）。
 */
export async function placeAutoHeroWith(deps: {
  /** 人が差し替え・AI の絵を始めたか。 */
  superseded: () => boolean;
  /** 自分のフォルダへ写す。返すのは保存した path。 */
  upload: () => Promise<string>;
  /** 写した物を札の仮画像にする。 */
  save: (path: string) => Promise<void>;
  /** 使わなかった写しを消す（失敗しても構わない）。 */
  discard: (path: string) => Promise<void>;
}): Promise<"saved" | "superseded"> {
  if (deps.superseded()) return "superseded";
  const path = await deps.upload();
  if (deps.superseded()) {
    await deps.discard(path).catch(() => undefined);
    return "superseded";
  }
  await deps.save(path);
  return "saved";
}
