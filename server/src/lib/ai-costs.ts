/**
 * **AI の費用の分析**（オーナー依頼 2026-10-14「全ての AI の機能を、開発者の私だけ…機能とモデル
 * ごとのコスト管理できるようにして」）。
 *
 * 数える物: AI を呼んだ1回ずつの記録（`ai_runs` の loop = `ai_call`、`ai-call-log.ts`）の
 * 使った量（`meta.in` = 入力のトークン、`meta.out` = 出力のトークン。考えた分も出力に入っている）。
 * 単価（米ドル / 100 万トークン）は `ai-model-prices.ts` の確かめた表に、開発者が画面で入れた値
 * （`app_config.ai_prices`）を重ねる。円は「1 ドル = 何円」（同じ所に保存、画面で変えられる）で出す。
 *
 * - 単価の分からないモデル（Lovable の口・OpenRouter の口・表に無い版）は費用に入れず、
 *   回数と量だけ出して「単価未登録」と示す（画面から単価を入れれば次から入る）。
 * - **有料枠の単価**。Google の無料枠で動いている間の実際の請求は 0 円。
 * - 失敗した回は量が残らない（会社が返さない）ので費用は 0 として数える。
 * - 日付は日本時間。
 *
 * ここは表と純粋な関数だけ（試験・画面からも読める。DB にも鍵にも触らない）。読み出しは
 * `admin-ai.server.ts` の `getAdminAiCosts`。
 */
import { AI_CALL_LOOP } from "./ai-call-log";
import { priceOf } from "./ai-model-prices";
import { taskInfo, taskLabel, type Label } from "./ai-task-settings";

export const AI_PRICES_KEY = "ai_prices";
export const AI_COST_DAYS = [1, 7, 30] as const;
export type AiCostDays = (typeof AI_COST_DAYS)[number];
/**
 * 1 ドル = 何円 の既定（2026-09-16 時点の公開値 約 156 円。画面で変えられる）。
 */
export const DEFAULT_USD_JPY = 156;

/** 保存する形: `{ usdJpy, models: { "会社:モデル": { in, out } } }`（米ドル / 100 万トークン）。 */
export type AiPricesConfig = {
  usdJpy: number;
  models: Record<string, { in: number; out: number }>;
};

/** 単価を入れられるモデルの名前（記録の `会社:モデル` と同じ形）。 */
const SAFE_LABEL = /^[a-z][a-z0-9-]{0,30}:[A-Za-z0-9._/:@+-]{1,160}$/;
const MAX_PRICE_USD = 1000;

function okPrice(v: unknown): v is number {
  return typeof v === "number" && Number.isFinite(v) && v >= 0 && v <= MAX_PRICE_USD;
}

export function isPriceModelLabel(v: unknown): v is string {
  return typeof v === "string" && SAFE_LABEL.test(v);
}

/** 保存されている値を読む（形の違う物は捨てる）。 */
export function normalizePricesConfig(raw: unknown): AiPricesConfig {
  const v = (raw && typeof raw === "object" ? raw : {}) as { usdJpy?: unknown; models?: unknown };
  const usdJpy =
    typeof v.usdJpy === "number" && Number.isFinite(v.usdJpy) && v.usdJpy >= 50 && v.usdJpy <= 500
      ? v.usdJpy
      : DEFAULT_USD_JPY;
  const models: AiPricesConfig["models"] = {};
  if (v.models && typeof v.models === "object" && !Array.isArray(v.models)) {
    for (const [k, p] of Object.entries(v.models as Record<string, unknown>)) {
      const q = p as { in?: unknown; out?: unknown } | null;
      if (isPriceModelLabel(k) && q && okPrice(q.in) && okPrice(q.out))
        models[k] = { in: q.in, out: q.out };
    }
  }
  return { usdJpy, models };
}

export type PriceInfo = {
  inUsd: number;
  outUsd: number;
  /** どこの値か（確かめた所と日付、または開発者の入力）。 */
  source: string;
  /** 開発者が画面で入れた値。 */
  custom: boolean;
};

/** そのモデルの単価。開発者の入力 → 確かめた表。どちらにも無ければ null。 */
export function priceFor(model: string, prices: AiPricesConfig): PriceInfo | null {
  const c = prices.models[model];
  if (c) return { inUsd: c.in, outUsd: c.out, source: "custom", custom: true };
  const p = priceOf(model);
  return p ? { inUsd: p.inUsd, outUsd: p.outUsd, source: p.source, custom: false } : null;
}

/** 日本時間の日付（`YYYY-MM-DD`）。 */
export function jstDay(iso: string): string {
  const t = Date.parse(iso);
  return Number.isFinite(t) ? new Date(t + 9 * 3_600_000).toISOString().slice(0, 10) : "";
}

export type AiCostRow = { created_at: string; meta: unknown };

type Sum = {
  calls: number;
  ok: number;
  failed: number;
  tokensIn: number;
  tokensOut: number;
  usd: number;
  /** 答えたのに単価の分からない回（費用に入っていない）。 */
  unpricedCalls: number;
};

export type AiCostTask = Sum & {
  task: string;
  feature: string | null;
  ios: boolean;
  label: Label;
  models: Array<{ model: string; calls: number; usd: number | null }>;
};

