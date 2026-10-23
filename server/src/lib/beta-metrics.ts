import { addDays, AI_UNIT_COST_USD } from "./admin-user-stats";
import { shadowCalibration, type ShadowCalibration, type ShadowRow } from "./calibration";
import {
  isLatencyEvent,
  LATENCY_EVENTS,
  MEMBER_FUNNEL_EVENTS,
  parseFunnelKey,
  TUTORIAL_STEPS,
  type CandidatePickVia,
  type LatencyEvent,
  type MemberFunnelEvent,
  type TutorialStep,
} from "./funnel-events";
import { retentionNow, TARGET_RETENTION } from "./srs";
import { taipeiDay } from "./taipei-day";

/**
 * **ベータの指標の集計**（ロードマップ Phase 9.4 / 11、2026-10-03）。
 *
 * 2〜4 週・10〜30 人のベータで「価値を感じたか・続いたか・お金を払う価値があるか」を
 * 見るための数。サーバ（`beta-metrics.functions.ts`）が読んだ行を、ここで数える。
 * どれも通信しない純粋な関数なので、試験と確認用ページ（`admin-beta` の場面）が同じ計算を通る。
 *
 * ## 誰を数えるか
 * - **数える人**（`users`）: 匿名でなく、管理者でもない口座。登録日は台湾の日付。
 * - 匿名の口座（チュートリアルの予備の道）は「登録前」として費用だけに入れる。
 * - 管理者（オーナー）の使った分は費用の「除外」に出し、1人あたりには入れない。
 *
 * ## 日付
 * すべて台湾の日付（`taipeiDay`）。未登録の人の AI の記録（`first-catch-run:<日付>`）だけは
 * 書く側が UTC の日付なので、その日付のまま数える（最大8時間ずれる）。
 */

/** 読む期間（日）。登録日ごとの継続（D30 まで）と6週の動きが入る長さ。 */
export const BETA_DATA_DAYS = 45;
/** 見比べる期間（直近7日・30日）。 */
export const BETA_WINDOWS = [7, 30] as const;
export type BetaWindow = (typeof BETA_WINDOWS)[number];
/** 復習の「1回の続き」を切る間（分）。これより空いたら別の回。 */
export const REVIEW_SESSION_GAP_MIN = 10;
/** 動きを見る週の数。 */
export const ENGAGEMENT_WEEKS = 6;

/**
 * **呼び出し1回あたりの仮の単価（米ドル）**。`AI_UNIT_COST_USD`（利用者ごとの画面と同じ値）に、
 * そこに無い種類を足した物。管理画面から上書きできる（`app_config.beta_unit_costs`）。
 * - `guest:first_catch_ai`: 未登録の人のチュートリアルの AI（返事を受け取った回だけ）。
 * - `run:<loop>`: `usage_events` に数えない AI の処理（`ai_runs` の loop）。
 * 正確な額は各 AI・音声の管理画面で確かめる（モデルと文の長さで変わる）。
 */
export const DEFAULT_UNIT_COST_USD: Readonly<Record<string, number>> = {
  ...AI_UNIT_COST_USD,
  first_catch_ai: 0.003,
  reader_meaning: 0.002,
  native_text: 0.002,
  scene_label: 0.001,
  "guest:first_catch_ai": 0.003,
  "run:review_distractor_pregen": 0.001,
};

/** 上書きの値を確かめて既定と混ぜる（0〜10 ドルの数だけ受け取る）。 */
export function normalizeUnitCosts(raw: unknown): Record<string, number> {
  const out: Record<string, number> = { ...DEFAULT_UNIT_COST_USD };
  if (raw && typeof raw === "object" && !Array.isArray(raw)) {
    for (const [k, v] of Object.entries(raw as Record<string, unknown>)) {
      if (!(k in DEFAULT_UNIT_COST_USD)) continue;
      if (typeof v === "number" && Number.isFinite(v) && v >= 0 && v <= 10) out[k] = v;
    }
  }
  return out;
}

