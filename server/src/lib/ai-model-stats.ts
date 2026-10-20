/**
 * **機能ごと・用途ごと・モデルごとの AI の速さと正確さ**（開発者の「AI の設定」の表。
 * オーナー依頼 2026-10-11「使うモデルによっての単語の候補の速さや解説の速さなどはない。
 * すべての AI を使っている個所の速さと正確性を計測したい」）。
 *
 * サーバ（`ai-model-stats.server.ts`）が読んだ `ai_runs` の行を、ここで数える（純粋な関数・試験あり）。
 *
 * ## 何から数えるか
 * - **速さ・成否・使った量**: AI を呼んだ1回ずつの行（loop = `ai_call`、`ai-call-log.ts`）。
 *   追いかけで負けた回・枠の確保で止めた回（`cancelled`）は AI の失敗ではないので、成否にも
 *   時間にも入れず、回数だけ別に出す。時間は答えた回だけの百分位。
 *   **登録前の人のチュートリアル**は `ai_runs` に行を持てない（`user_id` が口座に結び付いている）
 *   ので `ai_call` も無い。代わりに `app_config` の `first-catch-run:` の行（各回の結果と時間、
 *   `first-catch-guest.server.ts`）を `GUEST_FIRST_CATCH_LOOP` として読み、各回を1回と数える
 *   （量は残っていない。残すのは 14 日なので、30 日の表でもゲストの分は 14 日まで）。
 * - **使えない返事**（形が崩れて捨てた返事）: 撮った後の候補・カード・チュートリアルの記録
 *   （`capture_suggest` / `card_generate` / `first_catch_ai` / ゲストのチュートリアル）の各回の
 *   結果。`ai_call` の行は通信の成否しか知らない（返事の中身が使えたかは呼ぶ所が決める）ので、
 *   ここだけはこちらから。
 * - **候補の当たり**（写真の候補）: 利用者が候補の何番目を選んだか（`candidate_pick`）を、
 *   **その直前にその人へ候補を出したモデル**（同じ人の `capture_suggest` / チュートリアルの候補、
 *   15 分以内）に結び付ける。数え方は `/admin/beta` と同じ — 分母は「一覧から選んだ回 +
 *   一覧に無く母語で調べ直した回」、Top-1 は1番目を選んだ回、Top-3 は3番目までを選んだ回。
 *   「直前」は候補を出した時刻で決める（`sourceAt`。行を書いた順ではない）。
 * - **固定の写真の試し**（`ai_test`）: 開発者が選んだモデルに決まった写真を流した結果
 *   （本番の利用者には影響しない）。正解の付いた写真なので、Top-1 / Top-3 がいちばん確か。
 */
import { AI_CALL_LOOP, AI_TASKS } from "./ai-call-log";
import type { AiFeature } from "./ai-features";
import { callCostUsd } from "./ai-model-prices";

export const AI_STATS_DAYS = [1, 7, 30] as const;
export type AiStatsDays = (typeof AI_STATS_DAYS)[number];
export const AI_TEST_LOOP = "ai_test";
/** 候補を選んだ回を、どこまで前の「候補を出した回」に結び付けるか。 */
export const PICK_ATTRIBUTION_MS = 15 * 60_000;
/**
 * 撮った後の候補の古い行（返事ができた時刻 `meta.at` が無い、2026-10-11 より前）の、書き込みの
 * 遅れの見込み。行は返事を返した後に書く（`runAfterResponse`）ので、行の時刻は返事より遅い。
 */
export const LEGACY_SUGGEST_LAG_MS = 3_000;
/** サーバの時計（`meta.at`）と DB の時計（`created_at`）のずれの見込み。 */
export const PICK_CLOCK_SLACK_MS = 1_000;
/**
 * 登録前の人のチュートリアルの結果（`app_config` の `first-catch-run:` の行）を、表の行に
 * 並べる時の loop の名前。`ai_runs` にこの loop は無い（サーバが `app_config` から作る）。
 */
export const GUEST_FIRST_CATCH_LOOP = "first_catch_guest";

