import { createServerFn } from "@tanstack/react-start";
import { internalFailure } from "./safe-error";
import { removeAllUnder, type StorageBucket } from "./storage-cleanup";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { z } from "zod";
import { L1_ORDER } from "@/lib/l1";
import { DEFAULT_TARGET_LANGUAGE } from "@/lib/target-lang";
import { targetProfile } from "@/lib/target-profile";
import type { Database } from "@/integrations/supabase/types";

type MyProfile = Database["public"]["Tables"]["profiles"]["Row"];

export const getMyProfile = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  /**
   * `partial: true` は「私用の列が読めなかったので、言語や級は**置き場所**
   * を返している」という印。読む側はこれを見て、端末の写しを上書きしない。
   */
  .handler(async ({ context }): Promise<(MyProfile & { partial?: boolean }) | null> => {
    const { supabase, userId } = context;

    /**
     * **自分の行は SECURITY DEFINER の関数で読む。**
     *
     * `profiles` の私用の列（言語・級・plan・復習設定）は `authenticated` に
     * SELECT が与えられていない（SELECT ポリシーが `true` なので、列を配ると
     * 他人の設定まで読めてしまう）。そのため直に `select` すると必ず
     * `permission denied for table profiles` になり、下の `partial` 経路
     * ＝既定値が返って「設定が毎回戻る」ように見えていた。
     * `get_my_profile()` は `auth.uid()` の行だけを返すので、他人の設定を
     * 晒さずに本人の設定を読める。
     */
    const rpc = await (
      supabase as unknown as {
        rpc: (fn: string) => Promise<{ data: unknown; error: { message: string } | null }>;
      }
    ).rpc("get_my_profile");
    if (!rpc.error && rpc.data) {
      const row = Array.isArray(rpc.data) ? rpc.data[0] : rpc.data;
      if (row) return row as MyProfile;
    }

    const { data, error } = await supabase
      .from("profiles")
      .select(
        "id, display_name, avatar_url, native_language, ui_language, target_language, level_goal, pronunciation_strictness, onboarded, created_at, updated_at, album_bg, plan, review_mode, current_level, review_daily_limit, review_stage_focus",
      )
      .eq("id", userId)
      .maybeSingle();

    if (!error) return data as MyProfile | null;
    if (
      !/permission denied|not allowed|does not have|column .* does not exist|schema cache/i.test(
        error.message,
      )
    ) {
      throw internalFailure("profile", error, "設定を読み込めませんでした");
    }

    // Some environments intentionally grant only public profile columns to the
    // browser-facing role. Do not fall back to the service-role key here: home,
    // onboarding, and settings must not white-screen if that secret is absent.
    const { data: publicData, error: publicError } = await supabase
      .from("profiles")
      .select("id, display_name, avatar_url, created_at, onboarded")
      .eq("id", userId)
      .maybeSingle();
    if (publicError) throw internalFailure("profile", publicError, "設定を読み込めませんでした");
    if (!publicData) return null;

    // **ここで返す言語は「その人の設定」ではなく、ただの置き場所。**
    //
    // 私用の列が読めなかっただけで、設定そのものは DB に在る。ところが
    // この行を `useLanguagePrefsSync` がそのまま端末へ写すと、
    // **英語を学んでいる人の端末が黙って台湾華語に戻る** — 直したばかりの
    // 根っこ(学習言語がアプリに届かない)がそのまま再発する。
    //
    // だから `partial: true` を付けて、**言語の写しには使わせない**。
    // 値そのものも決め打ちを書かず、既定の1箇所から取る。
    return {
      id: publicData.id,
      display_name: publicData.display_name,
      avatar_url: publicData.avatar_url,
      created_at: publicData.created_at,
      updated_at: publicData.created_at,
      partial: true,
      native_language: L1_ORDER[0],
      ui_language: L1_ORDER[0],
      target_language: DEFAULT_TARGET_LANGUAGE,
      level_goal: targetProfile(DEFAULT_TARGET_LANGUAGE).levels.toStored(2),
      pronunciation_strictness: "normal",
      onboarded: publicData.onboarded,
      album_bg: "paper",
      plan: "free",
      review_mode: "speaking",
      current_level: null,
      review_daily_limit: 20,
      review_stage_focus: "all",
    };
  });

