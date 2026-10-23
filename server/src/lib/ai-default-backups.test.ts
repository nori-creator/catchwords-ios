import { describe, expect, it } from "vitest";
import { DEFAULT_BACKUPS } from "./ai-provider.server";

describe("既定の控え（2026-10-20 Lovable を離れた後）", () => {
  it("Gemini が止まった時は Claude が受ける（Lovable の口の次、Google の次）", () => {
    const order = DEFAULT_BACKUPS.map((d) => d.provider);
    expect(order).toEqual(["lovable", "google", "anthropic", "openrouter"]);
  });
  it("スキャンは速い Haiku、ほかは Sonnet", () => {
    const claude = DEFAULT_BACKUPS.find((d) => d.provider === "anthropic")!;
    expect(claude.model("scan")).toBe("claude-haiku-5-5");
    expect(claude.model("card")).toBe("claude-sonnet-5-5");
  });
});
