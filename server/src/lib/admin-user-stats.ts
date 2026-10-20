/**
 * **開発者だけが見る、利用者ごとの数字の計算**（オーナー指示 2026-09-27「開発者の私だけ、
 * 設定の欄から、それぞれのユーザーの詳しい情報を見れるようにして」）。
 *
 * 画面（`/admin/users`）とサーバ（`admin-users.functions.ts`）の間で使う、通信を
 * しない計算だけをここに置く（テストで確かめる）。
 */
import { memoryOf } from "./memory";
import { retentionNow } from "./srs";

/** 何日続けて撮ったか（今の連続と、いちばん長い連続）。日は "YYYY-MM-DD"。 */
export function streaks(days: string[], today: string): { current: number; best: number } {
  const set = [...new Set(days)].sort();
  if (!set.length) return { current: 0, best: 0 };
  const next = (d: string) => {
    const x = new Date(`${d}T12:00:00Z`);
    x.setUTCDate(x.getUTCDate() + 1);
    return x.toISOString().slice(0, 10);
  };
  let best = 1;
  let run = 1;
  for (let i = 1; i < set.length; i++) {
    run = next(set[i - 1]) === set[i] ? run + 1 : 1;
    best = Math.max(best, run);
  }
  // 今の連続: 今日か昨日で終わっていれば続いている。
  const has = new Set(set);
  let cur = 0;
  let d = has.has(today) ? today : next(set[set.length - 1]) === today ? set[set.length - 1] : "";
  while (d && has.has(d)) {
    cur++;
    const x = new Date(`${d}T12:00:00Z`);
    x.setUTCDate(x.getUTCDate() - 1);
    d = x.toISOString().slice(0, 10);
  }
  return { current: cur, best };
}

/**
 * **全体の中での位置**（オーナー指示 2026-09-28「ほかのユーザーとの比較」）。
 * `v` より小さい人の割合（0〜100、同じ値は半分と数える）。比べる相手がいなければ null。
 */
export function percentileRank(all: number[], v: number): number | null {
  const xs = all.filter((n) => Number.isFinite(n));
  if (!xs.length) return null;
  const below = xs.filter((n) => n < v).length;
  const same = xs.filter((n) => n === v).length;
  return Math.round((100 * (below + same / 2)) / xs.length);
}

/** 日ごとの数（古い順、`days` 日ぶん。無い日は 0）。日付は "YYYY-MM-DD"。 */
export function dailyCounts(
  keys: string[],
  today: string,
  days: number,
): Array<{ day: string; n: number }> {
  const m = new Map<string, number>();
  for (const k of keys) m.set(k, (m.get(k) ?? 0) + 1);
  const out: Array<{ day: string; n: number }> = [];
  const base = new Date(`${today}T12:00:00Z`);
  for (let i = days - 1; i >= 0; i--) {
    const d = new Date(base);
    d.setUTCDate(d.getUTCDate() - i);
    const key = d.toISOString().slice(0, 10);
    out.push({ day: key, n: m.get(key) ?? 0 });
  }
  return out;
}

/**
 * **続けて使っている割合**（登録から N 日後に開いた人の割合）。
 * 登録から N 日経っていない人は数に入れない（まだ判断できないため）。
 */
export function retention(
  users: Array<{ signup: string; activeDays: string[] }>,
  n: number,
  today: string,
): { rate: number | null; eligible: number } {
  const add = (d: string, k: number) => {
    const x = new Date(`${d}T12:00:00Z`);
    x.setUTCDate(x.getUTCDate() + k);
    return x.toISOString().slice(0, 10);
  };
  const eligible = users.filter((u) => add(u.signup, n) <= today);
  if (!eligible.length) return { rate: null, eligible: 0 };
  const kept = eligible.filter((u) => {
    const target = add(u.signup, n);
    return u.activeDays.some((d) => d >= target);
  }).length;
  return { rate: Math.round((100 * kept) / eligible.length), eligible: eligible.length };
}

