/**
 * **開発者の「分析」のその人の頁で、新しく出す数**（オーナー 2026-11-13「ユーザーのすごい細かいデータをグラフや
 * そのアプリ改善に使えるデータを一から…今のプライバシーポリシーに反さないように設計して」）。
 *
 * ここは数えるだけの純粋な関数（DB にも鍵にも触らない。試験 `admin-user-insights.test.ts`）。読み出しは
 * `admin-users.functions.ts` の `buildDetail`。
 *
 * ## プライバシーポリシー（第1条・第2条）の線
 * - 場所は**市と区まで**（`placeArea`）。緯度・経度・番地・学習者が書いた場所の名前（`location_custom`）は
 *   読まない・返さない。地図の円の位置は、iPhone がこの名前から引く（サーバは座標を返さない）。
 * - 語・写真・本人の書いた文は返さない。図鑑の分類ごとの**数**だけ。
 * - 使い方は**数**だけ（画面・機能・チュートリアルの段の回数、アプリの版・機種・iOS の版・表示言語）。
 */
import { placeArea } from "./analytics";

const HOUR_MS = 3_600_000;
const TAIPEI_MS = 8 * HOUR_MS; // 台湾は夏時間が無い

/** 台湾時間の曜日（月 = 0 … 日 = 6）と時（0〜23）。 */
export function taipeiSlot(iso: string): { weekday: number; hour: number } | null {
  const t = Date.parse(iso);
  if (!Number.isFinite(t)) return null;
  const d = new Date(t + TAIPEI_MS);
  return { weekday: (d.getUTCDay() + 6) % 7, hour: d.getUTCHours() };
}

/** 使う時間帯: 7 行（月〜日）× 24 列（0〜23 時、台湾時間）の回数。 */
export function heatGrid(times: Iterable<string>): number[][] {
  const grid = Array.from({ length: 7 }, () => Array.from({ length: 24 }, () => 0));
  for (const iso of times) {
    const s = taipeiSlot(iso);
    if (s) grid[s.weekday][s.hour] += 1;
  }
  return grid;
}

export type AreaCount = { name: string; n: number; morning: number; day: number; night: number };

/**
 * 撮った場所を市と区ごとに数える（多い順、最大 `max`）。朝 = 5〜10 時台、昼 = 11〜16 時台、夜 = それ以外
 * （台湾時間）。学習者が書いた・選んだ名前（`location_custom`）と、市と区に直せない名前は数えない。
 */
export function areaCounts(
  rows: Iterable<{ created_at: string; location_name: string | null; location_custom?: boolean | null }>,
  max = 10,
): AreaCount[] {
  const by = new Map<string, AreaCount>();
  for (const r of rows) {
    if (r.location_custom) continue;
    const name = placeArea(r.location_name);
    if (!name) continue;
    const a = by.get(name) ?? { name, n: 0, morning: 0, day: 0, night: 0 };
    a.n += 1;
    const h = taipeiSlot(r.created_at)?.hour ?? 0;
    if (h >= 5 && h < 11) a.morning += 1;
    else if (h >= 11 && h < 17) a.day += 1;
    else a.night += 1;
    by.set(name, a);
  }
  return [...by.values()].sort((a, b) => b.n - a.n || a.name.localeCompare(b.name)).slice(0, max);
}

/** 図鑑の分類（`words.category_key`）ごとの数。多い順。分類の無い語は "other"。 */
export function categoryCounts(keys: Iterable<string | null | undefined>): Array<{ key: string; n: number }> {
  const by = new Map<string, number>();
  for (const k of keys) {
    const key = k && k.trim() ? k.trim() : "other";
    by.set(key, (by.get(key) ?? 0) + 1);
  }
  return [...by].map(([key, n]) => ({ key, n })).sort((a, b) => b.n - a.n || a.key.localeCompare(b.key));
}

export type AppEventRow = { kind: string; created_at: string; meta?: unknown };

const obj = (v: unknown): Record<string, unknown> =>
  v && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, unknown>) : {};
const str = (v: unknown): string | null => (typeof v === "string" && v ? v : null);

