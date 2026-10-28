import { describe, expect, it } from "vitest";
import {
  boxCenter,
  locateInstruction,
  objectsNeedingBoxes,
  positionStats,
  readLocatedBoxes,
  validBox2d,
  withLocatedBoxes,
  withObjectPoints,
} from "./suggestion-position";

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

describe("re-asking for boxes the photo answer left out (2026-10-26)", () => {
  // The park photo: flash-lite named sky, building, tree and grass and sent no box at all.
  const park = withObjectPoints([
    { headword: "天空", group: 0, label: "空" },
    { headword: "大樓", group: 1, label: "ビル" },
    { headword: "高樓", group: 1 },
    { headword: "樹", group: 2, label: "木" },
    { headword: "草", group: 3, label: "草" },
  ]);

  it("asks for every object without a place, once per object", () => {
    expect(objectsNeedingBoxes(park)).toEqual([0, 1, 2, 3]);
  });

  it("also asks for an object whose box sits where an earlier one's is (two things, one box)", () => {
    const items = withObjectPoints([
      { headword: "鞦韆", group: 0, box_2d: [360, 400, 620, 720] },
      { headword: "人", group: 1, box_2d: [365, 405, 625, 715] },
      { headword: "樹", group: 2, box_2d: [0, 0, 750, 200] },
    ]);
    expect(objectsNeedingBoxes(items)).toEqual([1]);
  });

  it("asks for nothing when every object has its own place", () => {
    const items = withObjectPoints([
      { headword: "手", group: 0, box_2d: [300, 100, 900, 800] },
      { headword: "大拇指", group: 1, box_2d: [350, 120, 480, 300] },
    ]);
    expect(objectsNeedingBoxes(items)).toEqual([]);
  });

  it("names each object by its names and its everyday label in the instruction", () => {
    const text = locateInstruction(park, objectsNeedingBoxes(park));
    expect(text).toContain("- id 1: 大樓 / ビル / 高樓");
    expect(text).toContain('{"boxes":[{"id":0,"box_2d":[ymin,xmin,ymax,xmax]}]}');
  });

  it("reads only well-formed boxes for the objects asked about", () => {
    const boxes = readLocatedBoxes(
      {
        boxes: [
          { id: 0, box_2d: [0, 0, 300, 1000] },
          { id: "2", box_2d: [100, 300, 700, 600] },
          { id: 7, box_2d: [1, 1, 2, 2] },
          { id: 3, box_2d: [500, 500, 400, 600] },
        ],
      },
      [0, 1, 2, 3],
    );
    expect([...boxes.entries()]).toEqual([
      [0, [0, 0, 300, 1000]],
      [2, [100, 300, 700, 600]],
    ]);
    expect(readLocatedBoxes(null, [0]).size).toBe(0);
    expect(readLocatedBoxes({ boxes: "no" }, [0]).size).toBe(0);
  });

  it("gives every name of an object the box found for it, and the tags their own places", () => {
    const boxes = new Map<number, [number, number, number, number]>([
      [0, [0, 0, 300, 1000]],
      [1, [200, 350, 700, 600]],
      [2, [100, 0, 800, 300]],
      [3, [700, 0, 1000, 1000]],
    ]);
    const out = withLocatedBoxes(park, boxes);
    expect(out.map((s) => s.point)).toEqual([
      [500, 150],
      [475, 450],
      [475, 450],
      [150, 450],
      [500, 850],
    ]);
    expect(objectsNeedingBoxes(out)).toEqual([]);
  });

  it("never puts a re-asked box where another object's tag already is", () => {
    const items = withObjectPoints([
      { headword: "鞦韆", group: 0, box_2d: [360, 400, 620, 720] },
      { headword: "人", group: 1 },
    ]);
    const out = withLocatedBoxes(items, new Map([[1, [362, 402, 618, 718] as [number, number, number, number]]]));
    expect(out[1].point).toBeUndefined();
  });
});
