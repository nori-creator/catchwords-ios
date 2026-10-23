/**
 * **開発者の「AI の設定」の口**（Web の設定画面と iOS の両方から呼ぶ）。
 *
 * iOS は `/api/native-fn` に `{ "fn": "adminGetAiSettings", "data": {} }` の形で送る
 * （一覧は `native-fn.ts`）。約束と JSON の例は `docs/admin-ai-api.md`、中身は
 * `admin-ai.server.ts`。どの口も管理者だけ — 管理者でない人の読み取りは
 * `{ isAdmin: false }`、書き込みは 403。鍵の値は返さない。
 */
import { createServerFn } from "@tanstack/react-start";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";

async function deps(context: { supabase: unknown; userId: string }) {
  const mod = await import("./admin-ai.server");
  await mod.loadAdminAiServerModules();
  return { mod, deps: mod.realAdminAiDeps(context) };
}

/** いまの設定の全部（機能ごとの AI・画像・発音の声）と、選べる会社・モデル。 */
export const adminGetAiSettings = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const { mod, deps: d } = await deps(context);
    return mod.getAdminAiSettings(d);
  });

/** 1つの機能の AI を変える。`value` は `"auto"` か `"会社:モデル"`。 */
export const adminSetAiFeature = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => input as { feature: string; value: string })
  .handler(async ({ context, data }) => {
    const { mod, deps: d } = await deps(context);
    return mod.setAdminAiFeature(d, data);
  });

/**
 * 1つの用途の AI と控えを変える（2026-10-14〜）。`{ task, value?, backup? }`。
 * `value` は `"auto"` か `"会社:モデル"`、`backup` はそれに `"off"` を足した物。
 */
export const adminSetAiTask = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => input as { task: string; value?: string; backup?: string })
  .handler(async ({ context, data }) => {
    const { mod, deps: d } = await deps(context);
    return mod.setAdminAiTask(d, data);
  });

/** 用途ごと・モデルごと・日ごとの AI の費用（`ai-costs.ts`）。`{ days: 1 | 7 | 30 }`。 */
export const adminGetAiCosts = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => input)
  .handler(async ({ context, data }) => {
    const { mod, deps: d } = await deps(context);
    return mod.getAdminAiCosts(d, data);
  });

/**
 * 単価・為替を変える。`{ usdJpy? }` か `{ model, inUsd, outUsd }`（米ドル / 100 万トークン）か
 * `{ model, remove: true }`。
 */
export const adminSetAiPrice = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator(
    (input: unknown) =>
      input as {
        usdJpy?: number;
        model?: string;
        inUsd?: number;
        outUsd?: number;
        remove?: boolean;
      },
  )
  .handler(async ({ context, data }) => {
    const { mod, deps: d } = await deps(context);
    return mod.setAdminAiPrice(d, data);
  });

/** 文字検索の AI 画像を作る会社・モデル（`provider: "off"` で停止）。 */
export const adminSetImageConfig = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => input as { provider: string; model?: string })
  .handler(async ({ context, data }) => {
    const { mod, deps: d } = await deps(context);
    return mod.setAdminImageConfig(d, data);
  });

/** 1つの学習言語の発音の声（`provider: "default"` で既定の声に戻す）。 */
export const adminSetTtsVoice = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator(
    (input: unknown) =>
      input as {
        language: string;
        provider: string;
        voice?: string;
        model?: string;
        gender?: "female" | "male";
      },
  )
  .handler(async ({ context, data }) => {
    const { mod, deps: d } = await deps(context);
    return mod.setAdminTtsVoice(d, data);
  });

/**
 * 機能ごと・用途ごと・モデルごとの AI の速さと正確さ（`ai-model-stats.ts`）。
 * `{ days: 1 | 7 | 30, mine: boolean }`（`mine` = 自分の使った分だけ）。管理者でなければ
 * `{ isAdmin: false }`。
 */
export const adminGetAiStats = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => input)
  .handler(async ({ context, data }) => {
    const mod = await import("./ai-model-stats.server");
    return mod.loadAiModelStats(context, mod.parseAiStatsInput(data));
  });

/**
 * 「固定の写真で試す」の写真の一覧（`ai-test-photos.ts`）。iOS はこの `path` をアプリの入口の
 * URL に付けて写真を取り、1枚ずつ `adminTestPhotoCandidates` に送る。正解はサーバが持つ。
 */
export const adminGetAiTestPhotos = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const { deps: d } = await deps(context);
    if (!(await d.isAdmin())) return { isAdmin: false as const };
    const { AI_TEST_LANGUAGES, AI_TEST_PHOTOS, aiTestPhotoPath } = await import("./ai-test-photos");
    return {
      isAdmin: true as const,
      languages: [...AI_TEST_LANGUAGES],
      photos: AI_TEST_PHOTOS.map((p) => ({ id: p.id, kind: p.kind, path: aiTestPhotoPath(p.id) })),
    };
  });
