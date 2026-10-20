import { createOpenAICompatible } from "@ai-sdk/openai-compatible";
import { targetProfile } from "@/lib/target-profile";
import { generateText, Output } from "ai";
import type { z } from "zod";
import { UI_LANG_PROMPT_NAMES } from "./i18n";
import {
  DAILY_CAPS,
  USAGE_CHECK_FAILED_MESSAGE,
  aiBudgetLimits,
  reserveAiCall,
  resolveCallerTier,
  type AiCallerTier,
  type AiReservation,
} from "./ai-cap";
import type { BudgetDb } from "./budget-slots";
import { reserveUsageRow, type UsageReserveDb } from "./usage-reserve";
import {
  geminiKeywordTier,
  resolveGeminiModelId,
  withGeminiKeywords,
} from "./gemini-latest.server";
import { featureTier, parseFeatureValue, tierKeyword, type AiFeature } from "./ai-features";
import type { AiTask } from "./ai-call-log";
import { measuredGateway, measuredModel } from "./ai-call-log.server";
import { backedGateway } from "./ai-backup.server";
import { OFF, parseBackupValue } from "./ai-task-settings";

/**
 * Single switch point for every AI call in the app.
 *
 * Providers (env AI_PROVIDER):
 * - "lovable" (default): Lovable AI Gateway. Needs LOVABLE_API_KEY.
 * - "google": Gemini API via its OpenAI-compatible endpoint. Needs GEMINI_API_KEY.
 * - "openai-compatible": any OpenAI-compatible server. Needs AI_BASE_URL + AI_API_KEY.
 *
 * When AI_PROVIDER is unset we auto-detect from which key is present, keeping
 * the Lovable-hosted deployment working unchanged.
 *
 * Every feature goes through `getAiFor(feature, task)` (feature list: `ai-features.ts`,
 * tasks: `ai-call-log.ts`). Precedence, highest first — there is no hidden override:
 *   1. per-task admin setting `app_config.ai_models.tasks[task]` ("provider:model")
 *   2. per-feature admin setting `app_config.ai_models.features[feature]`
 *      ("provider:model"; "auto"/empty falls through)
 *   3. env AI_PROVIDER / AI_MODEL_FAST / AI_MODEL_RICH / AI_MODEL_RICH_PREMIUM
 *   4. keyword defaults: scan → latest-flash-lite, everything else → latest-flash
 *      (Pro section regeneration → latest-pro), resolved to the newest Gemini at runtime
 *
 * Every model `getAiFor` returns falls back once to a backup on another provider when the call
 * fails (`ai-backup.server.ts`; per-task `app_config.ai_models.backups[task]`, default
 * `resolveBackupFor`).
 */

const LOVABLE_BASE_URL = "https://ai.gateway.lovable.dev/v1";
const GOOGLE_BASE_URL = "https://generativelanguage.googleapis.com/v1beta/openai";

const LOVABLE_DEFAULT_MODEL = "google/gemini-3-flash-preview";
/** Lovable の口で動くと分かっているモデル（この口はモデルの一覧を出さない）。 */
export const LOVABLE_MODELS = [LOVABLE_DEFAULT_MODEL, "google/gemini-2.5-flash"] as const;
// 既定モデル。**OpenAI互換エンドポイントに実在するIDだけを書く**。
// 2026-07-27の障害: `-latest` エイリアス(gemini-flash-latest 等)は
// このエンドポイントでは解決されず 404 "Not Found" を返し、
// カード生成とスピーキング添削が全滅した。最新版へ乗り換えたいときは
// 設定の「AI の設定（開発者）」から明示的に指定する(env でも可)。
//
// 2026-10-09「常に最新の Gemini を自動で使う」: 既定は**合言葉**
// (`latest-flash-lite` / `latest-flash` / `latest-pro`)。`-latest` の別名とは違い、
// Google 公式のモデル一覧から**実在する版付きの ID** を実行時に選んで渡す
// (`gemini-latest.server.ts`)。一覧が読めなければ下の固定の安定版に落ちる。
/** 固定の安定版(どの会社の設定でも最後の退避先に使う)。 */
const GOOGLE_DEFAULT_FAST = "gemini-3.1-flash-lite";
const GOOGLE_AUTO_FAST = "latest-flash-lite";
const GOOGLE_AUTO_RICH = "latest-flash";
/** 課金ユーザー向け: いちばん新しい Gemini Pro。 */
const GOOGLE_AUTO_PREMIUM = "latest-pro";

/**
 * Google の OpenAI 互換ゲートウェイ。合言葉のモデルは呼ぶ時に最新の版へ置き換わる
 * (それ以外の ID はそのまま)。一覧の問い合わせにも同じ鍵を使う。
 */
function googleGateway(
  key: string,
  headers: Record<string, string> = { Authorization: `Bearer ${key}` },
) {
  return withGeminiKeywords(
    createOpenAICompatible({ name: "google", baseURL: GOOGLE_BASE_URL, headers }),
    { apiKey: key },
  );
}

/** その会社用のゲートウェイ。Google だけ合言葉を受け取れるように包む。 */
function gatewayFor(
  providerId: string,
  baseURL: string,
  key: string,
  headers: Record<string, string>,
) {
  if (providerId === "google" && baseURL === GOOGLE_BASE_URL) return googleGateway(key, headers);
  return createOpenAICompatible({ name: providerId, baseURL, headers });
}

/**
 * 画面の確認用: 合言葉なら「合言葉 → いま選ばれている版」、それ以外はそのまま。
 * Google 以外の会社では合言葉を解かない(その会社には意味が無い)。
 */
export async function describeModel(ai: Pick<AiConfig, "name">, modelId: string): Promise<string> {
  if (ai.name !== "google" || !geminiKeywordTier(modelId)) return modelId;
  return `${modelId} → ${await concreteModelId(ai, modelId)}`;
}

/**
 * **記録（DB・`ai_runs`）に残すモデル名**。合言葉（`latest-flash` など）なら、いま実際に
 * 呼ぶ版付きの ID（例 `gemini-3.8-flash`）へ解く。それ以外の ID はそのまま。
 * 合言葉のまま残すと、後から「どの版で作ったか」が分からない（版は日々変わる）。
 * 一覧は呼び出しと同じ覚え（`gemini-latest.server.ts`）を使うので、余計な往復は増えない。
 */
export async function concreteModelId(
  ai: Pick<AiConfig, "name">,
  modelId: string,
): Promise<string> {
  if (ai.name !== "google" || !geminiKeywordTier(modelId)) return modelId;
  return resolveGeminiModelId(modelId, { apiKey: findKey("google")?.value });
}

/**
 * 実行時のモデル切替(app_config.key='ai_models')。
 *
 * **機能ごと・用途ごとの割り当てと、用途ごとの控え**だけを持つ(オーナー決定 2026-10-09・
 * 2026-10-14)。値は `"auto"` か `"会社:モデル"`（控えは `"off"` も。形と表は `ai-features.ts`・
 * `ai-task-settings.ts`）。鍵そのものは DB に置かない — 会社の名前から環境変数の鍵を引く(`findKey`)。
 *
 * 以前あった全体の上書き(`provider` / `base_url` / `api_key_env` / `fast` / `rich` /
 * `rich_premium`)は**読まない**。画面の「詳しい設定」から書けたが、`provider` を入れると
 * env の AI_MODEL_* が黙って無視される落とし穴になっていた。古い行に残っていても害は無い。
 */
