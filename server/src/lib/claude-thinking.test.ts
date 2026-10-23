import { describe, expect, it } from "vitest";
import { claude5ThinkingOff } from "./claude-thinking";

describe("claude5ThinkingOff", () => {
  it("turns thinking off the way each Claude 5 model accepts", () => {
    expect(claude5ThinkingOff("anthropic:claude-haiku-5-5")).toEqual({ type: "disabled" });
    // Sonnet 5.5 は disabled を 400 で断る。
    expect(claude5ThinkingOff("anthropic:claude-sonnet-5-5")).toEqual({ type: "between_tools" });
    // Opus 5 系は考える量を切れない。
    expect(claude5ThinkingOff("anthropic:claude-opus-5-5")).toBeNull();
  });

  it("adds nothing for other providers", () => {
    expect(claude5ThinkingOff("google:gemini-3.5-flash-lite")).toBeNull();
    expect(claude5ThinkingOff("openrouter:anthropic/claude-haiku-5-5")).toBeNull();
  });
});
