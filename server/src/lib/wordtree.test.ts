import { describe, it, expect } from "vitest";
import { buildBranchPlan, resolveBranches, parseBranchPlan, type Branch } from "./wordtree";

/**
 * 単語の枝。復習を1回終えるごとに1本ずつ開く。
 *
 * ## なぜ守るか
 * 「次に何が開くか」は保存時に**固定**される(branch_plan)。だから
 * ここの順番が変わると、**すでに開いた枝が閉じたり、別の枝に化けたりする**。
 * 一度見せたものが後から変わるのは、集めるアプリでいちばんやってはいけない。
 */

const extras = {
  collocations: ["喝咖啡", "煮咖啡", "咖啡廳", "咖啡豆", "5本目は捨てられる"],
  examples_extra: [
    { zh: "我要一杯咖啡", ja: "コーヒーを一杯ください" },
    { zh: "這家咖啡很好喝", ja: "この店のコーヒーは美味しい" },
    { zh: "3本目は捨てられる", ja: "" },
  ],
  synonyms: ["咖啡因"],
  antonyms: ["茶"],
};

describe("buildBranchPlan", () => {
  it("種類ごとに上限を守り、決まった順に並べる", () => {
    const plan = buildBranchPlan(extras);
    expect(plan.map((b) => b.type)).toEqual([
      "collocation",
      "collocation",
      "collocation",
      "collocation",
      "example",
      "example",
      "synonym",
      "antonym",
    ]);
    // 上限を超えたぶんは落ちる(連語4本・用例2本まで)
    expect(plan.some((b) => b.zh === "5本目は捨てられる")).toBe(false);
    expect(plan.some((b) => b.zh === "3本目は捨てられる")).toBe(false);
  });

  it("extras が無ければ空", () => {
    expect(buildBranchPlan(null)).toEqual([]);
    expect(buildBranchPlan(undefined)).toEqual([]);
    expect(buildBranchPlan({})).toEqual([]);
  });

  it("空文字は枝にしない(見出しだけの空の枝を作らない)", () => {
    const plan = buildBranchPlan({ collocations: ["", "喝咖啡", ""] });
    expect(plan).toHaveLength(1);
    expect(plan[0].zh).toBe("喝咖啡");
  });
});

describe("resolveBranches", () => {
  const plan = buildBranchPlan(extras);

  it("復習0回では1本も開かない", () => {
    const r = resolveBranches(plan, 0);
    expect(r.unlocked).toHaveLength(0);
    expect(r.justUnlocked).toBeNull();
    expect(r.lockedCount).toBe(plan.length);
  });

  it("1回ごとに1本ずつ開く", () => {
    expect(resolveBranches(plan, 1).unlocked).toHaveLength(1);
    expect(resolveBranches(plan, 2).unlocked).toHaveLength(2);
    expect(resolveBranches(plan, 3).unlocked).toHaveLength(3);
  });

  it("類義語・対義語は、順番が来ても5回目までは開かない", () => {
    // 似た語を早く見せると、覚えかけの語と混ざる。
    //
    // **この規則を試すには、類義語が早い位置に来る語で試さなければならない。**
    // 上の `plan` は連語4本+用例2本が先にあるので、4回目までは
    // どのみち類義語に手が届かない — その語で「開いていない」ことを
    // 確かめても、規則が効いているのか順番のせいなのか区別できない。
    // 実際、最初そう書いていて、規則を丸ごと外しても素通りした。
    const early = buildBranchPlan({
      collocations: ["喝咖啡"],
      synonyms: ["咖啡因"],
      antonyms: ["茶"],
    });
    expect(early.map((b) => b.type)).toEqual(["collocation", "synonym", "antonym"]);

    // 2回目: 順番なら類義語が開くところだが、据え置かれるので連語1本のまま。
    const r2 = resolveBranches(early, 2);
    expect(r2.unlocked.map((b) => b.type)).toEqual(["collocation"]);

    // 5回目で解禁され、そこから順に開く。
    const r5 = resolveBranches(early, 5);
    expect(r5.unlocked.map((b) => b.type)).toEqual(["collocation", "synonym", "antonym"]);
  });

  it("一度開いた枝は、その後も同じ順で開いたまま", () => {
    // ここが崩れると「昨日見えていた枝が今日は別のものになっている」。
    let prev: Branch[] = [];
    for (let n = 1; n <= plan.length + 3; n++) {
      const now = resolveBranches(plan, n).unlocked;
      expect(now.slice(0, prev.length)).toEqual(prev);
      prev = now;
    }
  });

  it("全部開いたら、それ以上増えず locked は0", () => {
    const r = resolveBranches(plan, 999);
    expect(r.unlocked).toHaveLength(plan.length);
    expect(r.lockedCount).toBe(0);
    expect(r.reviewsUntilNext).toBeNull();
  });

  it("枝が1本も無い語でも落ちない", () => {
    const r = resolveBranches([], 5);
    expect(r.unlocked).toHaveLength(0);
    expect(r.lockedCount).toBe(0);
  });
});

describe("parseBranchPlan", () => {
  it("配列でなければ null", () => {
    expect(parseBranchPlan(null)).toBeNull();
    expect(parseBranchPlan({})).toBeNull();
    expect(parseBranchPlan("[]")).toBeNull();
  });

  it("壊れた要素だけを落として、残りは通す", () => {
    // DBのJSONBは何が入っているか分からない。1つ壊れているだけで
    // 枝が丸ごと消えるのでは、保存した意味がない。
    const parsed = parseBranchPlan([
      { type: "collocation", zh: "喝咖啡" },
      { type: "知らない種類", zh: "だめ" },
      { type: "example", zh: "" },
      null,
      "文字列",
      { type: "example", zh: "我要一杯咖啡", ja: "コーヒーを一杯" },
    ]);
    expect(parsed).toEqual([
      { type: "collocation", zh: "喝咖啡", ja: undefined },
      { type: "example", zh: "我要一杯咖啡", ja: "コーヒーを一杯" },
    ]);
  });
});
