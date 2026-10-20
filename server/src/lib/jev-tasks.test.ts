import { describe, expect, it } from "vitest";
import {
  acceptCategory,
  candidateQuestion,
  categoryQuestion,
  rankByWanted,
  recallQuestion,
} from "./jev-tasks";
import type { JevAnswer } from "./jev";

const choiceAns = (choice: string, confidence: number, probabilities: Record<string, number>) =>
  ({ type: "choice", choice, confidence, probabilities }) as JevAnswer;

describe("スキャンの候補の並べ替え", () => {
  it("選択肢の名前は c0, c1…（同じ語が2つでも壊れない）", () => {
    const q = candidateQuestion([
      { headword: "奶茶" },
      { headword: "奶茶", meaning: "ミルクティー" },
    ]);
    const crit = (q.questions.wanted as { criteria: Record<string, unknown> }).criteria;
    expect(Object.keys(crit)).toEqual(["c0", "c1"]);
  });

  it("見込みの高い順。同じなら元の順", () => {
    const r = rankByWanted(["a", "b", "c"], choiceAns("c2", 0.7, { c0: 0.1, c1: 0.1, c2: 0.8 }));
    expect(r!.order).toEqual([2, 0, 1]);
  });

  it("自信が低い・答えが無い・形が違うときは並べ替えない", () => {
    expect(rankByWanted(["a", "b"], choiceAns("c1", 0.2, { c0: 0.4, c1: 0.6 }))).toBeNull();
    expect(rankByWanted(["a", "b"], undefined)).toBeNull();
    expect(rankByWanted(["a", "b"], { type: "noul", noul: 0.9 })).toBeNull();
  });
});

describe("カテゴリー（「その他」に逃げたときだけ）", () => {
  it("選択肢は棚の鍵そのもの", () => {
    const q = categoryQuestion({ headword: "鍋子" }, ["kitchenware", "food", "other"]);
    const crit = (q.questions.category as { criteria: Record<string, unknown> }).criteria;
    expect(Object.keys(crit)).toEqual(["kitchenware", "food", "other"]);
  });

  it("自信が6割以上で「その他」以外のときだけ採る", () => {
    expect(acceptCategory(choiceAns("kitchenware", 0.8, { kitchenware: 0.8 }))).toBe("kitchenware");
    expect(acceptCategory(choiceAns("kitchenware", 0.5, { kitchenware: 0.5 }))).toBeNull();
    expect(acceptCategory(choiceAns("other", 0.9, { other: 0.9 }))).toBeNull();
  });
});

describe("記憶（影の実行）", () => {
  it("はい／いいえの問い1つ。この式の見込みは Jev に見せない（比べる相手なので）", () => {
    const q = recallQuestion({
      headword: "捷運",
      daysSinceLastReview: 3,
      intervalDays: 3,
      ease: 2.5,
      repetitions: 2,
      baselineRecall: 0.9,
    });
    expect(q.questions.recall.type).toBe("noul");
    expect(JSON.stringify(q.state)).not.toMatch(/0\.9|baseline/);
  });
});

import {
  allowDismiss,
  allowEntryFix,
  entryFixQuestion,
  entryOpinion,
  intervalDaysFrom,
  intervalQuestion,
  pickInterval,
  scheduleQuestion,
} from "./jev-tasks";

describe("辞書の点検の第二の目", () => {
  const q = entryFixQuestion(
    "垃圾",
    { zhuyin: "ㄌㄜˋ ㄙㄜˋ", pinyin: "lè sè", meaning: "ごみ" },
    { zhuyin: "ㄌㄜˋ ㄙㄜˋ", pinyin: "lè sè", meaning: "ごみ" },
  );
  it("選択肢は current / proposed / unsure", () => {
    const crit = (q.questions.which as { criteria: Record<string, unknown> }).criteria;
    expect(Object.keys(crit)).toEqual(["current", "proposed", "unsure"]);
  });
  it("直すのは AI が 0.85 以上 かつ Jev が案を6割以上で選んだときだけ", () => {
    const yes = entryOpinion(
      choiceAns("proposed", 0.8, { proposed: 0.7, current: 0.2, unsure: 0.1 }),
    );
    const no = entryOpinion(
      choiceAns("current", 0.8, { proposed: 0.3, current: 0.6, unsure: 0.1 }),
    );
    expect(allowEntryFix(0.9, yes)).toBe(true);
    expect(allowEntryFix(0.9, no)).toBe(false);
    expect(allowEntryFix(0.8, yes)).toBe(false);
    // Jev が使えないときは従来どおり
    expect(allowEntryFix(0.9, null)).toBe(true);
  });
  it("却下も同じ（Jev がいまの中身を6割以上）", () => {
    const cur = entryOpinion(
      choiceAns("current", 0.8, { proposed: 0.2, current: 0.7, unsure: 0.1 }),
    );
    expect(allowDismiss(0.9, cur)).toBe(true);
    expect(
      allowDismiss(0.9, entryOpinion(choiceAns("unsure", 0.5, { unsure: 0.5, current: 0.4 }))),
    ).toBe(false);
  });
});

