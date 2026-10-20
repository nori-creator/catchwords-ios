import { afterEach, describe, expect, it, vi } from "vitest";
import {
  AI_ATTEMPT_TIMEOUT,
  AiAttemptsFailed,
  attemptErrorCode,
  attemptQuotaHint,
  hedgeAfterFromEnv,
  runAiAttempts,
} from "./ai-attempts";

/** 返事をしない AI（中断されたら止まる）。 */
function hangs() {
  const seen: AbortSignal[] = [];
  const run = vi.fn(
    (signal: AbortSignal) =>
      new Promise<string>((_, reject) => {
        seen.push(signal);
        signal.addEventListener("abort", () => reject(new Error("aborted by signal")));
      }),
  );
  return { run, seen };
}

afterEach(() => {
  vi.useRealTimers();
});

describe("runAiAttempts", () => {
  it("returns the first provider's answer without touching the fallback", async () => {
    const backup = vi.fn(async () => "backup");
    const result = await runAiAttempts([
      { label: "a:fast", timeoutMs: 20_000, run: async () => "primary" },
      { label: "b:fast", timeoutMs: 20_000, run: backup },
    ]);
    expect(result.value).toBe("primary");
    expect(backup).not.toHaveBeenCalled();
    expect(result.attempts).toEqual([expect.objectContaining({ label: "a:fast", outcome: "ok" })]);
  });

  it("aborts a stalled provider at its deadline and falls back once", async () => {
    vi.useFakeTimers();
    const slow = hangs();
    const failed = vi.fn();
    const pending = runAiAttempts(
      [
        { label: "a:fast", timeoutMs: 20_000, run: slow.run },
        { label: "b:fast", timeoutMs: 20_000, run: async () => "backup" },
      ],
      { onAttemptFailed: failed },
    );
    await vi.advanceTimersByTimeAsync(19_999);
    expect(slow.seen[0].aborted).toBe(false);
    await vi.advanceTimersByTimeAsync(1);
    const result = await pending;
    expect(slow.seen[0].aborted).toBe(true);
    expect(result.value).toBe("backup");
    expect(result.attempts.map((a) => [a.label, a.outcome])).toEqual([
      ["a:fast", "timeout"],
      ["b:fast", "ok"],
    ]);
    expect(result.attempts[0].ms).toBe(20_000);
    expect(failed).toHaveBeenCalledWith(
      expect.objectContaining({ label: "a:fast", outcome: "timeout" }),
      "b:fast",
    );
  });

  it("moves on even when a provider ignores the abort signal", async () => {
    vi.useFakeTimers();
    const pending = runAiAttempts([
      { label: "a", timeoutMs: 1_000, run: () => new Promise<string>(() => {}) },
      { label: "b", timeoutMs: 1_000, run: async () => "ok" },
    ]);
    await vi.advanceTimersByTimeAsync(1_000);
    await expect(pending).resolves.toMatchObject({ value: "ok" });
  });

  it("falls back on a provider error and records its status code", async () => {
    const err = Object.assign(new Error("Too Many Requests"), { statusCode: 429 });
    const result = await runAiAttempts([
      {
        label: "a",
        timeoutMs: 1_000,
        run: async () => {
          throw err;
        },
      },
      { label: "b", timeoutMs: 1_000, run: async () => 42 },
    ]);
    expect(result.value).toBe(42);
    expect(result.attempts[0]).toMatchObject({ outcome: "error", code: "http_429" });
  });

  it("throws the timeout code when every attempt timed out, and is not chargeable", async () => {
    vi.useFakeTimers();
    const a = hangs();
    const b = hangs();
    const pending = runAiAttempts(
      [
        { label: "a", timeoutMs: 20_000, run: a.run },
        { label: "b", timeoutMs: 20_000, run: b.run },
      ],
      { timeoutMessage: "FIRST_CATCH_ANALYSIS_TIMEOUT" },
    );
    const settled = pending.catch((e: unknown) => e);
    await vi.advanceTimersByTimeAsync(40_000);
    const error = await settled;
    expect(error).toBeInstanceOf(AiAttemptsFailed);
    const failed = error as AiAttemptsFailed;
    expect(failed.message).toBe("FIRST_CATCH_ANALYSIS_TIMEOUT");
    expect(failed.timedOut).toBe(true);
    expect(failed.chargeable).toBe(false);
    expect(failed.attempts.map((x) => x.outcome)).toEqual(["timeout", "timeout"]);
    expect(a.run).toHaveBeenCalledTimes(1);
    expect(b.run).toHaveBeenCalledTimes(1);
  });

  it("keeps the reply-format code and counts the call when a reply arrived", async () => {
    const error = await runAiAttempts(
      [
        {
          label: "a",
          timeoutMs: 1_000,
          run: async () => {
            throw new Error("FIRST_CATCH_AI_FORMAT");
          },
        },
        {
          label: "b",
          timeoutMs: 1_000,
          run: async () => {
            throw new Error("socket hang up");
          },
        },
      ],
      { isUnusableReply: (e) => e instanceof Error && e.message === "FIRST_CATCH_AI_FORMAT" },
    ).then(
      () => {
        throw new Error("expected failure");
      },
      (e: unknown) => e as AiAttemptsFailed,
    );
    expect(error.attempts.map((x) => x.outcome)).toEqual(["unusable", "error"]);
    expect(error.chargeable).toBe(true);
    expect(error.timedOut).toBe(false);
    // 最後に本当に起きた失敗の文を返す（締め切りの印で上書きしない）。
    expect(error.message).toBe("socket hang up");
  });

  it("uses a mixed timeout + network failure as not chargeable", async () => {
    vi.useFakeTimers();
    const a = hangs();
    const pending = runAiAttempts([
      { label: "a", timeoutMs: 500, run: a.run },
      {
        label: "b",
        timeoutMs: 500,
        run: async () => {
          throw new TypeError("fetch failed");
        },
      },
    ]).then(
      () => {
        throw new Error("expected failure");
      },
      (e: unknown) => e as AiAttemptsFailed,
    );
    await vi.advanceTimersByTimeAsync(500);
    const error = await pending;
    expect(error.chargeable).toBe(false);
    expect(error.message).toBe("fetch failed");
    expect(error.attempts[1].code).toBe("TypeError");
  });
});

