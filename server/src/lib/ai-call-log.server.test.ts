import { generateText } from "ai";
import { MockLanguageModelV3 } from "ai/test";
import { beforeEach, describe, expect, it, vi } from "vitest";

const inserts: Array<Record<string, unknown>> = [];
let authHeader: string | null = null;

vi.mock("@/integrations/supabase/client.server", () => ({
  supabaseAdmin: {
    from: (table: string) => ({
      insert: async (row: Record<string, unknown>) => {
        inserts.push({ table, ...row });
        return { error: null };
      },
    }),
  },
}));
vi.mock("@tanstack/react-start/server", () => ({
  getRequest: () => ({ headers: new Headers(authHeader ? { authorization: authHeader } : {}) }),
}));

const { measuredGateway, measuredModel } = await import("./ai-call-log.server");

const b64url = (v: unknown) =>
  btoa(JSON.stringify(v)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const USER = "4b1c1f0e-8f4e-4c55-9d6e-2f8f0c1d2a3b";
const signedIn = () =>
  `Bearer ${b64url({ alg: "ES256" })}.${b64url({
    sub: USER,
    role: "authenticated",
    exp: Math.floor(Date.now() / 1000) + 600,
  })}.sig`;

const usage = {
  inputTokens: { total: 1200, noCache: 1200, cacheRead: 0, cacheWrite: 0 },
  outputTokens: { total: 300, text: 280, reasoning: 20 },
};
const answer = (modelId = "gemini-3.5-flash-lite") =>
  new MockLanguageModelV3({
    modelId,
    doGenerate: async () => ({
      content: [{ type: "text", text: "{}" }],
      finishReason: { unified: "stop", raw: "stop" },
      usage,
      warnings: [],
    }),
  });

const tag = { feature: "scan" as const, task: "photo_candidates" as const, provider: "google" };

beforeEach(() => {
  inserts.length = 0;
  authHeader = signedIn();
});

describe("measuredModel", () => {
  it("records one ai_call row per call without changing the answer", async () => {
    const res = await generateText({ model: measuredModel(answer(), tag), prompt: "hi" });
    expect(res.text).toBe("{}");
    await vi.waitFor(() => expect(inserts).toHaveLength(1));
    expect(inserts[0]).toMatchObject({
      table: "ai_runs",
      user_id: USER,
      loop: "ai_call",
      accepted: 1,
      meta: {
        feature: "scan",
        task: "photo_candidates",
        model: "google:gemini-3.5-flash-lite",
        ok: true,
        in: 1200,
        out: 300,
        reasoning: 20,
      },
    });
    expect((inserts[0].meta as { ms: number }).ms).toBeGreaterThanOrEqual(0);
  });

  it("records a failure with its code and still throws it", async () => {
    const failing = new MockLanguageModelV3({
      modelId: "claude-haiku-5-5",
      doGenerate: async () => {
        throw Object.assign(new Error("Too Many Requests"), { statusCode: 429 });
      },
    });
    await expect(
      generateText({
        model: measuredModel(failing, { ...tag, provider: "anthropic" }),
        prompt: "hi",
        maxRetries: 0,
      }),
    ).rejects.toThrow();
    await vi.waitFor(() => expect(inserts).toHaveLength(1));
    expect(inserts[0]).toMatchObject({
      accepted: 0,
      meta: { model: "anthropic:claude-haiku-5-5", ok: false, code: "http_429" },
    });
  });

  it("does not record calls made outside a signed-in user's request", async () => {
    authHeader = null;
    await generateText({ model: measuredModel(answer(), tag), prompt: "hi" });
    await new Promise((r) => setTimeout(r, 20));
    expect(inserts).toHaveLength(0);
  });
});

describe("measuredGateway", () => {
  it("wraps every model the gateway hands out, keeping the requested id", async () => {
    const gateway = Object.assign((id: string) => answer(id), { extra: 1 });
    const measured = measuredGateway(gateway, { ...tag, task: "wordbook" });
    expect(measured.extra).toBe(1);
    await generateText({ model: measured("gemini-3.8-flash"), prompt: "hi" });
    await vi.waitFor(() => expect(inserts).toHaveLength(1));
    expect(inserts[0]).toMatchObject({
      meta: { task: "wordbook", model: "google:gemini-3.8-flash" },
    });
  });
});
