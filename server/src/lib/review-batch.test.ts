import { describe, expect, it } from "vitest";
import { batchEndKind } from "./review-batch";

describe("batchEndKind", () => {
  it("束を出し切っても期限切れが残っていれば「終わり」と言わない", () => {
    // これがオーナー報告そのもの: 上限は無制限(0)、10枚の束を終えた、
    // でも期限切れは190枚残っている。
    expect(batchEndKind({ limit: 0, doneToday: 10, dueRemaining: 190 })).toBe("more");
  });

  it("無制限(0)では何枚やっても上限に当たらない", () => {
    expect(batchEndKind({ limit: 0, doneToday: 0, dueRemaining: 5 })).toBe("more");
    expect(batchEndKind({ limit: 0, doneToday: 999, dueRemaining: 1 })).toBe("more");
  });

  it("上限に当たり、かつ残りがあるときだけ capped", () => {
    expect(batchEndKind({ limit: 20, doneToday: 20, dueRemaining: 3 })).toBe("capped");
    expect(batchEndKind({ limit: 20, doneToday: 21, dueRemaining: 3 })).toBe("capped");
  });

  it("上限に当たっても残りが無ければ「終わり」", () => {
    // 上げたのに1枚も出てこない、を防ぐ。
    expect(batchEndKind({ limit: 20, doneToday: 20, dueRemaining: 0 })).toBe("done");
  });

  it("上限未満で残りがあれば続けられる", () => {
    expect(batchEndKind({ limit: 20, doneToday: 10, dueRemaining: 4 })).toBe("more");
  });

  it("残りが無ければ done", () => {
    expect(batchEndKind({ limit: 20, doneToday: 3, dueRemaining: 0 })).toBe("done");
  });

  it("負の残りや小数は 0 側へ丸める", () => {
    expect(batchEndKind({ limit: 0, doneToday: 0, dueRemaining: -1 })).toBe("done");
    expect(batchEndKind({ limit: 0, doneToday: 0, dueRemaining: 0.9 })).toBe("done");
    expect(batchEndKind({ limit: 0, doneToday: 0, dueRemaining: 1.9 })).toBe("more");
  });

  it("負の上限も無制限として扱う(設定が壊れていても capped にしない)", () => {
    expect(batchEndKind({ limit: -5, doneToday: 100, dueRemaining: 2 })).toBe("more");
  });
});
