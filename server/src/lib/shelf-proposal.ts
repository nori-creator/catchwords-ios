/**
 * AI が出した「新しい棚」の提案を、そのまま DB に入れられる形に直す。
 *
 * ## なぜここが要るか
 * 生成物は**必ず**想定外を出す。棚の鍵に日本語が来る、`__proto__` が来る、
 * 40字の説明文が来る、絵文字の欄に「なし」と書いてくる。DB 側にも
 * check 制約を置いてあるが、制約に当たれば**保存全体が落ちる** —
 * 語のキャッチという主目的まで巻き添えにする。
 * だから「直せるなら直す、直せないなら諦めて既定の分類に戻す」を
 * ここで完結させる。**呼び出し側は例外を受け取らない。**
 *
 * ## 諦めるのは失敗ではない
 * 新しい棚が作れなくても、語は既定の54棚のどれかに載る。
 * 棚が1つ増えないことと、キャッチが丸ごと失敗することは、
 * ユーザーにとって全く重さが違う。
 */

import { CATEGORY_KEYS, ROOM_KEYS } from "@/lib/category";

/** DB の check 制約と同じ形。ここを変えたらマイグレーションも変える。 */
const KEY_RE = /^[a-z][a-z0-9_]{1,38}$/;
const LABEL_MAX = 24;
const EMOJI_MAX = 8;

/** AI から来る生の提案(何が入っているか分からない)。 */
export type RawShelfProposal = {
  key?: unknown;
  label?: unknown;
  emoji?: unknown;
  room_key?: unknown;
  room_label?: unknown;
};

export type ShelfProposal = {
  key: string;
  label: string;
  emoji: string;
  room_key: string;
  room_label: string;
};

/** 鍵の形に寄せる。直せなければ null。 */
function toKey(v: unknown): string | null {
  if (typeof v !== "string") return null;
  const slug = v
    .trim()
    .toLowerCase()
    // 空白と区切りはアンダースコアへ。日本語や漢字はここで落ちる。
    .replace(/[\s\-./]+/g, "_")
    .replace(/[^a-z0-9_]/g, "")
    .replace(/_+/g, "_")
    .replace(/^_+|_+$/g, "")
    .slice(0, 39);
  return KEY_RE.test(slug) ? slug : null;
}

function toText(v: unknown, max: number): string | null {
  if (typeof v !== "string") return null;
  // 改行は棚の名前に入らない。1行に潰してから長さを見る。
  const t = v.replace(/\s+/g, " ").trim();
  if (!t) return null;
  // 切り詰めない。**長すぎるものは諦める。**
  // 24字で切ると「夜市で売っている甘い揚げ物のお…」のような中途半端な
  // 名前が棚になり、直す手段がユーザーに無い。
  return [...t].length <= max ? t : null;
}

/** 絵文字らしきもの1つ。文字が混ざっていたら諦める。 */
function toEmoji(v: unknown): string | null {
  if (typeof v !== "string") return null;
  const t = v.trim();
  if (!t || [...t].length > EMOJI_MAX) return null;
  // 文字・数字が入っているものは絵文字ではない(「なし」「N/A」など)。
  if (/[\p{L}\p{N}]/u.test(t)) return null;
  return /\p{Extended_Pictographic}/u.test(t) ? t : null;
}

/**
 * 提案を受け入れられる形に直す。**受け入れられないなら null。**
 *
 * @param known すでに在るその人の棚の鍵。ここに在るなら新規作成ではなく再利用。
 */
export function normalizeShelfProposal(
  raw: RawShelfProposal | null | undefined,
): ShelfProposal | null {
  if (!raw || typeof raw !== "object") return null;
  const key = toKey(raw.key);
  const label = toText(raw.label, LABEL_MAX);
  const roomKey = toKey(raw.room_key);
  const roomLabel = toText(raw.room_label, LABEL_MAX);
  if (!key || !label || !roomKey || !roomLabel) return null;

  // **既定の54棚と同じ鍵は作らせない。** 作ると同じ意味の棚が2つ並び、
  // 片方は i18n の名前、片方は AI の名前になる。既定が在るならそれを使う。
  if ((CATEGORY_KEYS as readonly string[]).includes(key)) return null;

  return {
    key,
    label,
    // 絵文字は無くても棚は成立する。既定を置いて先へ進む。
    emoji: toEmoji(raw.emoji) ?? "📦",
    room_key: roomKey,
    room_label: roomLabel,
  };
}

/**
 * 既定の8部屋のどれかを指しているか。
 * 指しているなら部屋の名前は i18n から出るので、AI の room_label は使わない
 * (「食べる」を AI が「食事」と書いてきたら、同じ部屋が2つの名前で出る)。
 */
export function isBuiltinRoom(roomKey: string): boolean {
  return (ROOM_KEYS as readonly string[]).includes(roomKey);
}
