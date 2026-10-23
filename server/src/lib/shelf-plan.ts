/**
 * 図鑑に何をどの順で描くか。**部屋と棚の組み立てはここだけ。**
 *
 * ## なぜ切り出したか
 * これまで `DexShelf` の中で `ROOM_KEYS` と `ROOM_CATEGORIES`(固定の8部屋・
 * 54棚)を直に回していた。そこへ「AIが作ったその人だけの棚」が混ざるので、
 * 並びの決め方が画面の描画と絡むと確かめられなくなる。
 * **純粋な関数にして、わざと壊して落ちるテストを書ける形にする。**
 *
 * ## 決め方
 * 1. 1枚がどの棚に載るかは `sticker.shelf_key ?? 語の分類`。
 *    `shelf_key` は**その人だけの上書き**で、null なら今までどおり。
 * 2. 棚の見た目(名前・絵文字・どの部屋か)は、その人の棚が在ればそれ、
 *    無ければ既定の54棚の定義。
 * 3. 部屋は**既定の8部屋が先、その人の部屋が後**。既定の中の棚の順は
 *    正規の順のまま — 「あの語はあのへん」という手がかりを壊さないため、
 *    棚が増えても既にある棚の相対位置は動かない。
 * 4. 中身のある部屋と棚だけを返す。
 */

import { ROOM_CATEGORIES, ROOM_KEYS, categoryEmoji, type RoomKey } from "@/lib/category";
import { isBuiltinCategory, stickerCategoryKey } from "@/lib/user-category";

/** その人だけの棚(DB の user_shelves 1行)。 */
export type UserShelf = {
  key: string;
  label: string;
  emoji: string;
  room_key: string;
  room_label: string;
};

/** 並べる対象。図鑑が持っている情報のうち、並びに要るものだけ。 */
export type ShelvedItem = {
  id: string;
  /** その人だけの棚の上書き。null なら語の分類を使う。 */
  shelf_key?: string | null;
  word: { category_key: string | null };
};

export type PlannedShelf<T> = {
  key: string;
  label: string;
  emoji: string;
  /** その人が作った棚か(既定の54棚ではない)。 */
  custom: boolean;
  items: T[];
};

export type PlannedRoom<T> = {
  key: string;
  label: string;
  custom: boolean;
  shelves: PlannedShelf<T>[];
};

/** 1枚が載る棚の鍵。**上書きが在ればそれ、無ければ語の分類。** */
export function shelfKeyOf(item: ShelvedItem, known: ReadonlySet<string>): string {
  // 消えた棚を指している行は、黙って語の既定へ戻す。棚を消したときに
  // 写真まで消えないように外部キーを張っていないので、ここで受ける。
  // 既定の54棚へ移した写真（2026-09-27 からできる）は常に効く。
  return stickerCategoryKey(item, known);
}

/**
 * 図鑑の並びを組む。
 *
 * @param labelForCategory 既定の54棚の表示名(i18n から渡す)。
 * @param labelForRoom     既定の8部屋の表示名(i18n から渡す)。
 */
export function buildShelfPlan<T extends ShelvedItem>({
  items,
  userShelves,
  activeShelf,
  labelForCategory,
  labelForRoom,
}: {
  items: readonly T[];
  userShelves: readonly UserShelf[];
  /** 絞り込み中の棚(null = すべて)。 */
  activeShelf?: string | null;
  labelForCategory: (key: string) => string;
  labelForRoom: (key: RoomKey) => string;
}): PlannedRoom<T>[] {
  const byKey = new Map<string, UserShelf>();
  for (const s of userShelves) byKey.set(s.key, s);
  const known = new Set(byKey.keys());

  // 棚 → 中身
  const buckets = new Map<string, T[]>();
  for (const it of items) {
    const k = shelfKeyOf(it, known);
    const list = buckets.get(k);
    if (list) list.push(it);
    else buckets.set(k, [it]);
  }

  const wanted = (activeShelf ?? "").trim() || null;
  const take = (key: string) => (!wanted || wanted === key ? (buckets.get(key) ?? []) : []);

  const rooms: PlannedRoom<T>[] = [];

  // 1. 既定の8部屋。**並べ替えない。**
  for (const room of ROOM_KEYS) {
    const shelves: PlannedShelf<T>[] = [];
    for (const cat of ROOM_CATEGORIES[room]) {
      const list = take(cat);
      if (list.length) {
        // 名前を付け直した既定の棚は、その名前で出す（棚の場所は変えない）。
        const renamed = byKey.get(cat);
        shelves.push({
          key: cat,
          label: renamed?.label || labelForCategory(cat),
          emoji: renamed?.emoji || categoryEmoji(cat),
          custom: false,
          items: list,
        });
      }
    }
    // その人の棚のうち、この既定の部屋に置くと言っているもの。
    for (const s of userShelves) {
      if (s.room_key !== room || isBuiltinCategory(s.key)) continue;
      const list = take(s.key);
      if (list.length) {
        shelves.push({ key: s.key, label: s.label, emoji: s.emoji, custom: true, items: list });
      }
    }
    if (shelves.length) {
      rooms.push({ key: room, label: labelForRoom(room), custom: false, shelves });
    }
  }

  // 2. その人の部屋(既定の8つに無い room_key)。作られた順に後ろへ。
  const builtinRooms = new Set<string>(ROOM_KEYS);
  const seen = new Set<string>();
  for (const s of userShelves) {
    if (isBuiltinCategory(s.key) || builtinRooms.has(s.room_key) || seen.has(s.room_key)) continue;
    seen.add(s.room_key);
    const shelves: PlannedShelf<T>[] = [];
    for (const t of userShelves) {
      if (t.room_key !== s.room_key || isBuiltinCategory(t.key)) continue;
      const list = take(t.key);
      if (list.length) {
        shelves.push({ key: t.key, label: t.label, emoji: t.emoji, custom: true, items: list });
      }
    }
    if (shelves.length) {
      rooms.push({ key: s.room_key, label: s.room_label, custom: true, shelves });
    }
  }

  return rooms;
}
