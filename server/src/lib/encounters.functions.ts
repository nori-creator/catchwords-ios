import { createServerFn } from "@tanstack/react-start";
import { DEFAULT_TARGET_LANGUAGE } from "./target-lang";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { z } from "zod";
import { nextSrs } from "./reviews.functions";

/**
 * Re-encounter loop: catching a word you already own is not a duplicate —
 * it's the single best review moment there is (real-world recall with full
 * context). checkOwnedWord detects it, recordEncounter turns it into an SRS
 * result plus an encounter log.
 */

export type OwnedWord = {
  sticker_id: string;
  word_id: string;
  headword: string;
  meaning_ja: string;
  reading_zhuyin: string | null;
  pinyin: string | null;
  cutout_url: string | null;
  encounter_count: number;
  taken_at: string;
  location_name: string | null;
};

const CheckInput = z.object({
  headword: z.string().min(1),
  language: z.string().default(DEFAULT_TARGET_LANGUAGE),
});

export const checkOwnedWord = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => CheckInput.parse(input))
  .handler(async ({ context, data }): Promise<{ owned: OwnedWord | null }> => {
    const { supabase, userId } = context;

    const { data: word } = await supabase
      .from("words")
      .select("id, headword, meaning_ja, reading_zhuyin, pinyin")
      .eq("language", data.language)
      .eq("headword", data.headword.trim())
      .maybeSingle();
    if (!word) return { owned: null };

    const { data: sticker } = await supabase
      .from("stickers")
      .select("id, cutout_image_url, taken_at, location_name")
      .eq("user_id", userId)
      .eq("word_id", word.id)
      .order("created_at", { ascending: true })
      .limit(1)
      .maybeSingle();
    if (!sticker) return { owned: null };

    let cutout_url: string | null = null;
    if (sticker.cutout_image_url) {
      const { data: s } = await supabase.storage
        .from("stickers")
        .createSignedUrl(sticker.cutout_image_url, 60 * 60);
      cutout_url = s?.signedUrl ?? null;
    }

    // encounter_count may not exist before the migration runs.
    let encounterCount = 0;
    {
      const { data: c, error } = await supabase
        .from("stickers")
        .select("encounter_count")
        .eq("id", sticker.id)
        .maybeSingle();
      if (!error && c) encounterCount = c.encounter_count ?? 0;
    }

    return {
      owned: {
        sticker_id: sticker.id,
        word_id: word.id,
        headword: word.headword,
        meaning_ja: word.meaning_ja,
        reading_zhuyin: word.reading_zhuyin,
        pinyin: word.pinyin,
        cutout_url,
        encounter_count: encounterCount,
        taken_at: sticker.taken_at,
        location_name: sticker.location_name,
      },
    };
  });

const RecordInput = z.object({
  sticker_id: z.string().uuid(),
  /**
   * 思い出せたか。**再会そのものは当てものではない**ので、写真を撮っただけの
   * 再会では null が来る(記録は残すが、復習の間隔は動かさない)。
   */
  recalled: z.boolean().nullable(),
  lat: z.number().nullable().optional(),
  lng: z.number().nullable().optional(),
  location_name: z.string().nullable().optional(),
  /** 今回撮った写真。ここに来るまで**捨てられていた**。 */
  image_path: z.string().nullable().optional(),
  cutout_path: z.string().nullable().optional(),
});

