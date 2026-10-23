import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  AI_CAP_CODES,
  ANONYMOUS_AI_BUDGET_ROOT,
  ANONYMOUS_DAILY_CAPS,
  CALLER_TIER_TTL_MS,
  DAILY_CAPS,
  DEFAULT_ANONYMOUS_AI_DAILY_CAP,
  DEFAULT_FREE_AI_DAILY_CAP,
  DEFAULT_GLOBAL_AI_DAILY_CAP,
  FREE_AI_BUDGET_ROOT,
  GLOBAL_AI_BUDGET_ROOT,
  GLOBAL_CAP_MESSAGE,
  USAGE_CHECK_FAILED_MESSAGE,
  aiBudgetLimits,
  dailyCapFor,
  dailyCapMessage,
  globalAiDailyCap,
  isAiCapError,
  reserveAiCall,
  resetAiCapLogForTest,
  resolveCallerTier,
  type AiCapDeps,
} from "./ai-cap";
import type { BudgetDb } from "./budget-slots";
import { readableError } from "./errors";

/** `app_config` の枠を覚える偽物（同時に来た2本が同じ数を読めるようにする）。 */
function budget() {
  const keys = new Map<string, string>(); // key → updated_at
  const deleted: string[] = [];
  const db = {
    from: () => ({
      select: () => ({
        like: async (_: string, pattern: string) => {
          await Promise.resolve();
          const p = pattern.slice(0, -1);
          return { count: [...keys.keys()].filter((k) => k.startsWith(p)).length, error: null };
        },
      }),
      insert: async ({ key }: { key: string }) => {
        await Promise.resolve();
        if (keys.has(key)) return { error: { code: "23505" } };
        keys.set(key, new Date().toISOString());
        return { error: null };
      },
      delete: () => ({
        like: (_: string, pattern: string) => ({
          lt: async () => {
            deleted.push(pattern);
            return { error: null };
          },
        }),
      }),
    }),
  } as unknown as BudgetDb;
  return { db, keys, deleted };
}

/**
 * その人ごとの `usage_events` を覚える偽物。`reserve` は Postgres の関数
 * `reserve_usage_event` と同じく、数えると入れるを1回で行う（間に他の呼び出しが入らない）。
 */
function usage() {
  const rows: Array<{ id: number; userId: string; kind: string }> = [];
  let next = 1;
  return {
    rows,
    reserve: async (userId: string, kind: string, limit: number) => {
      await Promise.resolve();
      const count = rows.filter((r) => r.userId === userId && r.kind === kind).length;
      if (count >= limit) return null;
      const id = next++;
      rows.push({ id, userId, kind });
      return id;
    },
    release: async (id: number) => {
      const i = rows.findIndex((r) => r.id === id);
      if (i >= 0) rows.splice(i, 1);
    },
  };
}

const NOW = new Date("2026-10-03T03:00:00Z"); // 台湾 11:00

function deps(over: Partial<AiCapDeps> = {}) {
  const u = usage();
  const b = budget();
  const d: AiCapDeps = {
    reserveUsage: u.reserve,
    releaseUsage: u.release,
    budgetDb: b.db,
    globalLimit: 5_000,
    now: () => NOW,
    warn: () => undefined,
    ...over,
  };
  return { d, u, b };
}

beforeEach(() => resetAiCapLogForTest());