/** 読む loop（サーバはこれだけを読む。語の入る loop は読まない）。 */
export const AI_STATS_LOOPS = [
  AI_CALL_LOOP,
  "capture_suggest",
  "card_generate",
  "first_catch_ai",
  "candidate_pick",
  AI_TEST_LOOP,
] as const;

export type AiStatsRow = {
  user_id: string;
  loop: string;
  created_at: string;
  meta: unknown;
};

export type Rate = { n: number; of: number; pct: number | null };

export type AiModelStat = {
  /** `会社:モデル`。 */
  model: string;
  /** 答えた回 + 失敗 + 締め切り切れ（`cancelled` は入れない）。 */
  calls: number;
  ok: number;
  failed: number;
  timeouts: number;
  cancelled: number;
  okPct: number | null;
  p50: number | null;
  p90: number | null;
  p99: number | null;
  /** 答えた回の平均（会社が量を返した回だけ）。 */
  avgIn: number | null;
  avgOut: number | null;
  avgReasoning: number | null;
  /** 答えた回の1回の費用の平均（米ドル。単価の分かるモデルだけ）。 */
  costUsd: number | null;
  /** 形が崩れて捨てた返事（記録のある用途だけ）。 */
  unusable: Rate | null;
  /** 写真の候補の当たり（写真の候補・チュートリアルの候補だけ）。 */
  picks: PickStat | null;
};

export type PickStat = {
  n: number;
  top1: number;
  top3: number;
  nativeSearch: number;
  top1Pct: number | null;
  top3Pct: number | null;
};

export type AiTaskStats = {
  task: string;
  feature: AiFeature | null;
  models: AiModelStat[];
};

export type AiTestStat = {
  task: string;
  model: string;
  /** 呼び方の違い（`thinking-off` = Claude に考えさせない）。既定の呼び方は null。 */
  variant: string | null;
  /** 学習言語（`zh-TW` / `en` / `ja`）。言語ごとに別の行。古い行で無ければ null。 */
  lang: string | null;
  /** 流した写真の数（失敗も入れる）。 */
  n: number;
  ok: number;
  /** 答えが返らなかった写真（時間切れ・会社の失敗）。正解の率では外れに数える。 */
  failed: number;
  top1: number;
  top3: number;
  top1Pct: number | null;
  top3Pct: number | null;
  /** 答えた写真だけの時間（失敗の数は `failed` で別に出す）。 */
  p50: number | null;
  p90: number | null;
  costUsd: number | null;
  /** 最後に流した時刻（ISO）。 */
  lastAt: string;
};

export type AiModelStatsReport = {
  days: AiStatsDays;
  mine: boolean;
  since: string;
  tasks: AiTaskStats[];
  tests: AiTestStat[];
};

/** 大きい順に並べた値の p 番目（最も近い順位の方式。`beta-metrics.ts` と同じ）。空なら null。 */
export function percentile(values: number[], p: number): number | null {
  const v = values.filter((n) => Number.isFinite(n)).sort((a, b) => a - b);
  if (!v.length) return null;
  const rank = Math.min(v.length, Math.max(1, Math.ceil((p / 100) * v.length)));
  return v[rank - 1];
}

const pct = (n: number, d: number): number | null =>
  d > 0 ? Math.round((1000 * n) / d) / 10 : null;
const avg = (v: number[]): number | null =>
  v.length ? Math.round(v.reduce((s, x) => s + x, 0) / v.length) : null;
const obj = (v: unknown): Record<string, unknown> =>
  v && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, unknown>) : {};
const str = (v: unknown): string | null => (typeof v === "string" && v ? v : null);
const num = (v: unknown): number | undefined =>
  typeof v === "number" && Number.isFinite(v) ? v : undefined;

const TASK_FEATURE = new Map<string, AiFeature | null>(AI_TASKS.map((t) => [t.id, t.feature]));
const TASK_ORDER = new Map<string, number>(AI_TASKS.map((t, i) => [t.id, i]));