export const recordEncounter = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => RecordInput.parse(input))
  .handler(async ({ context, data }) => {
    const { supabase, userId } = context;

    const { data: sticker, error: stErr } = await supabase
      .from("stickers")
      .select("id, encounter_count")
      .eq("id", data.sticker_id)
      .eq("user_id", userId)
      .maybeSingle();
    if (stErr || !sticker) throw new Error("ステッカーが見つかりません");

    const newCount = (sticker.encounter_count ?? 0) + 1;
    const row = {
      user_id: userId,
      sticker_id: data.sticker_id,
      recalled: data.recalled,
      lat: data.lat ?? null,
      lng: data.lng ?? null,
      location_name: data.location_name ?? null,
      image_path: data.image_path ?? null,
      cutout_path: data.cutout_path ?? null,
    };
    const ins = await supabase.from("encounters").insert(row);
    // Never report an uploaded photo as saved if its association failed.
    if (ins.error) throw ins.error;
    await supabase
      .from("stickers")
      .update({ encounter_count: newCount })
      .eq("id", data.sticker_id)
      .eq("user_id", userId);

    // 復習の間隔を動かすのは、**当てものに答えたときだけ**。
    //
    // 以前は再会そのものを「満点の復習」として数えていた。しかし再会は
    // 当てものではなく写真を撮る操作で、しかも**忘れたからもう一度撮る**
    // ことの方が多い(オーナー指摘)。それを満点として数えると間隔が伸び、
    // 一番出すべき語が出なくなる。答えが無い(null)なら記録だけ残す。
    if (data.recalled === null) {
      return { encounter_count: newCount, next_due_at: null, interval_days: null };
    }

    const { data: review } = await supabase
      .from("reviews")
      .select("id, ease, interval_days, repetitions, blur_seen")
      .eq("user_id", userId)
      .eq("sticker_id", data.sticker_id)
      .maybeSingle();

    let nextDueAt: string | null = null;
    let intervalDays: number | null = null;
    if (review) {
      const score = data.recalled ? 5 : 1;
      const next = nextSrs(
        { ease: review.ease, interval_days: review.interval_days, repetitions: review.repetitions },
        score,
      );
      nextDueAt = new Date(Date.now() + next.interval_days * 86400 * 1000).toISOString();
      intervalDays = next.interval_days;
      await supabase
        .from("reviews")
        .update({
          ease: next.ease,
          interval_days: next.interval_days,
          repetitions: next.repetitions,
          last_score: score,
          last_reviewed_at: new Date().toISOString(),
          due_at: nextDueAt,
        })
        .eq("id", review.id)
        .eq("user_id", userId);
      await supabase.from("review_history").insert({
        user_id: userId,
        review_id: review.id,
        sticker_id: data.sticker_id,
        score,
        correct: data.recalled,
        blur_seen: false,
        response_ms: 0,
        interval_days_after: next.interval_days,
        ease_after: next.ease,
        repetitions_after: next.repetitions,
      });
    }

    return { encounter_count: newCount, next_due_at: nextDueAt, interval_days: intervalDays };
  });

const EditEncounterInput = z.object({
  encounter_id: z.string().uuid(),
  /** 写真を替える。古い切り抜きは消す（新しい写真から作り直す）。 */
  image_path: z.string().min(1).optional(),
  /** 切り抜きだけを足す（写真はそのまま）。 */
  cutout_path: z.string().min(1).optional(),
  /** あとから自撮りを足す・撮り直す。 */
  selfie_path: z.string().min(1).optional(),
  /** その1枚をどの絵で見せるか。null = 設定に従う。 */
  hero_role: z.enum(["object", "cutout", "selfie"]).nullable().optional(),
});

/**
 * `editEncounter` が書く欄。**自分の場所（`<uid>/`）の絵だけ**。何も変えない入力は投げる。
 * 写真を替えた時は、切り抜きを一緒に渡さない限り古い切り抜きを消す（`replaceStickerPhoto` と同じ）。
 */
export function encounterPatch(
  data: z.infer<typeof EditEncounterInput>,
  userId: string,
): Record<string, string | null> {
  for (const p of [data.image_path, data.cutout_path, data.selfie_path]) {
    if (p !== undefined && !p.startsWith(`${userId}/`)) throw new Error("不正な画像パスです");
  }
  const patch: Record<string, string | null> = {};
  if (data.image_path !== undefined) {
    patch.image_path = data.image_path;
    patch.cutout_path = null;
  }
  if (data.cutout_path !== undefined) patch.cutout_path = data.cutout_path;
  if (data.selfie_path !== undefined) patch.selfie_path = data.selfie_path;
  if (data.hero_role !== undefined) patch.hero_role = data.hero_role;
  if (Object.keys(patch).length === 0) throw new Error("変える物がありません");
  return patch;
}

