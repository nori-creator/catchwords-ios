import { describe, it, expect } from "vitest";
import {
  nextSrs,
  retentionNow,
  stabilityOf,
  forgettingCurve,
  daysUntilRetention,
  easeToDifficulty,
  difficultyToEase,
  ratingOf,
  modeFor,
  effectiveDueMs,
  effectiveDueIso,
  dueNowOrFilter,
  MIN_EASE,
  MAX_EASE,
  MAX_INTERVAL_DAYS,
  CHOICE_GAIN,
  TARGET_RETENTION,
  type SrsState,
} from "./srs";

/**
 * 復習の間隔の計算（FSRS。2026-10-02 に SM-2 から変えた）。
 *
 * ## なぜここから始めたか
 * このアプリで**間違えても誰も気づかない**計算がここ。画面が壊れれば
 * 見て分かるが、間隔の計算が狂っても「なんとなく復習が多い/来ない」に
 * しかならない。気づいたときには、その人の学習が何ヶ月ぶん歪んでいる。
 *
 * 式そのものは `ts-fsrs` のもの（写していない）。ここで守るのは**向き**:
 * 正解を重ねるほど安定度が伸びて曲線がなだらかになる、間違えると縮んで急になる、
 * 撮っただけの語は 0%、出題日は 90%。
 */

const DAY = 86_400_000;
const fresh: SrsState = { ease: 2.5, interval_days: 0, repetitions: 0 };

/** 予定どおり（経過 = 安定度）に答え続ける。 */
function chain(start: SrsState, score: number, n: number): SrsState[] {
  const out: SrsState[] = [];
  let s = start;
  for (let i = 0; i < n; i++) {
    s = nextSrs(s, score, { elapsedDays: s.interval_days });
    out.push(s);
  }
  return out;
}

describe("採点 → 評価", () => {
  it("3未満は Again、3・4 は Hard、5 は Good。Easy は使わない", () => {
    expect([0, 1, 2].map(ratingOf)).toEqual([1, 1, 1]);
    expect([3, 4].map(ratingOf)).toEqual([2, 2]);
    expect(ratingOf(5)).toBe(3);
  });
});

describe("ease ↔ 難しさ D（列を増やさずに D を持つ）", () => {
  it("ease 3.0 ↔ D 1、ease 1.3 ↔ D 10、往復で元に戻る", () => {
    expect(easeToDifficulty(MAX_EASE)).toBeCloseTo(1, 9);
    expect(easeToDifficulty(MIN_EASE)).toBeCloseTo(10, 9);
    for (const e of [1.3, 1.8, 2.5, 2.9, 3.0]) {
      expect(difficultyToEase(easeToDifficulty(e))).toBeCloseTo(e, 9);
    }
    for (const d of [1, 3.6, 5, 9, 10]) {
      expect(easeToDifficulty(difficultyToEase(d))).toBeCloseTo(d, 9);
    }
  });
  it("SM-2 時代の範囲外の ease（3.0 超）は端に寄せる", () => {
    expect(easeToDifficulty(3.4)).toBeCloseTo(1, 9);
    expect(easeToDifficulty(1.0)).toBeCloseTo(10, 9);
    expect(easeToDifficulty(Number.NaN)).toBeGreaterThan(1);
  });
  it("出てくる ease は必ず 1.3〜3.0", () => {
    let s = fresh;
    for (const score of [5, 3, 1, 4, 5, 5, 1, 3, 3, 3, 3, 5]) {
      s = nextSrs(s, score, { elapsedDays: s.interval_days });
      expect(s.ease).toBeGreaterThanOrEqual(MIN_EASE);
      expect(s.ease).toBeLessThanOrEqual(MAX_EASE);
    }
  });
});