type ModelAcc = {
  okMs: number[];
  ok: number;
  failed: number;
  timeouts: number;
  cancelled: number;
  tin: number[];
  tout: number[];
  reasoning: number[];
  costs: number[];
  unusable: number;
  attempts: number;
  picks: { n: number; top1: number; top3: number; native: number } | null;
};

const newAcc = (): ModelAcc => ({
  okMs: [],
  ok: 0,
  failed: 0,
  timeouts: 0,
  cancelled: 0,
  tin: [],
  tout: [],
  reasoning: [],
  costs: [],
  unusable: 0,
  attempts: 0,
  picks: null,
});

/** 記録の loop から、その返事の用途（使えない返事・候補の当たりを数える先）。 */
function sourceTask(row: AiStatsRow): string | null {
  if (row.loop === "capture_suggest") return "photo_candidates";
  if (row.loop === "card_generate") return "card";
  if (row.loop === "first_catch_ai" || row.loop === GUEST_FIRST_CATCH_LOOP) {
    const action = obj(row.meta).action;
    return action === "suggest"
      ? "tutorial_candidates"
      : action === "card"
        ? "tutorial_card"
        : action === "lesson"
          ? "tutorial_lesson"
          : null;
  }
  return null;
}

/**
 * 候補を出した時刻（ms）。撮った後の候補の行は返事を返した**後**に書く（`runAfterResponse`）ので、
 * 行の時刻は返事より遅れる。すぐに選ぶと「選んだ」の行の方が先に書かれ、行の時刻で比べると
 * 1つ前の撮影に結び付いてしまう。返事ができた時刻（`meta.at`）があればそれを使い、無い古い行は
 * 書き込みの遅れを `LEGACY_SUGGEST_LAG_MS` まで見込む。チュートリアルの行は返事の前に書くので
 * 行の時刻のまま。
 */
function sourceAt(row: AiStatsRow): number {
  const at = num(obj(row.meta).at);
  if (at !== undefined) return at;
  const t = Date.parse(row.created_at);
  return row.loop === "capture_suggest" ? t - LEGACY_SUGGEST_LAG_MS : t;
}