const UpdateInput = z.object({
  display_name: z.string().min(1).max(60).optional(),
  avatar_url: z.string().url().nullable().optional(),
  /**
   * 母語。L1_ORDER にある12言語のみ。以前は自由文字列で、綴りを間違えても
   * 保存でき、読み側が黙って日本語にフォールバックしていた(=間違った母語
   * 向けの発音のコツが出るのに気づけない)。ここで弾く。
   */
  native_language: z.enum(L1_ORDER).optional(),
  ui_language: z.string().optional(),
  target_language: z.string().optional(),
  level_goal: z.string().optional(),
  /** TOCFL の現在レベル(生成物の語彙帯を現在→目標に収めるのに使う)。 */
  current_level: z.string().optional(),
  pronunciation_strictness: z.enum(["easy", "normal", "strict"]).optional(),
  /** 1日に出す復習の最大枚数(0 = 無制限)。DB側にも同じ範囲の制約がある。 */
  review_daily_limit: z.number().int().min(0).max(200).optional(),
  /** どの記憶段階を優先して出すか。 */
  review_stage_focus: z.enum(["all", "weak", "new"]).optional(),
  onboarded: z.boolean().optional(),
});

export const updateMyProfile = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => UpdateInput.parse(input))
  .handler(async ({ context, data }) => {
    const { supabase, userId } = context;
    // current_level は生成済みの型定義より新しい列(マイグレーション
    // 20260727100000)。型を再生成するまでは緩いクライアントとして扱う。
    const loose = supabase as unknown as {
      from: (t: string) => {
        update: (v: Record<string, unknown>) => {
          eq: (k: string, v: string) => Promise<{ error: { message: string } | null }>;
        };
      };
    };
    const save = (v: Record<string, unknown>) => loose.from("profiles").update(v).eq("id", userId);

    const payload = { ...(data as Record<string, unknown>) };
    let { error } = await save(payload);

    // 設定は1回のUPDATEでまとめて送る。そのため**まだ適用されていない
    // マイグレーションの列が1つ混ざっているだけで保存全体が失敗**し、
    // 「1日の復習枚数が変えられない」どころか言語もテーマも保存できなく
    // なっていた(2026-08-02の指摘)。未知の列はその名前だけ落として
    // 保存し直し、残りは必ず通す。
    const skipped: string[] = [];
    for (let i = 0; i < 6 && error; i++) {
      const key = offendingColumn(error.message, Object.keys(payload));
      if (!key || !(key in payload)) break;
      delete payload[key];
      skipped.push(key);
      console.warn(`[profile] column "${key}" rejected the value — saving without it`);
      if (Object.keys(payload).length === 0) return { ok: true, skipped };
      ({ error } = await save(payload));
    }
    if (error) throw internalFailure("profile", error, "設定を保存できませんでした");
    // **何が落ちたかを返す。** 黙って一部だけ保存すると、
    // 「保存しました」と言われた設定が次に開いたとき戻っている。
    return skipped.length > 0 ? { ok: true, skipped } : { ok: true };
  });

/**
 * 落ちた原因の列を1つ見つける。
 *
 * ## 「まだ無い列」だけでは足りない(オーナー報告 2026-08-26)
 * > 「学習言語を英語、表示言語を台湾華語にすると、設定のページを触ると
 * >  勝手に学習言語が台湾華語、表示言語が日本語に戻る」
 *
 * ここは**列がまだ無いとき**しか拾っていなかった。ところが設定は1回の
 * UPDATE でまとめて送るので、**検査制約(check constraint)に引っかかる列が
 * 1つ混ざっているだけで、言語もレベルもまとめて保存されない**。
 * 画面には「保存できませんでした」と出るが、選んだ値は画面に残るので
 * 保存できたように見え、次に開いたとき既定へ戻る。
 *
 * だから「無い列」だけでなく**値を撥ねた列**も同じように外して通す。
 * 外した列は呼ぶ側に返すので、黙って一部だけ保存したことにはならない。
 */