export type AiModelOverride = {
  features?: Partial<Record<AiFeature, string>>;
  /** 用途ごとの AI（機能の設定より先に効く）。 */
  tasks?: Partial<Record<string, string>>;
  /** 用途ごとの控え（`"off"` = 控えを使わない、無ければ `resolveBackupFor` の既定）。 */
  backups?: Partial<Record<string, string>>;
};

export type { AiFeature } from "./ai-features";
export { AI_FEATURES } from "./ai-features";

let overrideCache: { at: number; value: AiModelOverride | null } = { at: 0, value: null };

/** 保存した直後に、30秒待たずに新しい設定で動かす(管理の口から呼ぶ)。 */
export function forgetAiModelOverride(): void {
  overrideCache = { at: 0, value: null };
}

/** 30秒キャッシュ付きでモデル上書き設定を読む(呼び出しごとのDB往復を避ける)。 */
export async function getAiModelOverride(): Promise<AiModelOverride | null> {
  const now = Date.now();
  if (overrideCache.at > 0 && now - overrideCache.at < 30_000) return overrideCache.value;
  try {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    // app_config は生成済みの型定義より新しいテーブル(マイグレーション
    // 20260727100000)。型を再生成するまでは緩いクライアントとして扱う。
    const db = supabaseAdmin as unknown as {
      from: (t: string) => {
        select: (c: string) => {
          eq: (k: string, v: string) => { maybeSingle: () => Promise<{ data: unknown }> };
        };
      };
    };
    const { data } = await db
      .from("app_config")
      .select("value")
      .eq("key", "ai_models")
      .maybeSingle();
    const value = ((data as { value?: AiModelOverride } | null)?.value ??
      null) as AiModelOverride | null;
    overrideCache = { at: now, value };
    return value;
  } catch {
    overrideCache = { at: now, value: null };
    return null;
  }
}

/** 既知プロバイダの OpenAI 互換エンドポイント。 */
export const PROVIDER_PRESETS: Record<
  string,
  { base_url: string; api_key_env: string; label: string }
> = {
  google: { base_url: GOOGLE_BASE_URL, api_key_env: "GEMINI_API_KEY", label: "Google Gemini" },
  openai: {
    base_url: "https://api.openai.com/v1",
    api_key_env: "OPENAI_API_KEY",
    label: "OpenAI (ChatGPT)",
  },
  anthropic: {
    base_url: "https://api.anthropic.com/v1",
    api_key_env: "ANTHROPIC_API_KEY",
    label: "Anthropic Claude",
  },
  deepseek: {
    base_url: "https://api.deepseek.com/v1",
    api_key_env: "DEEPSEEK_API_KEY",
    label: "DeepSeek",
  },
  kimi: {
    base_url: "https://api.moonshot.ai/v1",
    api_key_env: "MOONSHOT_API_KEY",
    label: "Kimi (Moonshot)",
  },
  lovable: { base_url: LOVABLE_BASE_URL, api_key_env: "LOVABLE_API_KEY", label: "Lovable Gateway" },
  /**
   * OpenRouter（オーナー 2026-09-22 に鍵を追加）。1つの鍵で各社のモデルを
   * 呼べるので、**機能ごとに別のモデルを試す**のに使う（設定の開発者欄）。
   * 入口は公式 SDK `@openrouter/sdk` の本番の URL と同じ。
   */
  openrouter: {
    base_url: "https://openrouter.ai/api/v1",
    api_key_env: "OPENROUTER_API_KEY",
    label: "OpenRouter",
  },
};

/**
 * 提供元ごとの認証の見出し。Anthropic だけ形が違う。
 * OpenRouter は `X-Title` でアプリの名前を名乗れる（利用状況の画面に出る）。
 */
function providerHeaders(providerId: string, key: string): Record<string, string> {
  if (providerId === "anthropic") return { "x-api-key": key, "anthropic-version": "2023-06-01" };
  if (providerId === "openrouter")
    return { Authorization: `Bearer ${key}`, "X-Title": "CatchWords" };
  return { Authorization: `Bearer ${key}` };
}

/**
 * **速いモデル(Flash-Lite)はスキャンだけ**(オーナー決定 2026-10-09)。
 * スキャン(写真の物・文字の検出、単語の候補)は最新の Flash-Lite、解説・カード生成・
 * 添削・ヒント・日記・点検など**ほかの機能は全部**最新の Flash(丁寧な方)を使う。
 * 呼ぶ所は「速い方」を選んでいる所が多いので、ここでスキャン以外の速い方を丁寧な方に
 * 揃える(呼ぶ所を1つずつ直すと、新しく書いた所で漏れる)。
 */
export function forFeature(ai: AiConfig, feature: AiFeature): AiConfig {
  if (featureTier(feature) === "flash-lite" || ai.modelFast === ai.modelRich) return ai;
  return { ...ai, modelFast: ai.modelRich };
}

/** 会社の名前から、その会社の AI を組む(鍵が無い・知らない会社は null)。 */
export function providerConfig(providerId: string, model: string): AiConfig | null {
  const preset = PROVIDER_PRESETS[providerId];
  const key = findKey(providerId)?.value;
  if (!preset || !key) return null;
  const headers =
    providerId === "lovable"
      ? { "Lovable-API-Key": key, "X-Lovable-AIG-SDK": "vercel-ai-sdk" }
      : providerHeaders(providerId, key);
  return {
    provider: "openai-compatible",
    name: providerId,
    gateway: gatewayFor(providerId, preset.base_url, key, headers),
    modelFast: model,
    modelRich: model,
    modelRichPremium: model,
  };
}

/**
 * 機能ごとの AI を解決する。**アプリの AI は全部ここを通る**(機能の表は `ai-features.ts`)。
 *
 * ## 優先順位(上が勝つ。隠れた上書きは無い)
 * 1. 開発者の設定 `app_config.ai_models.features[feature]`
 *    - `"会社:モデル"` … その会社のそのモデル(鍵が無ければ 2 へ落ちる)
 *    - `"auto"` / 空 / 未設定 … 2 へ
 *    - 古い形の「モデル名だけ」… 2 の会社のまま、モデルだけ差し替え
 * 2. 環境変数 `AI_PROVIDER` / `AI_MODEL_FAST` / `AI_MODEL_RICH` / `AI_MODEL_RICH_PREMIUM`
 *    (`getAi`。どれも未設定なら 3)
 * 3. 合言葉の既定: スキャンは `latest-flash-lite`、ほかは `latest-flash`、Pro の項目作り直しは
 *    `latest-pro`(Google の最新の版へ実行時に置き換わる。`gemini-latest.server.ts`)
 *
 * どこかが欠けていても必ず動く設定に落ちる — **設定ミスで機能を止めない**。
 * 呼ぶ所は `withModelFallback` で包み、モデルが無い(404)時は控えのモデルへ落とす。
 */