/** 上書きとして保存する差分（既定と同じ値は保存しない）。 */
export function unitCostOverrides(costs: Record<string, number>): Record<string, number> {
  const normalized = normalizeUnitCosts(costs);
  return Object.fromEntries(
    Object.entries(normalized).filter(([k, v]) => DEFAULT_UNIT_COST_USD[k] !== v),
  );
}

/** 大きい順に並べた値の p 番目（最も近い順位の方式）。空なら null。 */
export function percentile(values: number[], p: number): number | null {
  const v = values.filter((n) => Number.isFinite(n)).sort((a, b) => a - b);
  if (!v.length) return null;
  const rank = Math.min(v.length, Math.max(1, Math.ceil((p / 100) * v.length)));
  return v[rank - 1];
}

const pct = (n: number, d: number): number | null => (d > 0 ? Math.round((100 * n) / d) : null);

/** `today` を含む直近 `days` 日に入るか。 */
export function inWindow(day: string, today: string, days: number): boolean {
  return day <= today && day >= addDays(today, -(days - 1));
}

/* ------------------------------------------------------------------------------------------
 * 入力（サーバが読んだ行を、この形に直して渡す）
 * ------------------------------------------------------------------------------------------ */

export type BetaUser = { id: string; signupDay: string };
export type BetaRawData = {
  /** 台湾の今日。 */
  today: string;
  /** 数える人（匿名でも管理者でもない口座）全員。 */
  users: BetaUser[];
  /** 匿名の口座（チュートリアルの予備の道）。費用を「登録前」に入れるため。 */
  anonIds: string[];
  /** 利用の記録（すべての種類、`BETA_DATA_DAYS` 日）。 */
  usage: Array<{ user_id: string; kind: string; day: string }>;
  /** 撮った札（作った日）。 */
  catches: Array<{ user_id: string; day: string }>;
  /** 復習の答え（ISO の時刻）。 */
  reviews: Array<{ user_id: string; at: string }>;
  /** `app_config` の `funnel:` の鍵。 */
  funnelKeys: string[];
  /**
   * 待ち時間（登録した人、`ai_runs` の `funnel_latency`）。`event` は `LATENCY_EVENTS` の段
   * （無ければ `candidates_shown` — 2026-10-03 より前の行は候補の待ち時間だけだった）。
   */
  latencies: Array<{ user_id: string; day: string; ms: number; event?: string }>;
  /** 候補のどれを選んだか（`ai_runs` の `candidate_pick`）。 */
  picks?: Array<{ user_id: string; day: string; via: CandidatePickVia; rank: number; n: number }>;
  /**
   * 語ごとの復習の状態の履歴（`review_history` の行と `reviews` のいまの行）。
   * `at` = その復習の時刻（ISO）、`interval_days` = その後の間隔（= 安定度）。
   * Personal Words Retained / Week を週の終わりの時点で数え直すのに使う。
   */
  reviewStates?: Array<{ user_id: string; sticker_id: string; at: string; interval_days: number }>;
  /** `model_shadow_predictions` の行（較正）。 */
  shadow?: ShadowRow[];
  /** いまの時刻（ms）。無ければ今日の終わり。試験で固定する。 */
  nowMs?: number;
  /** 最初のキャッチの AI の結果（会員 = `ai_runs`、未登録 = `first-catch-run:`）。 */
  runs: Array<{
    source: "member" | "guest";
    user_id?: string;
    day: string;
    ok: boolean;
    ms: number | null;
    action: string;
    /** 未登録の回で、返事を1つも受け取れず枠を返した（費用に数えない）。 */
    refunded?: boolean;
  }>;
  /** `ai_runs` の loop ごとの行（費用の `run:<loop>`）。 */
  aiRuns: Array<{ user_id: string; loop: string; day: string }>;
  /** 単価（`normalizeUnitCosts` 済み）。 */
  unitCosts: Record<string, number>;
  /** 読める上限で切れた表がある。 */
  truncated?: boolean;
};

/* ------------------------------------------------------------------------------------------
 * 出力（画面はこれを描くだけ）
 * ------------------------------------------------------------------------------------------ */