function offendingColumn(message: string, keys: string[]): string | null {
  const m = /column "?([a-z_]+)"? .*(does not exist|schema cache)/i.exec(message);
  if (m?.[1]) return m[1];
  // 検査制約は `profiles_ui_language_check` のような名前で出る。
  const c = /constraint "?([a-z_]+)"?/i.exec(message);
  if (c?.[1]) {
    const hit = keys.find((k) => c[1].includes(k));
    if (hit) return hit;
  }
  if (!/does not exist|schema cache|unknown column|violates|invalid input value/i.test(message)) {
    return null;
  }
  return keys.find((k) => message.includes(k)) ?? null;
}

/**
 * プロフィール写真の登録。ヘッダーの丸アイコンに出る「自分の顔」。
 * data URL(JPEG/PNG/WebP)を受け取り、公開バケット avatars の
 * `${userId}/avatar-<ts>.<ext>` に保存して、その公開URLを profiles に書く。
 * ファイル名に時刻を入れるのは、差し替えたときに古い画像がCDN/ブラウザの
 * キャッシュから返り続けるのを防ぐため。
 */
const AvatarInput = z.object({
  // 2MB 相当の base64 まで。巨大画像でストレージと転送を溶かさない。
  dataUrl: z
    .string()
    .regex(/^data:image\/(jpeg|jpg|png|webp);base64,/, "画像(JPEG/PNG/WebP)を選んでください")
    .max(2_800_000, "画像が大きすぎます(2MBまで)"),
});

export const setMyAvatar = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => AvatarInput.parse(input))
  .handler(async ({ context, data }) => {
    const { userId } = context;
    const match = /^data:image\/([a-z]+);base64,(.+)$/is.exec(data.dataUrl);
    if (!match) throw new Error("画像を読み取れませんでした");
    const [, rawExt, b64] = match;
    const ext = rawExt.toLowerCase() === "jpeg" ? "jpg" : rawExt.toLowerCase();
    const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));

    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const path = `${userId}/avatar-${Date.now()}.${ext}`;
    const contentType = `image/${rawExt.toLowerCase()}`;
    let { error: upErr } = await supabaseAdmin.storage
      .from("avatars")
      .upload(path, bytes, { contentType, upsert: true });

    // バケットはマイグレーションで作るが、まだ適用されていない環境では
    // 「写真を変えられない」だけの状態になる。サービスロールなら自分で
    // 作れるので、その場で作ってやり直す(公開・画像のみ・5MBまで)。
    if (upErr && /not found|does not exist|bucket/i.test(upErr.message)) {
      await supabaseAdmin.storage
        .createBucket("avatars", {
          public: true,
          fileSizeLimit: 5 * 1024 * 1024,
          allowedMimeTypes: ["image/jpeg", "image/png", "image/webp"],
        })
        .catch(() => {});
      ({ error: upErr } = await supabaseAdmin.storage
        .from("avatars")
        .upload(path, bytes, { contentType, upsert: true }));
    }
    if (upErr) throw internalFailure("profile", upErr, "写真をアップロードできませんでした");

    const {
      data: { publicUrl },
    } = supabaseAdmin.storage.from("avatars").getPublicUrl(path);

    const { error } = await supabaseAdmin
      .from("profiles")
      .update({ avatar_url: publicUrl } as never)
      .eq("id", userId);
    if (error) throw internalFailure("profile", error, "写真を保存できませんでした");
    return { avatar_url: publicUrl };
  });

/** プロフィール写真を外して、既定のマークに戻す。 */
export const clearMyAvatar = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { error } = await supabaseAdmin
      .from("profiles")
      .update({ avatar_url: null } as never)
      .eq("id", context.userId);
    if (error) throw internalFailure("profile", error, "写真を外せませんでした");
    return { ok: true };
  });

