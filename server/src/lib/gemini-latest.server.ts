/**
 * **いちばん新しい安定版の Gemini を、Google 公式のモデル一覧から実行時に選ぶ。**
 *
 * オーナー指示(2026-10-09)「常に最新の Gemini を自動で使う」。秘密(env)に
 * `gemini-3.1-flash-lite` のように版を書くと、新しい版が出ても誰かが書き換える
 * まで古いままになる。
 *
 * ## `-latest` の別名は使わない
 * 2026-07-27 の障害: `gemini-flash-latest` などの別名は OpenAI 互換の口では
 * 404 を返し、カード生成と添削が全滅した。ここでは**実在する版付きの ID**を
 * 一覧から選ぶので、その口にもそのまま渡せる。
 *
 * ## 選び方
 * `GET /v1beta/models` の `name` が `models/gemini-<major>(.<minor>)?-<tier>` に
 * **ぴったり一致**し(`-preview`・`-exp`・`-tts`・`-image`・`-live`・日付や番号の
 * 付いた物は外す)、`generateContent` を持つ物から、版がいちばん大きい物。
 * 版は数として比べる(3.10 は 3.9 より新しい)。
 *
 * 一覧は 6 時間覚える。失敗は 5 分だけ覚える(落ちている間に毎回待たせない)。
 * 同時の問い合わせは 1 本にまとめ、5 秒で諦める。鍵はどこにも書き出さない。
 */

export type GeminiTier = "flash" | "flash-lite" | "pro";

const LIST_URL = "https://generativelanguage.googleapis.com/v1beta/models";
const OK_TTL_MS = 6 * 60 * 60 * 1000;
const FAIL_TTL_MS = 5 * 60 * 1000;
const TIMEOUT_MS = 5_000;
const MAX_PAGES = 10;

type ModelEntry = { name?: unknown; supportedGenerationMethods?: unknown };

const NAME_RE = /^models\/gemini-(\d+)(?:\.(\d+))?-(flash-lite|flash|pro)$/;

/**
 * 一覧の中身から、その段のいちばん新しい安定版の ID(`models/` を外した物)を選ぶ。
 * 見つからなければ null。**通信をしない純粋な関数**(試験用に分けてある)。
 */
export function pickLatestGemini(models: readonly unknown[], tier: GeminiTier): string | null {
  let best: { id: string; major: number; minor: number } | null = null;
  for (const raw of models) {
    if (!raw || typeof raw !== "object") continue;
    const m = raw as ModelEntry;
    if (typeof m.name !== "string") continue;
    const match = NAME_RE.exec(m.name);
    if (!match || match[3] !== tier) continue;
    const methods = Array.isArray(m.supportedGenerationMethods) ? m.supportedGenerationMethods : [];
    if (!methods.includes("generateContent")) continue;
    const major = Number(match[1]);
    const minor = match[2] === undefined ? 0 : Number(match[2]);
    if (!best || major > best.major || (major === best.major && minor > best.minor)) {
      best = { id: m.name.slice("models/".length), major, minor };
    }
  }
  return best?.id ?? null;
}

type CacheEntry = { at: number; ttl: number; value: string | null };
const cache = new Map<GeminiTier, CacheEntry>();
let inflight: Promise<unknown[] | null> | null = null;

/** 試験用: 覚えている結果を消す。 */
export function resetGeminiLatestCache(): void {
  cache.clear();
  inflight = null;
}

function defaultKey(): string | undefined {
  for (const name of [
    "GEMINI_API_KEY",
    "GOOGLE_API_KEY",
    "GOOGLE_GENERATIVE_AI_API_KEY",
    "GOOGLE_AI_STUDIO_API_KEY",
    "GEMINI_KEY",
  ]) {
    const v = process.env[name]?.trim();
    if (v) return v;
  }
  return undefined;
}

/** 一覧を全ページ読む。失敗したら null(理由だけ記録し、鍵は出さない)。 */
async function fetchModelList(apiKey: string, fetchImpl: typeof fetch): Promise<unknown[] | null> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    const all: unknown[] = [];
    let pageToken: string | undefined;
    for (let page = 0; page < MAX_PAGES; page++) {
      const url = new URL(LIST_URL);
      url.searchParams.set("pageSize", "1000");
      if (pageToken) url.searchParams.set("pageToken", pageToken);
      const res = await fetchImpl(url.toString(), {
        headers: { "x-goog-api-key": apiKey },
        signal: controller.signal,
      });
      if (!res.ok) {
        console.warn(`[ai] Gemini model list failed: HTTP ${res.status}`);
        return null;
      }
      const body = (await res.json()) as { models?: unknown; nextPageToken?: unknown };
      if (Array.isArray(body.models)) all.push(...body.models);
      pageToken =
        typeof body.nextPageToken === "string" && body.nextPageToken
          ? body.nextPageToken
          : undefined;
      if (!pageToken) break;
    }
    return all;
  } catch (e) {
    const name = (e as Error)?.name === "AbortError" ? "timeout" : "network error";
    console.warn(`[ai] Gemini model list failed: ${name}`);
    return null;
  } finally {
    clearTimeout(timer);
  }
}

/**
 * その段(flash / flash-lite / pro)のいちばん新しい安定版の Gemini の ID。
 * 一覧が読めない・該当が無いときは null(呼ぶ側が固定の安定版に落とす)。
 */
