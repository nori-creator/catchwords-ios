/**
 * Claude 5 の「考えない」設定（Anthropic のモデルの資料、2026-10-11 確認）。
 * - Claude Sonnet 5.5 は `{ type: "disabled" }` を 400 で断る — いちばん考えない設定は `between_tools`
 * - Claude Opus 5.5 は考える量を切れない（常に考える）ので何もしない（`null`）
 * - ほか（Claude Haiku 5.5 など）は `{ type: "disabled" }`（考える量が既定の medium 以下の時に使える）
 * Claude 以外の会社にも何も足さない。
 */
export function claude5ThinkingOff(label: string): { type: "disabled" | "between_tools" } | null {
  const m = /^anthropic:(.+)$/.exec(label)?.[1] ?? "";
  if (!m.startsWith("claude-")) return null;
  if (/^claude-opus-5/.test(m)) return null;
  if (/^claude-sonnet-5-5/.test(m)) return { type: "between_tools" };
  return { type: "disabled" };
}