export async function getAiFor(feature: AiFeature, task?: AiTask): Promise<AiConfig> {
  const cfg = await resolveAiFor(feature, task);
  const measured = measuredAi(cfg, feature, task);
  const primaryName = cfg.name ?? cfg.provider;
  const backup = await resolveBackupFor(feature, task, primaryName);
  if (!backup) return measured;
  // 控えのモデルも呼んだ1回ずつを記録する（どれだけ控えに回ったかが開発者の表に出る）。
  const tag = { feature, task: task ?? feature, provider: backup.name };
  let made: ReturnType<AiConfig["gateway"]> | null = null;
  const makeBackup = () => (made ??= measuredModel(backup.gateway(backup.model), tag));
  return {
    ...measured,
    gateway: backedGateway(
      measured.gateway,
      makeBackup,
      `${task ?? feature} ${primaryName} → ${backup.name}:${backup.model}`,
    ),
  };
}

/** 控えの AI（会社・ゲートウェイ・モデル）。 */
export type AiBackup = { name: string; gateway: AiConfig["gateway"]; model: string };

/**
 * **既定の控え**: 1番手と**別の会社**で、鍵のある最初の物。会社ごと止まる失敗（残高切れ 402・
 * 鍵の失効・障害）は同じ会社の別のモデルでは直らないため。どれも写真を読める（スキャンの控えにも使える）。
 * 1. Lovable の口の Gemini 2.5 Flash（2026-10-11 の Google の 402 の間も動いていた）
 * 2. Google の最新の版（機能の段の合言葉）
 * 3. OpenRouter の Gemini 2.5 Flash
 */
export const DEFAULT_BACKUPS: ReadonlyArray<{
  provider: string;
  model: (feature: AiFeature) => string;
}> = [
  { provider: "lovable", model: () => "google/gemini-2.5-flash" },
  { provider: "google", model: (f) => tierKeyword(featureTier(f)) },
  { provider: "openrouter", model: () => "google/gemini-2.5-flash" },
];

/**
 * その用途の控え。開発者が選んだ物（`ai_models.backups[用途]`）→ 無ければ既定（`DEFAULT_BACKUPS`）。
 * `"off"` なら null（控えを使わない）。選んだ会社の鍵が無ければ既定へ落ちる。
 */
export async function resolveBackupFor(
  feature: AiFeature,
  task: AiTask | undefined,
  primaryName: string,
): Promise<AiBackup | null> {
  const ov = await getAiModelOverride();
  const chosen = task ? parseBackupValue(ov?.backups?.[task]) : null;
  if (chosen === OFF) return null;
  if (chosen) {
    const cfg = providerConfig(chosen.provider, chosen.model);
    if (cfg) return { name: chosen.provider, gateway: cfg.gateway, model: chosen.model };
    console.warn(
      `[ai] backup for "${task}" wants ${chosen.provider} but no key — using the default`,
    );
  }
  for (const d of DEFAULT_BACKUPS) {
    if (d.provider === primaryName) continue;
    const model = d.model(feature);
    const cfg = providerConfig(d.provider, model);
    if (cfg) return { name: d.provider, gateway: cfg.gateway, model };
  }
  return null;
}

/**
 * **呼んだ1回ずつを記録する形に包む**（`ai-call-log.server.ts`。機能ごと・用途ごと・モデルごとの
 * 速さと成否を、開発者の「AI の設定」で見比べるため）。`task` を渡さない呼び出しは機能の名前で数える。
 */
export function measuredAi(cfg: AiConfig, feature: AiFeature, task?: AiTask): AiConfig {
  const provider = cfg.name ?? cfg.provider;
  return {
    ...cfg,
    gateway: measuredGateway(cfg.gateway, { feature, task: task ?? feature, provider }),
  };
}

/** `getAiFor` の中身（包む前）。用途の設定があれば、それが機能の設定より先に効く。 */
async function resolveAiFor(feature: AiFeature, task?: string): Promise<AiConfig> {
  const ov = await getAiModelOverride();
  const taskSpec = task ? parseFeatureValue(ov?.tasks?.[task]) : null;
  if (taskSpec?.provider) {
    const cfg = providerConfig(taskSpec.provider, taskSpec.model);
    if (cfg) return cfg;
    console.warn(
      `[ai] task "${task}" wants ${taskSpec.provider} but no key — using the feature's AI`,
    );
  }
  const spec = parseFeatureValue(ov?.features?.[feature]);
  if (spec?.provider) {
    const cfg = providerConfig(spec.provider, spec.model);
    if (cfg) return cfg;
    console.warn(
      `[ai] feature "${feature}" wants ${spec.provider} but no key — using the default provider`,
    );
  }
  const base = forFeature(getAi(), feature);
  if (spec && !spec.provider) {
    // 古い形(モデル名だけ): 既定の会社のまま、モデルだけ差し替える。
    return { ...base, modelFast: spec.model, modelRich: spec.model, modelRichPremium: spec.model };
  }
  return base;
}

/**
 * 管理画面の確認用: その機能が**いま実際に使う**会社とモデル。
 * 合言葉は Google の最新の版へ解いて返す(`resolved`)。鍵の値は含めない。
 */
export async function describeFeature(
  feature: AiFeature,
  task?: string,
): Promise<{ provider: string; model: string; resolved: string } | { error: string }> {
  try {
    const ai = await resolveAiFor(feature, task);
    const provider = ai.name ?? ai.provider;
    const model = ai.modelFast;
    let resolved = model;
    if (provider === "google" && geminiKeywordTier(model)) {
      resolved = await resolveGeminiModelId(model, { apiKey: findKey("google")?.value });
    }
    return { provider, model, resolved };
  } catch (e) {
    return { error: e instanceof Error ? e.message : String(e) };
  }
}

/** 管理画面の確認用: その用途がいま使う AI と控え（控えが無ければ null）。鍵の値は含めない。 */
export async function describeTask(
  feature: AiFeature,
  task: AiTask,
): Promise<
  | {
      provider: string;
      model: string;
      resolved: string;
      backup: { provider: string; model: string; resolved: string } | null;
    }
  | { error: string }
> {
  const d = await describeFeature(feature, task);
  if ("error" in d) return d;
  try {
    const b = await resolveBackupFor(feature, task, d.provider);
    return {
      ...d,
      backup: b
        ? {
            provider: b.name,
            model: b.model,
            resolved: await concreteModelId({ name: b.name }, b.model),
          }
        : null,
    };
  } catch (e) {
    return { error: e instanceof Error ? e.message : String(e) };
  }
}

/**
 * モデルIDが存在しないと provider は 404 "Not Found" を返し、その機能が
 * まるごと死ぬ(2026-07-27の障害)。**モデル指定ミスでアプリを止めない**ため、
 * 404/400 のときだけ既知の安定モデルで1回だけやり直すラッパー。
 *
 * 使い方: `withModelFallback(ai, ai.modelRichPremium, (m) => generateText({model: ai.gateway(m), ...}))`
 */