/**
 * **2回目以降に撮った写真を、1回目と同じように直す**（オーナー指示 2026-10-30「2回目3回目だと…無いから足して」）。
 * 写真の差し替え・切り抜き・自撮り・表示する写真を、再会の1行（`encounters`）に書く。**自分の行だけ。**
 *
 * 自撮りと表示する写真の列（20261030120000_encounter_pictures.sql）がまだ無い環境では、投げずに
 * `saved: false` を返す（`setStickerHeroRole` と同じ）。
 */
export const editEncounter = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => EditEncounterInput.parse(input))
  .handler(async ({ context, data }): Promise<{ saved: boolean; reason?: string }> => {
    const { supabase, userId } = context;
    const patch = encounterPatch(data, userId);
    const { data: rows, error } = await supabase
      .from("encounters")
      .update(patch as never)
      .eq("id", data.encounter_id)
      .eq("user_id", userId)
      .select("id");
    if (error) {
      if (/selfie_path|hero_role|policy|permission/.test(error.message)) {
        console.warn("editEncounter: 移行待ち", error.message);
        return { saved: false, reason: "migration" };
      }
      throw new Error(error.message);
    }
    // 書き換えの決まり（RLS の UPDATE）がまだ無い時は、エラーにならず0行になる。
    if (!rows || rows.length === 0) return { saved: false, reason: "migration" };
    return { saved: true };
  });

/**
 * その単語をこれまでに撮った写真を、**古い順に**返す。
 *
 * 最初の1枚は `stickers` 側にあり、2枚目以降は再会1回につき1行
 * (`encounters`)。詳細の画面はこの2つを混ぜて時系列に並べる。
 * 署名付きURLは有効期限があるので、その場で作って返す。
 */
export const listStickerPhotos = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => z.object({ sticker_id: z.string().uuid() }).parse(input))
  .handler(async ({ context, data }) => {
    const { supabase, userId } = context;

    const { data: sticker } = await supabase
      .from("stickers")
      .select("id, object_image_url, cutout_image_url, taken_at, location_name")
      .eq("id", data.sticker_id)
      .eq("user_id", userId)
      .maybeSingle();
    if (!sticker) return { photos: [] as StickerPhoto[] };

    // 写真の列がまだ無い環境では、この読みが丸ごと落ちる。
    // **最初の1枚は必ず返す** — 再会の写真が読めないことと、
    // 詳細に写真が1枚も出ないことは、見え方の重さが違う。
    let encounters: Array<{
      image_path: string | null;
      cutout_path: string | null;
      created_at: string;
      location_name: string | null;
    }> = [];
    {
      const { data: rows, error } = await supabase
        .from("encounters")
        .select("image_path, cutout_path, created_at, location_name")
        .eq("sticker_id", data.sticker_id)
        .eq("user_id", userId)
        .order("created_at", { ascending: true });
      if (!error && rows) encounters = rows;
    }

    const wanted: Array<{ path: string; taken_at: string; place: string | null; first: boolean }> =
      [];
    const firstPath = sticker.cutout_image_url || sticker.object_image_url;
    if (firstPath) {
      wanted.push({
        path: firstPath,
        taken_at: sticker.taken_at,
        place: sticker.location_name,
        first: true,
      });
    }
    for (const e of encounters) {
      const p = e.image_path || e.cutout_path;
      if (p) wanted.push({ path: p, taken_at: e.created_at, place: e.location_name, first: false });
    }
    if (wanted.length === 0) return { photos: [] as StickerPhoto[] };

    const { data: signed } = await supabase.storage.from("stickers").createSignedUrls(
      wanted.map((w) => w.path),
      60 * 60 * 6,
    );
    const urlByPath = new Map<string, string>();
    for (const s of signed ?? []) {
      if (s.path && s.signedUrl && !s.error) urlByPath.set(s.path, s.signedUrl);
    }

    const photos: StickerPhoto[] = [];
    for (const w of wanted) {
      const url = urlByPath.get(w.path);
      if (url) photos.push({ url, taken_at: w.taken_at, place: w.place, first: w.first });
    }
    return { photos };
  });

