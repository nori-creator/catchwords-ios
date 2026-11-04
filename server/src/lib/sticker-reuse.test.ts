import { describe, expect, it } from "vitest";
import { mayReuseOwnedSticker, reuseOwnedSticker } from "./stickers.functions";

// 点検 S19（2026-11-03）: iOS は毎回 client_catch_id を送るので、同じ語の札の再会が一度も使われず2枚できていた。
describe("同じ語の札の再会", () => {
  it("client_catch_id があっても、ひと言・自撮りが無ければ再会にしてよい", () => {
    expect(mayReuseOwnedSticker({ client_catch_id: "c1" }, "u1")).toBe(true);
    expect(mayReuseOwnedSticker({ client_catch_id: "c1", caption: "おいしかった" }, "u1")).toBe(false);
    expect(mayReuseOwnedSticker({ client_catch_id: "c1", selfie_path: "u1/s.jpg" }, "u1")).toBe(false);
  });

  it("同じ写真の送り直しは、再会を二重に書かない", async () => {
    const encounters: Array<Record<string, unknown>> = [];
    const sticker = { id: "s1", encounter_count: 1 };
    const query = (rows: () => Array<Record<string, unknown>>) => {
      const filters: Array<[string, unknown]> = [];
      const q = {
        select: () => q,
        eq: (k: string, v: unknown) => (filters.push([k, v]), q),
        order: () => q,
        limit: () => q,
        maybeSingle: async () => ({
          data: rows().find((r) => filters.every(([k, v]) => r[k] === v)) ?? null,
          error: null,
        }),
      };
      return q;
    };
    const supabase = {
      from: (t: string) => {
        if (t === "stickers")
          return {
            ...query(() => [{ ...sticker, user_id: "u1", word_id: "w1" }]),
            update: (v: { encounter_count: number }) => {
              const u = {
                eq: () => u,
                select: async () => {
                  sticker.encounter_count = v.encounter_count;
                  return { data: [{ id: "s1" }], error: null };
                },
              };
              return u;
            },
          };
        return {
          ...query(() => encounters),
          insert: async (row: Record<string, unknown>) => (encounters.push({ id: encounters.length + 1, ...row }), { error: null }),
        };
      },
    };
    const enc = { image_path: "u1/p.jpg", cutout_path: null, lat: null, lng: null, location_name: null };
    expect(await reuseOwnedSticker(supabase, "u1", "w1", enc)).toBe("s1");
    expect(await reuseOwnedSticker(supabase, "u1", "w1", enc)).toBe("s1");
    expect(encounters).toHaveLength(1);
  });
});
