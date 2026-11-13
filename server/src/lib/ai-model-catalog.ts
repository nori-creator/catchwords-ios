/**
 * **開発者の「AI を選ぶ」画面のモデルの一覧**（オーナー 2026-11-13「毎回 Google が新しいモデルを
 * 出すたびに AI の設定から変更できるように」。模型 https://claude.ai/artifact/V6CDvMNQoRwVNVhqUQpdQm の A）。
 *
 * - 会社ごとに、いま使えるモデルを**新しい順**に並べる。版は数として比べる（3.10 は 3.9 より新しい）。
 *   Gemini 4 からは名前に flash / pro が無い（`gemini-4-hydrogen` など）ので、段ではなく版で並べる。
 *   同じ版の中は、サーバが初めて見た日の新しい順 → 名前の順。
 * - **New**: サーバが初めて見てから 14 日以内（`ai_model_seen`、開発者が画面を開いた時に書く）。
 *   初めて一覧を覚えた日は、その時あった物を New にしない（全部が New になるのを防ぐ）。
 * - **畳む**（「古い版・試験版」）: preview・exp・日付や番号の付いた版・`-latest` の別名、
 *   または同じ系統のいちばん新しい版より 2 つ以上古い世代（Gemini 4 の時の 2.x）。使用中の物は畳まない。
 * - 値段は費用の表と同じ（開発者の入力 → 確かめた表。無ければ null =「値段未登録」）。
 *
 * ここは純粋な関数だけ（DB にも通信にも触らない）。読み書きは `admin-ai.server.ts`。
 */
import { priceFor, type AiPricesConfig } from "./ai-costs";

export const MODEL_SEEN_KEY = "ai_model_seen";
/** New の印を付ける日数。 */
export const NEW_DAYS = 14;
/** 一覧を初めて覚えた時に、その時あった物へ付ける日（New にしない）。 */
const BOOT_SEEN = "1970-01-01T00:00:00.000Z";

/** 保存の形: `{ models: { "会社:モデル": 初めて見た時刻（ISO） } }`。 */
export type ModelSeen = { models: Record<string, string> };

export function normalizeModelSeen(raw: unknown): ModelSeen {
  const m = (raw as { models?: unknown } | null)?.models;
  const out: Record<string, string> = {};
  if (m && typeof m === "object" && !Array.isArray(m)) {
    for (const [k, v] of Object.entries(m as Record<string, unknown>)) {
      if (typeof v === "string" && Number.isFinite(Date.parse(v))) out[k] = v;
    }
  }
  return { models: out };
}

/**
 * いま見えたモデル（`会社:モデル`）を覚えに足す。初めて覚える時（空の時）は全部を古い物として入れる。
 * 変わったかどうかも返す（変わらなければ書かない）。
 */
export function mergeModelSeen(
  seen: ModelSeen,
  labels: readonly string[],
  now: Date,
): { seen: ModelSeen; changed: boolean } {
  const first = Object.keys(seen.models).length === 0;
  const models = { ...seen.models };
  let changed = false;
  for (const l of labels) {
    if (models[l]) continue;
    models[l] = first ? BOOT_SEEN : now.toISOString();
    changed = true;
  }
  return { seen: { models }, changed };
}

export function isNewModel(firstSeen: string | undefined, now: Date): boolean {
  if (!firstSeen) return false;
  const t = Date.parse(firstSeen);
  return Number.isFinite(t) && t > Date.parse(BOOT_SEEN) && now.getTime() - t < NEW_DAYS * 86_400_000;
}

/** 試験版・別名・日付や番号の付いた版（畳む物）。 */
const TRIAL =
  /(preview|-exp$|-exp-|experimental|-latest$|-\d{3}$|-\d{4}$|-\d{6,8}$|\d{4}-\d{2}-\d{2}|-\d{2}-\d{4}|-\d{2}-\d{2}$)/i;

export function isTrialModel(id: string): boolean {
  return TRIAL.test(id);
}

/** 名前の最初の版（`gemini-3.10-pro` → [3, 10]、`gemini-4-hydrogen` → [4, 0]、`claude-sonnet-5-5` → [5, 5]）。 */
export function modelVersion(id: string): [number, number] | null {
  const m = id.match(/(?:^|[-_/.:])v?(\d{1,3})(?:[.-](\d{1,2})(?=$|[-_/.:a-z]))?/i);
  if (!m) return null;
  return [Number(m[1]), m[2] === undefined ? 0 : Number(m[2])];
}

/** 同じ系統の印（数字の前まで。`gemini-4-hydrogen` → `gemini-`、`google/gemini-2.5-flash` → `google/gemini-`）。 */
export function modelFamily(id: string): string {
  const i = id.search(/\d/);
  return (i < 0 ? id : id.slice(0, i)).toLowerCase();
}

export type CatalogModel = {
  /** 会社の中のモデル ID（保存は `会社:ID`）。 */
  id: string;
  /** 画面の名前（会社が教えてくれれば、それ。無ければ ID）。 */
  name: string;
  /** 写真を読めるか（スキャンの用途に選べるか）。 */
  vision: boolean;
  /** 米ドル / 100 万トークン。null = 値段未登録。 */
  price: { inUsd: number; outUsd: number; custom: boolean } | null;
  /** どれかの用途・機能・控え・「使う AI」で使っている。 */
  inUse: boolean;
  /** サーバが初めて見てから 14 日以内。 */
  isNew: boolean;
  /** 「古い版・試験版」に畳む。 */
  folded: boolean;
};