export async function withModelFallback<T>(
  ai: AiConfig,
  preferred: string,
  run: (model: string) => Promise<T>,
): Promise<T> {
  // 1段だけの退避では足りなかった(2026-08-02): 管理者は modelRichPremium
  // (gemini-2.5-pro など)で走るが、無料枠のキーではそのモデルが 404 になる。
  // 退避先が1つしか無いとそこも落ちた時点で機能が死に、画面には生の
  // "Not Found" だけが出て「解説が出ない」ように見えていた。
  // 候補を順に試し、**最後の1つまで落ちて初めて**エラーにする。
  const chain = [preferred, ai.modelRich, ai.modelFast, GOOGLE_DEFAULT_FAST].filter(
    (m, i, a) => !!m && a.indexOf(m) === i,
  );
  let lastErr: unknown;
  for (let i = 0; i < chain.length; i++) {
    const model = chain[i];
    try {
      return await run(model);
    } catch (e) {
      lastErr = e;
      const msg = (e as Error)?.message ?? "";
      const looksMissingModel =
        /not found|404|does not exist|unknown model|invalid model|unsupported model/i.test(msg);
      // モデルの問題でないなら(認証・レート上限など)、別モデルで直る話では
      // ないので即座に投げ返す。
      if (!looksMissingModel) throw e;
      if (i < chain.length - 1) {
        console.warn(
          `[ai] model "${model}" unavailable (${msg.slice(0, 120)}) — trying "${chain[i + 1]}"`,
        );
      }
    }
  }
  // 全滅。**どのモデルを試したか**を残さないと原因に辿り着けない。
  throw new Error(
    `AIモデルが見つかりませんでした(試した順: ${chain.join(" → ")})。` +
      `設定のAIモデルを既定に戻すか、キーで使えるモデル名に変えてください。` +
      (lastErr instanceof Error ? ` 詳細: ${lastErr.message.slice(0, 160)}` : ""),
  );
}

/** 1回の呼び出しに使う AI（記録用の名前つき）。 */
export type AiTarget = {
  /** `会社:モデル`。記録と画面の確認用（鍵は含めない）。 */
  label: string;
  model: ReturnType<AiConfig["gateway"]>;
};

/**
 * 写真を読める速いモデルの、会社ごとの控え（どれも各社の OpenAI 互換口に実在する ID。
 * 2026-07-27 の障害のように、`-latest` などの別名は書かない）。
 */
const VISION_FAST_BACKUP: Record<string, string> = {
  google: GOOGLE_DEFAULT_FAST,
  lovable: "google/gemini-2.5-flash",
  openrouter: "google/gemini-2.5-flash",
};

/**
 * **その機能の AI と、落ちたときの2番手**（監査 2026-10-03「チュートリアルの写真の分析が
 * 45〜50秒待って失敗した」）。
 *
 * 1番手は今までと同じ `getAiFor(feature, task)` の速いモデル（設定の開発者欄で選んだ物）。
 * 2番手は、**すでに設定・鍵のある物**から、1番手と違う最初の1つ:
 * 0. 開発者がその用途に選んだ控え（`ai_models.backups[用途]`。`"off"` なら2番手は無し）
 * 1. 環境変数の設定（`getAi`。未設定なら合言葉の既定）の速いモデル
 * 2. 鍵のある会社の、写真を読める速い控え（`VISION_FAST_BACKUP`。別の会社を先に）
 * どれも1番手と同じなら、2番手は無し（1回だけ試す）。設定が欠けていても投げない。
 */
export async function getAiAttemptChain(feature: AiFeature, task?: AiTask): Promise<AiTarget[]> {
  const primary = await resolveAiFor(feature, task);
  const primaryName = primary.name ?? primary.provider;
  const chain: AiTarget[] = [];
  // 重ねないかは設定に書いた名前で見る（前と同じ）。記録の名前は版付きの ID（`concreteModelId`）。
  const seen: string[] = [];
  const add = async (name: string, gateway: AiConfig["gateway"], model: string | undefined) => {
    if (!model || chain.length >= 2) return;
    const key = `${name}:${model}`;
    if (seen.includes(key)) return;
    seen.push(key);
    const label = `${name}:${await concreteModelId({ name }, model)}`;
    // 1番手も2番手も、呼んだ1回ずつを記録する（`measuredAi` と同じ）。
    chain.push({
      label,
      model: measuredModel(gateway(model), { feature, task: task ?? feature, provider: name }),
    });
  };
  await add(primaryName, primary.gateway, primary.modelFast); // getAiFor が機能の段に揃え済み
  // 開発者が選んだ控え（`ai_models.backups[用途]`）が先。`"off"` なら2番手は無し。
  const ov = await getAiModelOverride();
  const chosen = task ? parseBackupValue(ov?.backups?.[task]) : null;
  if (chosen === OFF) return chain;
  if (chosen) {
    const cfg = providerConfig(chosen.provider, chosen.model);
    if (cfg) await add(chosen.provider, cfg.gateway, chosen.model);
  }
  const tryConfig = async (make: () => AiConfig | Promise<AiConfig>) => {
    try {
      const ai = forFeature(await make(), feature);
      await add(ai.name ?? ai.provider, ai.gateway, ai.modelFast);
    } catch {
      // 鍵の無い設定は2番手にしない（1番手はもう決まっている）。
    }
  };
  await tryConfig(getAi);
  const backups = Object.keys(VISION_FAST_BACKUP).sort(
    (a, b) => Number(a === primaryName) - Number(b === primaryName),
  );
  for (const id of backups) {
    if (chain.length >= 2) break;
    const cfg = providerConfig(id, VISION_FAST_BACKUP[id]);
    if (cfg) await add(id, cfg.gateway, VISION_FAST_BACKUP[id]);
  }
  return chain;
}

/**
 * **開発者の「固定の写真で試す」用**: 値（`"auto"` か `"会社:モデル"`）の AI を1つ返す。
 * 本番の設定は変えない。**呼んだ1回を `ai_call` に記録しない**（試しの結果は `ai_test` に別に
 * 残し、本番の表に混ぜない）。鍵が無ければ投げる。
 */
export async function aiTargetFor(feature: AiFeature, value: string): Promise<AiTarget> {
  const spec = parseFeatureValue(value);
  if (!spec) {
    const ai = await resolveAiFor(feature);
    const name = ai.name ?? ai.provider;
    return {
      label: `${name}:${await concreteModelId({ name }, ai.modelFast)}`,
      model: ai.gateway(ai.modelFast),
    };
  }
  if (!spec.provider) throw new Error('値は "auto" か "会社:モデル" です');
  const cfg = providerConfig(spec.provider, spec.model);
  if (!cfg) throw new Error(`${spec.provider} の鍵がサーバにありません`);
  return {
    label: `${spec.provider}:${await concreteModelId({ name: spec.provider }, spec.model)}`,
    model: cfg.gateway(spec.model),
  };
}

/**
 * キーが1つも無いときの文言。**何をどこに入れれば直るか**まで書く
 * (以前は "Missing GEMINI_API_KEY" だけで、利用者には何も分からなかった)。
 */
