import { describe, expect, it } from "vitest";
import {
  normalizeThinkingConfig,
  thinkingFor,
  withThinkingLevel,
} from "./ai-thinking";
import {
  getAdminAiSettings,
  setAdminAiThinking,
  testAdminAiModel,
  type AdminAiDeps,
  type AppConfigKey,
} from "./admin-ai.server";

describe("考える深さの保存の形", () => {
  it("「会社:モデル」と段の組だけを残す", () => {
    expect(
      normalizeThinkingConfig({
        "google:gemini-4-hydrogen": "low",
        "google:gemini-3.8-flash": "fast",
        nomodel: "high",
        "google:": "high",
      }),
    ).toEqual({ "google:gemini-4-hydrogen": "low" });
    expect(normalizeThinkingConfig(null)).toEqual({});
    expect(normalizeThinkingConfig(["low"])).toEqual({});
  });

  it("Google のモデルだけに効く", () => {
    const cfg = { "google:gemini-4-hydrogen": "low" as const, "anthropic:claude-sonnet-5-5": "low" as const };
    expect(thinkingFor(cfg, "google", "gemini-4-hydrogen")).toBe("low");
    expect(thinkingFor(cfg, "google", "gemini-3.8-flash")).toBeNull();
    expect(thinkingFor(cfg, "anthropic", "claude-sonnet-5-5")).toBeNull();
  });
});

describe("呼ぶ本文に段を足す", () => {
  const cfg = { "google:gemini-4-hydrogen": "medium" as const };

  it("保存されたモデルなら reasoning_effort を足す", () => {
    const body = { model: "gemini-4-hydrogen", messages: [] };
    expect(withThinkingLevel(body, cfg, "google")).toEqual({ ...body, reasoning_effort: "medium" });
  });

  it("ほかのモデル・呼ぶ所が決めた段・thinking_config はそのまま", () => {
    const other = { model: "gemini-3.8-flash" };
    expect(withThinkingLevel(other, cfg, "google")).toBe(other);
    const chosen = { model: "gemini-4-hydrogen", reasoning_effort: "high" };
    expect(withThinkingLevel(chosen, cfg, "google")).toBe(chosen);
    const native = { model: "gemini-4-hydrogen", extra_body: { google: { thinking_config: { thinking_level: "low" } } } };
    expect(withThinkingLevel(native, cfg, "google")).toBe(native);
  });

  it("「指定しない」で試す印があれば段を足さず、印は Google に送らない", () => {
    const pinned = { model: "gemini-4-hydrogen", catchwords_thinking: "auto", messages: [] };
    expect(withThinkingLevel(pinned, cfg, "google")).toEqual({ model: "gemini-4-hydrogen", messages: [] });
  });
});

function fakeDeps(opts: { tryOk?: boolean; config?: Partial<Record<AppConfigKey, unknown>> } = {}) {
  const store = new Map<AppConfigKey, unknown>(Object.entries(opts.config ?? {}) as [AppConfigKey, unknown][]);
  const tried: Array<{ value: string; thinking: string | null }> = [];
  const written: AppConfigKey[] = [];
  const deps: AdminAiDeps = {
    isAdmin: async () => true,
    readConfig: async (k) => store.get(k) ?? null,
    writeConfig: async (k, v) => {
      written.push(k);
      store.set(k, JSON.parse(JSON.stringify(v)));
    },
    aiProviders: async () => [
      {
        id: "google",
        name: "Google Gemini",
        hasKey: true,
        models: ["gemini-4-hydrogen", "gemini-3.8-flash"],
        visionModels: ["gemini-4-hydrogen", "gemini-3.8-flash"],
        error: null,
      },
      {
        id: "anthropic",
        name: "Anthropic",
        hasKey: true,
        models: ["claude-sonnet-5-5"],
        visionModels: ["claude-sonnet-5-5"],
        error: null,
      },
    ],
    describeFeature: async () => ({ provider: "google", model: "x", resolved: "x" }),
    describeTask: async () => ({ provider: "google", model: "x", resolved: "x", backup: null }),
    aiCallRows: async () => ({ rows: [], truncated: false }),
    aiStatus: () => ({ ok: true, provider: "google", error: null }),
    imageKeys: () => ({ lovable: false, openrouter: false, google: true, openai: false, higgsfield: false }),
    imageEnv: () => ({}),
    ttsHasKey: () => false,
    ttsDefaultEngine: () => "x",
    tryModel: async (p, m, thinking) => {
      tried.push({ value: `${p}:${m}`, thinking: thinking ?? null });
      return opts.tryOk === false
        ? { ok: false, ms: 900, error: "400 Bad Request: unsupported thinking level" }
        : { ok: true, ms: 2100, error: null };
    },
  };
  return { deps, store, tried, written };
}