/** 図鑑の升目で入れ替える再会の写真の上限（1つの札あたり）。 */
export const GRID_PHOTO_LIMIT = 4;

/**
 * 升目に出す再会の写真の、署名する物の一覧。**小さな写し（`.thumb.webp`）を先に**、
 * 無い時（古い写真・写しの作成に失敗）だけ元の写真へ戻るよう、両方を並べる。
 */
export function gridPhotoPaths(
  rows: ReadonlyArray<{ image_path: string | null; cutout_path: string | null }>,
  limit = GRID_PHOTO_LIMIT,
): Array<{ path: string; thumb: string }> {
  const out: Array<{ path: string; thumb: string }> = [];
  for (const r of rows) {
    const p = r.image_path || r.cutout_path;
    if (!p || out.some((o) => o.path === p)) continue;
    out.push({ path: p, thumb: `${p}.thumb.webp` });
    if (out.length >= limit) break;
  }
  return out;
}

/** 署名の結果から、写真ごとに1つの URL（写しが在れば写し、無ければ元の写真）。 */
export function pickGridPhotoUrls(
  wanted: ReadonlyArray<{ path: string; thumb: string }>,
  signed: ReadonlyArray<{ path: string | null; signedUrl: string | null; error: string | null }>,
): string[] {
  const urlByPath = new Map<string, string>();
  for (const s of signed) if (s.path && s.signedUrl && !s.error) urlByPath.set(s.path, s.signedUrl);
  const out: string[] = [];
  for (const w of wanted) {
    const url = urlByPath.get(w.thumb) ?? urlByPath.get(w.path);
    if (url) out.push(url);
  }
  return out;
}

/**
 * **図鑑の升目で入れ替える、再会の写真**（オーナー指示 2026-10-08「同じ単語で複数回撮った
 * 場合は、図鑑の一覧を自動的に画像が変わるようにして」）。
 *
 * 詳細の `listStickerPhotos` は全部の写真を元の大きさで署名する。升目はマスが小さく、
 * 画面に見えている札の数だけ呼ばれるので、**上限つき（`GRID_PHOTO_LIMIT`）・小さな写し**
 * にする（画像の変換（transform）はこのアプリでは使っていないので、保存時に作った
 * `.thumb.webp` を使う）。最初の1枚（札の側）は図鑑の一覧が既に持っているので返さない。
 */
export const listStickerGridPhotos = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => z.object({ sticker_id: z.string().uuid() }).parse(input))
  .handler(async ({ context, data }): Promise<{ urls: string[] }> => {
    const { supabase, userId } = context;
    const { data: rows, error } = await supabase
      .from("encounters")
      .select("image_path, cutout_path")
      .eq("sticker_id", data.sticker_id)
      .eq("user_id", userId)
      .or("image_path.not.is.null,cutout_path.not.is.null")
      .order("created_at", { ascending: true })
      .limit(GRID_PHOTO_LIMIT);
    // 写真の列がまだ無い環境・読めない時は、入れ替えないだけ（表の1枚は一覧が出す）。
    if (error || !rows) return { urls: [] };
    const wanted = gridPhotoPaths(rows);
    if (wanted.length === 0) return { urls: [] };
    const { data: signed } = await supabase.storage.from("stickers").createSignedUrls(
      wanted.flatMap((w) => [w.thumb, w.path]),
      60 * 60 * 6,
    );
    return { urls: pickGridPhotoUrls(wanted, signed ?? []) };
  });

export type StickerPhoto = {
  url: string;
  taken_at: string;
  place: string | null;
  /** 最初にこの単語を捕まえたときの1枚。 */
  first: boolean;
};