export type WindowCount = Record<BetaWindow, number>;
export type RetentionCell = { kept: number; eligible: number; pct: number | null };
export type LatencyStat = {
  n: number;
  p50: number | null;
  p90: number | null;
  p99: number | null;
};
/** 候補の当たり方（写真の候補から選んだ回 + 母語で調べ直した回が分母）。 */
export type CandidateAccuracy = {
  /** 分母（写真の候補から選んだ + 母語で調べ直した）。 */
  n: number;
  /** 写真の候補から選んだ回。 */
  photoPicks: number;
  /** 写真の候補に無く、母語で調べ直した回（外れ）。 */
  nativeSearch: number;
  top1: number;
  top3: number;
  top1Pct: number | null;
  top3Pct: number | null;
  nativeSearchPct: number | null;
  /** 並んだ候補の数の中央値。 */
  medianCandidates: number | null;
};
/** North-star: Personal Words Retained / Week（PRODUCT.md › North-star outcome）。 */
export type RetainedWeek = {
  from: string;
  to: string;
  /** その週に使った人。 */
  activeUsers: number;
  /** 週の終わりに「いま思い出せる確率」が目標以上だった語の数（全員の合計）。 */
  retainedWords: number;
  /** 1人あたり（その週に使った人で割る）。 */
  perActiveUser: number | null;
  /** その週に使った人ごとの数の中央値（0 の人も入れる）。 */
  medianPerActiveUser: number | null;
  /** その週の AI・音声の推定費用（会員 + 登録前、米ドル）。 */
  aiUsd: number;
  /** その週に使った人1人あたりの AI 費用。 */
  aiUsdPerActiveUser: number | null;
};
export type ReliabilityRow = {
  window: BetaWindow;
  source: "all" | "member" | "guest";
  action: string;
  n: number;
  ok: number;
  pct: number | null;
  p50: number | null;
  p90: number | null;
};
export type EngagementWeek = {
  from: string;
  to: string;
  activeUsers: number;
  catches: number;
  reviews: number;
  catchesPerActive: number | null;
  reviewsPerActive: number | null;
  reviewSessions: number;
  medianReviewSessionMin: number | null;
};
export type CostKindRow = { key: string; calls: number; unit: number; usd: number };
export type BetaMetrics = {
  today: string;
  tutorial: Array<{ step: TutorialStep; sessions: WindowCount }>;
  signup: Array<{ stage: "signup" | "first_catch" | "first_review"; users: WindowCount }>;
  memberEvents: Array<{ kind: MemberFunnelEvent; users: WindowCount; events: WindowCount }>;
  candidateLatency: Record<BetaWindow, LatencyStat>;
  /** QA.md › Performance checks の4つの待ち時間（p50/p90/p99）。 */
  latency: Record<LatencyEvent, Record<BetaWindow, LatencyStat>>;
  candidateAccuracy: Record<BetaWindow, CandidateAccuracy>;
  northStar: { targetPct: number; weeks: RetainedWeek[] };
  calibration: ShadowCalibration;
  retention: {
    cohorts: Array<{
      day: string;
      users: number;
      d1: RetentionCell;
      d7: RetentionCell;
      d30: RetentionCell;
    }>;
    /** その日（ちょうど N 日目）に使った割合。 */
    exact: { d1: RetentionCell; d7: RetentionCell; d30: RetentionCell };
    /** N 日目以降のどこかで戻った割合（利用者ごとの画面の「継続」と同じ考え方）。 */
    onOrAfter: { d1: RetentionCell; d7: RetentionCell; d30: RetentionCell };
  };
  engagement: EngagementWeek[];
  cost: {
    unitCosts: Record<string, number>;
    days: Array<{ day: string; usd: number; calls: number }>;
    byKind: CostKindRow[];
    totalUsd: number;
    memberUsd: number;
    guestUsd: number;
    excludedUsd: number;
    activeUsers30: number;
    perActiveUserMonthUsd: number | null;
  };
  reliability: ReliabilityRow[];
  truncated: boolean;
};

const windowCount = (f: (w: BetaWindow) => number): WindowCount =>
  Object.fromEntries(BETA_WINDOWS.map((w) => [w, f(w)])) as WindowCount;

/* ------------------------------------------------------------------------------------------
 * 1. ファネル
 * ------------------------------------------------------------------------------------------ */

