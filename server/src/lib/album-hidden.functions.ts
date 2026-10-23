import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";

/**
 * **ホームのアルバムから外した写真**（オーナー指示 2026-09-28「画像を削除するボタンを
 * 画像の右端に出して。赤バツ。ただし図鑑からは削除しないで、ホームアルバムだけから
 * 消して。またあとから戻すこともできるようにして」）。
 *
 * 札は消さない。`stickers.album_hidden` の印を立てる／下ろすだけ（移行
 * `20260928120000_album_hidden`）。**列がまだ無い環境でも止めない**: 読めなければ
 * 「無い」と答え、書けなければ `saved: false` を返す（端末に覚える側へ回す、
 * `album-hidden.ts`）。型は生成物より新しい列なので最小限の形で当てる。
 */
type Result<T> = { data: T | null; error: { message: string } | null };
type Q<T> = PromiseLike<Result<T>> & { eq: (c: string, v: string | boolean) => Q<T> };
const db = (client: unknown) =>
  client as {
    from: (t: string) => {
      select: (cols: string) => Q<Array<{ id: string }>>;
      update: (row: object) => Q<null>;
    };
  };

export const listAlbumHidden = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const { supabase, userId } = context;
    const { data, error } = await db(supabase)
      .from("stickers")
      .select("id")
      .eq("user_id", userId)
      .eq("album_hidden", true);
    if (error) return { ids: [] as string[], available: false };
    return { ids: (data ?? []).map((r) => r.id), available: true };
  });

export const setAlbumHidden = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) =>
    z.object({ sticker_id: z.string().uuid(), hidden: z.boolean() }).parse(input),
  )
  .handler(async ({ context, data }) => {
    const { supabase, userId } = context;
    const { error } = await db(supabase)
      .from("stickers")
      .update({ album_hidden: data.hidden })
      .eq("id", data.sticker_id)
      .eq("user_id", userId);
    return { saved: !error };
  });