export const MISSING_KEY_MESSAGE =
  "AIキーが未設定です。デプロイ環境の環境変数に GEMINI_API_KEY" +
  "(Google AI Studio のキー)を追加してください。" +
  "OPENAI_API_KEY / ANTHROPIC_API_KEY / DEEPSEEK_API_KEY / MOONSHOT_API_KEY でも動きます。";

export type AiConfig = {
  provider: "lovable" | "google" | "openai-compatible";
  /** 記録用の会社名（`google` / `lovable` / `openrouter` / `custom` …）。鍵は含めない。 */
  name?: string;
  gateway: ReturnType<typeof createOpenAICompatible>;
  modelFast: string;
  modelRich: string;
  /** Proユーザー向け上位モデル(AI_MODEL_RICH_PREMIUM)。未設定なら modelRich。 */
  modelRichPremium: string;
};

/**
 * 各プロバイダのAPIキーを環境変数から探す。
 *
 * 2026-07-28の障害: 本番で `AI_PROVIDER=google` なのに `GEMINI_API_KEY` が
 * 無く、**スキャンが丸ごと失敗**した。原因の半分は「キー名が1つに決め打ち」
 * だったこと(Google AI Studio のキーは GOOGLE_API_KEY 等の名前で置かれる
 * ことが多い)。ここで**よくある別名も全部見る**。
 */
const KEY_ALIASES: Record<string, string[]> = {
  google: [
    "GEMINI_API_KEY",
    "GOOGLE_API_KEY",
    "GOOGLE_GENERATIVE_AI_API_KEY",
    "GOOGLE_AI_STUDIO_API_KEY",
    "GEMINI_KEY",
  ],
  openai: ["OPENAI_API_KEY"],
  anthropic: ["ANTHROPIC_API_KEY"],
  deepseek: ["DEEPSEEK_API_KEY"],
  kimi: ["MOONSHOT_API_KEY", "KIMI_API_KEY"],
  lovable: ["LOVABLE_API_KEY"],
  // 秘密の名前はオーナーから聞いていないので、よくある綴りを全部見る。
  openrouter: ["OPENROUTER_API_KEY", "OPENROUTER_KEY", "OPEN_ROUTER_API_KEY", "OPENROUTER_TOKEN"],
  "openai-compatible": ["AI_API_KEY"],
};

/** そのプロバイダのキーを見つけて返す(見つからなければ null)。 */
export function findKey(provider: string): { env: string; value: string } | null {
  for (const name of KEY_ALIASES[provider] ?? []) {
    const v = process.env[name];
    if (v && v.trim()) return { env: name, value: v.trim() };
  }
  return null;
}

/** どのプロバイダが今すぐ使えるか(診断パネル用)。 */
export function availableProviders(): Array<{ id: string; key_env: string | null }> {
  return Object.keys(KEY_ALIASES).map((id) => {
    const found = findKey(id);
    return { id, key_env: found?.env ?? null };
  });
}

/**
 * 使うプロバイダを決める。
 * **キーが無いプロバイダは選ばない** — AI_PROVIDER の指定があっても、
 * そのキーが無ければ使える別のプロバイダに自動で移る。
 * 1つのキーの欠落でアプリ全体が止まらないようにするための最重要ルール。
 */
function detectProvider(): AiConfig["provider"] {
  const explicit = process.env.AI_PROVIDER;
  if (explicit === "openai-compatible") {
    if (process.env.AI_BASE_URL && findKey("openai-compatible")) return "openai-compatible";
  } else if (explicit === "google" || explicit === "lovable") {
    if (findKey(explicit)) return explicit;
    console.warn(
      `[ai] AI_PROVIDER=${explicit} but no API key found — falling back to whatever is configured`,
    );
  }
  // 指定が無い/指定先のキーが無い → 実際にキーがあるものを順に選ぶ。
  if (findKey("google")) return "google";
  if (process.env.AI_BASE_URL && findKey("openai-compatible")) return "openai-compatible";
  if (findKey("lovable")) return "lovable";
  return "google"; // 何も無い: getAi() が設定手順つきのエラーを投げる
}

/** env のモデル名。空文字は未設定として扱う。 */
function envModel(name: string): string | undefined {
  const v = process.env[name]?.trim();
  return v ? v : undefined;
}

export function getAi(): AiConfig {
  const provider = detectProvider();

  if (provider === "google") {
    const key = findKey("google")?.value;
    if (!key) throw new Error(MISSING_KEY_MESSAGE);
    return {
      provider,
      name: "google",
      gateway: googleGateway(key),
      // 未設定なら「いつも最新」の合言葉。env に版付きの ID を書けばそれに固定できる。
      modelFast: envModel("AI_MODEL_FAST") ?? GOOGLE_AUTO_FAST,
      modelRich: envModel("AI_MODEL_RICH") ?? GOOGLE_AUTO_RICH,
      // 課金ユーザーは Gemini Pro。env で上書きも可能。
      modelRichPremium: envModel("AI_MODEL_RICH_PREMIUM") ?? GOOGLE_AUTO_PREMIUM,
    };
  }

  if (provider === "openai-compatible") {
    const baseURL = process.env.AI_BASE_URL;
    const key = findKey("openai-compatible")?.value;
    const model = process.env.AI_MODEL_RICH ?? process.env.AI_MODEL_FAST;
    if (!baseURL || !key) throw new Error(MISSING_KEY_MESSAGE);
    if (!model)
      throw new Error(
        "AI_MODEL_FAST / AI_MODEL_RICH を設定してください(AI_PROVIDER=openai-compatible)",
      );
    return {
      provider,
      name: "custom",
      gateway: createOpenAICompatible({
        name: "custom",
        baseURL,
        headers: { Authorization: `Bearer ${key}` },
      }),
      modelFast: process.env.AI_MODEL_FAST ?? model,
      modelRich: process.env.AI_MODEL_RICH ?? model,
      modelRichPremium: process.env.AI_MODEL_RICH_PREMIUM ?? process.env.AI_MODEL_RICH ?? model,
    };
  }

  const key = findKey("lovable")?.value;
  if (!key) throw new Error(MISSING_KEY_MESSAGE);
  return {
    provider: "lovable",
    name: "lovable",
    gateway: createOpenAICompatible({
      name: "lovable",
      baseURL: LOVABLE_BASE_URL,
      headers: {
        "Lovable-API-Key": key,
        "X-Lovable-AIG-SDK": "vercel-ai-sdk",
      },
    }),
    modelFast: process.env.AI_MODEL_FAST ?? LOVABLE_DEFAULT_MODEL,
    modelRich: process.env.AI_MODEL_RICH ?? LOVABLE_DEFAULT_MODEL,
    modelRichPremium:
      process.env.AI_MODEL_RICH_PREMIUM ?? process.env.AI_MODEL_RICH ?? LOVABLE_DEFAULT_MODEL,
  };
}

/** Pull a JSON object out of AI text that may carry fences or prose around it. */
export function parseJsonFromAiText(text: string): unknown {
  const trimmed = text.trim();
  const fenced = trimmed.match(/```(?:json)?\s*([\s\S]*?)\s*```/i);
  if (fenced?.[1]) return JSON.parse(fenced[1]);
  const start = trimmed.indexOf("{");
  const end = trimmed.lastIndexOf("}");
  if (start >= 0 && end > start) return JSON.parse(trimmed.slice(start, end + 1));
  return JSON.parse(trimmed);
}

