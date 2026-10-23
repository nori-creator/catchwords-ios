import { forgettingCurve, stabilityOf } from "./srs";

/**
 * **期限が来た札のうち、どれから出すか**（ROADMAP Phase 7-3「Prioritize the
 * highest-value/most-at-risk items internally」）。
 *
 * 前は `due_at` の古い順だけだった。期限の古さは「どれだけ忘れているか」の代わりに
 * ならない — 安定度 180 日の語が 3 日遅れても思い出せる確率はほとんど落ちないが、
 * 安定度 1 日の語が 3 日遅れると半分近くまで落ちる。1日の枚数に上限がある（既定 20 枚・
 * 1回 10 枚）ので、**いま落としそうな語・その人にとって大事な語**を先に出す。
 *
 * ## 点数 = 危うさ × 大事さ
 * - **危うさ** = 1 − いま思い出せる確率（`srs.ts` の `forgettingCurve`。画面の % と
 *   同じ式）。まだ一度も復習していない札は 1（まだ覚えていない）。
 * - **大事さ** = 1 + 次の足し算（どれも 0〜1 に収め、重みで束ねる）
 *   - 撮ってからの新しさ（`RECENCY_HALF_LIFE_DAYS` で半分）— 撮った場面の記憶が
 *     新しいうちに固めると、写真が手掛かりとして効く。
 *   - 何度も出会った語（再会の回数）— 実際の生活でよく出る語。
 *   - お気に入り（列が在れば）。
 *   - つまずいた回数 — 覚えにくい語は先に、ただし上限付き（つまずきの山で埋めない）。
 *
 * 危うさを掛け算にしてあるので、**思い出せる語は大事でも後ろ**へ行く
 * （大事さだけで前に出ると、覚えている語に1日の枠を使ってしまう）。
 *
 * 同じ点数なら期限の古い順、それでも同じなら id 順（並びが毎回変わらないように）。
 * ここには外の世界に触れるものを入れない。
 */

export type ReviewPriorityInput = {
  id: string;
  /** 安定度（日）。`reviews.interval_days` そのもの。0 = 未復習。 */
  interval_days: number;
  /** 最後に復習した時刻（ISO）。null = 未復習。 */
  last_reviewed_at: string | null;
  /** 期限（ISO）。同点の並びに使う。 */
  due_at?: string | null;
  /** 撮った時刻（ISO。`stickers.taken_at`）。 */
  caught_at?: string | null;
  /** 出会った回数（最初の1枚 + 再会）。無ければ 1。 */
  encounters?: number | null;
  /** お気に入り（列ができたら渡す）。 */
  favourite?: boolean | null;
  /** 通算でつまずいた回数（`review_history` の score < LAPSE_SCORE）。 */
  lapses?: number | null;
};

export const RECENCY_HALF_LIFE_DAYS = 30;
export const PRIORITY_WEIGHTS = {
  recency: 0.5,
  encounters: 0.3,
  favourite: 0.5,
  lapses: 0.2,
} as const;

const DAY_MS = 86_400_000;
const clamp01 = (x: number) => (x < 0 ? 0 : x > 1 ? 1 : x);
const ms = (iso: string | null | undefined) => {
  const v = iso ? Date.parse(iso) : NaN;
  return Number.isFinite(v) ? v : null;
};

/** いま思い出せる確率（0〜1）。未復習は 0。 */
export function predictedRecall(row: ReviewPriorityInput, nowMs: number): number {
  const s = stabilityOf(row.interval_days);
  const last = ms(row.last_reviewed_at);
  if (s <= 0 || last == null) return 0;
  return forgettingCurve((nowMs - last) / DAY_MS, s);
}

/** 大事さ（1 以上）。 */
export function reviewValue(row: ReviewPriorityInput, nowMs: number): number {
  const caught = ms(row.caught_at);
  const ageDays =
    caught == null ? Number.POSITIVE_INFINITY : Math.max(0, (nowMs - caught) / DAY_MS);
  const recency = Number.isFinite(ageDays) ? Math.pow(0.5, ageDays / RECENCY_HALF_LIFE_DAYS) : 0;
  // 1回目は普通。2回目から伸び、5回で頭打ち。
  const enc = clamp01((Math.max(1, row.encounters ?? 1) - 1) / 4);
  const fav = row.favourite ? 1 : 0;
  const lapses = clamp01((row.lapses ?? 0) / 3);
  return (
    1 +
    PRIORITY_WEIGHTS.recency * recency +
    PRIORITY_WEIGHTS.encounters * enc +
    PRIORITY_WEIGHTS.favourite * fav +
    PRIORITY_WEIGHTS.lapses * lapses
  );
}

/** 点数（大きいほど先）。 */
export function reviewPriority(row: ReviewPriorityInput, nowMs: number): number {
  const risk = 1 - predictedRecall(row, nowMs);
  return risk * reviewValue(row, nowMs);
}

/**
 * 点数の高い順に並べ直した**新しい配列**を返す（元の配列は触らない）。
 * 行の他の項目はそのまま持ち回る（`getDueReviews` の行をそのまま渡せる）。
 */
export function rankDueReviews<T extends ReviewPriorityInput>(
  rows: readonly T[],
  nowMs: number,
): T[] {
  const scored = rows.map((row) => ({
    row,
    score: reviewPriority(row, nowMs),
    due: ms(row.due_at) ?? Number.POSITIVE_INFINITY,
  }));
  scored.sort(
    (a, b) =>
      b.score - a.score ||
      a.due - b.due ||
      (a.row.id < b.row.id ? -1 : a.row.id > b.row.id ? 1 : 0),
  );
  return scored.map((s) => s.row);
}