/** チュートリアルの段ごとのセッション数（同じセッションの同じ段は鍵が1つなので1回）。 */
export function tutorialFunnel(
  keys: string[],
  today: string,
): Array<{ step: TutorialStep; sessions: WindowCount }> {
  const parsed = keys.map(parseFunnelKey).filter((k): k is NonNullable<typeof k> => !!k);
  return TUTORIAL_STEPS.map((step) => ({
    step,
    sessions: windowCount(
      (w) => parsed.filter((k) => k.step === step && inWindow(k.day, today, w)).length,
    ),
  }));
}

/** 登録 → 最初のキャッチ → 最初の復習（その期間に登録した人のうち）。 */
export function signupFunnel(
  users: BetaUser[],
  catches: Array<{ user_id: string }>,
  reviews: Array<{ user_id: string }>,
  today: string,
): BetaMetrics["signup"] {
  const caught = new Set(catches.map((c) => c.user_id));
  const reviewed = new Set(reviews.map((r) => r.user_id));
  const cohort = (w: BetaWindow) => users.filter((u) => inWindow(u.signupDay, today, w));
  return [
    { stage: "signup", users: windowCount((w) => cohort(w).length) },
    {
      stage: "first_catch",
      users: windowCount((w) => cohort(w).filter((u) => caught.has(u.id)).length),
    },
    {
      stage: "first_review",
      users: windowCount((w) => cohort(w).filter((u) => reviewed.has(u.id)).length),
    },
  ];
}

/** 登録した人の段ごとの人数と回数。 */
export function memberEventFunnel(
  usage: Array<{ user_id: string; kind: string; day: string }>,
  userIds: Set<string>,
  today: string,
): BetaMetrics["memberEvents"] {
  return MEMBER_FUNNEL_EVENTS.map((kind) => {
    const rows = usage.filter((e) => e.kind === kind && userIds.has(e.user_id));
    const inW = (w: BetaWindow) => rows.filter((e) => inWindow(e.day, today, w));
    return {
      kind,
      users: windowCount((w) => new Set(inW(w).map((e) => e.user_id)).size),
      events: windowCount((w) => inW(w).length),
    };
  });
}

export function latencyStat(values: number[]): LatencyStat {
  return {
    n: values.length,
    p50: percentile(values, 50),
    p90: percentile(values, 90),
    p99: percentile(values, 99),
  };
}

/** 段ごと・期間ごとの待ち時間。`event` の無い古い行は候補の待ち時間として数える。 */
export function latencyByEvent(
  latencies: BetaRawData["latencies"],
  today: string,
): Record<LatencyEvent, Record<BetaWindow, LatencyStat>> {
  const eventOf = (l: BetaRawData["latencies"][number]): LatencyEvent | null =>
    l.event === undefined ? "candidates_shown" : isLatencyEvent(l.event) ? l.event : null;
  return Object.fromEntries(
    LATENCY_EVENTS.map((ev) => [
      ev,
      Object.fromEntries(
        BETA_WINDOWS.map((w) => [
          w,
          latencyStat(
            latencies
              .filter((l) => eventOf(l) === ev && inWindow(l.day, today, w))
              .map((l) => l.ms),
          ),
        ]),
      ),
    ]),
  ) as Record<LatencyEvent, Record<BetaWindow, LatencyStat>>;
}

/**
 * **候補の当たり方**（ロードマップ Phase 3.2、QA.md › AI quality benchmark の実地の版）。
 * 分母は「写真の候補から選んだ」+「候補に無く母語で調べ直した」。打っただけの語と
 * スキャンからの候補は、写真の候補の AI を測らないので入れない。
 */
