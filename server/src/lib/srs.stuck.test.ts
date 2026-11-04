import { describe, expect, it } from "vitest";
import { nextSrs } from "./srs";

// 点検 S17（2026-11-03）: 3回間違えた語は、正解し続けても間隔が 1 日のままだった。
describe("苦手な語も、正解すれば間隔が伸びる", () => {
  const after3Misses = () => {
    let st = { ease: 2.5, interval_days: 0, repetitions: 0 };
    for (let i = 0; i < 3; i++) st = nextSrs(st, 1, { elapsedDays: 1 });
    return st;
  };
  for (const score of [5, 4]) {
    it(`採点 ${score} を予定どおりに続けると毎回伸びる`, () => {
      let st = after3Misses();
      expect(st.interval_days).toBe(1);
      for (let i = 0; i < 10; i++) {
        const before = st.interval_days;
        st = nextSrs(st, score, { elapsedDays: before });
        expect(st.interval_days).toBeGreaterThan(before);
      }
      expect(st.interval_days).toBeGreaterThanOrEqual(10);
    });
  }
  it("同じ日の二度目の正解では伸ばさない", () => {
    const st = nextSrs({ ease: 1.3, interval_days: 10, repetitions: 3 }, 5, { elapsedDays: 0 });
    expect(st.interval_days).toBe(10);
  });
  it("間違えたら縮む", () => {
    const st = nextSrs({ ease: 2.5, interval_days: 20, repetitions: 4 }, 1, { elapsedDays: 20 });
    expect(st.interval_days).toBeLessThan(20);
  });
});