/** `ms` 後に `value` で答える AI（中断されたら止まる）。 */
function answersAfter<T>(ms: number, value: T) {
  const seen: AbortSignal[] = [];
  const run = vi.fn(
    (signal: AbortSignal) =>
      new Promise<T>((resolve, reject) => {
        seen.push(signal);
        const t = setTimeout(() => resolve(value), ms);
        signal.addEventListener("abort", () => {
          clearTimeout(t);
          reject(new Error("aborted by signal"));
        });
      }),
  );
  return { run, seen };
}

describe("runAiAttempts hedging (追いかけ)", () => {
  it("does not start the fallback when the primary answers before the hedge delay", async () => {
    vi.useFakeTimers();
    const primary = answersAfter(3_000, "primary");
    const backup = answersAfter(1_000, "backup");
    const pending = runAiAttempts(
      [
        { label: "a", timeoutMs: 20_000, run: primary.run },
        { label: "b", timeoutMs: 20_000, run: backup.run },
      ],
      { hedgeAfterMs: 6_000 },
    );
    await vi.advanceTimersByTimeAsync(3_000);
    const result = await pending;
    expect(result).toMatchObject({ value: "primary", via: "a", hedged: false, ms: 3_000 });
    await vi.advanceTimersByTimeAsync(10_000);
    expect(backup.run).not.toHaveBeenCalled();
  });

  it("starts the fallback in parallel after the delay, takes the first valid answer and aborts the loser", async () => {
    vi.useFakeTimers();
    const primary = hangs();
    const backup = answersAfter(2_000, "backup");
    const hedge = vi.fn();
    const pending = runAiAttempts(
      [
        { label: "a", timeoutMs: 20_000, run: primary.run },
        { label: "b", timeoutMs: 20_000, run: backup.run },
      ],
      { hedgeAfterMs: 6_000, onHedge: hedge },
    );
    await vi.advanceTimersByTimeAsync(5_999);
    expect(backup.run).not.toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(1);
    expect(backup.run).toHaveBeenCalledTimes(1);
    expect(hedge).toHaveBeenCalledWith("b", 6_000);
    expect(primary.seen[0].aborted).toBe(false);
    await vi.advanceTimersByTimeAsync(2_000);
    const result = await pending;
    expect(result).toMatchObject({ value: "backup", via: "b", hedged: true, ms: 8_000 });
    expect(primary.seen[0].aborted).toBe(true);
    expect(result.attempts).toEqual([
      { label: "a", startMs: 0, ms: 8_000, outcome: "cancelled" },
      { label: "b", startMs: 6_000, ms: 2_000, outcome: "ok", hedged: true },
    ]);
  });

  it("keeps the primary's answer when it arrives first after the hedge started", async () => {
    vi.useFakeTimers();
    const primary = answersAfter(7_000, "primary");
    const backup = answersAfter(5_000, "backup");
    const pending = runAiAttempts(
      [
        { label: "a", timeoutMs: 20_000, run: primary.run },
        { label: "b", timeoutMs: 20_000, run: backup.run },
      ],
      { hedgeAfterMs: 6_000 },
    );
    await vi.advanceTimersByTimeAsync(7_000);
    const result = await pending;
    expect(result).toMatchObject({ value: "primary", via: "a", hedged: true });
    expect(backup.seen[0].aborted).toBe(true);
    expect(result.attempts.map((a) => [a.label, a.outcome])).toEqual([
      ["a", "ok"],
      ["b", "cancelled"],
    ]);
  });

  it("ignores an invalid early answer from one side and waits for the other", async () => {
    vi.useFakeTimers();
    const primary = answersAfter(9_000, "primary");
    const pending = runAiAttempts(
      [
        { label: "a", timeoutMs: 20_000, run: primary.run },
        {
          label: "b",
          timeoutMs: 20_000,
          run: async () => {
            throw new Error("FORMAT");
          },
        },
      ],
      { hedgeAfterMs: 6_000, isUnusableReply: (e) => (e as Error).message === "FORMAT" },
    );
    await vi.advanceTimersByTimeAsync(9_000);
    const result = await pending;
    expect(result.value).toBe("primary");
    expect(result.attempts.map((a) => a.outcome)).toEqual(["ok", "unusable"]);
  });

  it("a fast primary failure still falls back at once (no waiting for the hedge delay)", async () => {
    vi.useFakeTimers();
    const backup = vi.fn(async () => "backup");
    const pending = runAiAttempts(
      [
        {
          label: "a",
          timeoutMs: 20_000,
          run: async () => {
            throw Object.assign(new Error("Too Many Requests"), { statusCode: 429 });
          },
        },
        { label: "b", timeoutMs: 20_000, run: backup },
      ],
      { hedgeAfterMs: 6_000 },
    );
    await vi.advanceTimersByTimeAsync(0);
    const result = await pending;
    expect(result).toMatchObject({ value: "backup", via: "b", hedged: false, ms: 0 });
    expect(result.attempts[0]).toMatchObject({ outcome: "error", code: "http_429" });
    await vi.advanceTimersByTimeAsync(10_000);
    expect(backup).toHaveBeenCalledTimes(1);
  });

  it("never runs more than one extra call, and the overall wait is capped by the deadlines", async () => {
    vi.useFakeTimers();
    const a = hangs();
    const b = hangs();
    const c = hangs();
    const pending = runAiAttempts(
      [
        { label: "a", timeoutMs: 20_000, run: a.run },
        { label: "b", timeoutMs: 20_000, run: b.run },
        { label: "c", timeoutMs: 20_000, run: c.run },
      ],
      { hedgeAfterMs: 6_000, timeoutMessage: "SLOW" },
    );
    const settled = pending.catch((e: unknown) => e as AiAttemptsFailed);
    await vi.advanceTimersByTimeAsync(20_000);
    // 1番手が締め切り切れでも、追いかけ（2番手）が走っている間は3番手を始めない。
    expect(c.run).not.toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(6_000);
    // 2番手も切れたら3番手（同時に走るのは最大2つ）。
    expect(c.run).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(20_000);
    const error = (await settled) as AiAttemptsFailed;
    expect(error.message).toBe("SLOW");
    expect(error.ms).toBe(46_000);
    expect(error.chargeable).toBe(false);
  });

  it("reads the delay from the environment (0 = off)", () => {
    expect(hedgeAfterFromEnv(undefined, 6_000)).toBe(6_000);
    expect(hedgeAfterFromEnv("", 6_000)).toBe(6_000);
    expect(hedgeAfterFromEnv("4000", 6_000)).toBe(4_000);
    expect(hedgeAfterFromEnv("nope", 6_000)).toBe(6_000);
    expect(hedgeAfterFromEnv("0", 6_000)).toBeUndefined();
  });
});

