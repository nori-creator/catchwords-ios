import { describe, expect, it } from "vitest";
import { boxCenter, positionStats, validBox2d, withObjectPoints } from "./suggestion-position";

describe("validBox2d", () => {
  it("keeps a [ymin, xmin, ymax, xmax] box on the 0-1000 scale (rounded)", () => {
    expect(validBox2d([100, 200, 300.4, 400.6])).toEqual([100, 200, 300, 401]);
  });

  it("drops anything that is not four numbers inside the photo with a size", () => {
    expect(validBox2d(undefined)).toBeNull();
    expect(validBox2d([1, 2, 3])).toBeNull();
    expect(validBox2d([100, 200, "300", 400])).toBeNull();
    expect(validBox2d([100, 200, 1300, 400])).toBeNull();
    expect(validBox2d([-1, 200, 300, 400])).toBeNull();
    expect(validBox2d([300, 200, 100, 400])).toBeNull();
    expect(validBox2d([100, 400, 300, 400])).toBeNull();
  });
});

describe("boxCenter", () => {
  it("is [x, y] (the order the iOS app reads), not Gemini's [y, x]", () => {
    expect(boxCenter([100, 600, 300, 1000])).toEqual([800, 200]);
  });
});

describe("withObjectPoints", () => {
  it("gives every name of one object that object's box and centre point", () => {
    const out = withObjectPoints([
      { headword: "珍珠奶茶", group: 0, box_2d: [400, 100, 900, 300] },
      { headword: "機車", group: 1, box_2d: [200, 500, 800, 1000] },
      // The other name of the bubble tea came without a box (the prompt allows that).
      { headword: "珍奶", group: 0 },
    ]);
    expect(out.map((s) => s.point)).toEqual([
      [200, 650],
      [750, 500],
      [200, 650],
    ]);
    expect(out[2].box_2d).toEqual([400, 100, 900, 300]);
  });

  it("a name with its own box keeps its own box (a wrong group number must not pile every tag on one object)", () => {
    // 2026-10-15: tablet, cup, stylus and tissue all came back as group 0 — with "first box of the group"
    // every tag landed in the middle of the tablet.
    const out = withObjectPoints([
      { headword: "平板", group: 0, box_2d: [100, 100, 700, 900] },
      { headword: "杯子", group: 0, box_2d: [600, 50, 900, 250] },
      { headword: "觸控筆", group: 0, box_2d: [300, 850, 700, 900] },
      { headword: "面紙", group: 0, box_2d: [50, 800, 300, 1000] },
      // The other name of the tablet came without a box: it inherits the object's first box.
      { headword: "平板電腦", group: 0 },
    ]);
    expect(out.map((s) => s.point)).toEqual([
      [500, 400],
      [150, 750],
      [875, 500],
      [900, 175],
      [500, 400],
    ]);
    expect(positionStats(out)).toEqual({ n: 5, groups: 1, with_point: 5, distinct_points: 4 });
  });

  it("leaves names without a usable box (or without a group and box) unpositioned", () => {
    const out = withObjectPoints([
      { headword: "桌子", group: 3, box_2d: [500, 500, 400, 900] },
      { headword: "招牌" },
      { headword: "傘", box_2d: [0, 0, 500, 500] },
    ]);
    expect(out[0]).not.toHaveProperty("point");
    expect(out[0]).not.toHaveProperty("box_2d");
    expect(out[1]).not.toHaveProperty("point");
    expect(out[2].point).toEqual([250, 250]);
  });
});
