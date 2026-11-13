import { describe, expect, it } from "vitest";
import {
  ADMIN_ONLY_MESSAGE,
  estimateAdminAiCost,
  getAdminAiSettings,
  mainFrom,
  setAdminAiAll,
  setAdminAiBackup,
  setAdminAiTask,
  testAdminAiModel,
  undoAdminAiModels,
  type AdminAiDeps,
  type AppConfigKey,
} from "./admin-ai.server";
import { AI_TASK_INFOS } from "./ai-task-settings";
import { AI_FEATURES } from "./ai-features";
import { chosenBackup } from "./ai-provider.server";

function fakeDeps(opts: { admin?: boolean; config?: Partial<Record<AppConfigKey, unknown>> } = {}) {
  const store = new Map<AppConfigKey, unknown>(Object.entries(opts.config ?? {}) as [AppConfigKey, unknown][]);
  const tried: string[] = [];
  const deps: AdminAiDeps = {
    isAdmin: async () => opts.admin ?? true,
    readConfig: async (k) => store.get(k) ?? null,
    writeConfig: async (k, v) => void store.set(k, JSON.parse(JSON.stringify(v))),
    aiProviders: async () => [
      {
        id: "google",
        name: "Google Gemini",
        hasKey: true,
        models: ["gemini-4-hydrogen", "gemini-3.8-flash", "text-only-1"],
        visionModels: ["gemini-4-hydrogen", "gemini-3.8-flash"],
        error: null,
        labels: { "gemini-4-hydrogen": "Gemini 4 Hydrogen" },
      },
      { id: "openai", name: "OpenAI", hasKey: false, models: [], visionModels: [], error: null },
    ],
    describeFeature: async () => ({ provider: "google", model: "x", resolved: "x" }),
    describeTask: async () => ({
      provider: "google",
      model: "x",
      resolved: "x",
      backup: { provider: "anthropic", model: "claude-sonnet-5-5", resolved: "claude-sonnet-5-5" },
    }),
    aiCallRows: async () => ({
      rows: [
        {
          created_at: new Date(Date.now() - 10 * 60_000).toISOString(),
          meta: { ok: true, ms: 3000, task: "card", model: "google:gemini-3.8-flash", in: 1_000_000, out: 0 },
        },
      ],
      truncated: false,
    }),
    aiStatus: () => ({ ok: true, provider: "google", error: null }),
    imageKeys: () => ({ lovable: false, openrouter: false, google: true, openai: false, higgsfield: false }),
    imageEnv: () => ({}),
    ttsHasKey: () => false,
    ttsDefaultEngine: () => "x",
    tryModel: async (p, m) => {
      tried.push(`${p}:${m}`);
      return { ok: true, ms: 1234, error: null };
    },
  };
  return { deps, store, tried };
}

describe("setAdminAiAll / undoAdminAiModels", () => {
  it("writes one model to every feature and every task, keeps backups, and can go back once", async () => {
    const before = { features: { card: "google:gemini-3.8-flash" }, backups: { card: "off" }, backup: "anthropic:claude-sonnet-5-5" };
    const { deps, store } = fakeDeps({ config: { ai_models: before } });
    const r = await setAdminAiAll(deps, { value: "google:gemini-4-hydrogen" });
    expect(r).toMatchObject({ ok: true, tasks: AI_TASK_INFOS.length, features: AI_FEATURES.length });
    const saved = store.get("ai_models") as Record<string, Record<string, string> | string>;
    expect(Object.values(saved.tasks as object).every((v) => v === "google:gemini-4-hydrogen")).toBe(true);
    expect(Object.keys(saved.tasks as object)).toHaveLength(AI_TASK_INFOS.length);
    expect(Object.values(saved.features as object).every((v) => v === "google:gemini-4-hydrogen")).toBe(true);
    expect(saved.backups).toEqual({ card: "off" });
    expect(saved.backup).toBe("anthropic:claude-sonnet-5-5");
    expect(saved.main).toBe("google:gemini-4-hydrogen");

    await undoAdminAiModels(deps);
    expect(store.get("ai_models")).toEqual(before);
    await expect(undoAdminAiModels(deps)).rejects.toThrow("戻せる設定がありません");
  });

  it("refuses a model that cannot read photos, an unknown or keyless provider, and non-admins", async () => {
    const { deps } = fakeDeps();
    await expect(setAdminAiAll(deps, { value: "google:text-only-1" })).rejects.toThrow("写真を読めない");
    await expect(setAdminAiAll(deps, { value: "openai:gpt-5" })).rejects.toThrow("鍵");
    await expect(setAdminAiAll(deps, { value: "auto" })).rejects.toThrow("会社:モデル");
    const other = fakeDeps({ admin: false });
    await expect(setAdminAiAll(other.deps, { value: "google:gemini-4-hydrogen" })).rejects.toThrow(ADMIN_ONLY_MESSAGE);
  });

  it("keeps the main model and the one backup when a single task is changed", async () => {
    const { deps, store } = fakeDeps();
    await setAdminAiAll(deps, { value: "google:gemini-4-hydrogen" });
    await setAdminAiBackup(deps, { backup: "google:gemini-3.8-flash" });
    await setAdminAiTask(deps, { task: "card", value: "google:gemini-3.8-flash" });
    const saved = store.get("ai_models") as Record<string, unknown>;
    expect(saved.main).toBe("google:gemini-4-hydrogen");
    expect(saved.backup).toBe("google:gemini-3.8-flash");
    expect((saved.tasks as Record<string, string>).card).toBe("google:gemini-3.8-flash");
    await setAdminAiBackup(deps, { backup: "auto" });
    expect((store.get("ai_models") as Record<string, unknown>).backup).toBeUndefined();
  });
});