describe("nextSrs — 向き（オーナー指示 2026-10-02）", () => {
  it("正解を重ねるほど安定度（= 次までの日数）が伸び、曲線がなだらかになる", () => {
    // 「復習を何回もして何回も正解することによって…より滑らかになって復習の頻度が落ちる」
    const states = chain(fresh, 5, 6);
    for (let i = 1; i < states.length; i++) {
      expect(states[i].interval_days).toBeGreaterThan(states[i - 1].interval_days);
      // 同じ経過日数での忘れ方がゆるくなる = 7日後の % が上がる。
      expect(forgettingCurve(7, states[i].interval_days)).toBeGreaterThan(
        forgettingCurve(7, states[i - 1].interval_days),
      );
    }
    expect(states.map((s) => s.repetitions)).toEqual([1, 2, 3, 4, 5, 6]);
  });

  it("間違えると安定度が縮み（前より小さく）、次の復習が早く来る。連続回数は 0", () => {
    // 「長期記憶でも復習で一度間違えたらその傾きがまた少し急になって復習する頻度が増える」
    const mature = { ease: 2.5, interval_days: 90, repetitions: 6 };
    const lapsed = nextSrs(mature, 1, { elapsedDays: 90 });
    expect(lapsed.repetitions).toBe(0);
    expect(lapsed.interval_days).toBeLessThan(mature.interval_days);
    expect(lapsed.interval_days).toBeGreaterThanOrEqual(1);
    // 曲線は急になる。
    expect(forgettingCurve(7, lapsed.interval_days)).toBeLessThan(
      forgettingCurve(7, mature.interval_days),
    );
    // 長くもっていた語ほど学び直しも速い（明日ではなく数日）。若い語は明日。
    const young = nextSrs({ ease: 2.5, interval_days: 2, repetitions: 1 }, 1, { elapsedDays: 2 });
    expect(young.interval_days).toBe(1);
    expect(lapsed.interval_days).toBeGreaterThan(young.interval_days);
  });

  it("間違えると ease（覚えやすさ）が下がり、以後の伸びが鈍る", () => {
    const before = { ease: 2.5, interval_days: 30, repetitions: 3 };
    const lapsed = nextSrs(before, 1, { elapsedDays: 30 });
    expect(lapsed.ease).toBeLessThan(before.ease);
    // 同じ安定度から Good を1回: ease が低い方が伸びが小さい。
    const a = nextSrs({ ease: lapsed.ease, interval_days: 10, repetitions: 1 }, 5, {
      elapsedDays: 10,
    });
    const b = nextSrs({ ease: before.ease, interval_days: 10, repetitions: 1 }, 5, {
      elapsedDays: 10,
    });
    expect(a.interval_days).toBeLessThan(b.interval_days);
  });

  it("Hard（ぼかし・時間切れ・ヒント）は Good より伸びが小さく、ease も下がる", () => {
    const prev = { ease: 2.5, interval_days: 10, repetitions: 2 };
    const hard = nextSrs(prev, 3, { elapsedDays: 10 });
    const hard4 = nextSrs(prev, 4, { elapsedDays: 10 });
    const good = nextSrs(prev, 5, { elapsedDays: 10 });
    expect(hard).toEqual(hard4);
    expect(hard.interval_days).toBeGreaterThanOrEqual(prev.interval_days);
    expect(hard.interval_days).toBeLessThan(good.interval_days);
    expect(hard.ease).toBeLessThan(prev.ease);
    expect(hard.repetitions).toBe(3);
  });

  it("遅れて思い出せた分は数える（R が低いほど伸びる）。早すぎる・同じ日はほぼ伸びない", () => {
    const prev = { ease: 2.5, interval_days: 30, repetitions: 3 };
    const late = nextSrs(prev, 5, { elapsedDays: 60 }).interval_days;
    const onTime = nextSrs(prev, 5, { elapsedDays: 30 }).interval_days;
    const early = nextSrs(prev, 5, { elapsedDays: 3 }).interval_days;
    const sameDay = nextSrs(prev, 5, { elapsedDays: 0 }).interval_days;
    expect(late).toBeGreaterThan(onTime);
    expect(onTime).toBeGreaterThan(early);
    expect(sameDay).toBe(prev.interval_days);
    // 経過が分からなければ予定どおりと見なす。
    expect(nextSrs(prev, 5).interval_days).toBe(onTime);
  });

  it("最初の復習は評価だけで決まる（Good 2日・Hard 1日・Again 1日）", () => {
    expect(nextSrs(fresh, 5).interval_days).toBe(2);
    expect(nextSrs(fresh, 3).interval_days).toBe(1);
    expect(nextSrs(fresh, 1)).toMatchObject({ interval_days: 1, repetitions: 0 });
    expect(nextSrs(fresh, 5).repetitions).toBe(1);
  });

  it("列は整数の日・1 以上（DB の `interval_days integer`）", () => {
    let s = fresh;
    for (const score of [1, 3, 5, 1, 5, 5, 5, 1, 3]) {
      s = nextSrs(s, score, { elapsedDays: s.interval_days });
      expect(Number.isInteger(s.interval_days)).toBe(true);
      expect(s.interval_days).toBeGreaterThanOrEqual(1);
    }
  });

  it("渡された状態を書き換えない", () => {
    const before = { ...fresh };
    nextSrs(fresh, 5);
    expect(fresh).toEqual(before);
  });
});

