import { beforeEach, describe, expect, it } from "vitest";
import {
  bandGenLevels,
  bandLevels,
  fillEmptyLevelContent,
  isLevelBandKey,
  isLevelSection,
  levelBandKey,
  overlayLevelContent,
  splitLevelExtras,
} from "./level-content";
import { TOCFL_SCALE } from "./level-scale";
import {
  callerLevelBand,
  fillLevelContent,
  readLevelContent,
  resetLevelContentAvailability,
} from "./level-content.server";

/** 例文・チャンクの共有（オーナー決定 2026-10-25、docs/sharing-rules.md S1〜S8）。 */
describe("帯の鍵（S3）", () => {
  it("現状の帯 > 目標の帯（1・2 = A、3・4 = B、5・6 = C）", () => {
    expect(levelBandKey({ current: "TOCFL-1", goal: "TOCFL-2" })).toBe("A>A");
    expect(levelBandKey({ current: "TOCFL-2", goal: "TOCFL-3" })).toBe("A>B");
    expect(levelBandKey({ current: "TOCFL-1", goal: "TOCFL-4" })).toBe("A>B");
    expect(levelBandKey({ current: "TOCFL-5", goal: "TOCFL-6" })).toBe("C>C");
    expect(levelBandKey({ current: "TOCFL-3", goal: "TOCFL-5" })).toBe("B>C");
  });

  it("レベル1の人とレベル5の人は別の帯", () => {
    expect(levelBandKey({ current: "TOCFL-1", goal: "TOCFL-2" })).not.toBe(
      levelBandKey({ current: "TOCFL-5", goal: "TOCFL-6" }),
    );
  });

  it("現状が空なら目標の1つ下、目標が読めなければ2級", () => {
    expect(levelBandKey({ current: null, goal: "TOCFL-3" })).toBe("A>B");
    expect(levelBandKey({ current: null, goal: "TOCFL-5" })).toBe("B>C");
    expect(levelBandKey({ current: "", goal: "" })).toBe("A>A");
  });

  it("形の確かめ（DB の CHECK と同じ）", () => {
    expect(isLevelBandKey("A>B")).toBe(true);
    expect(isLevelBandKey("legacy")).toBe(false);
    expect(isLevelBandKey("D>A")).toBe(false);
  });
});

describe("帯の代表の級（S7）", () => {
  it("現状 = 現状の帯の下の級、目標 = 目標の帯の上の級", () => {
    expect(bandLevels("A>B", TOCFL_SCALE)).toEqual({ current: "TOCFL-1", goal: "TOCFL-4" });
    expect(bandLevels("C>C", TOCFL_SCALE)).toEqual({ current: "TOCFL-5", goal: "TOCFL-6" });
  });
  it("控えの印は古い形と混ざらない", () => {
    expect(bandGenLevels("A>B")).toBe("band:A>B");
  });
});

describe("レベルで分ける項目（S2）", () => {
  it("例文とチャンクだけ。意味・量詞・関連語・台湾メモは言語の置き場", () => {
    const { level, rest } = splitLevelExtras({
      example_scene: "s",
      examples_extra: [],
      usage_chunks: [],
      example_chunks: [],
      measure_words: [],
      related_words: [],
      taiwan_note: "n",
      usage_context: "c",
      explain_lang: "ja",
    });
    expect(Object.keys(level).sort()).toEqual(
      ["example_chunks", "example_scene", "examples_extra", "usage_chunks"].sort(),
    );
    expect(Object.keys(rest).sort()).toEqual(
      ["explain_lang", "measure_words", "related_words", "taiwan_note", "usage_context"].sort(),
    );
    expect(isLevelSection("example")).toBe(true);
    expect(isLevelSection("usage_chunks")).toBe(true);
    expect(isLevelSection("measure_words")).toBe(false);
  });

  it("重ねると、言語の置き場の例文・チャンクは消え、帯の行の物だけになる（S6）", () => {
    const reader = { usage_chunks: [{ ja: "old" }], taiwan_note: "n" };
    expect(overlayLevelContent(reader, null)).toEqual({ taiwan_note: "n" });
    expect(
      overlayLevelContent(reader, {
        level_band: "A>B",
        example_sentence: "s",
        example_translation: null,
        extras: { usage_chunks: [{ ja: "new" }], taiwan_note: "x" },
      }),
    ).toEqual({ taiwan_note: "n", usage_chunks: [{ ja: "new" }] });
  });
});