describe("mainFrom", () => {
  it("uses the saved main, else the most used provider:model", () => {
    expect(mainFrom({ main: "google:a", tasks: { card: "google:b" } })).toMatchObject({ value: "google:a", derived: false });
    expect(mainFrom({ tasks: { card: "google:b", word_candidates: "google:b" }, features: { scan: "google:c" } })).toMatchObject({
      value: "google:b",
      provider: "google",
      model: "b",
      derived: true,
    });
    expect(mainFrom({ features: {} })).toBeNull();
  });
});

describe("chosenBackup", () => {
  it("prefers the task's own backup, then the one backup for every task", () => {
    expect(chosenBackup({ backups: { card: "off" }, backup: "google:x" }, "card")).toBe("off");
    expect(chosenBackup({ backup: "google:x" }, "card")).toEqual({ provider: "google", model: "x" });
    expect(chosenBackup({}, "card")).toBeNull();
  });
});

describe("getAdminAiSettings (2026-11-13 additions)", () => {
  it("returns the catalog, the main model, groups, the last hour and the 30-day cost, and remembers the models it saw", async () => {
    const { deps, store } = fakeDeps({
      config: {
        ai_models: { tasks: { card: "google:gemini-4-hydrogen", photo_candidates: "google:gemini-4-hydrogen" } },
        ai_model_seen: { models: { "google:gemini-3.8-flash": "1970-01-01T00:00:00.000Z" } },
      },
    });
    const s = await getAdminAiSettings(deps);
    if (!s.isAdmin) throw new Error("admin expected");
    expect(s.main).toMatchObject({ value: "google:gemini-4-hydrogen", name: "Gemini 4 Hydrogen", derived: true });
    const google = s.catalog.find((p) => p.id === "google")!;
    expect(google.models[0]).toMatchObject({ id: "gemini-4-hydrogen", isNew: true, inUse: true });
    expect(s.catalog.find((p) => p.id === "openai")!.hasKey).toBe(false);
    expect(s.tasks.find((t) => t.id === "card")).toMatchObject({ group: "card", sameAsMain: true });
    expect(s.tasks.find((t) => t.id === "journal_correct")).toMatchObject({ group: "journal", sameAsMain: false });
    expect(s.recent).toEqual({ ok: 1, failed: 0, avgMs: 3000 });
    expect(s.cost30.usd).toBeCloseTo(0.75, 5);
    expect(s.backup).toBe("auto");
    expect(s.backupAuto).toMatchObject({ provider: "anthropic" });
    expect(s.undoAvailable).toBe(false);
    expect(Object.keys((store.get("ai_model_seen") as { models: object }).models)).toContain("google:gemini-4-hydrogen");
  });
});

describe("testAdminAiModel / estimateAdminAiCost", () => {
  it("tries the model once and prices the last 30 days with it", async () => {
    const { deps, tried } = fakeDeps({ config: { ai_prices: { models: { "google:gemini-4-hydrogen": { in: 1.5, out: 7.5 } } } } });
    expect(await testAdminAiModel(deps, { value: "google:gemini-4-hydrogen" })).toMatchObject({ ok: true, ms: 1234 });
    expect(tried).toEqual(["google:gemini-4-hydrogen"]);
    const e = await estimateAdminAiCost(deps, { value: "google:gemini-4-hydrogen" });
    if (!e.isAdmin) throw new Error("admin expected");
    expect(e.nowUsd).toBeCloseTo(0.75, 5);
    expect(e.afterUsd).toBeCloseTo(1.5, 5);
    expect(e.afterJpy).toBe(Math.round(1.5 * e.usdJpy));
  });
});