/**
 * Structured generation that survives Gemini's flaky OpenAI-compatible
 * structured output. `result.experimental_output` is a getter that THROWS
 * "No object generated: response did not match schema" — so `out ?? fallback`
 * never falls back; every feature built on Output.object (card, journal,
 * speaking, audit, synth) was failing whenever the provider hiccuped.
 *
 * Order of attempts:
 *  1. Output.object, then the same response's raw text re-parsed as JSON
 *  2. a fresh plain-text call with a "JSONのみ" instruction (the pattern that
 *     keeps suggestWords stable), parsed + schema-validated
 */
export async function generateStructured<S extends z.ZodTypeAny>(opts: {
  model: Parameters<typeof generateText>[0]["model"];
  prompt: string;
  schema: S;
  /** モデルが存在しない(404)ときに1度だけ使う代替モデル。 */
  fallbackModel?: Parameters<typeof generateText>[0]["model"];
}): Promise<z.infer<S>> {
  try {
    const result = await generateText({
      model: opts.model,
      prompt: opts.prompt,
      experimental_output: Output.object({ schema: opts.schema }) as never,
    });
    try {
      const out = (result as unknown as { experimental_output?: unknown }).experimental_output;
      if (out != null) return opts.schema.parse(out);
    } catch {
      /* NoObjectGeneratedError — try the raw text below */
    }
    try {
      return opts.schema.parse(parseJsonFromAiText(result.text));
    } catch {
      /* fall through to the plain-text retry */
    }
  } catch {
    /* the call itself failed — retry once in plain-text mode */
  }

  // 最後の砦: プレーンテキストでもう一度。モデルIDが無効(404)なら
  // fallbackModel で1回だけ試す — モデル指定ミスで機能を殺さない。
  const plainPrompt =
    `${opts.prompt}\n\n` +
    `重要: 出力は要求されたキーを持つ有効なJSONオブジェクトのみ。` +
    `説明文・前置き・後書きは一切書かない(\`\`\`jsonフェンスは可)。`;
  try {
    const retry = await generateText({ model: opts.model, prompt: plainPrompt });
    return opts.schema.parse(parseJsonFromAiText(retry.text));
  } catch (e) {
    const msg = (e as Error)?.message ?? "";
    if (
      !opts.fallbackModel ||
      !/not found|404|does not exist|unknown model|invalid model/i.test(msg)
    ) {
      throw e;
    }
    console.warn(`[ai] structured call fell back to the safe model (${msg.slice(0, 120)})`);
    const retry = await generateText({ model: opts.fallbackModel, prompt: plainPrompt });
    return opts.schema.parse(parseJsonFromAiText(retry.text));
  }
}

/**
 * 学習者の目標レベル(profiles.level_goal, 例 "TOCFL-2")。AIプロンプトの
 * 語彙難易度をユーザーレベルに合わせるために使う。失敗時はβの既定値。
 */
export async function getUserLevelGoal(userId: string): Promise<string> {
  try {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data } = await supabaseAdmin
      .from("profiles")
      .select("level_goal, target_language")
      .eq("id", userId)
      .maybeSingle();
    const row = data as { level_goal?: string; target_language?: string | null } | null;
    const goal = row?.level_goal;
    if (goal && goal.trim()) return goal;
    // **既定値も学習言語から作る。** ここを `"TOCFL-2"` で決め打ちして
    // いたので、英語を学ぶ人の目標がまだ空のときにプロンプトへ
    // 「TOCFL 2級に合わせて」と書かれ、CEFR しか使わない側に
    // 台湾華語の級が紛れ込んでいた(オーナー報告④)。
    return defaultLevelGoal(row?.target_language);
  } catch {
    return defaultLevelGoal(null);
  }
}

/** 目標がまだ空のときの既定。学習言語の目盛りの2段目(初級の真ん中)。 */
function defaultLevelGoal(targetLanguage: string | null | undefined): string {
  return targetProfile(targetLanguage ?? undefined).levels.toStored(2);
}

/**
 * Proプラン判定(Phase C の土台)。profiles.plan はサーバー/管理者だけが
 * 変更できる(ユーザー側updateMyProfileの許可リストに含めない)。判定に
 * 失敗したら必ず free 扱い — 課金判定のフェイルオープンはしない。
 */
export async function isProUser(userId: string): Promise<boolean> {
  try {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data, error } = await supabaseAdmin
      .from("profiles")
      .select("plan")
      .eq("id", userId)
      .maybeSingle();
    if (error) return false;
    if ((data as { plan?: string } | null)?.plan === "pro") return true;
    // 開発者(admin)は Pro 扱い — 課金機能を自分で試せないと検証できない。
    const { data: isAdmin } = await supabaseAdmin.rpc("has_role", {
      _user_id: userId,
      _role: "admin",
    });
    return Boolean(isAdmin);
  } catch {
    return false;
  }
}

/**
 * 学習者の現在レベルと目標レベル。生成物の語彙・文法は
 * 「現在レベル〜目標レベル」の帯に収めるのが最も伸びる(i+1)。
 * current_level が未設定なら目標の1つ下を現在とみなす。
 *
 * **形は保存されているまま返す**(`"TOCFL-2"` / `"B1"`)。読み替えは
 * `level-instruction.ts` がやる — 目盛りを知っているのはあちら。
 */
export async function getUserLevels(userId: string): Promise<{ current: string; goal: string }> {
  const goal = await getUserLevelGoal(userId);
  try {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data } = await supabaseAdmin
      .from("profiles")
      .select("current_level")
      .eq("id", userId)
      .maybeSingle();
    const cur = (data as { current_level?: string | null } | null)?.current_level;
    if (cur && cur.trim()) return { current: cur, goal };
  } catch {
    /* 列が無い環境ではフォールバック */
  }
  // 現在の級が空なら**目標の1つ下**。級の表記はその人の目盛りで作る
  // (`TOCFL-${n}` と直に書くと、英語の学習者に華語の表記が渡る)。
  const { parseLevelStep } = await import("./level-scale");
  const { targetProfile } = await import("./target-profile");
  const scale = targetProfile(await getUserTargetLanguage(userId)).levels;
  const step = parseLevelStep(goal);
  const n = typeof step === "number" ? step : 2;
  return { current: scale.toStored(Math.max(1, n - 1) as 1 | 2 | 3 | 4 | 5 | 6), goal };
}

/**
 * その人が**何語を学んでいるか**。
 *
 * 級の目盛り・カードの項目・読み上げの言語が全部ここから決まる。
 * 読めなければ既定(`normalizeTargetLanguage` が落とす)。
 */
export async function getUserTargetLanguage(userId: string): Promise<string> {
  const { normalizeTargetLanguage } = await import("./target-lang");
  try {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data } = await supabaseAdmin
      .from("profiles")
      .select("target_language")
      .eq("id", userId)
      .maybeSingle();
    return normalizeTargetLanguage((data as { target_language?: string } | null)?.target_language);
  } catch {
    return normalizeTargetLanguage(null);
  }
}