export function candidateAccuracy(
  picks: NonNullable<BetaRawData["picks"]>,
  today: string,
): Record<BetaWindow, CandidateAccuracy> {
  return Object.fromEntries(
    BETA_WINDOWS.map((w) => {
      const inW = picks.filter((p) => inWindow(p.day, today, w));
      const photo = inW.filter((p) => p.via === "photo");
      const native = inW.filter((p) => p.via === "native_search").length;
      const n = photo.length + native;
      const top1 = photo.filter((p) => p.rank === 1).length;
      const top3 = photo.filter((p) => p.rank <= 3).length;
      const acc: CandidateAccuracy = {
        n,
        photoPicks: photo.length,
        nativeSearch: native,
        top1,
        top3,
        top1Pct: pct(top1, n),
        top3Pct: pct(top3, n),
        nativeSearchPct: pct(native, n),
        medianCandidates: percentile(
          photo.map((p) => p.n),
          50,
        ),
      };
      return [w, acc];
    }),
  ) as Record<BetaWindow, CandidateAccuracy>;
}

/* ------------------------------------------------------------------------------------------
 * 2. 継続（登録日ごと）
 * ------------------------------------------------------------------------------------------ */

/** 利用者ごとの「使った日」（利用の記録・復習・撮った札のどれか）。 */
export function activeDaysByUser(
  usage: Array<{ user_id: string; day: string }>,
  catches: Array<{ user_id: string; day: string }>,
  reviewDays: Array<{ user_id: string; day: string }>,
): Map<string, Set<string>> {
  const m = new Map<string, Set<string>>();
  for (const e of [...usage, ...catches, ...reviewDays]) {
    let s = m.get(e.user_id);
    if (!s) m.set(e.user_id, (s = new Set()));
    s.add(e.day);
  }
  return m;
}

/**
 * N 日目の継続。**その日が終わった人だけ**を数に入れる（今日はまだ途中なので入れない）。
 * `exact`: ちょうど N 日目に使った。`onOrAfter`: N 日目以降のどこかで使った。
 */
export function retentionCell(
  users: BetaUser[],
  active: Map<string, Set<string>>,
  n: number,
  today: string,
  mode: "exact" | "onOrAfter",
): RetentionCell {
  const eligible = users.filter((u) => addDays(u.signupDay, n) < today);
  const kept = eligible.filter((u) => {
    const target = addDays(u.signupDay, n);
    const days = active.get(u.id);
    if (!days) return false;
    if (mode === "exact") return days.has(target);
    for (const d of days) if (d >= target) return true;
    return false;
  }).length;
  return { kept, eligible: eligible.length, pct: pct(kept, eligible.length) };
}

export function retentionTable(
  users: BetaUser[],
  active: Map<string, Set<string>>,
  today: string,
  days: number = BETA_DATA_DAYS,
): BetaMetrics["retention"] {
  const from = addDays(today, -(days - 1));
  const inRange = users.filter((u) => u.signupDay >= from && u.signupDay <= today);
  const byDay = new Map<string, BetaUser[]>();
  for (const u of inRange) byDay.set(u.signupDay, [...(byDay.get(u.signupDay) ?? []), u]);
  const cell = (list: BetaUser[], n: number, mode: "exact" | "onOrAfter") =>
    retentionCell(list, active, n, today, mode);
  return {
    cohorts: [...byDay.entries()]
      .sort((a, b) => (a[0] < b[0] ? 1 : -1))
      .map(([day, list]) => ({
        day,
        users: list.length,
        d1: cell(list, 1, "exact"),
        d7: cell(list, 7, "exact"),
        d30: cell(list, 30, "exact"),
      })),
    exact: {
      d1: cell(inRange, 1, "exact"),
      d7: cell(inRange, 7, "exact"),
      d30: cell(inRange, 30, "exact"),
    },
    onOrAfter: {
      d1: cell(inRange, 1, "onOrAfter"),
      d7: cell(inRange, 7, "onOrAfter"),
      d30: cell(inRange, 30, "onOrAfter"),
    },
  };
}

/* ------------------------------------------------------------------------------------------
 * 3. 使い方（週ごと）
 * ------------------------------------------------------------------------------------------ */

/**
 * 復習の「1回」の長さ（分）。同じ人の答えが `gapMin` 分より空いたら別の回。
 * 1問だけの回は 0 分。回の日は始めた時刻の台湾の日付。
 */