export function median(nums: Array<number | null | undefined>): number | null {
  const v = nums
    .filter((n): n is number => typeof n === "number" && Number.isFinite(n))
    .sort((a, b) => a - b);
  if (!v.length) return null;
  const m = Math.floor(v.length / 2);
  return v.length % 2 ? v[m] : Math.round((v[m - 1] + v[m]) / 2);
}

/** 画面の区分（離れる直前にいた画面の記録に使う）。 */
export const LEAVE_SCREENS = [
  "home",
  "dex",
  "capture",
  "scan",
  "review",
  "settings",
  "other",
] as const;
export type LeaveScreen = (typeof LEAVE_SCREENS)[number];

export function screenOf(pathname: string): LeaveScreen {
  const seg = pathname.replace(/^\/+/, "").split(/[/?#]/)[0];
  return (LEAVE_SCREENS as readonly string[]).includes(seg) ? (seg as LeaveScreen) : "other";
}

/** 1回あたりの滞在（分）。組の作り方は `sessionSpans`。 */
export function sessionMinutes(events: Array<{ kind: string; created_at: string }>): {
  sessions: number;
  medianMin: number | null;
  totalMin: number;
} {
  const lens = sessionSpans(events).map((s) => s.min);
  const total = lens.reduce((s, m) => s + m, 0);
  return {
    sessions: lens.length,
    medianMin: lens.length ? Math.round((median(lens.map((m) => m * 10)) ?? 0) / 10) : null,
    totalMin: Math.round(total),
  };
}

/**
 * **AI の費用の概算（米ドル）。** 呼び出し1回あたりの仮の単価 × 回数。
 * 単価は仮置き — 正確な額は各 AI の管理画面で確かめる（モデルと文の長さで変わる）。
 */
export const AI_UNIT_COST_USD: Record<string, number> = {
  scan_detect: 0.002,
  scan_parts: 0.002,
  suggest: 0.001,
  card: 0.004,
  phrase_card: 0.002,
  speaking_feedback: 0.002,
  correction: 0.003,
  journal_prompt: 0.001,
  wordbook: 0.004,
  quests: 0.001,
  tts: 0.0015,
  tts_pregen: 0.0015,
  removebg: 0.02,
};

export function aiCostEstimate(counts: Record<string, number>): {
  usd: number;
  byKind: Array<{ kind: string; count: number; usd: number }>;
} {
  const byKind = Object.entries(counts)
    .filter(([k]) => k in AI_UNIT_COST_USD)
    .map(([kind, count]) => ({ kind, count, usd: +(count * AI_UNIT_COST_USD[kind]).toFixed(4) }))
    .sort((a, b) => b.usd - a.usd);
  return { usd: +byKind.reduce((s, x) => s + x.usd, 0).toFixed(3), byKind };
}

/* ------------------------------------------------------------------------------------------
 * 2026-10-02 オーナー指示「利用者ごとの情報のチャートやグラフをもっと詳しく、細かく、
 * 見やすいようにアップデートして。見づらい。また名前なしのユーザーは消して、ユーザーの
 * 名前一覧は最も最近利用した人順に並べて。」
 *
 * グラフの数はサーバで作り、画面は描くだけにする（画面で生の記録を数えると、見本と本物で
 * 計算が分かれる）。どれも通信しないのでテストで確かめる。新しい表は足さない — いま読んで
 * いる記録（撮った札・復習の記録・札・利用の記録）だけから作る。
 * ------------------------------------------------------------------------------------------ */

/** "2026-09-27" → "9/27"（グラフの目盛り）。 */
export const md = (day: string) => `${Number(day.slice(5, 7))}/${Number(day.slice(8, 10))}`;
const WEEKDAY = ["日", "月", "火", "水", "木", "金", "土"];
/** "2026-09-27" → "9/27(日)"。触れた時の箱では曜日まで出す（週末に使う人かが分かる）。 */
export const mdw = (day: string) =>
  `${md(day)}(${WEEKDAY[new Date(`${day}T12:00:00Z`).getUTCDay()]})`;

/** 横軸に出す目盛り: 最後（いちばん新しい日 = 今日）から等間隔に `n` 個ほど。 */
export function evenTicks(xs: string[], n = 5): string[] {
  if (xs.length <= n) return xs;
  const step = Math.ceil((xs.length - 1) / (n - 1));
  const out: string[] = [];
  for (let i = xs.length - 1; i >= 0; i -= step) out.unshift(xs[i]);
  return out;
}

/**
 * 縦軸の目盛り: 0 から切りのよい間隔（1・2・5 × 10ⁿ、最小 1）で3〜4本。
 * recharts に任せると「0・15・41」のように最大値そのものが目盛りになり、読み取りにくかった。
 */
export function niceTicks(max: number, n = 3): number[] {
  if (!(max > 0)) return [0, 1];
  const raw = max / n;
  const mag = 10 ** Math.floor(Math.log10(raw));
  const step = Math.max(1, [1, 2, 5, 10].map((m) => m * mag).find((s) => s >= raw) ?? 10 * mag);
  const top = Math.ceil(max / step) * step;
  const out: number[] = [];
  for (let v = 0; v <= top + step / 2; v += step) out.push(Math.round(v * 1e6) / 1e6);
  return out;
}

/** "YYYY-MM-DD" に k 日足す（正午で計算するので日付の境でずれない）。 */
export function addDays(day: string, k: number): string {
  const x = new Date(`${day}T12:00:00Z`);
  x.setUTCDate(x.getUTCDate() + k);
  return x.toISOString().slice(0, 10);
}

/**
 * **名前のある人か**（一覧に出すか）。null・空・空白だけは「名前なし」。
 * 名前なしは登録の途中でやめた人や試しの口座がほとんどで、一覧を埋めて探しにくくしていた。
 * **口座も記録も消さない** — 一覧に出さないだけ（全体の数には入ったまま）。
 */
export function hasDisplayName(name: string | null | undefined): boolean {
  return typeof name === "string" && name.trim().length > 0;
}

/** いちばん新しい時刻（ISO 文字列）。どれも無ければ null。 */
export function latestIso(...isos: Array<string | null | undefined>): string | null {
  let best: string | null = null;
  let bestMs = -Infinity;
  for (const s of isos) {
    if (!s) continue;
    const t = Date.parse(s);
    if (Number.isFinite(t) && t > bestMs) {
      bestMs = t;
      best = s;
    }
  }
  return best;
}

/**
 * **一覧の並べ方**: 名前なしを外し、最後に使った時刻（`last_active`）の新しい順。
 * 使った記録の無い人は最後に（その中は登録の新しい順）。外した人数も返す
 * （画面に「名前のない N 人は出していません」と書く — 黙って減らすと数が合わなく見える）。
 */
export function adminUserList<
  T extends { display_name: string | null; last_active: string | null; created_at: string },
>(rows: T[]): { rows: T[]; hiddenNoName: number } {
  const named = rows.filter((r) => hasDisplayName(r.display_name));
  const ms = (s: string | null) => (s ? Date.parse(s) : NaN);
  const sorted = [...named].sort((a, b) => {
    const la = ms(a.last_active);
    const lb = ms(b.last_active);
    const ha = Number.isFinite(la);
    const hb = Number.isFinite(lb);
    if (ha !== hb) return ha ? -1 : 1;
    if (ha && hb && la !== lb) return lb - la;
    return (ms(b.created_at) || 0) - (ms(a.created_at) || 0);
  });
  return { rows: sorted, hiddenNoName: rows.length - named.length };
}

/**
 * 1回ずつの滞在（始まった時刻と分）。`session_start` と、その後の最初の `session_end` を
 * 組にし、3時間より長い組は数えない（閉じ忘れ・記録の取りこぼし）。
 */
export function sessionSpans(
  events: Array<{ kind: string; created_at: string }>,
): Array<{ start: string; min: number }> {
  const ev = [...events].sort((a, b) => a.created_at.localeCompare(b.created_at));
  const out: Array<{ start: string; min: number }> = [];
  let start: string | null = null;
  for (const e of ev) {
    if (e.kind === "session_start") start = e.created_at;
    else if (e.kind === "session_end" && start !== null) {
      const m = (Date.parse(e.created_at) - Date.parse(start)) / 60000;
      if (m >= 0 && m <= 180) out.push({ start, min: m });
      start = null;
    }
  }
  return out;
}

/**
 * 滞在の長さの区切り（分）。中央値1つでは「短い1回が多いのか、長く座る日があるのか」が
 * 分からないので、分布で出す。
 */
export const SESSION_BUCKETS: Array<{ label: string; max: number }> = [
  { label: "1分未満", max: 1 },
  { label: "1〜3分", max: 3 },
  { label: "3〜5分", max: 5 },
  { label: "5〜10分", max: 10 },
  { label: "10〜20分", max: 20 },
  { label: "20〜30分", max: 30 },
  { label: "30分以上", max: Infinity },
];

export function sessionLengthBuckets(mins: number[]): Array<{ label: string; n: number }> {
  const out = SESSION_BUCKETS.map((b) => ({ label: b.label, n: 0 }));
  for (const m of mins) {
    const i = SESSION_BUCKETS.findIndex((b) => m < b.max);
    out[i < 0 ? out.length - 1 : i].n++;
  }
  return out;
}

export type DailyActivity = {
  day: string;
  /** 撮った語。 */
  catches: number;
  /** 復習した回数と、そのうち正解。 */
  reviews: number;
  correct: number;
  /** アプリを開いた回数（`app_open`）。 */
  opens: number;
  /** その日に始まった滞在の合計（分、小数1桁）。 */
  minutes: number;
  /** AI の呼び出し回数と概算（米ドル、単価は `AI_UNIT_COST_USD`）。 */
  aiCalls: number;
  aiUsd: number;
};

/**
 * **日ごとの動き**（古い順、`days` 日ぶん。無い日も 0 で並べる — 抜けると棒の間隔が
 * 日付とずれて「休んだ日」が見えない）。日の区切りは `dayOf`（本番は台湾時間）。
 * 滞在は始まった日に数える。
 */
export function dailyActivity(input: {
  today: string;
  days: number;
  dayOf: (iso: string) => string;
  catches: string[];
  reviews: Array<{ at: string; correct: boolean | null }>;
  usage: Array<{ kind: string; created_at: string }>;
}): DailyActivity[] {
  const { today, days, dayOf } = input;
  const rows = new Map<string, DailyActivity>();
  for (let i = days - 1; i >= 0; i--) {
    const day = addDays(today, -i);
    rows.set(day, {
      day,
      catches: 0,
      reviews: 0,
      correct: 0,
      opens: 0,
      minutes: 0,
      aiCalls: 0,
      aiUsd: 0,
    });
  }
  for (const at of input.catches) {
    const r = rows.get(dayOf(at));
    if (r) r.catches++;
  }
  for (const v of input.reviews) {
    const r = rows.get(dayOf(v.at));
    if (!r) continue;
    r.reviews++;
    if (v.correct) r.correct++;
  }
  for (const e of input.usage) {
    const r = rows.get(dayOf(e.created_at));
    if (!r) continue;
    if (e.kind === "app_open") r.opens++;
    const unit = AI_UNIT_COST_USD[e.kind];
    if (unit !== undefined) {
      r.aiCalls++;
      r.aiUsd += unit;
    }
  }
  for (const s of sessionSpans(input.usage)) {
    const r = rows.get(dayOf(s.start));
    if (r) r.minutes += s.min;
  }
  return [...rows.values()].map((r) => ({
    ...r,
    minutes: Math.round(r.minutes * 10) / 10,
    aiUsd: +r.aiUsd.toFixed(4),
  }));
}

export type WeeklyReview = {
  /** 週の最初と最後の日（7日。最後の週は今日で終わる）。 */
  from: string;
  to: string;
  reviews: number;
  correct: number;
  /** 正答率。その週に1回も復習が無ければ null（0% ではない — 線を切る）。 */
  accuracy: number | null;
  /** 答えるまでの秒（中央値、小数1桁）。 */
  responseSec: number | null;
};

/** **週ごとの復習**（古い順、`weeks` 週ぶん）。日ごとだと1日数回の人は 0% と 100% を往復して読めない。 */
export function weeklyReviews(
  rows: Array<{ at: string; correct: boolean | null; response_ms: number | null }>,
  today: string,
  weeks: number,
  dayOf: (iso: string) => string,
): WeeklyReview[] {
  const out = Array.from({ length: weeks }, (_, i) => {
    const to = addDays(today, -7 * (weeks - 1 - i));
    return { from: addDays(to, -6), to, reviews: 0, correct: 0, ms: [] as number[] };
  });
  for (const r of rows) {
    const d = dayOf(r.at);
    const w = out.find((x) => d >= x.from && d <= x.to);
    if (!w) continue;
    w.reviews++;
    if (r.correct) w.correct++;
    if (typeof r.response_ms === "number" && r.response_ms > 0) w.ms.push(r.response_ms);
  }
  return out.map(({ ms, ...w }) => {
    const m = median(ms);
    return {
      ...w,
      accuracy: w.reviews ? Math.round((100 * w.correct) / w.reviews) : null,
      responseSec: m == null ? null : Math.round(m / 100) / 10,
    };
  });
}

/**
 * **復習の予定**: 期限を過ぎた札の数と、今日から `days` 日の各日に期限が来る札の数。
 * 期限の無い札と、`days` 日より先の札は数えない。
 */
export function dueSchedule(
  dues: Array<string | null>,
  today: string,
  days: number,
  dayOf: (iso: string) => string,
): { overdue: number; byDay: Array<{ day: string; n: number }> } {
  const byDay = Array.from({ length: days }, (_, i) => ({ day: addDays(today, i), n: 0 }));
  let overdue = 0;
  for (const iso of dues) {
    if (!iso) continue;
    const d = dayOf(iso);
    if (d < today) overdue++;
    else {
      const slot = byDay.find((x) => x.day === d);
      if (slot) slot.n++;
    }
  }
  return { overdue, byDay };
}

/** 曜日ごとの数（月〜日の順。日付は "YYYY-MM-DD"）。 */
export function weekdayCounts(days: string[]): number[] {
  const out = [0, 0, 0, 0, 0, 0, 0];
  for (const d of days) {
    const w = new Date(`${d}T12:00:00Z`).getUTCDay(); // 0 = 日曜
    out[(w + 6) % 7]++;
  }
  return out;
}

/**
 * **記憶の段の内訳**（札の数、段0〜5）。アプリの画面と同じ1本の数
 * （`retentionNow` → `memoryOf`）で決める — 管理画面だけ別の物差しにすると、本人の
 * 画面と食い違う（ARCHITECTURE.md「Displayed number」）。記憶の起点は最後に復習した時刻だけ。
 * 一度も復習していない札は 0%（撮っただけではまだ覚えていない — オーナー指示 2026-10-02）。
 * `created_at` は以前の起点の名残で、いまは読まない（本人の画面も撮った日を起点にしない）。
 */
export function memoryLevelCounts(
  cards: Array<{
    interval_days: number | null;
    ease: number | null;
    last_reviewed_at: string | null;
    created_at: string | null;
  }>,
  nowMs: number,
): number[] {
  const out = [0, 0, 0, 0, 0, 0];
  for (const c of cards) {
    const lastMs = c.last_reviewed_at ? Date.parse(c.last_reviewed_at) : null;
    const r = retentionNow(
      c.interval_days ?? 0,
      c.ease ?? 2.5,
      Number.isFinite(lastMs) ? lastMs : null,
      nowMs,
    );
    out[memoryOf({ retention: r, interval_days: c.interval_days ?? 0 }).level.level]++;
  }
  return out;
}
