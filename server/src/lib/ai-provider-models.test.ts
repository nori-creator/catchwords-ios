import { describe, expect, it } from "vitest";
import { parseModelList, recommendedKind, splitSpec, supportsVision } from "./ai-provider-models";

/** 2026-09-28「直感的に簡単に AI を変更できるようにして」。 */
describe("会社ごとのモデル一覧", () => {
  it("OpenAI 形式・Google（models/ 付き）・Anthropic（表示名つき）を読み、会話に使えない物を外す", () => {
    const list = parseModelList({
      data: [
        { id: "models/gemini-2.5-flash" },
        { id: "models/gemini-2.5-pro" },
        { id: "models/text-embedding-004" },
        { id: "gpt-4o-mini-tts" },
        { id: "claude-haiku-4-5", display_name: "Claude Haiku 4.5" },
        { id: "models/gemini-2.5-flash" },
      ],
    });
    expect(list.map((m) => m.id)).toEqual([
      "claude-haiku-4-5",
      "gemini-2.5-flash",
      "gemini-2.5-pro",
    ]);
    expect(list.find((m) => m.id === "gemini-2.5-flash")?.kind).toBe("fast");
    expect(list.find((m) => m.id === "gemini-2.5-pro")?.kind).toBe("smart");
    expect(list.find((m) => m.id === "claude-haiku-4-5")?.label).toBe("Claude Haiku 4.5");
    expect(parseModelList({ error: "x" })).toEqual([]);
  });

  it("スキャンには画像を読めるモデルだけ（DeepSeek など読めない会社は出さない）", () => {
    expect(supportsVision("google", "gemini-2.5-flash")).toBe(true);
    expect(supportsVision("openai", "gpt-4o-mini")).toBe(true);
    expect(supportsVision("openai", "gpt-3.5-turbo")).toBe(false);
    expect(supportsVision("anthropic", "claude-haiku-4-5")).toBe(true);
    expect(supportsVision("deepseek", "deepseek-chat")).toBe(false);
  });

  it("スキャンと復習は速さ、ほかは中身の質をおすすめ", () => {
    expect(recommendedKind("scan")).toBe("fast");
    expect(recommendedKind("card")).toBe("smart");
  });

  it("保存の形「会社:モデル」を分ける", () => {
    expect(splitSpec("google:gemini-2.5-pro")).toEqual({
      provider: "google",
      model: "gemini-2.5-pro",
    });
    expect(splitSpec("openrouter:anthropic/claude-x:free")).toEqual({
      provider: "openrouter",
      model: "anthropic/claude-x:free",
    });
    expect(splitSpec("gemini-2.5-flash")).toEqual({ provider: "", model: "gemini-2.5-flash" });
    expect(splitSpec("")).toEqual({ provider: "", model: "" });
  });
});