export type CatalogProvider = {
  id: string;
  name: string;
  hasKey: boolean;
  error: string | null;
  models: CatalogModel[];
};

/** 1つの会社のモデルの一覧を、画面に出す形に並べる。 */
export function buildCatalogModels(input: {
  provider: string;
  ids: readonly string[];
  names: Readonly<Record<string, string>>;
  vision: (id: string) => boolean;
  inUse: ReadonlySet<string>;
  seen: ModelSeen;
  prices: AiPricesConfig;
  now: Date;
}): CatalogModel[] {
  const { provider } = input;
  const newest = new Map<string, number>();
  for (const id of input.ids) {
    if (isTrialModel(id)) continue;
    const v = modelVersion(id);
    if (!v) continue;
    const f = modelFamily(id);
    newest.set(f, Math.max(newest.get(f) ?? 0, v[0]));
  }
  const rows = [...new Set(input.ids)].map((id) => {
    const label = `${provider}:${id}`;
    const v = modelVersion(id);
    const top = newest.get(modelFamily(id));
    const old = !!v && top !== undefined && v[0] < top - 1;
    const inUse = input.inUse.has(label);
    const p = priceFor(label, input.prices);
    return {
      row: {
        id,
        name: input.names[id] ?? id,
        vision: input.vision(id),
        price: p ? { inUsd: p.inUsd, outUsd: p.outUsd, custom: p.custom } : null,
        inUse,
        isNew: isNewModel(input.seen.models[label], input.now),
        folded: !inUse && (isTrialModel(id) || old),
      } satisfies CatalogModel,
      v: v ?? [0, 0],
      seen: Date.parse(input.seen.models[label] ?? BOOT_SEEN) || 0,
    };
  });
  rows.sort(
    (a, b) =>
      Number(a.row.folded) - Number(b.row.folded) ||
      b.v[0] - a.v[0] ||
      b.v[1] - a.v[1] ||
      b.seen - a.seen ||
      a.row.id.localeCompare(b.row.id),
  );
  return rows.map((r) => r.row);
}

/** 設定の中で使っている `会社:モデル`（用途・機能・控え・使う AI）。 */
export function modelsInUse(raw: unknown): Set<string> {
  const out = new Set<string>();
  const add = (v: unknown) => {
    if (typeof v !== "string") return;
    const s = v.trim();
    const i = s.indexOf(":");
    if (i > 0 && i < s.length - 1) out.add(s);
  };
  const r = (raw ?? {}) as Record<string, unknown>;
  for (const k of ["features", "tasks", "backups"]) {
    const t = r[k];
    if (t && typeof t === "object") for (const v of Object.values(t as object)) add(v);
  }
  add(r.main);
  add(r.backup);
  return out;
}

// ---- 直近の動き・費用の見積もり ---------------------------------------------

type CallRow = { created_at: string; meta: unknown };

/** 直近（`since` より後）の AI の呼び出しの成功・失敗・平均の秒（止めた回は数えない）。 */
export function recentAiCalls(
  rows: readonly CallRow[],
  since: Date,
): { ok: number; failed: number; avgMs: number | null } {
  let ok = 0;
  let failed = 0;
  let ms = 0;
  const from = since.getTime();
  for (const row of rows) {
    const t = Date.parse(row.created_at);
    if (!Number.isFinite(t) || t < from) continue;
    const m = (row.meta && typeof row.meta === "object" ? row.meta : {}) as Record<string, unknown>;
    if (m.ok !== true && m.code === "cancelled") continue;
    if (m.ok === true) {
      ok++;
      if (typeof m.ms === "number" && Number.isFinite(m.ms) && m.ms >= 0) ms += m.ms;
    } else failed++;
  }
  return { ok, failed, avgMs: ok ? Math.round(ms / ok) : null };
}

/**
 * 直近の使った量のまま、全部の用途を `label`（`会社:モデル`）に替えたら費用がどうなるか。
 * `nowUsd` は今の費用（値段の分かる回だけ）、`afterUsd` は替えた後（値段が分からなければ null）。
 */
export function estimateSwitchCost(
  rows: readonly CallRow[],
  prices: AiPricesConfig,
  label: string,
): {
  calls: number;
  tokensIn: number;
  tokensOut: number;
  nowUsd: number;
  unpricedNow: number;
  afterUsd: number | null;
} {
  const after = priceFor(label, prices);
  const memo = new Map<string, ReturnType<typeof priceFor>>();
  const price = (m: string) => {
    if (!memo.has(m)) memo.set(m, priceFor(m, prices));
    return memo.get(m)!;
  };
  let calls = 0;
  let tokensIn = 0;
  let tokensOut = 0;
  let nowUsd = 0;
  let unpricedNow = 0;
  for (const row of rows) {
    const m = (row.meta && typeof row.meta === "object" ? row.meta : {}) as Record<string, unknown>;
    if (m.ok !== true || typeof m.model !== "string") continue;
    const tin = typeof m.in === "number" && m.in > 0 ? m.in : 0;
    const tout = typeof m.out === "number" && m.out > 0 ? m.out : 0;
    calls++;
    tokensIn += tin;
    tokensOut += tout;
    const p = price(m.model);
    if (p) nowUsd += (tin * p.inUsd + tout * p.outUsd) / 1_000_000;
    else unpricedNow++;
  }
  return {
    calls,
    tokensIn,
    tokensOut,
    nowUsd,
    unpricedNow,
    afterUsd: after ? (tokensIn * after.inUsd + tokensOut * after.outUsd) / 1_000_000 : null,
  };
}