describe("attemptErrorCode", () => {
  it("keeps only short codes, never free text", () => {
    expect(attemptErrorCode(new Error(AI_ATTEMPT_TIMEOUT))).toBe(AI_ATTEMPT_TIMEOUT);
    expect(attemptErrorCode(new Error("user photo of my house at 3 Main St"))).toBe("error");
    expect(attemptErrorCode("nope")).toBe("unknown");
  });
});

/** Google の OpenAI 互換の口が返す 429 の形（本文は配列、`details` に上限の ID）。 */
function tooManyRequests(body: string) {
  return Object.assign(new Error("Too Many Requests"), { statusCode: 429, responseBody: body });
}

const GOOGLE_429 = JSON.stringify([
  {
    error: {
      code: 429,
      message:
        "You exceeded your current quota, please check your plan and billing details.\n" +
        "* Quota exceeded for metric: generativelanguage.googleapis.com/generate_content_free_tier_requests, " +
        "limit: 20, model: gemini-3.8-flash\nPlease retry in 33.1s.",
      status: "RESOURCE_EXHAUSTED",
      details: [
        {
          "@type": "type.googleapis.com/google.rpc.QuotaFailure",
          violations: [
            {
              quotaMetric: "generativelanguage.googleapis.com/generate_content_free_tier_requests",
              quotaId: "GenerateRequestsPerDayPerProjectPerModel-FreeTier",
              quotaDimensions: { location: "global", model: "gemini-3.8-flash" },
              quotaValue: "20",
            },
          ],
        },
        { "@type": "type.googleapis.com/google.rpc.RetryInfo", retryDelay: "33s" },
      ],
    },
  },
]);

