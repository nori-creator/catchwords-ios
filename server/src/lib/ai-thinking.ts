/**
 * **AI の「考える深さ」**（オーナー 2026-11-27「hydrogen使えるように、考える深さを指定できるようにして」）。
 *
 * Gemini 4（gemini-4-hydrogen など）は答える前に考え、何も指定しないと深く考える段で動く（第三者の資料。
 * Google の公式のページはこの環境から読めなかった）。本番で Hydrogen はカード作りが 4 回中 4 回 40 秒の締め切りに
 * 間に合わず、毎回控えの 3.8 Flash が作っていた（2026-11-27）。サーバーは深さを何も送っていなかった。
 *
 * - 保存先は `app_config.ai_thinking`（`{ "google:gemini-4-hydrogen": "low" }`）。モデルごと。`ai_models` とは
 *   別の鍵（`ai_models` を書く所は多く、知らない欄を落とすため）。
 * - 送り方は Google の OpenAI 互換の口の `reasoning_effort`（Gemini の thinking_level に読み替えられる）。
 *   `ai-provider.server.ts` の Google の口が、呼ぶたびに本文へ足す（呼ぶ所が自分で送った物はそのまま）。
 * - 段は low / medium / high / xhigh。モデルによって受け付けない段がある（Gemini 3 の preview は medium を
 *   断った例がある）ので、開発者の画面は**保存する前にその段で1回呼び、動いた時だけ保存する**。
 * - Google の Gemini だけ（ほかの会社は送り方が違う。Claude は `claude-thinking.ts`）。
 */

export const AI_THINKING_KEY = "ai_thinking";

export const THINKING_LEVELS = ["low", "medium", "high", "xhigh"] as const;
export type ThinkingLevel = (typeof THINKING_LEVELS)[number];

/** 「指定しない」（モデルの既定のまま）。保存からその行を消す。 */
export const THINKING_DEFAULT = "auto";

/**
 * 呼ぶ所が段を決めた印（本文の欄。Google には送らない）。開発者の「試しに1回呼ぶ」が `"auto"` で
 * **保存された段を使わずに**モデルの既定で呼ぶ時に付ける（段を選んだ時は `reasoning_effort` が付く）。
 */
export const THINKING_PIN_FIELD = "catchwords_thinking";

export function isThinkingLevel(value: unknown): value is ThinkingLevel {
  return typeof value === "string" && (THINKING_LEVELS as readonly string[]).includes(value);
}

/** 深さを送れる会社（Google の OpenAI 互換の口だけ）。 */
export function supportsThinkingLevel(provider: string): boolean {
  return provider === "google";
}

/** 保存の値を読む: `"会社:モデル"` → 段。形の違う行は捨てる。 */
export function normalizeThinkingConfig(raw: unknown): Record<string, ThinkingLevel> {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return {};
  const out: Record<string, ThinkingLevel> = {};
  for (const [k, v] of Object.entries(raw as Record<string, unknown>)) {
    const key = k.trim();
    const i = key.indexOf(":");
    if (i <= 0 || i === key.length - 1) continue;
    if (isThinkingLevel(v)) out[key] = v;
  }
  return out;
}

/** その会社・モデルに保存された段（無ければ null）。 */
export function thinkingFor(
  config: Record<string, ThinkingLevel> | null | undefined,
  provider: string,
  model: string,
): ThinkingLevel | null {
  if (!config || !supportsThinkingLevel(provider)) return null;
  return config[`${provider}:${model}`] ?? null;
}

/**
 * 呼ぶ本文に段を足す（OpenAI 互換の本文、`model` はその会社のモデル名）。呼ぶ所が `reasoning_effort` か
 * Gemini の `thinking_config` をもう決めていれば何もしない（両方を送ると断られる）。
 */
export function withThinkingLevel<T extends Record<string, unknown>>(
  body: T,
  config: Record<string, ThinkingLevel> | null | undefined,
  provider: string,
): T {
  if (THINKING_PIN_FIELD in body) {
    const { [THINKING_PIN_FIELD]: _pin, ...rest } = body;
    return rest as T;
  }
  const model = typeof body.model === "string" ? body.model : "";
  const level = model ? thinkingFor(config, provider, model) : null;
  if (!level) return body;
  if (body.reasoning_effort != null) return body;
  const extra = body.extra_body as { google?: { thinking_config?: unknown } } | undefined;
  if (extra?.google?.thinking_config != null) return body;
  return { ...body, reasoning_effort: level };
}
