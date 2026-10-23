import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import {
  builtinRoomOf,
  cleanCategoryEmoji,
  cleanCategoryLabel,
  isBuiltinCategory,
  newCategoryKey,
} from "./user-category";

/**
 * **カテゴリーを本人が作る・名前を変える・写真を移す・消す**
 * （オーナー指示 2026-09-27）。
 *
 * 表は `user_shelves`（その人のカテゴリー）と `stickers.shelf_key`（1枚ごとの
 * 移し先）。どちらも生成された型より新しいので、型は最小限の形で当てる。
 * **自分の行だけ**を触る — RLS も同じことを言うが、ここでも `user_id` で絞る。
 */
type Result = { error: { message: string } | null };
type Filter = PromiseLike<Result> & {
  eq: (column: string, value: string) => Filter;
  in: (column: string, values: string[]) => Filter;
};
type Table = {
  upsert: (row: object, options: { onConflict: string }) => PromiseLike<Result>;
  update: (row: object) => Filter;
  delete: () => Filter;
};
const tables = (client: unknown) => client as { from: (table: string) => Table };

const KEY = z.string().regex(/^[a-z][a-z0-9_]{1,38}$/);

/** 1枚の写真を別のカテゴリーへ移す。`null` で語の既定の分類へ戻す。 */
export const setStickerCategory = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) =>
    z.object({ sticker_id: z.string().uuid(), key: KEY.nullable() }).parse(input),
  )
  .handler(async ({ context, data }) => {
    const { supabase, userId } = context;
    const { error } = await tables(supabase)
      .from("stickers")
      .update({ shelf_key: data.key })
      .eq("id", data.sticker_id)
      .eq("user_id", userId);
    if (error) throw new Error(error.message);
    return { saved: true as const };
  });

/**
 * **カテゴリーの側から、入れる単語をまとめて変える**（オーナー指示 2026-09-28
 * 「ある単語をあるカテゴリーに追加削除できるようにして」）。1枚ごとの移し先
 * （`shelf_key`）を、行き先ごとにまとめて書く。どう書くかは `category-members.ts`。
 */
export const setStickersCategory = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) =>
    z
      .object({
        changes: z
          .array(z.object({ sticker_id: z.string().uuid(), key: KEY.nullable() }))
          .min(1)
          .max(500),
      })
      .parse(input),
  )
  .handler(async ({ context, data }) => {
    const { supabase, userId } = context;
    const byKey = new Map<string | null, string[]>();
    for (const c of data.changes) byKey.set(c.key, [...(byKey.get(c.key) ?? []), c.sticker_id]);
    for (const [key, ids] of byKey) {
      const { error } = await tables(supabase)
        .from("stickers")
        .update({ shelf_key: key })
        .eq("user_id", userId)
        .in("id", ids);
      if (error) throw new Error(error.message);
    }
    return { saved: data.changes.length };
  });

/**
 * カテゴリーを作る／名前と絵文字を変える。
 *
 * - `key` 無し … 新しく作る（鍵はここで決める）
 * - 既定の鍵 … その人だけの名前を付ける（棚の部屋は既定のまま）
 * - その人の鍵 … 名前と絵文字を変える
 */
export const saveMyCategory = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) =>
    z
      .object({
        key: KEY.optional(),
        label: z.string().max(80),
        emoji: z.string().max(16),
        /** 自分で作ったカテゴリーを並べる部屋の名前（表示言語で）。 */
        room_label: z.string().max(80),
        /** 新しく作るとき、重ならない鍵を選ぶために今の鍵を渡す。 */
        existing: z.array(z.string().max(40)).max(500).default([]),
      })
      .parse(input),
  )
  .handler(async ({ context, data }) => {
    const { supabase, userId } = context;
    const label = cleanCategoryLabel(data.label);
    if (!label) throw new Error("CATEGORY_LABEL_INVALID");
    const emoji = cleanCategoryEmoji(data.emoji);
    const key = data.key ?? newCategoryKey(data.existing);
    const builtin = isBuiltinCategory(key);
    const roomLabel = cleanCategoryLabel(data.room_label) ?? label;
    const { error } = await tables(supabase)
      .from("user_shelves")
      .upsert(
        {
          user_id: userId,
          key,
          label,
          emoji,
          room_key: builtin ? builtinRoomOf(key) : "mine",
          room_label: builtin ? label : roomLabel,
        },
        { onConflict: "user_id,key" },
      );
    if (error) throw new Error(error.message);
    return { key, label, emoji };
  });

/**
 * カテゴリーを消す。
 *
 * - 自分で作った物 … 行を消し、そこへ移していた写真は語の既定の分類へ戻す
 *   （**写真は消さない**）
 * - 既定の物 … 付け直した名前だけを消す（元の名前に戻る）
 */
export const deleteMyCategory = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => z.object({ key: KEY }).parse(input))
  .handler(async ({ context, data }) => {
    const { supabase, userId } = context;
    const db = tables(supabase);
    if (!isBuiltinCategory(data.key)) {
      const moved = await db
        .from("stickers")
        .update({ shelf_key: null })
        .eq("user_id", userId)
        .eq("shelf_key", data.key);
      if (moved.error) throw new Error(moved.error.message);
    }
    const { error } = await db
      .from("user_shelves")
      .delete()
      .eq("user_id", userId)
      .eq("key", data.key);
    if (error) throw new Error(error.message);
    return { deleted: true as const };
  });
