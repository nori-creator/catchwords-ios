/**
 * **ベータの計測で数える段の名前**（ロードマップ Phase 9.4 / Phase 11 の証拠集め、
 * 2026-10-03）。サーバの受け口（`metrics.functions.ts` の許可リスト・
 * `tutorial-funnel.server.ts`）と、集計（`beta-metrics.ts`）と、画面が同じ名前を読む。
 *
 * どこからも依存しない小さなファイルにしてある（利用者の画面の最初の塊に入るため）。
 */

/**
 * **登録した人の流れ**（`usage_events` に1行ずつ。本人の行なので user_id 付き）。
 * 撮る: camera_open → shutter → candidates_shown（待ち時間つき）→ candidate_picked →
 * meaning_shown（待ち時間つき）→ first_audio_played（待ち時間つき）→ catch_started →
 * catch_saved（待ち時間つき）。復習: review_started → review_answered → review_session_done。
 * 課金: paywall_viewed → checkout_started。中身（写真・語・答え）は送らない — 種類と時刻だけ。
 */
export const MEMBER_FUNNEL_EVENTS = [
  "camera_open",
  "shutter",
  "candidates_shown",
  "candidate_picked",
  "meaning_shown",
  "first_audio_played",
  "catch_started",
  "catch_saved",
  "review_started",
  "review_answered",
  "review_session_done",
  "paywall_viewed",
  "checkout_started",
] as const;
export type MemberFunnelEvent = (typeof MEMBER_FUNNEL_EVENTS)[number];

/**
 * 待ち時間（ms）を一緒に受け取る段。`ai_runs`（loop = `funnel_latency`）に残す
 * （QA.md › Performance checks の4つ、p50/p90/p99 で見る。2026-10-03）。
 * - `candidates_shown`: シャッター → 候補が並んだ。
 * - `meaning_shown`: 候補を押した → 意味の載ったカードが出た。
 * - `first_audio_played`: 発音を頼んだ（押した・自動で鳴らした）→ 音が鳴り始めた。
 * - `catch_saved`: 「図鑑に追加」を押した（`catch_started`）→ 保存が通った。
 */
export const LATENCY_EVENTS = [
  "candidates_shown",
  "meaning_shown",
  "first_audio_played",
  "catch_saved",
] as const satisfies readonly MemberFunnelEvent[];
export type LatencyEvent = (typeof LATENCY_EVENTS)[number];

export function isLatencyEvent(v: unknown): v is LatencyEvent {
  return typeof v === "string" && (LATENCY_EVENTS as readonly string[]).includes(v);
}

/**
 * **候補のどれを選んだか**（ロードマップ Phase 3.2 の Top-1/Top-3、2026-10-03）。
 * `candidate_picked` と一緒に `ai_runs`（loop = `candidate_pick`）へ1行。中身は
 * 順位・候補の数・どの道で選んだかだけ（語は送らない）。
 * - `photo`: 写真の候補の一覧から押した（`rank` = AI の並びで何番目か、1 から）。
 * - `native_search`: 写真の候補に無く、母語で打って調べ直した（写真の候補は外れ）。
 * - `typed`: 写真を撮らずに打った語（精度には数えない）。
 * - `scan`: スキャンの画面から渡された候補（別の AI なので精度には数えない）。
 */
export const CANDIDATE_PICK_LOOP = "candidate_pick";
export const CANDIDATE_PICK_VIA = ["photo", "native_search", "typed", "scan"] as const;
export type CandidatePickVia = (typeof CANDIDATE_PICK_VIA)[number];
/** 送ってよい候補の数の上限（AI は 3〜5 語、束を開いた2段目を入れても十分）。 */
export const MAX_CANDIDATE_RANK = 50;
export const FUNNEL_LATENCY_LOOP = "funnel_latency";
/** 待ち時間として受け取る上限（10分）。それより長いのは測り間違い。 */
export const MAX_FUNNEL_LATENCY_MS = 600_000;

/**
 * **登録前のチュートリアルの段**（人を特定しない、日ごとの数だけ）。
 * welcome_view（最初の画面）→ questions_done（質問に答えた）→ tutorial_start（本物の画面の
 * 案内が始まった）→ photo_taken → candidates_shown → catch_done（図鑑に入った）→
 * practice_done（2問の練習を終えた）→ signup_view（登録の画面）→ signup_done（登録して
 * 撮った1枚が口座に移った）。
 */
export const TUTORIAL_STEPS = [
  "welcome_view",
  "questions_done",
  "tutorial_start",
  "photo_taken",
  "candidates_shown",
  "catch_done",
  "practice_done",
  "signup_view",
  "signup_done",
] as const;
export type TutorialStep = (typeof TUTORIAL_STEPS)[number];

export function isTutorialStep(v: unknown): v is TutorialStep {
  return typeof v === "string" && (TUTORIAL_STEPS as readonly string[]).includes(v);
}

/**
 * `app_config` の鍵: `funnel:<台湾の日付>:<段>:<セッションの印>`。1行 = 1つのセッションが
 * その段に来た、1回。同じ鍵は一意の制約で入らないので、同じセッションの同じ段は1回だけ。
 * 印はブラウザのタブごとの乱数をサーバの鍵で混ぜた物（元の値に戻せない）。
 */
export const FUNNEL_ROOT = "funnel:";
/** 送りすぎを止める枠（IP の混ぜ値ごと・日ごと）。2日で消す。 */
export const FUNNEL_RATE_ROOT = "funnel-rate:";

export function funnelKey(day: string, step: TutorialStep, sid: string): string {
  return `${FUNNEL_ROOT}${day}:${step}:${sid}`;
}

export function parseFunnelKey(key: string): { day: string; step: TutorialStep } | null {
  const m = /^funnel:(\d{4}-\d{2}-\d{2}):([a-z_]+):[0-9a-f]+$/.exec(key);
  if (!m || !isTutorialStep(m[2])) return null;
  return { day: m[1], step: m[2] };
}

/** ブラウザが作るセッションの印の形（乱数の UUID など）。 */
export const FUNNEL_SESSION_ID = /^[A-Za-z0-9-]{16,64}$/;