/**
 * 解説文をどの言語で書くか。設定の「表示言語」(profiles.ui_language)に従う。
 * 学習対象の台湾華語はそのまま、**説明・訳だけ**をこの言語で書かせる。
 */
export async function getExplanationLanguage(userId: string): Promise<import("./i18n").UiLang> {
  const { normalizeUiLang } = await import("./i18n");
  try {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data } = await supabaseAdmin
      .from("profiles")
      .select("ui_language")
      .eq("id", userId)
      .maybeSingle();
    // **`=== "en" ? "en" : "ja"` と書かない。** 表示言語が3つになった日
    // (2026-08-25)に、この形が残っていると台湾の人の解説だけが黙って
    // 日本語で作られる — 画面は繁體中文なのに中身が日本語、という
    // いちばん気づきにくい壊れ方になる。一覧は `i18n.tsx` が持っている。
    return normalizeUiLang((data as { ui_language?: string } | null)?.ui_language);
  } catch {
    return normalizeUiLang(null);
  }
}

/**
 * プロンプトの中でその言語を何と呼ぶか。**日本語で書く**(指示文が日本語)。
 *
 * 表そのものは `i18n.tsx` が持つ — 表示言語の一覧を持っているのがあちらで、
 * ここに写しを置くと、4つ目の言語を足した日に片方だけ増える。
 */
export function explanationLanguageName(lang: import("./i18n").UiLang): string {
  // 同期で読みたい(プロンプトを組む所で await を増やさない)ので、
  // 表だけを静的に取り込む。`i18n.tsx` は React も持つが、この表は
  // 素のオブジェクトなので server から読んで問題ない。
  return UI_LANG_PROMPT_NAMES[lang];
}

/**
 * 学習者の母語(L1)を読む。学習言語のどこで転ぶかは母語で全く違うので、
 * 発音のコツ・添削の解説をここで切り替える。
 *
 * **母語は表示言語に統合した**(オーナー指示「母語と表示言語を統合して、
 * 日本語、英語、台湾華語にして」)。設定の行は1つになったので、ここは
 * `ui_language` を正として読む。ただし「表示言語=学習言語」だけは
 * 母語にできないので、そこだけ `native_language` を手掛かりに使う —
 * 判断は `reader-language.ts` の1箇所に置いてある。
 */
export async function getLearnerL1(userId: string): Promise<import("./l1").L1Info> {
  const { l1Info } = await import("./l1");
  const { readerL1 } = await import("./reader-language");
  try {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data } = await supabaseAdmin
      .from("profiles")
      .select("ui_language, native_language, target_language")
      .eq("id", userId)
      .maybeSingle();
    const row = data as {
      ui_language?: string | null;
      native_language?: string | null;
      target_language?: string | null;
    } | null;
    return l1Info(
      readerL1({
        uiLanguage: row?.ui_language,
        nativeLanguage: row?.native_language,
        targetLanguage: row?.target_language,
      }),
    );
  } catch {
    return l1Info("ja");
  }
}

/**
 * プロンプトに差し込む「この学習者の母語ではここで転ぶ」指示。
 * 抽象的に「母語に配慮して」と書くとモデルの解釈が揺れるので、
 * 音韻・文法の干渉項目を具体的に書き下して渡す。
 */
export async function l1Rule(
  userId: string,
  kind: import("./l1").L1RuleKind = "both",
): Promise<string> {
  const [info, { formatL1Rule, hasL1ContentFor }, target] = await Promise.all([
    getLearnerL1(userId),
    import("./l1"),
    getUserTargetLanguage(userId),
  ]);
  // **母語ごとの干渉の本文を持つ学習言語(日本語)のときだけ**学習言語を渡す。
  // 台湾華語は既定のまま、英語はまだ英語用の本文が無いので今回は触らない
  // (渡すと見出しだけ英語向けになり、本文は華語のつまずきのまま、という形になる)。
  return formatL1Rule(info, kind, hasL1ContentFor(target) ? target : undefined);
}

/**
 * その学習者の母語コード。extras に「どの母語向けに書いた解説か」を
 * 記録して、母語を変えたときに作り直せるようにするために使う。
 */
export async function getLearnerL1Code(userId: string): Promise<string> {
  return (await getLearnerL1(userId)).code;
}

/**
 * プロンプトに差し込む「解説の言語」指示。
 *
 * ## 学習言語も渡す
 * 前の版はここに「台湾華語の見出し語・例文・読みはそのまま」と**直に
 * 書いてあった**。英語のカードにそのまま流すと、AI に
 * 「英語の語だが、中国語の部分はそのまま残せ」と言うことになる。
 * 何を「そのまま」にするかは学習言語で決まるので、呼び名は
 * `target-profile.ts` の表から取る。
 */
export async function explanationLanguageRule(
  userId: string,
  targetLanguage?: string | null,
): Promise<string> {
  // **呼ぶ側が学習言語を渡さないときは、その人の学習言語を読む**(2026-10-01)。
  // 前は既定(台湾華語)に落ちていたので、日本語を学ぶ人に「台湾華語の見出し語は
  // そのまま」と言うことになっていた。呼ぶ所が多いので、ここで1回読む。
  const [lang, { targetProfile }, stored] = await Promise.all([
    getExplanationLanguage(userId),
    import("./target-profile"),
    targetLanguage === undefined ? getUserTargetLanguage(userId) : Promise.resolve(targetLanguage),
  ]);
  const profile = targetProfile(stored);
  const target = profile.promptName;
  if (lang === "en") {
    return (
      `**Write every explanation, meaning, translation and note in English.** ` +
      `Only the ${target} headwords, example sentences and readings stay in that language. ` +
      // 日本語を学ぶ人に「日本語を書くな」とは言えない(見出し語も例文も日本語)。
      // 言うのは**解説を日本語で書くな**ということ。
      (profile.scriptLang === "ja"
        ? `Do not write any explanation in Japanese.`
        : `Do not write any Japanese.`)
    );
  }
  const name = explanationLanguageName(lang);
  return `解説・意味・訳・注記はすべて${name}で書く(${target}の見出し語・例文・読みはそのまま)。`;
}

/**
 * プロンプトに差し込むレベル指示の共通文(現在→目標の帯に収める)。
 *
 * **帯の説明をここに書かない。** 以前はここに TOCFL の6行が直に
 * 書いてあり、英語を選べるようにした日から**英語の学習者に華語の級の
 * 話が渡る**状態になっていた。画面には出ないので、出来上がった中身を
 * 読むまで気づけない種類の壊れ方。文は `level-instruction.ts` が組む。
 */
