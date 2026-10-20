import { describe, expect, it } from "vitest";
import { AI_ATTEMPT_TIMEOUT } from "./ai-attempts";
import {
  AI_CALL_LOOP,
  AI_TASKS,
  aiCallErrorCode,
  aiCallRow,
  callerFromAuthHeader,
  isAiTask,
} from "./ai-call-log";
import { AI_FEATURE_IDS } from "./ai-features";

const b64url = (v: unknown) =>
  btoa(JSON.stringify(v)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const jwt = (claims: unknown) => `Bearer ${b64url({ alg: "ES256" })}.${b64url(claims)}.sig`;
const USER = "4b1c1f0e-8f4e-4c55-9d6e-2f8f0c1d2a3b";
const NOW = Date.UTC(2026, 9, 11, 12);

describe("callerFromAuthHeader", () => {
  it("reads the signed-in user's id from a Supabase access token", () => {
    const h = jwt({ sub: USER, role: "authenticated", exp: NOW / 1000 + 600 });
    expect(callerFromAuthHeader(h, NOW)).toBe(USER);
  });

  it("is null for anything that is not a live signed-in user's token", () => {
    expect(callerFromAuthHeader(null, NOW)).toBeNull();
    expect(callerFromAuthHeader("Basic abc", NOW)).toBeNull();
    expect(callerFromAuthHeader("Bearer sb_publishable_xxx", NOW)).toBeNull();
    // 公開鍵（anon）には持ち主がいない。
    expect(callerFromAuthHeader(jwt({ role: "anon" }), NOW)).toBeNull();
    expect(
      callerFromAuthHeader(jwt({ sub: USER, role: "authenticated", exp: NOW / 1000 - 1 }), NOW),
    ).toBeNull();
    expect(callerFromAuthHeader(jwt({ sub: "admin", role: "authenticated" }), NOW)).toBeNull();
    expect(callerFromAuthHeader("Bearer a.%%%.c", NOW)).toBeNull();
  });
});

describe("aiCallRow", () => {
  it("keeps only feature, task, model, time, outcome and token counts", () => {
    const row = aiCallRow(USER, {
      feature: "scan",
      task: "photo_candidates",
      model: "google:gemini-3.5-flash-lite",
      ms: 2104.6,
      ok: true,
      tokensIn: 1850,
      tokensOut: 320,
      reasoning: 0,
    });
    expect(row).toEqual({
      user_id: USER,
      loop: AI_CALL_LOOP,
      iterations: 1,
      accepted: 1,
      meta: {
        feature: "scan",
        task: "photo_candidates",
        model: "google:gemini-3.5-flash-lite",
        ms: 2105,
        ok: true,
        in: 1850,
        out: 320,
        reasoning: 0,
      },
    });
    // 量は列に入れない（`first_catch_ai` が同じ呼び出しの量を列に書いている）。
    expect(row).not.toHaveProperty("tokens_in");
  });

  it("records a short failure code and no token counts it does not have", () => {
    const row = aiCallRow(USER, {
      feature: "card",
      task: "card",
      model: "anthropic:claude-haiku-5-5",
      ms: 40_000,
      ok: false,
      code: "timeout",
    });
    expect(row.accepted).toBe(0);
    expect(row.meta).toEqual({
      feature: "card",
      task: "card",
      model: "anthropic:claude-haiku-5-5",
      ms: 40_000,
      ok: false,
      code: "timeout",
    });
  });
});

describe("aiCallErrorCode", () => {
  it("tells a deadline from a lost hedge or a cap stop", () => {
    const timedOut = new AbortController();
    timedOut.abort(new Error(AI_ATTEMPT_TIMEOUT));
    expect(aiCallErrorCode(new Error("aborted"), timedOut.signal)).toBe("timeout");

    expect(
      aiCallErrorCode(
        new Error("aborted"),
        AbortSignal.abort(new DOMException("t", "TimeoutError")),
      ),
    ).toBe("timeout");

    const lost = new AbortController();
    lost.abort();
    expect(aiCallErrorCode(new Error("aborted"), lost.signal)).toBe("cancelled");
  });

  it("falls back to the attempt code (HTTP status) when nobody stopped the call", () => {
    const e = Object.assign(new Error("Too Many Requests"), { statusCode: 429 });
    expect(aiCallErrorCode(e, new AbortController().signal)).toBe("http_429");
    expect(aiCallErrorCode(new Error("boom"))).toBe("error");
  });
});

describe("AI_TASKS", () => {
  it("names every task once and only uses real features", () => {
    const ids = AI_TASKS.map((t) => t.id);
    expect(new Set(ids).size).toBe(ids.length);
    for (const t of AI_TASKS)
      if (t.feature) expect(AI_FEATURE_IDS as readonly string[]).toContain(t.feature);
    expect(isAiTask("photo_candidates")).toBe(true);
    expect(isAiTask("nope")).toBe(false);
  });
});

describe("every AI call site names its task", () => {
  it("passes a task to getAiFor / getAiAttemptChain (so its speed is counted under the right row)", async () => {
    const { existsSync, readdirSync, readFileSync } = await import("node:fs");
    const { join, resolve } = await import("node:path");
    const root = resolve(__dirname, "..");
    // `routes` exists only in the web app; this server has `lib` alone.
    const files = ["lib", "routes"].filter((dir) => existsSync(join(root, dir))).flatMap((dir) =>
      readdirSync(join(root, dir))
        .filter((f) => /\.tsx?$/.test(f) && !f.includes(".test."))
        .map((f) => join(root, dir, f)),
    );
    const bare: string[] = [];
    for (const file of files) {
      if (file.endsWith("ai-provider.server.ts")) continue;
      const src = readFileSync(file, "latin1");
      for (const m of src.matchAll(/\b(getAiFor|getAiAttemptChain)\(\s*("[a-z_]+"|[\w.]+)\s*\)/g))
        bare.push(`${file.slice(root.length + 1)}: ${m[0]}`);
    }
    expect(bare).toEqual([]);
  });
});
