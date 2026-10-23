/**
 * **その人のカテゴリー**（オーナー指示 2026-09-27「ユーザーがカテゴリーの
 * 名前を変更したり、作成したり、写真のカテゴリーを移動したり、編集できる
 * ようにして」）。
 *
 * 表は前から在る（`user_shelves` と `stickers.shelf_key`、
 * 20260816110000_user_shelves.sql）。ここはその読み方を1か所に集める:
 *
 *   ・1枚のカテゴリー … `shelf_key` があればそれ、無ければ語の既定の分類
 *   ・名前と絵文字   … その人が付け直した物があればそれ、無ければ既定
 *
 * 既定の54分類の**名前を変える**ときも同じ表に1行を置く（鍵は既定の鍵の
 * まま）。行を消せば元の名前に戻る。写真は1枚も動かない。
 */
import {
  CATEGORY_KEYS,
  CATEGORY_META,
  asCategoryKey,
  wordCategoryKey,
  type CategoryKey,
} from "./category";
import type { UserShelf } from "./shelf-plan";

export type UserCategory = UserShelf;

const BUILTIN = new Set<string>(CATEGORY_KEYS);

/** 既定の54分類の鍵か。 */
export function isBuiltinCategory(key: string | null | undefined): key is CategoryKey {
  return !!key && BUILTIN.has(key);
}

/**
 * 1枚のカテゴリーの鍵。**上書きが在ればそれ、無ければ語の分類。**
 *
 * 上書きが既定の鍵なら常に効く。その人の鍵なら、その行がまだ在るときだけ
 * 効く（消したカテゴリーを指している写真は、黙って語の既定へ戻す）。
 * `userKeys` を渡さない呼び出しは、その人の鍵も信じる（行の一覧を持たない所）。
 */
export function stickerCategoryKey(
  item: {
    shelf_key?: string | null;
    word: { category_key?: string | null; headword?: string | null };
  },
  userKeys?: ReadonlySet<string>,
): string {
  const override = (item.shelf_key ?? "").trim();
  if (override && (BUILTIN.has(override) || !userKeys || userKeys.has(override))) return override;
  // 見出し語で直した分類（保存した時の古い取り違えを、読む時に正す）。
  return wordCategoryKey(item.word);
}

/** 見出しに出す名前と絵文字。その人が付け直した物を先に見る。 */
export function categoryDisplay(
  key: string,
  userCategories: readonly UserCategory[],
  labelForBuiltin: (key: CategoryKey) => string,
): { label: string; emoji: string; custom: boolean; renamed: boolean } {
  const mine = userCategories.find((c) => c.key === key);
  if (isBuiltinCategory(key)) {
    return {
      label: mine?.label || labelForBuiltin(key),
      emoji: mine?.emoji || CATEGORY_META[key].emoji,
      custom: false,
      renamed: !!mine,
    };
  }
  if (mine) return { label: mine.label, emoji: mine.emoji, custom: true, renamed: false };
  const other = asCategoryKey(key);
  return {
    label: labelForBuiltin(other),
    emoji: CATEGORY_META[other].emoji,
    custom: false,
    renamed: false,
  };
}

/** 名前の形。前後の空白を落とし、1〜24字（DB の制約と同じ）。 */
export function cleanCategoryLabel(raw: string): string | null {
  const label = raw.replace(/\s+/g, " ").trim();
  const length = [...label].length;
  return length >= 1 && length <= 24 ? label : null;
}

/** 絵文字1つ（空なら既定の箱）。DB の制約は 1〜8 字。 */
export function cleanCategoryEmoji(raw: string): string {
  const e = raw.trim();
  if (!e) return "📦";
  return [...e].slice(0, 2).join("").slice(0, 8);
}

/**
 * 新しいカテゴリーの鍵。**表示には使わない**ので中身は意味を持たない。
 * DB の形（英小文字で始まり、英小文字・数字・_ で 2〜39 字）に合わせる。
 */
export function newCategoryKey(existing: Iterable<string>, random: () => number = Math.random) {
  const taken = new Set(existing);
  for (;;) {
    const key = `u_${Math.floor(random() * 36 ** 8)
      .toString(36)
      .padStart(8, "0")}`;
    if (!taken.has(key) && !BUILTIN.has(key)) return key;
  }
}

/** 既定の分類が置かれる部屋（名前を付け直しても棚の部屋は変えない）。 */
export function builtinRoomOf(key: CategoryKey): string {
  return CATEGORY_META[key].room;
}