export type AiCostModel = Sum & { model: string; price: PriceInfo | null };

export type AiCostReport = {
  days: AiCostDays;
  since: string;
  usdJpy: number;
  total: Sum;
  tasks: AiCostTask[];
  models: AiCostModel[];
  /** 日ごと（古い順。呼び出しの無い日も 0 で入る）。 */
  daily: Array<{ day: string; calls: number; usd: number }>;
  /** 開発者が入れた単価（消すと確かめた表の値に戻る）。 */
  customPrices: Array<{ model: string; inUsd: number; outUsd: number }>;
};

const newSum = (): Sum => ({
  calls: 0,
  ok: 0,
  failed: 0,
  tokensIn: 0,
  tokensOut: 0,
  usd: 0,
  unpricedCalls: 0,
});

const num = (v: unknown): number => (typeof v === "number" && Number.isFinite(v) && v >= 0 ? v : 0);

/** 呼んだ1回ずつの記録から、用途ごと・モデルごと・日ごとの費用を数える。 */
export function computeAiCosts(
  rows: AiCostRow[],
  prices: AiPricesConfig,
  opts: { days: AiCostDays; since: string; now: Date },
): AiCostReport {
  const total = newSum();
  const byTask = new Map<
    string,
    { sum: Sum; models: Map<string, { calls: number; usd: number; priced: boolean }> }
  >();
  const byModel = new Map<string, Sum>();
  const byDay = new Map<string, { calls: number; usd: number }>();
  const priceMemo = new Map<string, PriceInfo | null>();
  const price = (m: string) => {
    if (!priceMemo.has(m)) priceMemo.set(m, priceFor(m, prices));
    return priceMemo.get(m)!;
  };

  for (const row of rows) {
    const m = (row.meta && typeof row.meta === "object" ? row.meta : {}) as Record<string, unknown>;
    const task = typeof m.task === "string" ? m.task : null;
    const model = typeof m.model === "string" ? m.model : null;
    if (!task || !model) continue;
    // 止めた回（追いかけで負けた・枠で止めた）は AI の失敗でも費用でもない。
    if (m.ok !== true && m.code === "cancelled") continue;
    const ok = m.ok === true;
    const tin = ok ? num(m.in) : 0;
    const tout = ok ? num(m.out) : 0;
    const p = price(model);
    const usd = p ? (tin * p.inUsd + tout * p.outUsd) / 1_000_000 : 0;
    const unpriced = ok && !p ? 1 : 0;

    const add = (s: Sum) => {
      s.calls++;
      if (ok) s.ok++;
      else s.failed++;
      s.tokensIn += tin;
      s.tokensOut += tout;
      s.usd += usd;
      s.unpricedCalls += unpriced;
    };
    add(total);
    let t = byTask.get(task);
    if (!t) {
      t = { sum: newSum(), models: new Map() };
      byTask.set(task, t);
    }
    add(t.sum);
    const tm = t.models.get(model) ?? { calls: 0, usd: 0, priced: !!p };
    tm.calls++;
    tm.usd += usd;
    t.models.set(model, tm);
    let ms = byModel.get(model);
    if (!ms) {
      ms = newSum();
      byModel.set(model, ms);
    }
    add(ms);
    const day = jstDay(row.created_at);
    if (day) {
      const d = byDay.get(day) ?? { calls: 0, usd: 0 };
      d.calls++;
      d.usd += usd;
      byDay.set(day, d);
    }
  }

  const tasks: AiCostTask[] = [...byTask.entries()]
    .map(([task, t]) => {
      const info = taskInfo(task);
      return {
        task,
        feature: info?.feature ?? null,
        ios: info?.ios ?? false,
        label: taskLabel(task),
        ...t.sum,
        models: [...t.models.entries()]
          .map(([model, x]) => ({ model, calls: x.calls, usd: x.priced ? x.usd : null }))
          .sort((a, b) => (b.usd ?? -1) - (a.usd ?? -1) || b.calls - a.calls),
      };
    })
    .sort((a, b) => b.usd - a.usd || b.calls - a.calls || a.task.localeCompare(b.task));

  const models: AiCostModel[] = [...byModel.entries()]
    .map(([model, s]) => ({ model, ...s, price: price(model) }))
    .sort((a, b) => b.usd - a.usd || b.calls - a.calls || a.model.localeCompare(b.model));

  // 期間の全部の日を並べる（呼び出しの無い日も 0 で）。
  const daily: AiCostReport["daily"] = [];
  const first = jstDay(opts.since);
  const last = jstDay(opts.now.toISOString());
  for (let d = first; d && d <= last;) {
    const x = byDay.get(d) ?? { calls: 0, usd: 0 };
    daily.push({ day: d, calls: x.calls, usd: x.usd });
    const next = new Date(`${d}T00:00:00Z`);
    next.setUTCDate(next.getUTCDate() + 1);
    d = next.toISOString().slice(0, 10);
  }

  return {
    days: opts.days,
    since: opts.since,
    usdJpy: prices.usdJpy,
    total,
    tasks,
    models,
    daily,
    customPrices: Object.entries(prices.models)
      .map(([model, p]) => ({ model, inUsd: p.in, outUsd: p.out }))
      .sort((a, b) => a.model.localeCompare(b.model)),
  };
}

export { AI_CALL_LOOP };