describe("reserveAiCall — その人の上限", () => {
  it("呼ぶ前に1回ぶんを記録する（成功の後に足すのではない）", async () => {
    const { d, u } = deps();
    await reserveAiCall(d, "u1", "card");
    expect(u.rows).toMatchObject([{ userId: "u1", kind: "card" }]);
  });

  it("上限に届いたら断り、印つきの文を投げる", async () => {
    const { d, u } = deps();
    for (let i = 0; i < DAILY_CAPS.wordbook; i++) await u.reserve("u1", "wordbook", 1_000);
    await expect(reserveAiCall(d, "u1", "wordbook")).rejects.toThrow(AI_CAP_CODES.daily);
    // 別の人は通る
    await expect(reserveAiCall(d, "u2", "wordbook")).resolves.toMatchObject({
      usageId: expect.any(Number),
    });
  });

  it("**数えられない・記録できないときは断る**（前は通していた）", async () => {
    const { d, u, b } = deps({
      reserveUsage: async () => {
        throw new Error("db down");
      },
    });
    await expect(reserveAiCall(d, "u1", "card")).rejects.toThrow(AI_CAP_CODES.unavailable);
    expect(u.rows).toEqual([]);
    // 全体の枠も使わない
    expect(b.keys.size).toBe(0);
  });

  it("確保した行の番号を返す（返事が無かった回に返せるように）", async () => {
    const { d } = deps();
    await expect(reserveAiCall(d, "u1", "card")).resolves.toEqual({ usageId: 1 });
    await expect(reserveAiCall(d, "u1", "uncapped_kind")).resolves.toEqual({ usageId: null });
  });

  it("**同時に送っても**その人の上限より多くは通らない（数えると入れるが1回）", async () => {
    const { d, u } = deps();
    for (let i = 0; i < DAILY_CAPS.wordbook - 2; i++) await u.reserve("u1", "wordbook", 1_000);
    const results = await Promise.allSettled(
      Array.from({ length: 10 }, () => reserveAiCall(d, "u1", "wordbook")),
    );
    expect(results.filter((r) => r.status === "fulfilled")).toHaveLength(2);
    expect(u.rows).toHaveLength(DAILY_CAPS.wordbook);
  });

  it("上限の無い種類は何もしない", async () => {
    const { d, u, b } = deps();
    await reserveAiCall(d, "u1", "uncapped_kind");
    expect(u.rows).toEqual([]);
    expect(b.keys.size).toBe(0);
  });

  it("確保が先なので、続けて送っても上限より多くは通らない", async () => {
    const { d, u } = deps();
    for (let i = 0; i < DAILY_CAPS.journal_prompt - 3; i++)
      await u.reserve("u1", "journal_prompt", 1_000);
    const results: boolean[] = [];
    for (let i = 0; i < 10; i++) {
      results.push(
        await reserveAiCall(d, "u1", "journal_prompt").then(
          () => true,
          () => false,
        ),
      );
    }
    expect(results.filter(Boolean)).toHaveLength(3);
    expect(u.rows).toHaveLength(DAILY_CAPS.journal_prompt);
  });
});

describe("reserveAiCall — 全員の 1 日の上限", () => {
  it("同時に来ても全体の上限より多くは通さない", async () => {
    const { d, b } = deps({ globalLimit: 5 });
    const results = await Promise.allSettled(
      Array.from({ length: 12 }, (_, i) => reserveAiCall(d, `u${i}`, "card")),
    );
    const ok = results.filter((r) => r.status === "fulfilled");
    expect(ok).toHaveLength(5);
    expect(b.keys.size).toBe(5);
    for (const k of b.keys.keys())
      expect(k.startsWith(`${GLOBAL_AI_BUDGET_ROOT}2026-10-03:`)).toBe(true);
    const refused = results.find((r) => r.status === "rejected") as PromiseRejectedResult;
    expect(String(refused.reason)).toContain(AI_CAP_CODES.global);
  });

  it("全体の上限に届いたら記録に残す", async () => {
    const error = vi.spyOn(console, "error").mockImplementation(() => undefined);
    const { d } = deps({ globalLimit: 1 });
    await reserveAiCall(d, "u1", "card");
    await expect(reserveAiCall(d, "u2", "card")).rejects.toThrow(AI_CAP_CODES.global);
    expect(error).toHaveBeenCalledWith(
      "[usage] global AI daily ceiling reached",
      expect.objectContaining({ limit: 1 }),
    );
    error.mockRestore();
  });

  it("全体の上限に届いた人は、その人の行を増やさない", async () => {
    const { d, u } = deps({ globalLimit: 1 });
    await reserveAiCall(d, "u1", "card");
    await reserveAiCall(d, "u1", "card").catch(() => undefined);
    expect(u.rows).toHaveLength(1);
  });

  it("発音（tts）は全体の上限に数えない", async () => {
    const { d, b, u } = deps({ globalLimit: 1 });
    await reserveAiCall(d, "u1", "tts");
    await reserveAiCall(d, "u1", "tts");
    expect(b.keys.size).toBe(0);
    expect(u.rows).toHaveLength(2);
  });

  it("その日の最初の枠で古い日の枠を掃除する", async () => {
    const { d, b } = deps();
    await reserveAiCall(d, "u1", "card");
    expect(b.deleted).toEqual([`${GLOBAL_AI_BUDGET_ROOT}%`]);
    await reserveAiCall(d, "u1", "card");
    expect(b.deleted).toHaveLength(1);
  });

  it("上限は環境変数で変えられる（読めなければ既定 5,000）", () => {
    expect(globalAiDailyCap(undefined)).toBe(DEFAULT_GLOBAL_AI_DAILY_CAP);
    expect(DEFAULT_GLOBAL_AI_DAILY_CAP).toBe(5_000);
    expect(globalAiDailyCap("1200")).toBe(1200);
    for (const bad of ["", "0", "-3", "abc", "1.5"])
      expect(globalAiDailyCap(bad)).toBe(DEFAULT_GLOBAL_AI_DAILY_CAP);
  });
});