export function reviewSessions(
  reviews: Array<{ user_id: string; at: string }>,
  gapMin: number = REVIEW_SESSION_GAP_MIN,
): Array<{ user_id: string; day: string; minutes: number; answers: number }> {
  const byUser = new Map<string, number[]>();
  for (const r of reviews) {
    const t = Date.parse(r.at);
    if (!Number.isFinite(t)) continue;
    byUser.set(r.user_id, [...(byUser.get(r.user_id) ?? []), t]);
  }
  const out: Array<{ user_id: string; day: string; minutes: number; answers: number }> = [];
  for (const [user_id, times] of byUser) {
    times.sort((a, b) => a - b);
    let start = times[0];
    let last = times[0];
    let answers = 1;
    const close = () =>
      out.push({
        user_id,
        day: taipeiDay(new Date(start)),
        minutes: Math.round((last - start) / 6000) / 10,
        answers,
      });
    for (const t of times.slice(1)) {
      if (t - last > gapMin * 60_000) {
        close();
        start = t;
        answers = 0;
      }
      last = t;
      answers++;
    }
    close();
  }
  return out;
}

const per = (n: number, d: number) => (d > 0 ? Math.round((10 * n) / d) / 10 : null);

export function weeklyEngagement(
  users: Set<string>,
  active: Map<string, Set<string>>,
  catches: Array<{ user_id: string; day: string }>,
  reviews: Array<{ user_id: string; at: string }>,
  today: string,
  weeks: number = ENGAGEMENT_WEEKS,
): EngagementWeek[] {
  const ownReviews = reviews.filter((r) => users.has(r.user_id));
  const reviewDays = ownReviews.map((r) => taipeiDay(r.at));
  const sessions = reviewSessions(ownReviews);
  return Array.from({ length: weeks }, (_, i) => {
    const to = addDays(today, -7 * i);
    const from = addDays(to, -6);
    const inWeek = (d: string) => d >= from && d <= to;
    let activeUsers = 0;
    for (const id of users) {
      const days = active.get(id);
      if (days && [...days].some(inWeek)) activeUsers++;
    }
    const c = catches.filter((x) => users.has(x.user_id) && inWeek(x.day)).length;
    const r = reviewDays.filter(inWeek).length;
    const s = sessions.filter((x) => inWeek(x.day)).map((x) => x.minutes);
    const med = percentile(s, 50);
    return {
      from,
      to,
      activeUsers,
      catches: c,
      reviews: r,
      catchesPerActive: per(c, activeUsers),
      reviewsPerActive: per(r, activeUsers),
      reviewSessions: s.length,
      medianReviewSessionMin: med,
    };
  });
}

/* ------------------------------------------------------------------------------------------
 * 4. AI・音声の費用（推定）
 * ------------------------------------------------------------------------------------------ */

type CostCall = { key: string; day: string; who: "member" | "guest" | "excluded" };

/** 費用に数える呼び出しを1件ずつ並べる（誰の分か付き）。 */
export function costCalls(raw: BetaRawData): CostCall[] {
  const { unitCosts } = raw;
  const users = new Set(raw.users.map((u) => u.id));
  const anon = new Set(raw.anonIds);
  const group = (uid: string | undefined) =>
    uid && users.has(uid) ? "member" : uid && anon.has(uid) ? "guest" : "excluded";
  const calls: CostCall[] = [];
  for (const e of raw.usage)
    if (e.kind in unitCosts) calls.push({ key: e.kind, day: e.day, who: group(e.user_id) });
  for (const r of raw.aiRuns) {
    const key = `run:${r.loop}`;
    if (key in unitCosts) calls.push({ key, day: r.day, who: group(r.user_id) });
  }
  for (const r of raw.runs)
    if (r.source === "guest" && !r.refunded)
      calls.push({ key: "guest:first_catch_ai", day: r.day, who: "guest" });
  return calls;
}

