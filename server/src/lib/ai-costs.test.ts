import { describe, expect, it } from "vitest";
import {
  computeAiCosts,
  jstDay,
  normalizePricesConfig,
  priceFor,
  DEFAULT_USD_JPY,
} from "./ai-costs";
import { AI_TASK_INFOS, IOS_AI_TASKS } from "./ai-task-settings";

const row = (at: string, meta: Record<string, unknown>) => ({ created_at: at, meta });
const now = new Date("2026-10-14T12:00:00Z");
const since = new Date(now.getTime() - 7 * 86_400_000).toISOString();

describe("単価", () => {
  it("確かめた表を使い、開発者の入力が勝つ。どちらにも無ければ null", () => {
    const prices = normalizePricesConfig({
      models: { "lovable:google/gemini-2.5-flash": { in: 0.3, out: 2.5 } },
    });
    expect(priceFor("google:gemini-3.8-flash", prices)).toMatchObject({
      inUsd: 0.75,
      custom: false,
    });
    expect(priceFor("anthropic:claude-opus-5-5", prices)).toMatchObject({ inUsd: 4, outUsd: 20 });
    expect(priceFor("lovable:google/gemini-2.5-flash", prices)).toMatchObject({
      inUsd: 0.3,
      outUsd: 2.5,
      custom: true,
    });
    expect(priceFor("google:gemini-2.5-pro", prices)).toBeNull();
  });

  it("形の違う値は捨て、為替は既定に戻る", () => {
    const p = normalizePricesConfig({
      usdJpy: 9999,
      models: {
        "bad name": { in: 1, out: 1 },
        "google:x": { in: -1, out: 1 },
        "google:y": { in: 1, out: 2 },
      },
    });
    expect(p.usdJpy).toBe(DEFAULT_USD_JPY);
    expect(p.models).toEqual({ "google:y": { in: 1, out: 2 } });
  });
});

describe("computeAiCosts", () => {
  it("用途ごと・モデルごと・日ごとに、使った量 × 単価で数える（単価の無いモデルは未登録として分ける）", () => {
    const rows = [
      // 3.8 Flash: 入力 $0.75 / 出力 $3.75（100 万トークンあたり）
      row("2026-10-14T01:00:00Z", {
        task: "card",
        model: "google:gemini-3.8-flash",
        ok: true,
        in: 1_000_000,
        out: 200_000,
      }),
      row("2026-10-13T16:00:00Z", {
        task: "card",
        model: "google:gemini-3.8-flash",
        ok: false,
        code: "http_402",
      }),
      row("2026-10-13T10:00:00Z", {
        task: "card",
        model: "lovable:google/gemini-2.5-flash",
        ok: true,
        in: 5000,
        out: 1000,
      }),
      row("2026-10-12T10:00:00Z", {
        task: "photo_candidates",
        model: "anthropic:claude-haiku-5-5",
        ok: true,
        in: 2_000_000,
        out: 0,
      }),
      // 追いかけで負けた回は数えない
      row("2026-10-12T10:00:00Z", {
        task: "photo_candidates",
        model: "google:gemini-3.5-flash-lite",
        ok: false,
        code: "cancelled",
      }),
    ];
    const r = computeAiCosts(rows, normalizePricesConfig(null), { days: 7, since, now });
    expect(r.total.calls).toBe(4);
    expect(r.total.failed).toBe(1);
    expect(r.total.unpricedCalls).toBe(1);
    expect(r.total.usd).toBeCloseTo(0.75 + 0.75 + 0.2, 6);
    const card = r.tasks.find((t) => t.task === "card")!;
    expect(card).toMatchObject({ calls: 3, ok: 2, failed: 1, ios: true, unpricedCalls: 1 });
    expect(card.usd).toBeCloseTo(1.5, 6);
    expect(card.label.ja).toBe("単語カード");
    expect(card.models.find((m) => m.model.startsWith("lovable"))?.usd).toBeNull();
    expect(r.models[0]).toMatchObject({ model: "google:gemini-3.8-flash", calls: 2 });
    expect(r.models.find((m) => m.model.startsWith("lovable"))?.price).toBeNull();
    // 日本時間で日を分ける（10-13T16:00Z は日本の 10-14）
    expect(r.daily.at(-1)).toMatchObject({ day: "2026-10-14", calls: 2 });
    expect(r.daily.find((d) => d.day === "2026-10-13")).toMatchObject({ calls: 1 });
    expect(r.daily).toHaveLength(8);
    expect(r.usdJpy).toBe(DEFAULT_USD_JPY);
  });

  it("jstDay", () => {
    expect(jstDay("2026-10-13T15:00:00Z")).toBe("2026-10-14");
    expect(jstDay("2026-10-13T14:59:59Z")).toBe("2026-10-13");
  });
});

describe("用途の表", () => {
  it("iOS の用途は全部表にあり、名前が付いている", () => {
    for (const id of IOS_AI_TASKS) {
      const t = AI_TASK_INFOS.find((x) => x.id === id);
      expect(t?.ios).toBe(true);
      expect(t?.label.ja).not.toBe(id);
    }
    // iOS に無い機能は iOS の用途に入れない
    for (const id of [
      "journal_correct",
      "journal_prompts",
      "phrase_card",
      "wordbook",
      "scan_parts",
      "distractors",
      "lexicon_audit",
    ]) {
      expect(AI_TASK_INFOS.find((x) => x.id === id)?.ios).toBe(false);
    }
    expect(AI_TASK_INFOS.find((x) => x.id === "image_verify")?.needsVision).toBe(true);
  });
});