describe("setAdminAiThinking", () => {
  it("その段で1回呼んで動いたら保存する（ai_models には触らない）", async () => {
    const { deps, store, tried, written } = fakeDeps({ config: { ai_models: { main: "google:gemini-3.8-flash" } } });
    const r = await setAdminAiThinking(deps, { value: "google:gemini-4-hydrogen", level: "low" });
    expect(r).toEqual({ ok: true, value: "google:gemini-4-hydrogen", level: "low", ms: 2100 });
    expect(tried).toEqual([{ value: "google:gemini-4-hydrogen", thinking: "low" }]);
    expect(store.get("ai_thinking")).toEqual({ "google:gemini-4-hydrogen": "low" });
    expect(written).toEqual(["ai_thinking"]);
    expect(store.get("ai_models")).toEqual({ main: "google:gemini-3.8-flash" });
  });

  it("動かなかった段は保存しない", async () => {
    const { deps, store } = fakeDeps({ tryOk: false, config: { ai_thinking: { "google:gemini-4-hydrogen": "high" } } });
    await expect(setAdminAiThinking(deps, { value: "google:gemini-4-hydrogen", level: "medium" })).rejects.toThrow(
      /保存していません/,
    );
    expect(store.get("ai_thinking")).toEqual({ "google:gemini-4-hydrogen": "high" });
  });

  it("auto はその行を消す（試さない）", async () => {
    const { deps, store, tried } = fakeDeps({
      config: { ai_thinking: { "google:gemini-4-hydrogen": "low", "google:gemini-3.8-flash": "high" } },
    });
    const r = await setAdminAiThinking(deps, { value: "google:gemini-4-hydrogen", level: "auto" });
    expect(r.ms).toBeNull();
    expect(tried).toEqual([]);
    expect(store.get("ai_thinking")).toEqual({ "google:gemini-3.8-flash": "high" });
  });

  it("Google 以外・知らない段は断る", async () => {
    const { deps } = fakeDeps();
    await expect(setAdminAiThinking(deps, { value: "anthropic:claude-sonnet-5-5", level: "low" })).rejects.toThrow(
      /Google/,
    );
    await expect(setAdminAiThinking(deps, { value: "google:gemini-4-hydrogen", level: "fast" })).rejects.toThrow();
  });

  it("設定の読み取りに今の段と選べる段が出る・試しにその段で呼べる", async () => {
    const { deps, tried } = fakeDeps({ config: { ai_thinking: { "google:gemini-4-hydrogen": "low" } } });
    const s = await getAdminAiSettings(deps);
    if (!s.isAdmin) throw new Error("admin expected");
    expect(s.thinking).toEqual({ "google:gemini-4-hydrogen": "low" });
    expect(s.thinkingLevels).toEqual(["auto", "low", "medium", "high", "xhigh"]);
    await testAdminAiModel(deps, { value: "google:gemini-4-hydrogen", thinking: "medium" });
    expect(tried.at(-1)).toEqual({ value: "google:gemini-4-hydrogen", thinking: "medium" });
    await testAdminAiModel(deps, { value: "google:gemini-4-hydrogen", thinking: "auto" });
    expect(tried.at(-1)).toEqual({ value: "google:gemini-4-hydrogen", thinking: "auto" });
    await testAdminAiModel(deps, { value: "google:gemini-4-hydrogen" });
    expect(tried.at(-1)).toEqual({ value: "google:gemini-4-hydrogen", thinking: null });
    await testAdminAiModel(deps, { value: "anthropic:claude-sonnet-5-5", thinking: "low" });
    expect(tried.at(-1)).toEqual({ value: "anthropic:claude-sonnet-5-5", thinking: null });
  });
});