describe("復習の間隔（Jev が決める。オーナー指示 2026-09-23）", () => {
  const ans = (x: number) =>
    ({ type: "score", score: x, confidence: 0.5, probabilities: { "0": 1 } }) as JevAnswer;

  it("段の期待値から日数へ", () => {
    expect(intervalQuestion().type).toBe("score");
    expect(intervalDaysFrom(ans(0))).toBe(1);
    expect(intervalDaysFrom(ans(2))).toBe(7);
    expect(intervalDaysFrom(ans(2.5))).toBe(11);
    expect(intervalDaysFrom(ans(9))).toBe(120);
    expect(intervalDaysFrom(ans(Number.NaN))).toBeNull();
    expect(intervalDaysFrom(undefined)).toBeNull();
  });

  it("間隔の問いには**この復習の結果**を見せる", () => {
    const q = scheduleQuestion({
      headword: "捷運",
      daysSinceLastReview: 3,
      intervalDaysBefore: 3,
      ease: 2.5,
      repetitionsBefore: 2,
      recalled: true,
      score: 5,
      responseSeconds: 2.1,
    });
    expect(Object.keys(q.questions)).toEqual(["interval"]);
    expect(JSON.stringify(q.state)).toMatch(/"recalled":true/);
  });

  it("思い出せなかった語は明日（Jev が延ばしても使わない）", () => {
    expect(pickInterval(1, 30, 1)).toEqual({ days: 1, source: "srs" });
    expect(pickInterval(1, 30, 2)).toEqual({ days: 1, source: "srs" });
  });

  it("Jev の答えが無ければ SM-2 のまま", () => {
    expect(pickInterval(8, null, 5)).toEqual({ days: 8, source: "srs" });
  });

  it("Jev の日数を使う。ただし SM-2 の半分〜2倍に収める", () => {
    expect(pickInterval(8, 11, 5)).toEqual({ days: 11, source: "jev" });
    expect(pickInterval(8, 60, 5)).toEqual({ days: 16, source: "jev" });
    expect(pickInterval(8, 1, 5)).toEqual({ days: 4, source: "jev" });
    // 下限 1日・上限 365日。
    expect(pickInterval(1, 1, 5)).toEqual({ days: 1, source: "jev" });
    expect(pickInterval(300, 120, 5).days).toBe(150);
    expect(pickInterval(300, 999, 5).days).toBe(365);
  });
});

import { candidateQuestion as cq, doubtfulTaiwanTerms } from "./jev-tasks";

describe("スキャンの候補: 台湾の言い方かも同じ1回で聞く（2026-09-23 の3回目）", () => {
  it("候補ごとに tw の問いが付く（並べ替えの問いと一緒）", () => {
    const q = cq([{ headword: "出租车" }, { headword: "計程車" }]);
    expect(Object.keys(q.questions).sort()).toEqual(["tw0", "tw1", "wanted"]);
  });
  it("はっきり疑わしい（15% 未満）ものだけを返す。迷うもの・答えの無いものは疑わない", () => {
    expect(
      doubtfulTaiwanTerms(3, {
        tw0: { type: "noul", noul: 0.05 },
        tw1: { type: "noul", noul: 0.4 },
      }),
    ).toEqual([0]);
    expect(doubtfulTaiwanTerms(2, undefined)).toEqual([]);
  });
});
