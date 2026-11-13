import { describe, expect, it } from "vitest";
import {
  buildCatalogModels,
  estimateSwitchCost,
  isNewModel,
  isTrialModel,
  mergeModelSeen,
  modelVersion,
  modelsInUse,
  normalizeModelSeen,
  recentAiCalls,
} from "./ai-model-catalog";
import { normalizePricesConfig } from "./ai-costs";

const NOW = new Date("2026-11-13T08:00:00Z");
const prices = normalizePricesConfig({ models: { "google:gemini-4-hydrogen": { in: 1.5, out: 7.5 } } });

describe("modelVersion", () => {
  it("reads versions as numbers, Gemini 4 names without a tier included", () => {
    expect(modelVersion("gemini-4-hydrogen")).toEqual([4, 0]);
    expect(modelVersion("gemini-3.10-pro")).toEqual([3, 10]);
    expect(modelVersion("gemini-3.8-flash")).toEqual([3, 8]);
    expect(modelVersion("claude-sonnet-5-5")).toEqual([5, 5]);
    expect(modelVersion("google/gemini-2.5-flash")).toEqual([2, 5]);
    expect(modelVersion("gpt-4o-2024-08-06")).toEqual([4, 0]);
  });
});

describe("isTrialModel", () => {
  it("folds previews, experiments, aliases and dated or numbered versions", () => {
    for (const id of [
      "gemini-3.1-pro-preview",
      "gemini-2.0-flash-exp",
      "gemini-flash-latest",
      "gemini-1.5-flash-001",
      "gpt-4o-2024-08-06",
      "claude-sonnet-4-20250514",
      "gemini-2.5-flash-preview-09-2025",
    ])
      expect(isTrialModel(id), id).toBe(true);
    for (const id of ["gemini-4-hydrogen", "gemini-3.8-flash", "claude-sonnet-5-5", "gpt-5"])
      expect(isTrialModel(id), id).toBe(false);
  });
});

describe("model seen / New", () => {
  it("does not mark everything New the first time, and marks a later arrival", () => {
    const first = mergeModelSeen(normalizeModelSeen(null), ["google:gemini-3.8-flash"], NOW);
    expect(first.changed).toBe(true);
    expect(isNewModel(first.seen.models["google:gemini-3.8-flash"], NOW)).toBe(false);
    const later = mergeModelSeen(first.seen, ["google:gemini-3.8-flash", "google:gemini-4-hydrogen"], NOW);
    expect(later.changed).toBe(true);
    expect(isNewModel(later.seen.models["google:gemini-4-hydrogen"], NOW)).toBe(true);
    const again = mergeModelSeen(later.seen, ["google:gemini-4-hydrogen"], NOW);
    expect(again.changed).toBe(false);
    const in15 = new Date(NOW.getTime() + 15 * 86_400_000);
    expect(isNewModel(later.seen.models["google:gemini-4-hydrogen"], in15)).toBe(false);
  });
});

describe("buildCatalogModels", () => {
  it("puts Gemini 4 on top, newest first, and folds trials and two-generation-old versions", () => {
    const seen = {
      models: {
        "google:gemini-4-argon": "2026-10-14T00:00:00.000Z",
        "google:gemini-4-carbon": "2026-11-11T00:00:00.000Z",
        "google:gemini-4-hydrogen": "2026-11-13T07:00:00.000Z",
      },
    };
    const rows = buildCatalogModels({
      provider: "google",
      ids: [
        "gemini-2.5-flash",
        "gemini-3.5-flash-lite",
        "gemini-3.8-flash",
        "gemini-4-argon",
        "gemini-4-carbon",
        "gemini-4-hydrogen",
        "gemini-3.1-pro-preview",
      ],
      names: { "gemini-4-hydrogen": "Gemini 4 Hydrogen" },
      vision: () => true,
      inUse: new Set(["google:gemini-4-hydrogen"]),
      seen,
      prices,
      now: NOW,
    });
    expect(rows.map((r) => r.id)).toEqual([
      "gemini-4-hydrogen",
      "gemini-4-carbon",
      "gemini-4-argon",
      "gemini-3.8-flash",
      "gemini-3.5-flash-lite",
      "gemini-3.1-pro-preview",
      "gemini-2.5-flash",
    ]);
    const h = rows[0];
    expect(h).toMatchObject({ name: "Gemini 4 Hydrogen", inUse: true, isNew: true, folded: false });
    expect(h.price).toEqual({ inUsd: 1.5, outUsd: 7.5, custom: true });
    expect(rows.find((r) => r.id === "gemini-4-argon")!.isNew).toBe(false);
    expect(rows.find((r) => r.id === "gemini-3.8-flash")!).toMatchObject({ folded: false, name: "gemini-3.8-flash" });
    expect(rows.find((r) => r.id === "gemini-3.1-pro-preview")!.folded).toBe(true);
    expect(rows.find((r) => r.id === "gemini-2.5-flash")!.folded).toBe(true);
  });

  it("never folds a model in use", () => {
    const rows = buildCatalogModels({
      provider: "google",
      ids: ["gemini-4-hydrogen", "gemini-2.5-flash"],
      names: {},
      vision: () => true,
      inUse: new Set(["google:gemini-2.5-flash"]),
      seen: { models: {} },
      prices,
      now: NOW,
    });
    expect(rows.find((r) => r.id === "gemini-2.5-flash")!.folded).toBe(false);
  });
});

describe("modelsInUse", () => {
  it("collects every provider:model of the saved settings", () => {
    const set = modelsInUse({
      features: { card: "google:a" },
      tasks: { card: "google:b", x: "auto" },
      backups: { card: "off", y: "anthropic:c" },
      main: "google:d",
      backup: "openrouter:e",
    });
    expect([...set].sort()).toEqual(["anthropic:c", "google:a", "google:b", "google:d", "openrouter:e"]);
  });
});

describe("recentAiCalls / estimateSwitchCost", () => {
  const rows = [
    { created_at: "2026-11-13T07:30:00Z", meta: { ok: true, ms: 2000, model: "google:gemini-3.8-flash", in: 1_000_000, out: 100_000 } },
    { created_at: "2026-11-13T07:40:00Z", meta: { ok: true, ms: 4000, model: "google:unknown-model", in: 1_000_000, out: 0 } },
    { created_at: "2026-11-13T07:50:00Z", meta: { ok: false, code: "timeout", model: "google:gemini-3.8-flash" } },
    { created_at: "2026-11-13T07:55:00Z", meta: { ok: false, code: "cancelled", model: "openrouter:x" } },
    { created_at: "2026-11-13T05:00:00Z", meta: { ok: true, ms: 9000, model: "google:gemini-3.8-flash", in: 0, out: 0 } },
  ];

  it("counts the last hour without cancelled calls", () => {
    expect(recentAiCalls(rows, new Date("2026-11-13T07:00:00Z"))).toEqual({ ok: 2, failed: 1, avgMs: 3000 });
  });

  it("prices the same tokens with the chosen model", () => {
    const e = estimateSwitchCost(rows, prices, "google:gemini-4-hydrogen");
    expect(e.calls).toBe(3);
    expect(e.unpricedNow).toBe(1);
    // now: 3.8 Flash $0.75 in / $3.75 out → 0.75 + 0.375
    expect(e.nowUsd).toBeCloseTo(1.125, 5);
    // after: 2M in × 1.5 + 0.1M out × 7.5
    expect(e.afterUsd).toBeCloseTo(3.75, 5);
    expect(estimateSwitchCost(rows, prices, "google:no-price").afterUsd).toBeNull();
  });
});
