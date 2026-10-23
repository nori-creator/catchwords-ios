/**
 * 期限が来た札の並べ方（ROADMAP Phase 7-3「Prioritize the highest-value/most-at-risk items」）。
 */
import { describe, expect, it } from "vitest";
import { forgettingCurve } from "./srs";
import {
  predictedRecall,
  rankDueReviews,
  reviewPriority,
  reviewValue,
  type ReviewPriorityInput,
} from "./review-priority";

const DAY = 86_400_000;
const NOW = Date.parse("2026-10-03T00:00:00Z");
const ago = (days: number) => new Date(NOW - days * DAY).toISOString();

const row = (over: Partial<ReviewPriorityInput> & { id: string }): ReviewPriorityInput => ({
  interval_days: 10,
  last_reviewed_at: ago(10),
  due_at: ago(0),
  caught_at: ago(200),
  ...over,
});

describe("いま思い出せる確率", () => {
  it("srs.ts の forgettingCurve と同じ数（画面の % と食い違わない）", () => {
    const r = row({ id: "a", interval_days: 7, last_reviewed_at: ago(12) });
    expect(predictedRecall(r, NOW)).toBeCloseTo(forgettingCurve(12, 7), 10);
  });

  it("未復習は 0（まだ覚えていない = いちばん危うい）", () => {
    expect(predictedRecall(row({ id: "a", interval_days: 0, last_reviewed_at: null }), NOW)).toBe(
      0,
    );
  });
});

describe("並べ方", () => {
  it("期限の古さではなく、忘れかけの度合いで並べる", () => {
    // 安定度 180 日の語が 20 日遅れ vs 安定度 2 日の語が 1 日遅れ。
    const sturdy = row({
      id: "sturdy",
      interval_days: 180,
      last_reviewed_at: ago(200),
      due_at: ago(20),
    });
    const fragile = row({
      id: "fragile",
      interval_days: 2,
      last_reviewed_at: ago(3),
      due_at: ago(1),
    });
    expect(rankDueReviews([sturdy, fragile], NOW).map((r) => r.id)).toEqual(["fragile", "sturdy"]);
  });

  it("同じ危うさなら、最近撮った語・何度も出会った語・お気に入りを先に", () => {
    const base = { interval_days: 5, last_reviewed_at: ago(8) };
    const old = row({ id: "old", ...base, caught_at: ago(300) });
    const recent = row({ id: "recent", ...base, caught_at: ago(2) });
    const met = row({ id: "met", ...base, caught_at: ago(300), encounters: 5 });
    const fav = row({ id: "fav", ...base, caught_at: ago(300), favourite: true });
    const ranked = rankDueReviews([old, met, recent, fav], NOW).map((r) => r.id);
    expect(ranked[ranked.length - 1]).toBe("old");
    expect(reviewValue(recent, NOW)).toBeGreaterThan(reviewValue(old, NOW));
    expect(reviewValue(met, NOW)).toBeGreaterThan(reviewValue(old, NOW));
    expect(reviewValue(fav, NOW)).toBeGreaterThan(reviewValue(old, NOW));
  });

  it("覚えている語は、大事でも忘れかけの語より後ろ", () => {
    const remembered = row({
      id: "remembered",
      interval_days: 60,
      last_reviewed_at: ago(1),
      caught_at: ago(1),
      favourite: true,
      encounters: 9,
    });
    const slipping = row({
      id: "slipping",
      interval_days: 1,
      last_reviewed_at: ago(6),
      caught_at: ago(300),
    });
    expect(reviewPriority(slipping, NOW)).toBeGreaterThan(reviewPriority(remembered, NOW));
  });

  it("同点は期限の古い順、それでも同じなら id 順。元の配列は触らない", () => {
    const a = row({ id: "b", due_at: ago(1) });
    const b = row({ id: "a", due_at: ago(3) });
    const c = row({ id: "c", due_at: ago(3) });
    const input = [a, c, b];
    expect(rankDueReviews(input, NOW).map((r) => r.id)).toEqual(["a", "c", "b"]);
    expect(input.map((r) => r.id)).toEqual(["b", "c", "a"]);
  });

  it("行の他の項目はそのまま持ち回る", () => {
    const withExtra = { ...row({ id: "x" }), stickers: { caption: "keep" } };
    expect(rankDueReviews([withExtra], NOW)[0].stickers.caption).toBe("keep");
  });
});