/**
 * **4択の正解で記憶を言い過ぎない**（2026-10-03 監査「6 回正解で次が 3 年後」）。
 *
 * 直す前（伸びを FSRS のまま、上限 100 年）: 2 → 11 → 46 → 163 → 497 → 1346 日。
 * 直した後（4択の正解は伸びを半分、上限 180 日）: 2 → 6 → 17 → 42 → 96 → 180 日。
 */
describe("4択（見分ける）の証拠は控えめに数える", () => {
  it("上限は 180 日、伸びの係数は 0.5", () => {
    expect(MAX_INTERVAL_DAYS).toBe(180);
    expect(CHOICE_GAIN).toBe(0.5);
  });

  it("**4択で 6 回続けて正解しても、次は 180 日以内**（前は 1346 日 = 3.7 年）", () => {
    const states = chain(fresh, 5, 6);
    expect(states.map((s) => s.interval_days)).toEqual([2, 6, 17, 42, 96, 180]);
    for (const s of states) expect(s.interval_days).toBeLessThanOrEqual(MAX_INTERVAL_DAYS);
  });

  it("その先いくら正解しても 180 日を超えない（半年に 1 回は出る）", () => {
    const states = chain(fresh, 5, 20);
    expect(Math.max(...states.map((s) => s.interval_days))).toBe(MAX_INTERVAL_DAYS);
    // 遅れて答えても（R が低いほど伸びる）上限は同じ。
    const late = nextSrs({ ease: 3, interval_days: 150, repetitions: 9 }, 5, { elapsedDays: 400 });
    expect(late.interval_days).toBe(MAX_INTERVAL_DAYS);
  });

  it("証拠の既定は 4択（何も渡さなければ控えめな方）", () => {
    const prev = { ease: 2.5, interval_days: 10, repetitions: 2 };
    expect(nextSrs(prev, 5, { elapsedDays: 10 })).toEqual(
      nextSrs(prev, 5, { elapsedDays: 10, evidence: "choice" }),
    );
  });

  it("思い出す形（話す・打つ）の正解は 4択より大きく伸びる。上限は同じ 180 日", () => {
    const prev = { ease: 2.5, interval_days: 10, repetitions: 2 };
    const choice = nextSrs(prev, 5, { elapsedDays: 10, evidence: "choice" });
    const recall = nextSrs(prev, 5, { elapsedDays: 10, evidence: "recall" });
    expect(recall.interval_days).toBeGreaterThan(choice.interval_days);
    // 伸びの分（S' − S）がおよそ半分。
    const gainChoice = choice.interval_days - prev.interval_days;
    const gainRecall = recall.interval_days - prev.interval_days;
    expect(Math.abs(gainChoice - gainRecall * CHOICE_GAIN)).toBeLessThanOrEqual(1);
    // 難しさ D（ease）の動きは証拠の強さによらない（評価だけで決まる）。
    expect(choice.ease).toBeCloseTo(recall.ease, 9);
    let s = nextSrs(fresh, 5);
    for (let i = 0; i < 10; i++) {
      s = nextSrs(s, 5, { elapsedDays: s.interval_days, evidence: "recall" });
      expect(s.interval_days).toBeLessThanOrEqual(MAX_INTERVAL_DAYS);
    }
  });

  it("Hard（ぼかし・時間切れ）の 4択の正解は Good の 4択よりさらに伸びない。最初の復習と間違いは変わらない", () => {
    const prev = { ease: 2.5, interval_days: 10, repetitions: 2 };
    const hard = nextSrs(prev, 4, { elapsedDays: 10 });
    const good = nextSrs(prev, 5, { elapsedDays: 10 });
    expect(hard.interval_days).toBeLessThan(good.interval_days);
    expect(hard.interval_days).toBeGreaterThanOrEqual(prev.interval_days);
    // 未復習からの初期値・間違えたときの縮み方には係数を掛けない。
    for (const score of [1, 3, 5]) {
      expect(nextSrs(fresh, score, { evidence: "choice" })).toEqual(
        nextSrs(fresh, score, { evidence: "recall" }),
      );
    }
    const mature = { ease: 2.5, interval_days: 90, repetitions: 6 };
    expect(nextSrs(mature, 1, { elapsedDays: 90, evidence: "choice" })).toEqual(
      nextSrs(mature, 1, { elapsedDays: 90, evidence: "recall" }),
    );
  });
});