export function computeAiModelStats(
  rows: AiStatsRow[],
  opts: { days: AiStatsDays; mine: boolean; since: string },
): AiModelStatsReport {
  const byTask = new Map<string, { feature: AiFeature | null; models: Map<string, ModelAcc> }>();
  const accFor = (task: string, feature: AiFeature | null, model: string): ModelAcc => {
    let t = byTask.get(task);
    if (!t) {
      t = {
        feature: TASK_FEATURE.has(task) ? (TASK_FEATURE.get(task) ?? null) : feature,
        models: new Map(),
      };
      byTask.set(task, t);
    }
    if (t.feature == null && feature) t.feature = feature;
    let m = t.models.get(model);
    if (!m) {
      m = newAcc();
      t.models.set(model, m);
    }
    return m;
  };

  // 1. 呼んだ1回ずつ（速さ・成否・使った量）
  for (const row of rows) {
    if (row.loop !== AI_CALL_LOOP) continue;
    const m = obj(row.meta);
    const task = str(m.task);
    const model = str(m.model);
    if (!task || !model) continue;
    const feature = str(m.feature) as AiFeature | null;
    const acc = accFor(task, feature, model);
    const code = str(m.code);
    if (m.ok === true) {
      acc.ok++;
      const ms = num(m.ms);
      if (ms !== undefined) acc.okMs.push(ms);
      const tin = num(m.in);
      const tout = num(m.out);
      const reasoning = num(m.reasoning);
      if (tin !== undefined) acc.tin.push(tin);
      if (tout !== undefined) acc.tout.push(tout);
      if (reasoning !== undefined) acc.reasoning.push(reasoning);
      const cost = callCostUsd(model, tin, tout);
      if (cost != null) acc.costs.push(cost);
    } else if (code === "cancelled") acc.cancelled++;
    else if (code === "timeout") acc.timeouts++;
    else acc.failed++;
  }

  // 1b. 登録前の人のチュートリアル（`ai_call` が無いので、各回の結果を呼んだ1回として数える）。
  //     形が崩れた返事（`unusable`）も AI は答えているので「答えた回」（`ai_call` と同じ）。
  for (const row of rows) {
    if (row.loop !== GUEST_FIRST_CATCH_LOOP) continue;
    const task = sourceTask(row);
    const attempts = obj(row.meta).attempts;
    if (!task || !Array.isArray(attempts)) continue;
    for (const a of attempts) {
      const label = str(obj(a).label);
      const outcome = str(obj(a).outcome);
      if (!label || !outcome) continue;
      const acc = accFor(task, null, label);
      if (outcome === "ok" || outcome === "unusable") {
        acc.ok++;
        const ms = num(obj(a).ms);
        if (ms !== undefined) acc.okMs.push(ms);
      } else if (outcome === "cancelled") acc.cancelled++;
      else if (outcome === "timeout") acc.timeouts++;
      else acc.failed++;
    }
  }

  // 2. 使えない返事（各回の結果を持つ記録から）
  for (const row of rows) {
    const task = sourceTask(row);
    if (!task) continue;
    const attempts = obj(row.meta).attempts;
    if (!Array.isArray(attempts)) continue;
    for (const a of attempts) {
      const label = str(obj(a).label);
      const outcome = str(obj(a).outcome);
      if (!label || !outcome || outcome === "cancelled") continue;
      const acc = accFor(task, null, label);
      acc.attempts++;
      if (outcome === "unusable") acc.unusable++;
    }
  }

  // 3. 候補の当たり（選んだ回を、直前に候補を出したモデルへ）。登録前の人は「選んだ」の記録が
  //    無い（`candidate_pick` はログインした人だけ）ので、候補を出した回にも入れない。
  const sources = rows
    .filter((r) => {
      if (r.loop === GUEST_FIRST_CATCH_LOOP) return false;
      const task = sourceTask(r);
      return (
        (task === "photo_candidates" || task === "tutorial_candidates") && obj(r.meta).ok === true
      );
    })
    .map((r) => ({
      user: r.user_id,
      at: sourceAt(r),
      task: sourceTask(r)!,
      model: str(obj(r.meta).via),
    }))
    .filter((s) => s.model && Number.isFinite(s.at))
    .sort((a, b) => a.at - b.at);
  const byUser = new Map<string, typeof sources>();
  for (const s of sources) {
    const list = byUser.get(s.user) ?? [];
    list.push(s);
    byUser.set(s.user, list);
  }
  for (const row of rows) {
    if (row.loop !== "candidate_pick") continue;
    const m = obj(row.meta);
    const via = m.via;
    if (via !== "photo" && via !== "native_search") continue;
    const at = Date.parse(row.created_at);
    const list = byUser.get(row.user_id);
    if (!list || !Number.isFinite(at)) continue;
    let src: (typeof sources)[number] | null = null;
    for (const s of list) {
      if (s.at > at + PICK_CLOCK_SLACK_MS) break;
      src = s;
    }
    if (!src || at - src.at > PICK_ATTRIBUTION_MS) continue;
    const acc = accFor(src.task, null, src.model!);
    acc.picks ??= { n: 0, top1: 0, top3: 0, native: 0 };
    acc.picks.n++;
    if (via === "native_search") acc.picks.native++;
    else {
      const rank = num(m.rank);
      if (rank === 1) acc.picks.top1++;
      if (rank !== undefined && rank <= 3) acc.picks.top3++;
    }
  }

  const tasks: AiTaskStats[] = [...byTask.entries()]
    .map(([task, t]) => ({
      task,
      feature: t.feature,
      models: [...t.models.entries()]
        .map(([model, a]): AiModelStat => {
          const calls = a.ok + a.failed + a.timeouts;
          return {
            model,
            calls,
            ok: a.ok,
            failed: a.failed,
            timeouts: a.timeouts,
            cancelled: a.cancelled,
            okPct: pct(a.ok, calls),
            p50: percentile(a.okMs, 50),
            p90: percentile(a.okMs, 90),
            p99: percentile(a.okMs, 99),
            avgIn: avg(a.tin),
            avgOut: avg(a.tout),
            avgReasoning: avg(a.reasoning),
            costUsd: a.costs.length ? a.costs.reduce((s, x) => s + x, 0) / a.costs.length : null,
            unusable: a.attempts
              ? { n: a.unusable, of: a.attempts, pct: pct(a.unusable, a.attempts) }
              : null,
            picks: a.picks
              ? {
                  n: a.picks.n,
                  top1: a.picks.top1,
                  top3: a.picks.top3,
                  nativeSearch: a.picks.native,
                  top1Pct: pct(a.picks.top1, a.picks.n),
                  top3Pct: pct(a.picks.top3, a.picks.n),
                }
              : null,
          };
        })
        // よく使われているモデルを上に。
        .sort(
          (x, y) =>
            y.calls - x.calls ||
            (y.picks?.n ?? 0) - (x.picks?.n ?? 0) ||
            x.model.localeCompare(y.model),
        ),
    }))
    .sort(
      (a, b) =>
        (TASK_ORDER.get(a.task) ?? 999) - (TASK_ORDER.get(b.task) ?? 999) ||
        a.task.localeCompare(b.task),
    );

  return { ...opts, tasks, tests: computeAiTests(rows) };
}