export async function resolveLatestGemini(
  tier: GeminiTier,
  opts: { apiKey?: string; fetch?: typeof fetch; now?: () => number } = {},
): Promise<string | null> {
  const now = opts.now ?? Date.now;
  const hit = cache.get(tier);
  if (hit && now() - hit.at < hit.ttl) return hit.value;

  const apiKey = opts.apiKey ?? defaultKey();
  if (!apiKey) return null;

  // 同時に来た問い合わせ(段が違っても)は 1 本の一覧読みにまとめる。
  if (!inflight) {
    inflight = fetchModelList(apiKey, opts.fetch ?? fetch).finally(() => {
      inflight = null;
    });
  }
  const models = await inflight;
  const at = now();
  if (!models) {
    cache.set(tier, { at, ttl: FAIL_TTL_MS, value: null });
    return null;
  }
  // 一覧は全段ぶん入っているので、まとめて覚える。
  for (const t of ["flash", "flash-lite", "pro"] as const) {
    const value = pickLatestGemini(models, t);
    cache.set(t, { at, ttl: value ? OK_TTL_MS : FAIL_TTL_MS, value });
  }
  return cache.get(tier)?.value ?? null;
}

/**
 * 「いつも最新」の合言葉。設定・env にこれを書くと、実行時に版付きの ID へ置き換わる。
 * `auto` は `latest-flash` と同じ。
 */
export const GEMINI_KEYWORDS: Record<string, GeminiTier> = {
  "latest-flash": "flash",
  "latest-flash-lite": "flash-lite",
  "latest-pro": "pro",
  auto: "flash",
};

/**
 * 一覧が読めないときの固定の安定版(OpenAI 互換の口に実在する ID)。
 * 本番で実際に動いていた gemini-3.1-flash-lite に揃える: 2.5 系は 2026-09-18 から
 * 「過去に使ったことのある利用者だけ」に絞られたので、このプロジェクトでは 404 になりうる。
 */
export const GEMINI_STATIC_FALLBACK: Record<GeminiTier, string> = {
  flash: "gemini-3.1-flash-lite",
  "flash-lite": "gemini-3.1-flash-lite",
  pro: "gemini-3.1-flash-lite",
};

/** 合言葉ならその段、そうでなければ null。 */
export function geminiKeywordTier(modelId: string): GeminiTier | null {
  return GEMINI_KEYWORDS[modelId.trim().toLowerCase()] ?? null;
}

/**
 * モデル ID を実際に呼ぶ ID へ。合言葉でなければそのまま。
 * 合言葉で一覧が読めなければ固定の安定版。
 */
export async function resolveGeminiModelId(
  modelId: string,
  opts: Parameters<typeof resolveLatestGemini>[1] = {},
): Promise<string> {
  const tier = geminiKeywordTier(modelId);
  if (!tier) return modelId;
  return (await resolveLatestGemini(tier, opts)) ?? GEMINI_STATIC_FALLBACK[tier];
}

// ---------------------------------------------------------------------------
// 合言葉を受け取れるゲートウェイ
// ---------------------------------------------------------------------------

type CompatProvider = import("@ai-sdk/openai-compatible").OpenAICompatibleProvider;
type LanguageModel = ReturnType<CompatProvider>;
type CallOptions = Parameters<LanguageModel["doGenerate"]>[0];

const MISSING_MODEL_RE =
  /not found|404|does not exist|unknown model|invalid model|unsupported model/i;

/**
 * 合言葉のモデル(`latest-flash` など)を、**最初に呼ばれた時**に版付きの ID へ
 * 置き換えて本物のモデルへ渡す入れ物。`getAi()` は同期なので、ここで遅れて決める。
 *
 * 選んだ版がこの口で 404 になったら(一覧には載るが OpenAI 互換の口に無い、など)、
 * その段の固定の安定版で 1 回だけやり直す — 新しい版のせいで機能を止めない。
 */
export function lazyGeminiModel(
  inner: (id: string) => LanguageModel,
  keyword: string,
  tier: GeminiTier,
  opts: Parameters<typeof resolveLatestGemini>[1] = {},
): LanguageModel {
  let resolvedId: string | null = null;
  const fallbackId = GEMINI_STATIC_FALLBACK[tier];
  const resolve = async (): Promise<string> => {
    resolvedId = (await resolveLatestGemini(tier, opts)) ?? fallbackId;
    return resolvedId;
  };
  const run = async <R>(call: (m: LanguageModel) => PromiseLike<R>): Promise<R> => {
    const id = await resolve();
    try {
      return await call(inner(id));
    } catch (e) {
      const msg = (e as Error)?.message ?? "";
      if (id === fallbackId || !MISSING_MODEL_RE.test(msg)) throw e;
      console.warn(`[ai] ${keyword} → "${id}" unavailable — using "${fallbackId}"`);
      return await call(inner(fallbackId));
    }
  };
  const probe = inner(fallbackId);
  return {
    specificationVersion: probe.specificationVersion,
    provider: probe.provider,
    get modelId() {
      return resolvedId ?? keyword;
    },
    // OpenAI 互換のモデルでは、受け付ける URL はモデル ID によらない。
    get supportedUrls() {
      return probe.supportedUrls;
    },
    doGenerate: (options: CallOptions) => run((m) => m.doGenerate(options)),
    doStream: (options: CallOptions) => run((m) => m.doStream(options)),
  };
}

/**
 * Google のゲートウェイを包む。合言葉のモデルだけ遅れて決め、それ以外の ID は
 * **そのまま**本物に渡す(`languageModel` / `chatModel` も同じ)。
 */
export function withGeminiKeywords(
  provider: CompatProvider,
  opts: Parameters<typeof resolveLatestGemini>[1] = {},
): CompatProvider {
  const pick = (make: (id: string) => LanguageModel) => (id: string) => {
    const tier = geminiKeywordTier(id);
    return tier ? lazyGeminiModel(make, id, tier, opts) : make(id);
  };
  const call = pick((id) => provider(id));
  return Object.assign(call, provider, {
    languageModel: pick((id) => provider.languageModel(id)),
    chatModel: pick((id) => provider.chatModel(id)),
  }) as CompatProvider;
}