/**
 * **DB に入っている長い間隔は書き換えない。** 読むときに 180 日で頭を打つ。
 * 2026-10-03 より前に、4択の正解だけで数年先へ飛んだ語を、表示・次の計算・出題の
 * どれでも 180 日として扱う。
 */
describe("既存の長い間隔は読むときに 180 日として働く（移行なし）", () => {
  const now = Date.UTC(2026, 9, 3);
  const legacy = { ease: 2.5, interval_days: 1346, repetitions: 6 };

  it("安定度は 180 日で頭打ち。% は 180 日目に 90%（1346 日のままなら 98% と言い過ぎていた）", () => {
    expect(stabilityOf(legacy.interval_days, legacy.ease)).toBe(MAX_INTERVAL_DAYS);
    const r = retentionNow(legacy.interval_days, legacy.ease, now - 180 * DAY, now);
    expect(Math.round(r)).toBe(90);
    expect(100 * forgettingCurve(180, 1346)).toBeGreaterThan(97);
  });

  it("次の計算も 180 日から始まり、180 日を超えない", () => {
    const good = nextSrs(legacy, 5, { elapsedDays: 200 });
    expect(good.interval_days).toBe(MAX_INTERVAL_DAYS);
    expect(good.repetitions).toBe(7);
    const lapsed = nextSrs(legacy, 1, { elapsedDays: 200 });
    expect(lapsed.interval_days).toBeLessThan(30);
    expect(lapsed.repetitions).toBe(0);
  });

  it("出題の期限は `due_at` と「最後の復習 + 180 日」の早い方", () => {
    const last = new Date(now - 200 * DAY).toISOString();
    const farDue = new Date(now + 1146 * DAY).toISOString();
    expect(effectiveDueMs(farDue, last)).toBe(now - 20 * DAY);
    expect(effectiveDueIso(farDue, last)).toBe(new Date(now - 20 * DAY).toISOString());
    // 最近復習した札は `due_at` のまま。
    const soon = new Date(now + 3 * DAY).toISOString();
    expect(effectiveDueMs(soon, new Date(now - 10 * DAY).toISOString())).toBe(now + 3 * DAY);
    // 未復習（最後の復習が無い）は `due_at` のまま、期限が無ければ null のまま。
    expect(effectiveDueMs(soon, null)).toBe(now + 3 * DAY);
    expect(effectiveDueMs(null, last)).toBeNull();
    expect(effectiveDueIso(null, null)).toBeNull();
  });

  it("DB で選ぶ条件も同じ規則（`due_at <= 今` か、期限があって最後の復習が 180 日以上前）", () => {
    expect(dueNowOrFilter(now)).toBe(
      `due_at.lte."${new Date(now).toISOString()}",` +
        `and(due_at.not.is.null,last_reviewed_at.lte."${new Date(now - 180 * DAY).toISOString()}")`,
    );
  });
});

describe("忘却曲線（FSRS のべき関数）", () => {
  it("出題日（経過 = 安定度）の定着度は 90%（間隔・ease によらない）", () => {
    for (const s of [1, 3, 7, 30, 90, 365]) {
      expect(forgettingCurve(s, s)).toBeCloseTo(TARGET_RETENTION, 6);
    }
    expect(TARGET_RETENTION).toBe(0.9);
  });
  it("時間が経つほど下がり、安定度が大きいほどゆっくり", () => {
    expect(forgettingCurve(0, 10)).toBe(1);
    expect(forgettingCurve(5, 10)).toBeGreaterThan(forgettingCurve(20, 10));
    expect(forgettingCurve(20, 30)).toBeGreaterThan(forgettingCurve(20, 10));
    expect(forgettingCurve(100000, 1)).toBeGreaterThanOrEqual(0);
  });
  it("安定度が無ければ 0（撮っただけの語）", () => {
    expect(forgettingCurve(0, 0)).toBe(0);
    expect(forgettingCurve(3, 0)).toBe(0);
  });
  it("daysUntilRetention は forgettingCurve の逆", () => {
    for (const s of [1, 10, 90]) {
      for (const r of [0.95, 0.9, 0.7, 0.5]) {
        const d = daysUntilRetention(s, r);
        expect(forgettingCurve(d, s)).toBeCloseTo(r, 6);
      }
      expect(daysUntilRetention(s, 0.9)).toBeCloseTo(s, 6);
    }
    expect(daysUntilRetention(0, 0.9)).toBe(0);
  });
});

