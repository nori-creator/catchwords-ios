import { describe, expect, it } from "vitest";
import { appUsage, areaCounts, categoryCounts, heatGrid, taipeiSlot } from "./admin-user-insights";

describe("taipeiSlot", () => {
  it("reads the weekday (Monday first) and hour in Taipei time", () => {
    // 2026-11-13 is a Friday; 00:30 UTC is 08:30 in Taipei.
    expect(taipeiSlot("2026-11-13T00:30:00Z")).toEqual({ weekday: 4, hour: 8 });
    // Sunday 20:00 UTC is Monday 04:00 in Taipei.
    expect(taipeiSlot("2026-11-15T20:00:00Z")).toEqual({ weekday: 0, hour: 4 });
    expect(taipeiSlot("not a date")).toBeNull();
  });
});

describe("heatGrid", () => {
  it("counts each time in its weekday × hour cell", () => {
    const g = heatGrid(["2026-11-13T00:30:00Z", "2026-11-13T00:59:00Z", "2026-11-15T20:00:00Z"]);
    expect(g).toHaveLength(7);
    expect(g[4][8]).toBe(2);
    expect(g[0][4]).toBe(1);
    expect(g.flat().reduce((a, b) => a + b, 0)).toBe(3);
  });
});

describe("areaCounts", () => {
  it("keeps only the city and district, never the street or a learner-written name", () => {
    const rows = [
      { created_at: "2026-11-13T00:30:00Z", location_name: "台北市 大安區 和平東路一段162號" }, // 08:30 morning
      { created_at: "2026-11-13T05:00:00Z", location_name: "台北市 大安區 復興南路一段1號" }, // 13:00 day
      { created_at: "2026-11-13T13:00:00Z", location_name: "台北市 中正區 羅斯福路一段" }, // 21:00 night
      { created_at: "2026-11-13T13:00:00Z", location_name: "阿嬤的家", location_custom: true },
      { created_at: "2026-11-13T13:00:00Z", location_name: "162 Main Street" },
      { created_at: "2026-11-13T13:00:00Z", location_name: null },
    ];
    const out = areaCounts(rows);
    expect(out).toEqual([
      { name: "台北市 大安區", n: 2, morning: 1, day: 1, night: 0 },
      { name: "台北市 中正區", n: 1, morning: 0, day: 0, night: 1 },
    ]);
    expect(JSON.stringify(out)).not.toMatch(/號|路|阿嬤|Main/);
  });
});

describe("categoryCounts", () => {
  it("counts keys, most first, a missing key as other", () => {
    expect(categoryCounts(["drink", "food", "drink", null, ""])).toEqual([
      { key: "drink", n: 2 },
      { key: "other", n: 2 },
      { key: "food", n: 1 },
    ]);
  });
});

describe("appUsage", () => {
  const now = new Date("2026-11-13T12:00:00Z");
  it("reads the device, tutorial, screens, features and the screen before leaving", () => {
    const ev = [
      { kind: "app_open", created_at: "2026-11-01T01:00:00Z", meta: { app_version: "1.0.6 (40)", device: "iphone", os: "26.1", lang: "es" } },
      { kind: "session_start", created_at: "2026-11-01T01:00:01Z" },
      { kind: "tutorial_step", created_at: "2026-11-01T01:00:02Z", meta: { step: "shoot" } },
      { kind: "tutorial_step", created_at: "2026-11-01T01:02:00Z", meta: { step: "dex_cover" } },
      { kind: "tutorial_skip", created_at: "2026-11-01T01:03:00Z" },
      { kind: "screen_view", created_at: "2026-11-01T01:04:00Z", meta: { screen: "home" } },
      { kind: "screen_view", created_at: "2026-11-01T01:05:00Z", meta: { screen: "review" } },
      { kind: "feature_use", created_at: "2026-11-01T01:05:30Z", meta: { feature: "lasso" } },
      { kind: "feature_use", created_at: "2026-11-01T01:05:40Z", meta: { feature: "lasso" } },
      { kind: "session_end", created_at: "2026-11-01T01:06:00Z" },
      { kind: "app_open", created_at: "2026-11-12T01:00:00Z", meta: { app_version: "1.0.7 (44)", device: "iphone", os: "26.2", lang: "es" } },
      { kind: "screen_view", created_at: "2026-11-12T01:01:00Z", meta: { screen: "camera" } },
      { kind: "session_end", created_at: "2026-11-12T01:06:00Z" },
      { kind: "leave_home", created_at: "2026-10-01T01:00:00Z" },
      // older than 30 days: not in the 30-day counts
      { kind: "screen_view", created_at: "2026-09-01T01:00:00Z", meta: { screen: "dex" } },
    ];
    const u = appUsage(ev, now);
    expect(u.device).toEqual({ appVersion: "1.0.7 (44)", device: "iphone", os: "26.2", lang: "es", at: "2026-11-12T01:00:00Z" });
    expect(u.tutorial).toEqual({ parts: ["camera", "dex"], lastStep: "dex_cover", lastAt: "2026-11-01T01:02:00Z", ended: 1 });
    expect(u.screens30).toEqual([
      { key: "camera", n: 1 },
      { key: "home", n: 1 },
      { key: "review", n: 1 },
    ]);
    expect(u.features30).toEqual([{ key: "lasso", n: 2 }]);
    expect(u.lastScreens).toEqual([
      { key: "camera", n: 1 },
      { key: "home", n: 1 },
      { key: "review", n: 1 },
    ]);
  });

  it("is empty for someone whose app sends nothing yet", () => {
    const u = appUsage([{ kind: "session_end", created_at: "2026-11-01T01:00:00Z" }], now);
    expect(u.device).toBeNull();
    expect(u.tutorial.parts).toEqual([]);
    expect(u.lastScreens).toEqual([]);
  });
});