export function costEstimate(raw: BetaRawData, activeUsers30: number): BetaMetrics["cost"] {
  const { today, unitCosts } = raw;
  const calls = costCalls(raw);
  const in30 = calls.filter((c) => inWindow(c.day, today, 30));
  const sum = (list: typeof calls) =>
    +list.reduce((s, c) => s + (unitCosts[c.key] ?? 0), 0).toFixed(4);
  const counted = in30.filter((c) => c.who !== "excluded");
  const byKind = new Map<string, number>();
  for (const c of counted) byKind.set(c.key, (byKind.get(c.key) ?? 0) + 1);
  const days = Array.from({ length: 30 }, (_, i) => {
    const day = addDays(today, i - 29);
    const list = counted.filter((c) => c.day === day);
    return { day, usd: sum(list), calls: list.length };
  });
  const memberUsd = sum(counted.filter((c) => c.who === "member"));
  const guestUsd = sum(counted.filter((c) => c.who === "guest"));
  const totalUsd = +(memberUsd + guestUsd).toFixed(4);
  return {
    unitCosts,
    days,
    byKind: [...byKind.entries()]
      .map(([key, n]) => ({
        key,
        calls: n,
        unit: unitCosts[key] ?? 0,
        usd: +(n * (unitCosts[key] ?? 0)).toFixed(4),
      }))
      .sort((a, b) => b.usd - a.usd || b.calls - a.calls),
    totalUsd,
    memberUsd,
    guestUsd,
    excludedUsd: sum(in30.filter((c) => c.who === "excluded")),
    activeUsers30,
    perActiveUserMonthUsd: activeUsers30 > 0 ? +(totalUsd / activeUsers30).toFixed(4) : null,
  };
}

/* ------------------------------------------------------------------------------------------
 * 5. 解析の確かさ（最初のキャッチの AI）
 * ------------------------------------------------------------------------------------------ */

export function analysisReliability(
  runs: BetaRawData["runs"],
  today: string,
  excludedUserIds: Set<string> = new Set(),
): ReliabilityRow[] {
  const counted = runs.filter((r) => !(r.user_id && excludedUserIds.has(r.user_id)));
  const actions = [...new Set(counted.map((r) => r.action))].sort();
  const rows: ReliabilityRow[] = [];
  for (const w of BETA_WINDOWS) {
    const inW = counted.filter((r) => inWindow(r.day, today, w));
    const add = (source: ReliabilityRow["source"], action: string, list: typeof inW) => {
      const ok = list.filter((r) => r.ok).length;
      // 待ち時間は失敗した回も入れる（利用者はその間待っていた）。
      const ms = list.filter((r) => typeof r.ms === "number").map((r) => r.ms as number);
      rows.push({
        window: w,
        source,
        action,
        n: list.length,
        ok,
        pct: pct(ok, list.length),
        p50: percentile(ms, 50),
        p90: percentile(ms, 90),
      });
    };
    add("all", "all", inW);
    add(
      "member",
      "all",
      inW.filter((r) => r.source === "member"),
    );
    add(
      "guest",
      "all",
      inW.filter((r) => r.source === "guest"),
    );
    for (const a of actions)
      add(
        "all",
        a,
        inW.filter((r) => r.action === a),
      );
  }
  return rows;
}

/* ------------------------------------------------------------------------------------------
 * 6. North-star: Personal Words Retained / Week（PRODUCT.md）
 * ------------------------------------------------------------------------------------------ */

/** 台湾の日付の終わり（ms）。 */
export function endOfTaipeiDay(day: string): number {
  return Date.parse(`${day}T23:59:59.999+08:00`);
}

/**
 * その時刻に「いま思い出せる確率」が目標（`TARGET_RETENTION`、90%）以上の語を、人ごとに数える。
 * 語ごとに、その時刻より前の最後の復習の状態（間隔 = 安定度）から `retentionNow` で出す
 * （画面の % と同じ式）。撮っただけで復習していない語は 0% なので数に入らない。
 */
export function retainedWordsAt(
  states: NonNullable<BetaRawData["reviewStates"]>,
  atMs: number,
  target: number = TARGET_RETENTION,
): Map<string, number> {
  const last = new Map<string, { user_id: string; t: number; interval: number }>();
  for (const s of states) {
    const t = Date.parse(s.at);
    if (!Number.isFinite(t) || t > atMs) continue;
    const key = `${s.user_id}:${s.sticker_id}`;
    const prev = last.get(key);
    if (!prev || t >= prev.t) last.set(key, { user_id: s.user_id, t, interval: s.interval_days });
  }
  const out = new Map<string, number>();
  for (const v of last.values()) {
    if (retentionNow(v.interval, 0, v.t, atMs) / 100 >= target)
      out.set(v.user_id, (out.get(v.user_id) ?? 0) + 1);
  }
  return out;
}

