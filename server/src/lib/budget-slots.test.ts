import { afterEach, describe, expect, it, vi } from "vitest";
import {
  BUDGET_KEEP_DAYS,
  pruneBudgetRows,
  reserveBudgetSlot,
  shouldPruneAfter,
  type BudgetDb,
} from "./budget-slots";

/** `app_config` の行（鍵と作った時刻）を持つ偽物。delete は like と lt を本当に当てる。 */
function table(rows: Array<{ key: string; updated_at: string }>) {
  const db = {
    from: () => ({
      select: () => ({
        like: async (_: string, pattern: string) => ({
          count: rows.filter((r) => r.key.startsWith(pattern.slice(0, -1))).length,
          error: null,
        }),
      }),
      insert: async ({ key }: { key: string }) => {
        if (rows.some((r) => r.key === key)) return { error: { code: "23505" } };
        rows.push({ key, updated_at: new Date().toISOString() });
        return { error: null };
      },
      delete: () => ({
        like: (_: string, pattern: string) => ({
          lt: async (_c: string, before: string) => {
            const root = pattern.slice(0, -1);
            for (let i = rows.length - 1; i >= 0; i--)
              if (rows[i].key.startsWith(root) && rows[i].updated_at < before) rows.splice(i, 1);
            return { error: null };
          },
        }),
      }),
    }),
  } as unknown as BudgetDb;
  return db;
}

const errors = { unavailable: "UNAVAILABLE", limit: "LIMIT" };

afterEach(() => vi.restoreAllMocks());

describe("reserveBudgetSlot", () => {
  it("returns the slot number and stops at the limit", async () => {
    const rows: Array<{ key: string; updated_at: string }> = [];
    const db = table(rows);
    expect(await reserveBudgetSlot(db, "p:", 2, errors)).toBe(0);
    expect(await reserveBudgetSlot(db, "p:", 2, errors)).toBe(1);
    await expect(reserveBudgetSlot(db, "p:", 2, errors)).rejects.toThrow("LIMIT");
  });
});

describe("pruneBudgetRows（古い日の枠を消す）", () => {
  it(`removes rows of that root older than ${BUDGET_KEEP_DAYS} days and keeps the rest`, async () => {
    const now = new Date("2026-10-03T00:00:00Z");
    const ago = (days: number) => new Date(now.getTime() - days * 86_400_000).toISOString();
    const rows = [
      { key: "first-catch-budget:2026-09-29:global:0", updated_at: ago(4) },
      { key: "first-catch-budget:2026-09-30:ip:abc:0", updated_at: ago(3) },
      { key: "first-catch-budget:2026-10-02:global:0", updated_at: ago(1) },
      { key: "first-catch-budget:2026-10-03:global:0", updated_at: ago(0) },
      { key: "ai_models", updated_at: ago(30) },
      { key: "tts_voice", updated_at: ago(90) },
    ];
    expect(await pruneBudgetRows(table(rows), "first-catch-budget:", now)).toBe(true);
    expect(rows.map((r) => r.key)).toEqual([
      "first-catch-budget:2026-10-02:global:0",
      "first-catch-budget:2026-10-03:global:0",
      "ai_models",
      "tts_voice",
    ]);
  });

  it("never throws (cleanup must not block a reservation)", async () => {
    vi.spyOn(console, "warn").mockImplementation(() => undefined);
    const broken = {
      from: () => ({
        delete: () => ({
          like: () => ({
            lt: async () => {
              throw new Error("offline");
            },
          }),
        }),
      }),
    } as unknown as BudgetDb;
    expect(await pruneBudgetRows(broken, "x:")).toBe(false);
  });

  it("runs on the first slot of the day and every 50th after", () => {
    expect(shouldPruneAfter(0)).toBe(true);
    expect(shouldPruneAfter(1)).toBe(false);
    expect(shouldPruneAfter(50)).toBe(true);
  });
});
