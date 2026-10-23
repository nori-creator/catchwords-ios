import { describe, it, expect } from "vitest";
import { compareByMemory, memoryLevel, memoryOf, type MemorySortable } from "./memory";

const w = (o: Partial<MemorySortable>): MemorySortable => ({
  retention: 100,
  interval_days: 1,
  ...o,
});

/**
 * **画面の数は1つ: いま思い出せる確率。**（オーナー指示 2026-09-23
 * 「ユーザーが混乱しないように、単語の数値は1つに統一したい」／PRODUCT.md）
 *
 * 段（色と名前）も同じ数から決める。**段が上がれば % も必ず上がる**
 * （オーナー報告 2026-09-16 の逆転を戻さない）。
 */
describe("画面の % と段", () => {
  it("段は % だけで決まり、境目は重ならない", () => {
    const table: Array<[number, number]> = [
      [0, 0],
      [29, 0],
      [30, 1],
      [49, 1],
      [50, 2],
      [69, 2],
      [70, 3],
      [84, 3],
      [85, 4],
      [94, 4],
      [95, 5],
      [100, 5],
    ];
    for (const [pct, level] of table) {
      expect([pct, memoryLevel(pct).level]).toEqual([pct, level]);
    }
  });

  it("% が上がれば段は下がらない（単調）", () => {
    let prev = -1;
    for (let s = 0; s <= 100; s++) {
      const lv = memoryLevel(s).level;
      expect(lv).toBeGreaterThanOrEqual(prev);
      prev = lv;
    }
  });

  it("% は定着度そのもの（忘却曲線の縦軸と同じ数）", () => {
    expect(memoryOf({ retention: 87.4, interval_days: 3 }).percent).toBe(87);
    expect(memoryOf({ retention: 100, interval_days: 0 }).percent).toBe(100);
    // 壊れた値でも 0〜100 に収める。
    expect(memoryOf({ retention: 130, interval_days: 3 }).percent).toBe(100);
    expect(memoryOf({ retention: Number.NaN, interval_days: 3 }).percent).toBe(0);
  });

  it("もつ長さは % に混ぜない（2つ目の % を作らない）", () => {
    const young = memoryOf({ retention: 97, interval_days: 3 });
    const mature = memoryOf({ retention: 97, interval_days: 90 });
    expect(mature.percent).toBe(young.percent);
  });
});

describe("記憶の並べ替え", () => {
  /**
   * オーナー報告 2026-09-15 の画面。**9語すべてが 100%** で、
   * 「覚えた」と「長期記憶」が交互に現れていた。
   */
  it("同じ 100% なら、もちが短い語が上（先に忘れる順）", () => {
    const words = [
      w({ headword: "紅茶", interval_days: 40 }),
      w({ headword: "海綿", interval_days: 5 }),
      w({ headword: "床", interval_days: 60 }),
      w({ headword: "手", interval_days: 3 }),
    ];
    const sorted = [...words].sort(compareByMemory);
    expect(sorted.map((x) => x.headword)).toEqual(["手", "海綿", "紅茶", "床"]);
    // **段も % も単調に増える**（オーナー指示 2026-09-16）。
    const levels = sorted.map((x) => memoryOf(x).level.level);
    const pcts = sorted.map((x) => memoryOf(x).percent);
    expect(levels).toEqual([...levels].sort((a, b) => a - b));
    expect(pcts).toEqual([...pcts].sort((a, b) => a - b));
  });

  /**
   * **並びの約束そのもの。** どんな組み合わせを混ぜても、並べたあとの
   * % と段が一度も下がらないこと。1つでも下がれば、オーナーが見た
   * 「長期記憶なのに % が低い」が戻ってくる。
   */
  it("どう混ぜても、並べたあとの % と段は下がらない", () => {
    const words: MemorySortable[] = [];
    for (const retention of [12, 45, 68, 83, 91, 100]) {
      for (const interval_days of [0, 1, 5, 21, 60, 200]) {
        words.push(w({ headword: `${retention}-${interval_days}`, retention, interval_days }));
      }
    }
    const sorted = [...words].sort(compareByMemory);
    expect(sorted).toHaveLength(words.length);
    let lastPct = -1;
    let lastLevel = -1;
    for (const x of sorted) {
      const { percent, level } = memoryOf(x);
      expect(percent).toBeGreaterThanOrEqual(lastPct);
      expect(level.level).toBeGreaterThanOrEqual(lastLevel);
      lastPct = percent;
      lastLevel = level.level;
    }
  });

  it("弱い語が先に来る", () => {
    const weak = w({ retention: 20, interval_days: 1 });
    const strong = w({ retention: 100, interval_days: 40 });
    expect(compareByMemory(weak, strong)).toBeLessThan(0);
    expect(compareByMemory(strong, weak)).toBeGreaterThan(0);
  });

  it("全部同じなら見出し語で決める（開くたびに順が変わらない）", () => {
    const a = w({ headword: "あ" });
    const b = w({ headword: "い" });
    expect(compareByMemory(a, b)).toBeLessThan(0);
    expect(compareByMemory(a, a)).toBe(0);
  });
});
