import { generateText } from "ai";
import { describe, expect, it } from "vitest";
import { concreteModelId, forFeature, getAi, providerConfig } from "./ai-provider.server";
import { chunksV2Prompt } from "./chunks-v2.prompt";

/**
 * **AI の呼び方の計測**（本物の AI を呼ぶ。普段の `npm test` では飛ばす）: 同じ指示文を、考える量の設定だけ変えて 1 回ずつ呼び、
 * 時間・考えたトークン・返事の長さ・失敗の理由を並べる。チャンク v2 の速さは「モデルが既定で考えるか」で決まるので、
 * 設定が本当に届いているか（SDK が欄を消していないか、口が 400 で断らないか）をここで確かめる。
 *   CHUNK_PROBE=1 GEMINI_API_KEY=… ANTHROPIC_API_KEY=… npx vitest run chunks-v2.probe
 */
const ON = process.env.CHUNK_PROBE === "1";
const PROBE_MS = Number(process.env.CHUNK_PROBE_MS ?? 45_000);

type Variant = { name: string; providerOptions?: Record<string, Record<string, unknown>> };

const GOOGLE_VARIANTS: Variant[] = [
  { name: "既定（何も足さない）" },
  { name: "reasoningEffort: low", providerOptions: { google: { reasoningEffort: "low" } } },
  { name: "reasoningEffort: minimal", providerOptions: { google: { reasoningEffort: "minimal" } } },
  { name: "reasoningEffort: none", providerOptions: { google: { reasoningEffort: "none" } } },
  { name: "extra_body thinking_level minimal", providerOptions: { google: { extra_body: { google: { thinking_config: { thinking_level: "minimal", include_thoughts: false } } } } } },
  { name: "extra_body thinking_budget 0", providerOptions: { google: { extra_body: { google: { thinking_config: { thinking_budget: 0, include_thoughts: false } } } } } },
];
const CLAUDE_VARIANTS: Variant[] = [
  { name: "既定（何も足さない）" },
  { name: "thinking disabled", providerOptions: { anthropic: { thinking: { type: "disabled" } } } },
];

describe.skipIf(!ON)("AI の呼び方の計測（本物の AI）", () => {
  it("考える量の設定ごとの時間", { timeout: 20 * 60 * 1000 }, async () => {
    const prompt = chunksV2Prompt({ headword: "筆袋" });
    const lines: string[] = [`| 会社:モデル | 設定 | ms | 考えた tokens | 出力 tokens | 返事の字数 | 結果 |`, `|---|---|---|---|---|---|---|`];
    const google = forFeature(getAi(), "card");
    const claude = providerConfig("anthropic", process.env.AI_CHUNKS_V2_CLAUDE_MODEL ?? "claude-haiku-5-5");
    const targets: Array<{ label: string; cfg: typeof google; model: string; variants: Variant[] }> = [];
    if ((google.name ?? google.provider) === "google") targets.push({ label: `google:${await concreteModelId({ name: "google" }, google.modelRich)}`, cfg: google, model: google.modelRich, variants: GOOGLE_VARIANTS });
    if (claude) targets.push({ label: `anthropic:${claude.modelRich}`, cfg: claude, model: claude.modelRich, variants: CLAUDE_VARIANTS });
    for (const t of targets) {
      for (const v of t.variants) {
        const t0 = Date.now();
        try {
          const r = await generateText({
            model: t.cfg.gateway(t.model),
            prompt,
            abortSignal: AbortSignal.timeout(PROBE_MS),
            maxRetries: 0,
            ...(v.providerOptions ? { providerOptions: v.providerOptions as never } : {}),
          });
          const u = r.usage as { outputTokens?: number; outputTokenDetails?: { reasoningTokens?: number }; reasoningTokens?: number };
          const reasoning = u.outputTokenDetails?.reasoningTokens ?? u.reasoningTokens ?? "-";
          lines.push(`| ${t.label} | ${v.name} | ${Date.now() - t0} | ${reasoning} | ${u.outputTokens ?? "-"} | ${r.text.length} | ok |`);
        } catch (e) {
          const err = e as Error & { statusCode?: number; responseBody?: string };
          const why = `${err?.name ?? "error"}${err?.statusCode ? ` ${err.statusCode}` : ""}: ${String(err?.responseBody ?? err?.message ?? "").replace(/\s+/g, " ").slice(0, 160)}`;
          lines.push(`| ${t.label} | ${v.name} | ${Date.now() - t0} | - | - | - | ${why} |`);
        }
      }
    }
    // Gemini の版ごとの可否（latest-pro = 2.5 Pro が時々断られて flash-lite に落ちた事の原因を見る）。短い指示で 1 回ずつ。
    if ((google.name ?? google.provider) === "google") {
      const raw = providerConfig("google", "x");
      lines.push(`| | | | | | | |`);
      for (const id of (process.env.CHUNK_PROBE_GEMINI_MODELS ?? "gemini-2.5-pro,gemini-3.1-pro,gemini-3.5-pro,gemini-3.8-pro,gemini-3.8-flash,gemini-3.1-flash-lite").split(",")) {
        const t0 = Date.now();
        try {
          const r = await generateText({ model: raw!.gateway(id.trim()), prompt: "用台灣華語回答：1+1=？只回答數字。", abortSignal: AbortSignal.timeout(PROBE_MS), maxRetries: 0, providerOptions: { google: { reasoningEffort: "low" } } as never });
          lines.push(`| google:${id.trim()} | 可否 | ${Date.now() - t0} | - | - | ${r.text.length} | ok |`);
        } catch (e) {
          const err = e as Error & { statusCode?: number; responseBody?: string };
          lines.push(`| google:${id.trim()} | 可否 | ${Date.now() - t0} | - | - | - | ${err?.name ?? "error"}${err?.statusCode ? ` ${err.statusCode}` : ""}: ${String(err?.responseBody ?? err?.message ?? "").replace(/\s+/g, " ").slice(0, 200)} |`);
        }
      }
    }
    console.info(["# AI の呼び方の計測", "", ...lines].join("\n"));
    expect(targets.length).toBeGreaterThan(0);
  });
});