describe("上限の文は画面の言語で出る（`errors.ts` の KNOWN_CODES）", () => {
  const t = (k: string) => `[${k}]`;
  it.each(["ja", "en", "zh-TW"] as const)("%s", async (lang) => {
    const { d, u } = deps();
    for (let i = 0; i < DAILY_CAPS.card; i++) await u.reserve("u1", "card", 1_000);
    const e = await reserveAiCall(d, "u1", "card").catch((x: unknown) => x);
    expect(readableError(e, "FB", lang, t)).toBe("[err.dailyCap]");
    expect(readableError(new Error(`${AI_CAP_CODES.global} x`), "FB", lang, t)).toBe(
      "[err.aiBusy]",
    );
    expect(readableError(new Error(`${AI_CAP_CODES.unavailable} x`), "FB", lang, t)).toBe(
      "[err.usageCheck]",
    );
  });

  it("iOS の道は日本語の文でも上限と分かる（429）", async () => {
    const { statusForError } = await import("./native-fn");
    const { d, u } = deps();
    for (let i = 0; i < DAILY_CAPS.card; i++) await u.reserve("u1", "card", 1_000);
    const e = await reserveAiCall(d, "u1", "card").catch((x: unknown) => x);
    expect(statusForError(e)).toBe(429);
    expect(statusForError(new Error(`${AI_CAP_CODES.unavailable} x`))).toBe(503);
  });
});