describe("attemptQuotaHint", () => {
  it("keeps which limit was hit (id, metric/limit/model, retry seconds) and nothing else", () => {
    const hint = attemptQuotaHint(tooManyRequests(GOOGLE_429));
    expect(hint).toBe(
      "GenerateRequestsPerDayPerProjectPerModel-FreeTier " +
        "generate_content_free_tier_requests/20/gemini-3.8-flash retry_33s",
    );
    expect(hint).not.toMatch(/billing|quota, please/);
  });

  it("reads the body from the cause too, and is undefined when there is no body or no limit in it", () => {
    expect(attemptQuotaHint({ cause: tooManyRequests(GOOGLE_429) })).toContain("FreeTier");
    expect(attemptQuotaHint(new Error("Too Many Requests"))).toBeUndefined();
    expect(
      attemptQuotaHint(tooManyRequests('{"error":{"message":"Internal error"}}')),
    ).toBeUndefined();
    expect(attemptQuotaHint(null)).toBeUndefined();
  });

  it("is recorded on the failed attempt before falling back", async () => {
    const result = await runAiAttempts([
      {
        label: "google:gemini-3.8-flash",
        timeoutMs: 20_000,
        run: async () => {
          throw tooManyRequests(GOOGLE_429);
        },
      },
      { label: "lovable:google/gemini-2.5-flash", timeoutMs: 20_000, run: async () => "card" },
    ]);
    expect(result.value).toBe("card");
    expect(result.via).toBe("lovable:google/gemini-2.5-flash");
    expect(result.attempts[0]).toEqual(
      expect.objectContaining({
        outcome: "error",
        code: "http_429",
        quota: expect.stringContaining("GenerateRequestsPerDayPerProjectPerModel-FreeTier"),
      }),
    );
    expect(result.attempts[1]).not.toHaveProperty("quota");
  });
});