export async function levelInstruction(userId: string): Promise<string> {
  const [{ current, goal }, target] = await Promise.all([
    getUserLevels(userId),
    getUserTargetLanguage(userId),
  ]);
  const [{ targetProfile }, { levelRuleText }] = await Promise.all([
    import("./target-profile"),
    import("./level-instruction"),
  ]);
  const profile = targetProfile(target);
  // 「その語彙表に無い難語を使うな」と言うとき、**どの語彙表かを言う**。
  // 華語の学習者に CEFR-J を、英語の学習者に台湾教育部の表を挙げても
  // モデルには効かない。
  const AUTHORITY: Record<string, string> = {
    TOCFL: "台湾教育部の語彙表・TOCFL公式語彙表",
    CEFR: "CEFR-J Wordlist(投野由紀夫研究室)",
    // JLPT は2010年から公式の語彙表を出していない。旧出題基準と、それに沿った
    // 一般の語彙リストを挙げる(無い物を「公式の表」と呼ばない)。
    JLPT: "日本語能力試験(JLPT)の旧出題基準の語彙表とそれに沿った級別語彙リスト",
  };
  return levelRuleText(
    profile.levels,
    current,
    goal,
    AUTHORITY[profile.levels.id] ?? AUTHORITY.TOCFL,
  );
}

/**
 * TTS goes through the same gateway idea but a different endpoint.
 * Default: Lovable gateway with an OpenAI TTS model. Override with
 * TTS_BASE_URL + TTS_API_KEY (+ TTS_MODEL) for any OpenAI-compatible
 * /audio/speech server.
 */
export type TtsConfig = {
  url: string;
  headers: Record<string, string>;
  model: string;
};

export function getTts(): TtsConfig {
  const baseURL = process.env.TTS_BASE_URL;
  const key = process.env.TTS_API_KEY;
  if (baseURL && key) {
    return {
      url: `${baseURL.replace(/\/$/, "")}/audio/speech`,
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
      model: process.env.TTS_MODEL ?? "gpt-4o-mini-tts",
    };
  }
  const lovableKey = process.env.LOVABLE_API_KEY;
  if (!lovableKey) {
    throw new Error(
      "TTSキーが設定されていません。LOVABLE_API_KEY か TTS_BASE_URL + TTS_API_KEY を設定してください。",
    );
  }
  return {
    url: `${LOVABLE_BASE_URL}/audio/speech`,
    headers: { "Content-Type": "application/json", "Lovable-API-Key": lovableKey },
    model: process.env.TTS_MODEL ?? "openai/gpt-4o-mini-tts",
  };
}

type UsageClient = {
  from: (table: "usage_events") => {
    insert: (row: { user_id: string; kind: string }) => PromiseLike<{ error: unknown }>;
  };
};

/**
 * Best-effort AI usage metering. Never throws: metering must not break the
 * feature being metered (and the usage_events table may not exist yet).
 */
export async function logUsage(supabase: unknown, userId: string, kind: string): Promise<void> {
  try {
    const res = (await (supabase as UsageClient)
      .from("usage_events")
      .insert({ user_id: userId, kind })) as { error?: { message?: string } | null } | undefined;
    // 利用の記録が落ちると、日次上限と管理画面の数が静かに少なくなる。サーバの記録には残す。
    if (res?.error) console.warn("[usage] log failed", { kind, message: res.error.message });
  } catch (e) {
    console.warn("[usage] log failed", { kind, message: (e as Error)?.message ?? e });
  }
}

/**
 * **AI を呼ぶ前の上限の確かめと、1回ぶんの確保**（中身と理由は `ai-cap.ts`）。
 *
 * - その人の 24 時間の上限（種類ごと。匿名の人は小さい `ANONYMOUS_DAILY_CAPS`）
 * - 全員を合わせた 1 日の上限（`AI_GLOBAL_DAILY_CAP`、既定 5,000）と、Pro でない人の
 *   子の枠（無料 `AI_FREE_DAILY_CAP` 既定 2,500・匿名 `AI_ANON_DAILY_CAP` 既定 500）
 * - 数えられないときは断る（2026-10-03 から。前は通していた）
 *
 * **呼ぶ前に1回ぶんを `usage_events` に記録する**ので、呼ぶ側は成功の後に同じ種類を
 * `logUsage` しない（二重に数えない）。Counted via the service role because the
 * authenticated role has no SELECT grant on other users' usage_events.
 */
export async function assertWithinDailyCap(userId: string, kind: string): Promise<void> {
  await reserveAiCallFor(userId, kind);
}

/**
 * `assertWithinDailyCap` と同じ。確保した `usage_events` の行の番号を返す（返事を
 * 1つも受け取れなかった回に返す道 — チュートリアルの AI — が使う）。
 */
export async function reserveAiCallFor(userId: string, kind: string): Promise<AiReservation> {
  if (!DAILY_CAPS[kind]) return { usageId: null };
  let supabaseAdmin: (typeof import("@/integrations/supabase/client.server"))["supabaseAdmin"];
  try {
    ({ supabaseAdmin } = await import("@/integrations/supabase/client.server"));
  } catch (e) {
    // 数える道具が無い = 数えられない。**閉じる側に倒す。**
    console.warn("[usage] cap check failed", { kind, message: (e as Error)?.message ?? e });
    throw new Error(USAGE_CHECK_FAILED_MESSAGE);
  }
  const tier = await aiCallerTier(userId);
  const limits = aiBudgetLimits(process.env);
  return reserveAiCall(
    {
      reserveUsage: (uid, k, limit, since) =>
        reserveUsageRow(supabaseAdmin as unknown as UsageReserveDb, uid, k, limit, since),
      releaseUsage: async (id) => {
        const res = await supabaseAdmin.from("usage_events").delete().eq("id", id);
        if (res.error) console.warn("[usage] release failed", { kind });
      },
      budgetDb: supabaseAdmin as unknown as BudgetDb,
      globalLimit: limits.global,
      freeLimit: limits.free,
      anonymousLimit: limits.anonymous,
      tier,
    },
    userId,
    kind,
  );
}

/**
 * 確保した1回を返す（AI を呼ばずに済んだ回 — 控えのカードを返した `generateCard` など）。その人の
 * `usage_events` の行を消す。**投げない**（返せなくても、その人の回数が1つ多く数えられるだけ）。
 */
export async function releaseAiCall(usageId: number | null | undefined): Promise<boolean> {
  if (usageId == null) return false;
  try {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const res = await supabaseAdmin.from("usage_events").delete().eq("id", usageId);
    if (res.error) console.warn("[usage] release failed", res.error.message);
    return !res.error;
  } catch (e) {
    console.warn("[usage] release failed", (e as Error)?.message ?? e);
    return false;
  }
}

/**
 * 呼ぶ人の種類（匿名・無料・Pro）。匿名かどうかは Supabase の利用者の記録
 * （`is_anonymous`）で見る — `requireSupabaseAuth` の claims を上限の関数まで渡さない
 * 道（`/api/native-ai`・上限を呼ぶ関数の全部）もあるので、ここで1か所で調べる。
 */
export async function aiCallerTier(userId: string): Promise<AiCallerTier> {
  return resolveCallerTier(
    {
      isAnonymous: async (uid) => {
        const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
        const { data, error } = await supabaseAdmin.auth.admin.getUserById(uid);
        if (error || !data?.user) throw new Error(error?.message ?? "no user");
        return data.user.is_anonymous === true;
      },
      isPro: isProUser,
    },
    userId,
  );
}