/** チュートリアルの段（`TourStep` の名前を英小文字と _ にした物）を、学習者の見る 5 つのまとまりへ。 */
export const TOUR_PARTS: Array<{ part: string; steps: string[] }> = [
  { part: "camera", steps: ["tap_camera", "shoot", "pick", "detail", "peel"] },
  { part: "home", steps: ["home_added"] },
  { part: "dex", steps: ["dex_tab", "dex_cover", "dex_map", "dex_grid", "dex_shadow", "dex_open"] },
  { part: "review", steps: ["review_pick", "review_next", "memory_curve"] },
  { part: "word", steps: ["word_section", "word_settings"] },
  { part: "complete", steps: ["complete"] },
];

export type AppUsage = {
  /** 一番新しいアプリの記録に添えてあった版・機種・iOS の版・表示言語（1.0.7 から）。 */
  device: { appVersion: string | null; device: string | null; os: string | null; lang: string | null; at: string } | null;
  tutorial: {
    /** 通ったまとまり（camera / home / dex / review / word / complete）。 */
    parts: string[];
    /** 最後に記録された段と、その時刻。 */
    lastStep: string | null;
    lastAt: string | null;
    /** 「終了」で終えた回数。 */
    ended: number;
  };
  /** 直近30日に開いた画面の回数（home / dex / word / camera / review / settings …）。 */
  screens30: Array<{ key: string; n: number }>;
  /** 直近30日に使った機能の回数（`APP_FEATURES`）。 */
  features30: Array<{ key: string; n: number }>;
  /** アプリを離れる直前に開いていた画面（離れた回ごと、多い順）。 */
  lastScreens: Array<{ key: string; n: number }>;
};

const ranked = (m: Map<string, number>) =>
  [...m].map(([key, n]) => ({ key, n })).sort((a, b) => b.n - a.n || a.key.localeCompare(b.key));

/**
 * アプリから届いた記録（`usage_events`）の数え上げ。`now` から30日を「直近」とする。
 * 離れる直前の画面 = `session_end` の前に最後に届いた `screen_view`（同じ開いている間の物）。
 * 古いアプリの `leave_*` も同じ表に足す。
 */
export function appUsage(events: AppEventRow[], now: Date): AppUsage {
  const since = now.getTime() - 30 * 86_400_000;
  const sorted = [...events].sort((a, b) => a.created_at.localeCompare(b.created_at));
  let device: AppUsage["device"] = null;
  const parts = new Set<string>();
  let lastStep: string | null = null;
  let lastAt: string | null = null;
  let ended = 0;
  const screens = new Map<string, number>();
  const features = new Map<string, number>();
  const leaves = new Map<string, number>();
  let current: string | null = null;
  const bump = (m: Map<string, number>, k: string) => m.set(k, (m.get(k) ?? 0) + 1);
  for (const e of sorted) {
    const m = obj(e.meta);
    const recent = Date.parse(e.created_at) >= since;
    if (str(m.app_version) || str(m.device) || str(m.os) || str(m.lang))
      device = {
        appVersion: str(m.app_version),
        device: str(m.device),
        os: str(m.os),
        lang: str(m.lang),
        at: e.created_at,
      };
    switch (e.kind) {
      case "session_start":
      case "app_open":
        if (e.kind === "session_start") current = null;
        break;
      case "screen_view": {
        const s = str(m.screen);
        if (s) {
          current = s;
          if (recent) bump(screens, s);
        }
        break;
      }
      case "session_end":
        if (current) bump(leaves, current);
        current = null;
        break;
      case "feature_use": {
        const f = str(m.feature);
        if (f && recent) bump(features, f);
        break;
      }
      case "tutorial_step": {
        const step = str(m.step);
        if (step) {
          const part = TOUR_PARTS.find((p) => p.steps.includes(step))?.part;
          if (part) parts.add(part);
          lastStep = step;
          lastAt = e.created_at;
        }
        break;
      }
      case "tutorial_skip":
        ended += 1;
        break;
      default:
        if (e.kind.startsWith("leave_")) bump(leaves, e.kind.slice(6));
    }
  }
  return {
    device,
    tutorial: {
      parts: TOUR_PARTS.map((p) => p.part).filter((p) => parts.has(p)),
      lastStep,
      lastAt,
      ended,
    },
    screens30: ranked(screens),
    features30: ranked(features),
    lastScreens: ranked(leaves),
  };
}