/** 固定の写真の試し（`ai_test`）をモデル・呼び方・学習言語ごとに。 */
export function computeAiTests(rows: AiStatsRow[]): AiTestStat[] {
  const groups = new Map<
    string,
    {
      task: string;
      model: string;
      variant: string | null;
      lang: string | null;
      rows: Array<Record<string, unknown>>;
      lastAt: string;
    }
  >();
  for (const row of rows) {
    if (row.loop !== AI_TEST_LOOP) continue;
    const m = obj(row.meta);
    const task = str(m.task);
    const model = str(m.model);
    if (!task || !model) continue;
    const variant = str(m.variant);
    const lang = str(m.lang);
    const key = `${task}\u0000${model}\u0000${variant ?? ""}\u0000${lang ?? ""}`;
    const g = groups.get(key) ?? { task, model, variant, lang, rows: [], lastAt: row.created_at };
    g.rows.push(m);
    if (row.created_at > g.lastAt) g.lastAt = row.created_at;
    groups.set(key, g);
  }
  return (
    [...groups.values()]
      .map((g): AiTestStat => {
        const ok = g.rows.filter((m) => m.ok === true);
        const ranks = ok.map((m) => num(m.rank));
        const top1 = ranks.filter((r) => r === 1).length;
        const top3 = ranks.filter((r) => r !== undefined && r <= 3).length;
        const costs = ok
          .map((m) => callCostUsd(g.model, num(m.in), num(m.out)))
          .filter((c): c is number => c != null);
        return {
          task: g.task,
          model: g.model,
          variant: g.variant,
          lang: g.lang,
          n: g.rows.length,
          ok: ok.length,
          failed: g.rows.length - ok.length,
          top1,
          top3,
          top1Pct: pct(top1, g.rows.length),
          top3Pct: pct(top3, g.rows.length),
          p50: percentile(
            ok.map((m) => num(m.ms) ?? NaN),
            50,
          ),
          p90: percentile(
            ok.map((m) => num(m.ms) ?? NaN),
            90,
          ),
          costUsd: costs.length ? costs.reduce((s, x) => s + x, 0) / costs.length : null,
          lastAt: g.lastAt,
        };
      })
      // 同じ言語の行を並べて、その中で正解の率の高い順（言語の違う行どうしは比べられない）。
      .sort(
        (a, b) =>
          a.task.localeCompare(b.task) ||
          (a.lang ?? "￿").localeCompare(b.lang ?? "￿") ||
          (b.top1Pct ?? -1) - (a.top1Pct ?? -1),
      )
  );
}
