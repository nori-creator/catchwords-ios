import { describe, expect, it } from "vitest";
import {
  brierScore,
  calibrationReport,
  expectedCalibrationError,
  logLoss,
  reliabilityBins,
  shadowCalibration,
  type ShadowRow,
} from "./calibration";

describe("Brier スコア・対数損失", () => {
  it("言い切って当たれば 0、言い切って外れれば最大", () => {
    expect(brierScore([{ p: 1, y: true }])).toBe(0);
    expect(brierScore([{ p: 0, y: true }])).toBe(1);
    expect(
      brierScore([
        { p: 0.5, y: true },
        { p: 0.5, y: false },
      ]),
    ).toBe(0.25);
    expect(brierScore([])).toBeNull();
  });

  it("対数損失は 0 と 1 を丸めて無限大にしない", () => {
    expect(logLoss([{ p: 0.5, y: true }])).toBeCloseTo(Math.log(2), 4);
    const worst = logLoss([{ p: 0, y: true }]);
    expect(worst).not.toBeNull();
    expect(Number.isFinite(worst as number)).toBe(true);
    expect(worst as number).toBeGreaterThan(9);
    expect(logLoss([])).toBeNull();
  });

  it("0〜1 の外の見込み・壊れた値は数えない", () => {
    expect(
      brierScore([
        { p: NaN, y: true },
        { p: 1.5, y: false },
        { p: 1, y: true },
      ]),
    ).toBe(0);
  });
});

describe("信頼度の表", () => {
  it("10% 刻みの箱に分け、1.0 ちょうどは最後の箱", () => {
    const bins = reliabilityBins([
      { p: 0.05, y: false },
      { p: 0.95, y: true },
      { p: 1, y: true },
      { p: 0.92, y: false },
    ]);
    expect(bins).toHaveLength(10);
    expect(bins[0]).toMatchObject({ lo: 0, hi: 0.1, n: 1, observed: 0, meanPredicted: 0.05 });
    expect(bins[9].n).toBe(3);
    expect(bins[9].observed).toBeCloseTo(2 / 3, 3);
    expect(bins[5]).toMatchObject({ n: 0, observed: null, meanPredicted: null });
  });

  it("較正の良い見込みは ECE が小さく、言い過ぎは大きい", () => {
    // 80% と言って 8/10 当たる → ずれ 0。
    const good = Array.from({ length: 10 }, (_, i) => ({ p: 0.8, y: i < 8 }));
    expect(calibrationReport(good).ece).toBe(0);
    // 95% と言って半分しか当たらない → ずれ 0.45。
    const over = Array.from({ length: 10 }, (_, i) => ({ p: 0.95, y: i < 5 }));
    expect(calibrationReport(over).ece).toBeCloseTo(0.45, 4);
    expect(expectedCalibrationError(reliabilityBins([]))).toBeNull();
  });
});

describe("影の記録から復習の式と Jev を比べる", () => {
  const row = (over: Partial<ShadowRow>): ShadowRow => ({
    task: "recall",
    model: "jev-latest",
    predicted: 0.9,
    baseline: 0.5,
    outcome: true,
    day: "2026-10-01",
    ...over,
  });

  it("両方の見込みと結果が揃った recall の行だけを、同じ問いの組で比べる", () => {
    const c = shadowCalibration([
      row({}),
      row({ outcome: false, predicted: 0.2, baseline: 0.5 }),
      row({ outcome: null }), // 結果がまだ
      row({ baseline: null }), // 式の見込みが無い
      row({ task: "interval" }), // 間隔は確率ではない
      row({ model: "jev-v2", predicted: 0.8, baseline: 0.6 }),
    ]);
    expect(c.n).toBe(3);
    expect(c.models).toEqual(["jev-latest", "jev-v2"]);
    // Jev: (0.1² + 0.2² + 0.2²) / 3 = 0.03、式: (0.5² + 0.5² + 0.4²) / 3 = 0.22
    expect(c.jev.brier).toBeCloseTo(0.03, 4);
    expect(c.scheduler.brier).toBeCloseTo(0.22, 4);
    expect(c.scheduler.baseRate).toBeCloseTo(2 / 3, 3);
  });

  it("行が無ければ空の報告（画面は「まだデータがありません」）", () => {
    const c = shadowCalibration([]);
    expect(c.n).toBe(0);
    expect(c.jev.brier).toBeNull();
    expect(c.scheduler.bins.every((b) => b.n === 0)).toBe(true);
  });
});