describe("帯の行の空きだけ埋める", () => {
  const card = {
    example_sentence: "我騎腳踏車上學。",
    example_translation: "I ride a bike to school.",
    extras: { example_scene: "school", usage_chunks: [{ ja: "ride" }], measure_words: [{ word: "一台" }] },
  };

  it("何も無い行: 文・訳・札・チャンクを入れる（ほかの項目は入れない）", () => {
    expect(fillEmptyLevelContent(null, card)).toEqual({
      example_sentence: "我騎腳踏車上學。",
      example_translation: "I ride a bike to school.",
      extras: { example_scene: "school", usage_chunks: [{ ja: "ride" }] },
    });
  });

  it("文が在る行: 別の文の札・訳は入れず、空のチャンクだけ入れる", () => {
    const current = {
      level_band: "A>B",
      example_sentence: "腳踏車壞了。",
      example_translation: null,
      extras: {},
    };
    expect(fillEmptyLevelContent(current, card)).toEqual({ extras: { usage_chunks: [{ ja: "ride" }] } });
  });

  it("全部埋まっていれば書かない", () => {
    const current = {
      level_band: "A>B",
      example_sentence: "我騎腳踏車上學。",
      example_translation: "t",
      extras: { example_scene: "x", usage_chunks: [{ ja: "x" }] },
    };
    expect(fillEmptyLevelContent(current, card)).toBeNull();
  });
});

/** DB の偽物（使う形だけ）。 */
function fakeAdmin(opts: {
  stickers?: { level_band: string | null }[];
  stickersError?: { message: string; code?: string };
  rows?: Record<string, unknown>[];
}) {
  const writes: { table: string; op: string; value: unknown }[] = [];
  const chain = (result: () => unknown) => {
    const q: Record<string, unknown> = {};
    for (const m of ["select", "eq", "is", "order", "limit"]) q[m] = () => q;
    q.then = (res: (v: unknown) => unknown, rej?: (e: unknown) => unknown) =>
      Promise.resolve(result()).then(res, rej);
    return q;
  };
  const admin = {
    from(table: string) {
      return {
        select: () =>
          chain(() =>
            table === "stickers"
              ? opts.stickersError
                ? { data: null, error: opts.stickersError }
                : { data: opts.stickers ?? [], error: null }
              : { data: opts.rows ?? [], error: null },
          ),
        update: (value: unknown) => {
          writes.push({ table, op: "update", value });
          return chain(() => ({ data: null, error: null }));
        },
        upsert: (value: unknown) => {
          writes.push({ table, op: "upsert", value });
          return Promise.resolve({ data: null, error: null });
        },
      };
    },
  };
  return { admin, writes };
}

describe("札の帯（S4）と移行の前", () => {
  beforeEach(() => resetLevelContentAvailability());

  it("列がまだ無ければ、全員を古い語として扱う（今までどおり）", async () => {
    const { admin } = fakeAdmin({ stickersError: { message: "column stickers.level_band does not exist", code: "42703" } });
    expect(await callerLevelBand(admin, "u", "w")).toBeNull();
  });

  it("legacy の札は古い語、帯の付いた札はその帯（後でレベルを変えても変わらない）", async () => {
    expect(await callerLevelBand(fakeAdmin({ stickers: [{ level_band: "legacy" }] }).admin, "u", "w")).toBeNull();
    resetLevelContentAvailability();
    expect(await callerLevelBand(fakeAdmin({ stickers: [{ level_band: "C>C" }] }).admin, "u", "w")).toBe("C>C");
  });
});

describe("帯の行の読み書き", () => {
  beforeEach(() => resetLevelContentAvailability());
  const key = { explainLang: "en", l1: "en" };

  it("ぴったりの行を先に、無ければ同じ言語・同じ帯の行。別の言語には落ちない（問い合わせが言語で絞る）", async () => {
    const rows = [
      { l1: "ja", level_band: "A>B", example_sentence: "a", example_translation: null, extras: {} },
      { l1: "en", level_band: "A>B", example_sentence: "b", example_translation: null, extras: {} },
    ];
    expect((await readLevelContent(fakeAdmin({ rows }).admin, "w", key, "A>B"))?.example_sentence).toBe("b");
    expect(
      (await readLevelContent(fakeAdmin({ rows: [rows[0]] }).admin, "w", key, "A>B"))?.example_sentence,
    ).toBe("a");
    expect(await readLevelContent(fakeAdmin({ rows: [rows[0]] }).admin, "w", key, "A>B", { exact: true })).toBeNull();
  });

  it("作ったカードで空の行を作る。読む人の言語でない訳は入れない", async () => {
    const { admin, writes } = fakeAdmin({ rows: [] });
    await fillLevelContent(admin, "w", key, "A>B", {
      example_sentence: "我騎腳踏車上學。",
      example_translation: "自転車で通学する。",
      extras: { usage_chunks: [{ parts: [], ja: "ride a bike" }], taiwan_note: "n" },
    });
    expect(writes).toHaveLength(1);
    const v = writes[0].value as Record<string, unknown>;
    expect(v).toMatchObject({ word_id: "w", explain_lang: "en", l1: "en", level_band: "A>B" });
    expect(v.example_sentence).toBe("我騎腳踏車上學。");
    expect(v.example_translation).toBeNull();
    expect(Object.keys(v.extras as object)).toEqual(["usage_chunks"]);
  });
});
