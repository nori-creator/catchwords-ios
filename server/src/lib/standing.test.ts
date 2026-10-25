import { describe, expect, it } from "vitest";
import {
  countByUser,
  distinctDaysByUser,
  retentionByUser,
  standingOf,
} from "./standing";

describe("standingOf", () => {
  it("ranks by how many have more, ties share the rank", () => {
    const counts = new Map([
      ["me", 10],
      ["a", 20],
      ["b", 10],
      ["c", 3],
    ]);
    expect(standingOf(10, counts, "me")).toEqual({
      rank: 2,
      total: 4,
      topPercent: 50,
    });
  });

  it("is never top 0% and leaves out people with nothing", () => {
    const counts = new Map([
      ["me", 5],
      ["a", 0],
      ...Array.from(
        { length: 300 },
        (_, i) => [`u${i}`, 1] as [string, number],
      ),
    ]);
    const s = standingOf(5, counts, "me");
    expect(s?.rank).toBe(1);
    expect(s?.total).toBe(301);
    expect(s?.topPercent).toBe(1);
  });

  it("counts the caller even when the map does not hold them", () => {
    expect(standingOf(3, new Map([["a", 1]]), "me")).toEqual({
      rank: 1,
      total: 2,
      topPercent: 50,
    });
  });

  it("does not compare a caller with nothing", () => {
    expect(standingOf(0, new Map([["a", 1]]), "me")).toBeNull();
  });
});

describe("countByUser / distinctDaysByUser", () => {
  it("counts rows and distinct days per user", () => {
    expect(
      countByUser([{ user_id: "a" }, { user_id: "a" }, { user_id: "b" }]),
    ).toEqual(
      new Map([
        ["a", 2],
        ["b", 1],
      ]),
    );
    expect(
      distinctDaysByUser([
        { user_id: "a", day: "2026-10-01" },
        { user_id: "a", day: "2026-10-01" },
        { user_id: "a", day: "2026-10-02" },
        { user_id: "b", day: "2026-10-02" },
      ]),
    ).toEqual(
      new Map([
        ["a", 2],
        ["b", 1],
      ]),
    );
  });
});

describe("retentionByUser", () => {
  it("is the share of days used since the start, for accounts at least a week old", () => {
    const r = retentionByUser(
      new Map([
        ["a", 7],
        ["b", 3],
        ["new", 2],
      ]),
      new Map([
        ["a", "2026-10-01"],
        ["b", "2026-10-01"],
        ["new", "2026-10-09"],
      ]),
      "2026-10-10",
    );
    expect(r.get("a")).toEqual({ rate: 70, active: 7, days: 10 });
    expect(r.get("b")).toEqual({ rate: 30, active: 3, days: 10 });
    expect(r.has("new")).toBe(false);
  });
});