export function retainedWeekly(
  raw: BetaRawData,
  active: Map<string, Set<string>>,
  weeks: number = ENGAGEMENT_WEEKS,
): BetaMetrics["northStar"] {
  const { today } = raw;
  const users = new Set(raw.users.map((u) => u.id));
  const states = (raw.reviewStates ?? []).filter((s) => users.has(s.user_id));
  const nowMs = raw.nowMs ?? endOfTaipeiDay(today);
  const calls = costCalls(raw).filter((c) => c.who !== "excluded");
  return {
    targetPct: Math.round(TARGET_RETENTION * 100),
    weeks: Array.from({ length: weeks }, (_, i) => {
      const to = addDays(today, -7 * i);
      const from = addDays(to, -6);
      const inWeek = (d: string) => d >= from && d <= to;
      const activeIds = [...users].filter((id) => {
        const days = active.get(id);
        return !!days && [...days].some(inWeek);
      });
      const retained = retainedWordsAt(states, Math.min(endOfTaipeiDay(to), nowMs));
      const counts = activeIds.map((id) => retained.get(id) ?? 0);
      let retainedWords = 0;
      for (const n of retained.values()) retainedWords += n;
      const aiUsd = +calls
        .filter((c) => inWeek(c.day))
        .reduce((s, c) => s + (raw.unitCosts[c.key] ?? 0), 0)
        .toFixed(4);
      return {
        from,
        to,
        activeUsers: activeIds.length,
        retainedWords,
        perActiveUser: per(
          counts.reduce((s, n) => s + n, 0),
          activeIds.length,
        ),
        medianPerActiveUser: percentile(counts, 50),
        aiUsd,
        aiUsdPerActiveUser: activeIds.length ? +(aiUsd / activeIds.length).toFixed(4) : null,
      };
    }),
  };
}

/* ------------------------------------------------------------------------------------------
 * まとめ
 * ------------------------------------------------------------------------------------------ */

export function computeBetaMetrics(raw: BetaRawData): BetaMetrics {
  const { today } = raw;
  const userIds = new Set(raw.users.map((u) => u.id));
  const own = <T extends { user_id: string }>(list: T[]) =>
    list.filter((x) => userIds.has(x.user_id));
  const reviewDays = own(raw.reviews).map((r) => ({ user_id: r.user_id, day: taipeiDay(r.at) }));
  const active = activeDaysByUser(own(raw.usage), own(raw.catches), reviewDays);
  let activeUsers30 = 0;
  for (const id of userIds) {
    const days = active.get(id);
    if (days && [...days].some((d) => inWindow(d, today, 30))) activeUsers30++;
  }
  const latencies = own(raw.latencies);
  const excluded = new Set(
    [...raw.runs.map((r) => r.user_id), ...raw.usage.map((e) => e.user_id)].filter(
      (id): id is string => !!id && !userIds.has(id) && !raw.anonIds.includes(id),
    ),
  );
  return {
    today,
    tutorial: tutorialFunnel(raw.funnelKeys, today),
    signup: signupFunnel(raw.users, own(raw.catches), own(raw.reviews), today),
    memberEvents: memberEventFunnel(raw.usage, userIds, today),
    candidateLatency: latencyByEvent(latencies, today).candidates_shown,
    latency: latencyByEvent(latencies, today),
    candidateAccuracy: candidateAccuracy(own(raw.picks ?? []), today),
    northStar: retainedWeekly(raw, active),
    calibration: shadowCalibration(raw.shadow ?? []),
    retention: retentionTable(raw.users, active, today),
    engagement: weeklyEngagement(userIds, active, raw.catches, raw.reviews, today),
    cost: costEstimate(raw, activeUsers30),
    reliability: analysisReliability(raw.runs, today, excluded),
    truncated: !!raw.truncated,
  };
}
