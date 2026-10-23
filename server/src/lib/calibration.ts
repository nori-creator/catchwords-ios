/**
 * **予測の較正**（ロードマップ Phase 6.6 / 6.7、ARCHITECTURE.md › Memory、2026-10-03）。
 *
 * `model_shadow_predictions` の `task = 'recall'` の行には、同じ1問について
 * - `baseline` … このアプリの式（`retentionNow`、復習の予定を決めている側）の見込み、
 * - `predicted` … Jev（影の実行）の見込み、
 * - `outcome` … 実際に思い出せたか（最初の答えの正誤）
 * が並ぶ。ここでは「見込みがどれだけ当たったか」を数える。通信しない純粋な関数だけ
 * （`/admin/beta` とその試験・確認用ページが同じ計算を通る）。
 *
 * - **Brier スコア** = (見込み − 結果)² の平均。0 が完璧、0.25 は「いつも 50%」と同じ。
 * - **対数損失**（log loss）= −平均 log(当たった側の見込み)。見込みは [ε, 1−ε] に丸める。
 * - **信頼度の表**（reliability table）: 見込みを 10% 刻みの箱に分け、箱ごとに
 *   「見込みの平均」と「実際に思い出せた割合」を並べる。較正が良いほど2つが近い。
 * - **ECE**（期待較正誤差）: 箱ごとの |見込みの平均 − 実際の割合| を件数で重み付けした平均。
 */

/** 予測1件。`p` は 0〜1、`y` は実際に思い出せたか。 */
export type CalibrationPoint = { p: number; y: boolean };

export type ReliabilityBin = {
  /** 箱の下端（含む）と上端（最後の箱だけ 1 を含む）。 */
  lo: number;
  hi: number;
  n: number;
  /** 箱の中の見込みの平均（0〜1）。空なら null。 */
  meanPredicted: number | null;
  /** 箱の中で実際に思い出せた割合（0〜1）。空なら null。 */
  observed: number | null;
};

export type CalibrationReport = {
  n: number;
  /** 実際に思い出せた割合。 */
  baseRate: number | null;
  brier: number | null;
  logLoss: number | null;
  ece: number | null;
  bins: ReliabilityBin[];
};

/** 対数損失で見込みを丸める幅（0 と 1 を言い切った外れで無限大にしない）。 */
export const LOG_LOSS_EPS = 1e-4;
/** 信頼度の表の箱の数（10% 刻み）。 */
export const CALIBRATION_BINS = 10;

const round = (n: number, d = 4) => +n.toFixed(d);

/** 0〜1 の有限な見込みだけを残す（壊れた行は数えない）。 */
export function cleanPoints(points: readonly CalibrationPoint[]): CalibrationPoint[] {
  return points.filter((x) => Number.isFinite(x.p) && x.p >= 0 && x.p <= 1);
}

export function brierScore(points: readonly CalibrationPoint[]): number | null {
  const v = cleanPoints(points);
  if (!v.length) return null;
  return round(v.reduce((s, x) => s + (x.p - (x.y ? 1 : 0)) ** 2, 0) / v.length);
}

export function logLoss(points: readonly CalibrationPoint[], eps = LOG_LOSS_EPS): number | null {
  const v = cleanPoints(points);
  if (!v.length) return null;
  const sum = v.reduce((s, x) => {
    const p = Math.min(1 - eps, Math.max(eps, x.p));
    return s - Math.log(x.y ? p : 1 - p);
  }, 0);
  return round(sum / v.length);
}

/** 見込みを等幅の箱に分ける。1.0 ちょうどは最後の箱に入れる。 */
export function reliabilityBins(
  points: readonly CalibrationPoint[],
  bins = CALIBRATION_BINS,
): ReliabilityBin[] {
  const v = cleanPoints(points);
  const acc = Array.from({ length: bins }, () => ({ n: 0, p: 0, y: 0 }));
  for (const x of v) {
    const i = Math.min(bins - 1, Math.floor(x.p * bins));
    acc[i].n++;
    acc[i].p += x.p;
    acc[i].y += x.y ? 1 : 0;
  }
  return acc.map((a, i) => ({
    lo: round(i / bins, 2),
    hi: round((i + 1) / bins, 2),
    n: a.n,
    meanPredicted: a.n ? round(a.p / a.n) : null,
    observed: a.n ? round(a.y / a.n) : null,
  }));
}

export function expectedCalibrationError(bins: readonly ReliabilityBin[]): number | null {
  const total = bins.reduce((s, b) => s + b.n, 0);
  if (!total) return null;
  const sum = bins.reduce(
    (s, b) =>
      b.n && b.meanPredicted != null && b.observed != null
        ? s + b.n * Math.abs(b.meanPredicted - b.observed)
        : s,
    0,
  );
  return round(sum / total);
}

export function calibrationReport(
  points: readonly CalibrationPoint[],
  bins = CALIBRATION_BINS,
): CalibrationReport {
  const v = cleanPoints(points);
  const table = reliabilityBins(v, bins);
  return {
    n: v.length,
    baseRate: v.length ? round(v.filter((x) => x.y).length / v.length) : null,
    brier: brierScore(v),
    logLoss: logLoss(v),
    ece: expectedCalibrationError(table),
    bins: table,
  };
}

/** `model_shadow_predictions` の1行（読む列だけ）。 */
export type ShadowRow = {
  task: string;
  model: string;
  predicted: number | null;
  baseline: number | null;
  outcome: boolean | null;
  /** 台湾の日付。 */
  day: string;
};

export type ShadowCalibration = {
  /** 結果の付いた recall の行の数。 */
  n: number;
  /** 復習の予定を決めている式（`baseline`）。 */
  scheduler: CalibrationReport;
  /** Jev の影の見込み（`predicted`）。モデル名ごとではなく全部まとめて。 */
  jev: CalibrationReport;
  /** 見たモデルの名前（新しい版が混ざっていないか確かめるため）。 */
  models: string[];
};

/**
 * 影の記録から、復習の式と Jev の較正を並べて出す。**同じ問いの組**だけで比べる
 * （両方の見込みと結果が揃った行）。片方しか無い行を混ぜると、問いの難しさの違いで
 * 差が出てしまう。
 */
export function shadowCalibration(rows: readonly ShadowRow[]): ShadowCalibration {
  const paired = rows.filter(
    (r) =>
      r.task === "recall" &&
      typeof r.outcome === "boolean" &&
      typeof r.predicted === "number" &&
      typeof r.baseline === "number",
  );
  return {
    n: paired.length,
    scheduler: calibrationReport(
      paired.map((r) => ({ p: r.baseline as number, y: r.outcome as boolean })),
    ),
    jev: calibrationReport(
      paired.map((r) => ({ p: r.predicted as number, y: r.outcome as boolean })),
    ),
    models: [...new Set(paired.map((r) => r.model))].sort(),
  };
}