describe("匿名の人・無料の人の枠（監査 2026-10-03 H4）", () => {
  it("匿名の人の上限はずっと小さい。チュートリアルの AI だけは同じ", () => {
    for (const kind of Object.keys(DAILY_CAPS)) {
      const anon = dailyCapFor(kind, "anonymous") ?? 0;
      if (kind === "first_catch_ai") {
        expect(anon).toBe(DAILY_CAPS.first_catch_ai);
        continue;
      }
      expect(anon, kind).toBeLessThanOrEqual(Math.max(1, Math.floor(DAILY_CAPS[kind] / 5)));
    }
    expect(dailyCapFor("card", "free")).toBe(DAILY_CAPS.card);
    expect(dailyCapFor("card", "pro")).toBe(DAILY_CAPS.card);
    expect(dailyCapFor("uncapped_kind", "anonymous")).toBeUndefined();
  });

  it("匿名の人は小さい上限で止まる", async () => {
    const { d } = deps({ tier: "anonymous" });
    for (let i = 0; i < ANONYMOUS_DAILY_CAPS.card; i++) await reserveAiCall(d, "a1", "card");
    await expect(reserveAiCall(d, "a1", "card")).rejects.toThrow(AI_CAP_CODES.daily);
  });

  it("匿名の人は匿名の子の枠と全体の枠の両方に数える", async () => {
    const { d, b } = deps({ tier: "anonymous" });
    await reserveAiCall(d, "a1", "first_catch_ai");
    const keys = [...b.keys.keys()];
    expect(keys.some((k) => k.startsWith(`${ANONYMOUS_AI_BUDGET_ROOT}2026-10-03:`))).toBe(true);
    expect(keys.some((k) => k.startsWith(`${GLOBAL_AI_BUDGET_ROOT}2026-10-03:`))).toBe(true);
    expect(keys.some((k) => k.startsWith(FREE_AI_BUDGET_ROOT))).toBe(false);
  });

  it("匿名・無料の人が子の枠を使い切っても、Pro の人は全体の残りで通る", async () => {
    const shared = budget();
    const u = usage();
    const base = {
      reserveUsage: u.reserve,
      releaseUsage: u.release,
      budgetDb: shared.db,
      globalLimit: 10,
      anonymousLimit: 3,
      freeLimit: 4,
      now: () => NOW,
      warn: () => undefined,
    };
    const anon = await Promise.allSettled(
      Array.from({ length: 20 }, (_, i) =>
        reserveAiCall({ ...base, tier: "anonymous" }, `a${i}`, "first_catch_ai"),
      ),
    );
    expect(anon.filter((r) => r.status === "fulfilled")).toHaveLength(3);
    const free = await Promise.allSettled(
      Array.from({ length: 20 }, (_, i) =>
        reserveAiCall({ ...base, tier: "free" }, `f${i}`, "card"),
      ),
    );
    expect(free.filter((r) => r.status === "fulfilled")).toHaveLength(4);
    // 残りの 3 は Pro の人が使える
    const pro = await Promise.allSettled(
      Array.from({ length: 5 }, (_, i) => reserveAiCall({ ...base, tier: "pro" }, `p${i}`, "card")),
    );
    expect(pro.filter((r) => r.status === "fulfilled")).toHaveLength(3);
    // 枠で断られた人の行は返してある
    expect(u.rows).toHaveLength(10);
  });

  it("全体の枠で断られた時、その人の1行は返す", async () => {
    const { d, u } = deps({ tier: "free", globalLimit: 1 });
    await reserveAiCall(d, "u1", "card");
    await expect(reserveAiCall(d, "u2", "card")).rejects.toThrow(AI_CAP_CODES.global);
    expect(u.rows.map((r) => r.userId)).toEqual(["u1"]);
  });

  it("子の枠の上限は環境変数で変えられ、全体より大きくならない", () => {
    expect(aiBudgetLimits({})).toEqual({
      global: DEFAULT_GLOBAL_AI_DAILY_CAP,
      free: DEFAULT_FREE_AI_DAILY_CAP,
      anonymous: DEFAULT_ANONYMOUS_AI_DAILY_CAP,
    });
    expect(DEFAULT_FREE_AI_DAILY_CAP + DEFAULT_ANONYMOUS_AI_DAILY_CAP).toBeLessThan(
      DEFAULT_GLOBAL_AI_DAILY_CAP,
    );
    expect(
      aiBudgetLimits({
        AI_GLOBAL_DAILY_CAP: "100",
        AI_FREE_DAILY_CAP: "500",
        AI_ANON_DAILY_CAP: "7",
      }),
    ).toEqual({ global: 100, free: 100, anonymous: 7 });
  });

  it("絵の生成とチュートリアルの AI は全体の枠に数える。Jev の並べ替えは数えない", async () => {
    const { d, b } = deps();
    await reserveAiCall(d, "u1", "image_gen");
    await reserveAiCall(d, "u1", "first_catch_ai");
    expect(b.keys.size).toBe(2);
    await reserveAiCall(d, "u1", "jev_rank");
    expect(b.keys.size).toBe(2);
    expect(DAILY_CAPS.image_gen).toBeLessThanOrEqual(20);
  });

  it("上限の失敗を見分ける", () => {
    expect(isAiCapError(new Error(dailyCapMessage(3)))).toBe(true);
    expect(isAiCapError(new Error(GLOBAL_CAP_MESSAGE))).toBe(true);
    expect(isAiCapError(new Error(USAGE_CHECK_FAILED_MESSAGE))).toBe(true);
    expect(isAiCapError(new Error("network"))).toBe(false);
  });
});

describe("resolveCallerTier", () => {
  it("匿名・無料・Pro を見分け、少しの間覚える", async () => {
    const isAnonymous = vi.fn(async (id: string) => id.startsWith("anon"));
    const isPro = vi.fn(async (id: string) => id.startsWith("pro"));
    let t = 0;
    const d = { isAnonymous, isPro, now: () => t };
    expect(await resolveCallerTier(d, "anon-1")).toBe("anonymous");
    expect(await resolveCallerTier(d, "pro-1")).toBe("pro");
    expect(await resolveCallerTier(d, "free-1")).toBe("free");
    expect(isAnonymous).toHaveBeenCalledTimes(3);
    await resolveCallerTier(d, "anon-1");
    expect(isAnonymous).toHaveBeenCalledTimes(3);
    t = CALLER_TIER_TTL_MS + 1;
    await resolveCallerTier(d, "anon-1");
    expect(isAnonymous).toHaveBeenCalledTimes(4);
  });

  it("匿名か分からない時は断る（閉じる側）。Pro か分からない時は無料扱い", async () => {
    vi.spyOn(console, "warn").mockImplementation(() => undefined);
    await expect(
      resolveCallerTier(
        {
          isAnonymous: async () => {
            throw new Error("auth down");
          },
          isPro: async () => true,
        },
        "x1",
      ),
    ).rejects.toThrow(AI_CAP_CODES.unavailable);
    expect(
      await resolveCallerTier(
        {
          isAnonymous: async () => false,
          isPro: async () => {
            throw new Error("db down");
          },
        },
        "x2",
      ),
    ).toBe("free");
  });
});