const DeleteInput = z.object({
  // The client must send the literal confirmation the user typed — a stray
  // fetch or replayed request can never wipe an account by accident.
  confirm: z.literal("削除"),
});

/**
 * Permanent account deletion (App Store / Play Store requirement, privacy
 * policy §6). Deletes every user-owned row explicitly (child→parent order)
 * rather than relying on auth.users cascades, then removes uploaded photos
 * and finally the auth user itself. Shared data survives by design: the tts
 * cache is anonymous, and words created by the user stay (created_by is
 * detached) because other users' stickers may reference them.
 *
 * Idempotent-ish: if a step fails the account still exists and the user can
 * retry — nothing here leaves the account half-usable.
 */
export const deleteMyAccount = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => DeleteInput.parse(input))
  .handler(async ({ context }) => {
    const { userId } = context;
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");

    // 1) Uploaded photos (stickers bucket, everything under `${userId}/`, **every
    //    level** — first-catch transfers live in sub-folders) and the profile
    //    photo (public avatars bucket, `${userId}/avatar-*`). 監査 2026-10-03:
    //    前は stickers の一番上の階層だけで、avatars は残っていた。
    //    The tts bucket is a shared pronunciation cache — never touched.
    for (const bucket of ["stickers", "avatars"] as const) {
      try {
        await removeAllUnder(
          supabaseAdmin.storage.from(bucket) as unknown as StorageBucket,
          userId,
          { missingOk: true }, // bucket missing in a fresh env — nothing to clean
        );
      } catch (e) {
        throw internalFailure("account-delete", e, "写真の削除に失敗しました");
      }
    }

    // 2) Detach shared words the user contributed (kept for other learners).
    {
      const { error } = await supabaseAdmin
        .from("words")
        .update({ created_by: null })
        .eq("created_by", userId);
      if (error) throw internalFailure("account-delete", error, "退会処理に失敗しました");
    }

    // 3) Row deletes, children before parents (FK order verified against the
    //    live schema: posts cascade likes/comments/notifications; stickers
    //    cascade encounters/reviews/review_history).
    const steps: Array<[table: string, column: string]> = [
      ["notifications", "user_id"],
      ["notifications", "actor_id"],
      ["post_likes", "user_id"],
      ["post_comments", "user_id"],
      ["posts", "user_id"],
      ["review_history", "user_id"],
      ["reviews", "user_id"],
      ["encounters", "user_id"],
      ["daily_quests", "user_id"],
      ["stickers", "user_id"],
      ["follows", "follower_id"],
      ["follows", "following_id"],
      ["journal_entries", "user_id"],
      ["scan_events", "user_id"],
      ["usage_events", "user_id"],
      ["ai_runs", "user_id"],
      ["user_roles", "user_id"],
      ["profiles", "id"],
    ];
    for (const [table, column] of steps) {
      const { error } = await supabaseAdmin
        .from(table as never)
        .delete()
        .eq(column, userId);
      // Tables from not-yet-applied migrations simply don't exist — skip them.
      if (error && !/does not exist|relation .* not/i.test(error.message)) {
        throw new Error(`${table} の削除に失敗しました: ${error.message}`);
      }
    }

    // 4) Sign in with Apple: revoke the Apple grant (Apple's account-deletion rule, TN3194)
    //    with the refresh token kept at sign-in (`apple_tokens`). **Never blocks the
    //    deletion** — no token (signed up before this change / not Apple), missing
    //    secrets or an Apple error are logged and the deletion continues.
    {
      const { revokeAppleForUser } = await import("./apple-revoke.server");
      await revokeAppleForUser(userId);
    }

    // 5) The auth user itself — after this the session token is dead.
    const { error: authErr } = await supabaseAdmin.auth.admin.deleteUser(userId);
    if (authErr) throw new Error(`アカウントの削除に失敗しました: ${authErr.message}`);

    return { ok: true };
  });