describe("retentionNow", () => {
  const now = Date.UTC(2026, 0, 10);

  it("**撮っただけの語は 0%**（未復習: 起点が無い／安定度が無い）", () => {
    // オーナー指示 2026-10-02「写真を撮ったときはまだ覚えてないから 0% になるように」。
    expect(retentionNow(0, 2.5, null, now)).toBe(0);
    expect(retentionNow(0, 2.5, now - DAY, now)).toBe(0);
    expect(retentionNow(3, 2.5, null, now)).toBe(0);
  });

  it("復習の直後は 100%", () => {
    expect(retentionNow(3, 2.5, now, now)).toBe(100);
    // 端末の時計がずれて未来を指しても100%を超えない
    expect(retentionNow(3, 2.5, now + DAY, now)).toBe(100);
  });

  it("時間が経つほど下がり、出題日に 90%、0を下回らない", () => {
    const d1 = retentionNow(3, 2.5, now - DAY, now);
    const d3 = retentionNow(3, 2.5, now - 3 * DAY, now);
    const d7 = retentionNow(3, 2.5, now - 7 * DAY, now);
    expect(d1).toBeGreaterThan(d3);
    expect(d3).toBeGreaterThan(d7);
    expect(Math.round(d3)).toBe(90);
    expect(retentionNow(3, 2.5, now - 3650 * DAY, now)).toBeGreaterThanOrEqual(0);
  });

  /**
   * **既存のデータは跳ばない。** SM-2 の間隔は「ease 2.5 の語が出題日に 90%」になるよう
   * 安定度を合わせてあったので（2026-09-16）、間隔をそのまま安定度と読んでも出題日の値は
   * 同じ 90%。ease 1.3 の語は 82% → 90%、3.0 の語は 92% → 90% と、数ポイントの差で収まる。
   */
  it("既存の間隔をそのまま安定度と読んでも、出題日の値は 90% 前後に収まる", () => {
    const K = 1 / (2.5 * Math.log(1 / 0.9));
    const oldR = (i: number, e: number) => 100 * Math.exp(-i / (Math.max(1, i) * e * K));
    for (const interval of [1, 3, 7, 30, 90]) {
      for (const ease of [1.3, 2.5, 3.0]) {
        const now2 = now;
        const neu = retentionNow(interval, ease, now2 - interval * DAY, now2);
        expect(Math.abs(neu - oldR(interval, ease))).toBeLessThanOrEqual(8.5);
        expect(Math.round(neu)).toBe(90);
      }
    }
  });
});

describe("stabilityOf", () => {
  it("安定度は `interval_days` そのもの（0 = 未復習）。ease は効かない。180 日で頭打ち", () => {
    expect(stabilityOf(0, 2.5)).toBe(0);
    expect(stabilityOf(180)).toBe(180);
    expect(stabilityOf(36500)).toBe(180);
    expect(stabilityOf(10, 1.3)).toBe(10);
    expect(stabilityOf(10, 3.0)).toBe(10);
    expect(stabilityOf(0.4)).toBe(1);
  });
});

describe("modeFor", () => {
  it("回を重ねるほど難しい形式へ上がる", () => {
    expect(modeFor(0)).toBe("recognition");
    expect(modeFor(1)).toBe("recognition");
    expect(modeFor(2)).toBe("listening");
    expect(modeFor(3)).toBe("listening");
    expect(modeFor(4)).toBe("reverse");
    expect(modeFor(5)).toBe("reverse");
    expect(modeFor(6)).toBe("production");
    expect(modeFor(999)).toBe("production");
  });
});
