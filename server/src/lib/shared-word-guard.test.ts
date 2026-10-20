/**
 * 共有の語を、画面の送った中身で書き換えさせない（監査 2026-10-03）。
 * 判定（`shared-word-guard.ts`）と、それを使う保存の道（`applyWordExtrasUpdate`・
 * `upsertWord`）を、偽の DB で動かして確かめる。
 */
import { beforeEach, describe, expect, it, vi } from "vitest";

const adminMock = vi.hoisted(() => ({ current: null as unknown }));
const distractors = vi.hoisted(() => vi.fn(async () => {}));
vi.mock("@/integrations/supabase/auth-middleware", () => ({ requireSupabaseAuth: {} }));
vi.mock("@/integrations/supabase/client.server", () => ({
  get supabaseAdmin() {
    return adminMock.current;
  },
}));
// 誤答の作り置きは AI を呼ぶので偽物にする（何を渡したかだけ見る）。
vi.mock("./reviews.functions", () => ({ pregenerateDistractors: distractors }));
vi.mock("./ai-provider.server", async (orig) => ({
  ...(await orig<typeof import("./ai-provider.server")>()),
  getExplanationLanguage: vi.fn(async () => "en"),
}));

beforeEach(() => distractors.mockClear());

import {
  BoundedExtrasSchema,
  EXTRAS_LIMITS,
  WordInputSchema,
  fillEmptySharedColumns,
  fillEmptySharedExtras,
  fillReaderExplanation,
  isExplanationLangCode,
  jsonBoundsProblem,
  sharedColumnsFromCard,
} from "./shared-word-guard";
import {
  applyWordExtrasUpdate,
  upsertWord,
  type UpdateWordExtrasData,
  type WordUpsertInput,
} from "./stickers.functions";

describe("fillEmptySharedColumns（共有の列は空の所だけ埋める）", () => {
  const full = {
    meaning_ja: "自転車",
    reading_zhuyin: "ㄐㄧㄠˇ ㄊㄚˋ ㄔㄜ",
    pinyin: "jiǎotàchē",
    part_of_speech: "名詞",
    level: "TOCFL-2",
    example_sentence: "我騎腳踏車上學。",
    example_translation: "自転車で通学する。",
  };

  it("埋まっている列は、何を送っても書き換えない", () => {
    expect(
      fillEmptySharedColumns(
        full,
        { meaning_ja: "悪意のある意味", example_sentence: "書き換え", level: "TOCFL-7" },
        { verified: false },
      ),
    ).toEqual({});
  });

  it("空の列だけ、送られた値で埋める（空白だけの列も空とみなす）", () => {
    expect(
      fillEmptySharedColumns(
        { ...full, example_sentence: null, example_translation: "  " },
        {
          meaning_ja: "別の意味",
          example_sentence: "我每天騎腳踏車。",
          example_translation: "毎日自転車に乗る。",
        },
        { verified: false },
      ),
    ).toEqual({ example_sentence: "我每天騎腳踏車。", example_translation: "毎日自転車に乗る。" });
  });

  it("人が確かめた語は、空の列でも書かない", () => {
    expect(
      fillEmptySharedColumns({}, { meaning_ja: "意味", pinyin: "x" }, { verified: true }),
    ).toEqual({});
  });

  it("空の値・知らない鍵は書かない", () => {
    expect(
      fillEmptySharedColumns(
        {},
        { meaning_ja: "", pinyin: "  ", source: "verified", created_by: "me" },
        { verified: false },
      ),
    ).toEqual({});
  });
});

describe("fillEmptySharedExtras（共有の解説も空の項目だけ）", () => {
  const ja = {
    explain_lang: "ja",
    usage_context: "通学のとき",
    mnemonic: "",
    speaking_scaffold_x: { keep: true },
  };

  it("空の解説には、送られた物を丸ごと入れる（知らない鍵は残す）", () => {
    const out = fillEmptySharedExtras(
      { speaking_scaffold_x: 1 },
      {
        explain_lang: "en",
        usage_context: "commuting",
      },
    );
    expect(out).toEqual({ speaking_scaffold_x: 1, explain_lang: "en", usage_context: "commuting" });
  });

  it("中身のある解説の項目は上書きしない。同じ言語の空の項目だけ足す", () => {
    const out = fillEmptySharedExtras(ja, {
      explain_lang: "ja",
      usage_context: "書き換え",
      mnemonic: "足で踏む車",
    });
    expect(out).toEqual({ ...ja, mnemonic: "足で踏む車" });
  });

  it("言語の違う解説は混ぜない", () => {
    expect(fillEmptySharedExtras(ja, { explain_lang: "en", mnemonic: "pedal car" })).toBeNull();
  });

  it("足す物が無ければ null（書きに行かない）", () => {
    expect(fillEmptySharedExtras(ja, { explain_lang: "ja", usage_context: "別" })).toBeNull();
    expect(fillEmptySharedExtras(ja, { explain_lang: "ja" })).toBeNull();
  });
});

describe("大きさの上限", () => {
  it("普通のカードは通す", () => {
    const card = {
      usage_context: "通学のとき",
      examples_extra: Array.from({ length: 3 }, () => ({
        zh: "我騎腳踏車。",
        ja: "自転車に乗る。",
        chunks: [{ text: "騎", pos: "V", alts: [{ text: "坐", ja: "座る" }] }],
      })),
    };
    expect(jsonBoundsProblem(card)).toBeNull();
    expect(BoundedExtrasSchema.parse(card).usage_context).toBe("通学のとき");
  });

  it("長すぎる文字列・多すぎる配列・多すぎる鍵・深すぎる入れ子・大きすぎる全体を断る", () => {
    const long = "あ".repeat(EXTRAS_LIMITS.maxStringChars + 1);
    expect(() => BoundedExtrasSchema.parse({ trivia: long })).toThrow();
    expect(() =>
      BoundedExtrasSchema.parse({ synonyms: Array(EXTRAS_LIMITS.maxArrayItems + 1).fill("x") }),
    ).toThrow();
    const many = Object.fromEntries(
      Array.from({ length: EXTRAS_LIMITS.maxObjectKeys + 1 }, (_, i) => [`k${i}`, 1]),
    );
    expect(() => BoundedExtrasSchema.parse(many)).toThrow();
    let deep: unknown = "x";
    for (let i = 0; i < EXTRAS_LIMITS.maxDepth + 2; i++) deep = { d: deep };
    expect(jsonBoundsProblem(deep)).toMatch(/deep/);
    const big = {
      synonyms: Array(EXTRAS_LIMITS.maxArrayItems).fill("x".repeat(EXTRAS_LIMITS.maxStringChars)),
    };
    expect(jsonBoundsProblem(big)).toMatch(/too large/);
  });

  it("語の入力の文字列にも上限がある（見出し・意味・例文・品詞・級・分類）", () => {
    const ok = { headword: "腳踏車", meaning_ja: "自転車", category_key: "vehicle" };
    expect(WordInputSchema.parse(ok).part_of_speech).toBe("名詞");
    for (const [k, n] of [
      ["headword", 101],
      ["meaning_ja", 1001],
      ["example_sentence", 2001],
      ["part_of_speech", 101],
      ["level", 61],
      ["category_key", 65],
    ] as const) {
      expect(() => WordInputSchema.parse({ ...ok, [k]: "x".repeat(n) })).toThrow();
    }
  });

  it("解説の行の鍵は言語の符号だけ", () => {
    for (const v of ["", "ja", "en", "zh-TW", "ko"]) expect(isExplanationLangCode(v)).toBe(true);
    for (const v of ["日本語", "ja; drop table", "x".repeat(20), 3])
      expect(isExplanationLangCode(v)).toBe(false);
  });
});

// --- 保存の道を偽の DB で動かす ------------------------------------------------

type Row = Record<string, unknown>;
type DbError = { message: string; code?: string } | null;

/**
 * 偽の DB。`words` の1行・控え（`generated_cards`）・辞書を持ち、書いた物を覚える。
 * `receipts: "missing"` は控えの表がまだ無い環境（移行待ち）。
 */
function fakeDb(opts: {
  owns?: boolean;
  word?: Row | null;
  existingId?: string | null;
  receipts?: Row[] | "missing";
  dictionary?: Row[];
  insertError?: DbError;
  afterRaceId?: string;
}) {
  const updates: Row[] = [];
  const inserts: Row[] = [];
  let wordLookups = 0;
  const chain = (result: () => unknown) => {
    const c: Record<string, unknown> = {};
    for (const m of ["select", "eq", "limit", "in", "order"]) c[m] = () => c;
    c.maybeSingle = async () => result();
    c.single = async () => result();
    c.gte = async () => result();
    c.then = (res: (v: unknown) => unknown, rej: (e: unknown) => unknown) =>
      Promise.resolve(result()).then(res, rej);
    return c;
  };
  const user = {
    from: (t: string) => {
      if (t === "stickers")
        return chain(() => ({ data: opts.owns ? { id: "s1" } : null, error: null }));
      if (t === "categories") return chain(() => ({ data: { key: "vehicle" }, error: null }));
      if (t === "words")
        return chain(() => {
          wordLookups++;
          if (wordLookups > 1 && opts.afterRaceId) return { data: { id: opts.afterRaceId } };
          return { data: opts.existingId ? { id: opts.existingId } : null };
        });
      throw new Error(`unexpected user table ${t}`);
    },
  };
  const admin = {
    from: (t: string) => {
      if (t === "generated_cards") {
        return chain(() =>
          opts.receipts === "missing"
            ? {
                data: null,
                error: {
                  code: "PGRST205",
                  message: "Could not find the table 'public.generated_cards'",
                },
              }
            : { data: opts.receipts ?? [], error: null },
        );
      }
      if (t === "dictionary_entries")
        return chain(() => ({ data: opts.dictionary ?? [], error: null }));
      if (t === "profiles") return chain(() => ({ data: null, error: null }));
      if (t !== "words") throw new Error(`unexpected ${t}`);
      return {
        ...chain(() => ({ data: opts.word ?? null, error: null })),
        update: (row: Row) => {
          updates.push(row);
          return { eq: async () => ({ error: null }) };
        },
        insert: (row: Row) => {
          inserts.push(row);
          return chain(() =>
            opts.insertError
              ? { data: null, error: opts.insertError }
              : { data: { id: "new" }, error: null },
          );
        },
      };
    },
  };
  return { user, admin, updates, inserts };
}

const receipt = (over: Row = {}): Row => ({
  language: "zh-TW",
  headword: "腳踏車",
  explain_lang: "en",
  l1: "en",
  kind: "card",
  card: {
    meaning_ja: "bicycle (server)",
    example_sentence: "我騎腳踏車上學。",
    example_translation: "I ride a bike to school.",
    level: "TOCFL-2",
    extras: { explain_lang: "en", explain_l1: "en", usage_context: "commuting (server)" },
  },
  created_at: new Date().toISOString(),
  ...over,
});

const sharedWord = {
  id: "w1",
  headword: "腳踏車",
  language: "zh-TW",
  source: "ai",
  meaning_ja: "自転車",
  reading_zhuyin: "ㄐㄧㄠˇ ㄊㄚˋ ㄔㄜ",
  pinyin: "jiǎotàchē",
  part_of_speech: "名詞",
  level: "TOCFL-2",
  example_sentence: "",
  example_translation: null,
  extras: { explain_lang: "ja", usage_context: "通学のとき" },
};

/** 画面（あるいはアプリを通さない呼び出し）が送る、悪意のある中身。 */
const req = (over: Partial<UpdateWordExtrasData> = {}): UpdateWordExtrasData =>
  ({
    word_id: "00000000-0000-0000-0000-000000000001",
    extras: BoundedExtrasSchema.parse({
      explain_lang: "en",
      explain_l1: "en",
      usage_context: "ATTACKER TEXT",
      mnemonic: "ATTACKER TEXT",
    }),
    ...over,
  }) as UpdateWordExtrasData;

describe("applyWordExtrasUpdate（updateWordExtras の中身）", () => {
  const deps = (db: ReturnType<typeof fakeDb>, save = vi.fn(async () => ({ saved: true }))) => ({
    deps: { supabase: db.user, admin: db.admin, saveExplanation: save },
    save,
  });

  it("札を持っていない人は何も書けない", async () => {
    const db = fakeDb({ owns: false, word: sharedWord, receipts: [receipt()] });
    const { deps: d, save } = deps(db);
    await expect(applyWordExtrasUpdate(d, "u", req())).rejects.toThrow("権限がありません");
    expect(db.updates).toEqual([]);
    expect(save).not.toHaveBeenCalled();
  });

  it("送られた文は使わず、サーバの控えで空の所だけ埋める（H2）", async () => {
    const db = fakeDb({ owns: true, word: sharedWord, receipts: [receipt()] });
    const { deps: d, save } = deps(db);
    const r = await applyWordExtrasUpdate(
      d,
      "u",
      req({
        patch: { meaning_ja: "ATTACKER", example_sentence: "ATTACKER", level: "TOCFL-9" },
        reader_meaning: "ATTACKER",
      }),
    );
    expect(r.ok).toBe(true);
    // 共有の行: 埋まっている意味・級はそのまま、空の例文と訳だけを**控えの中身**で。
    // 英語の解説は日本語の共有の解説に混ぜない。
    expect(db.updates).toEqual([
      { example_sentence: "我騎腳踏車上學。", example_translation: "I ride a bike to school." },
    ]);
    // 読む人の行: 控えの意味と解説。送られた文はどこにも無い。
    expect(save).toHaveBeenCalledTimes(1);
    const arg = (save.mock.calls[0] as unknown[])[0] as Row;
    expect(arg).toMatchObject({
      explain_lang: "en",
      l1: "en",
      meaning: "bicycle (server)",
      example_translation: "I ride a bike to school.",
    });
    expect(JSON.stringify(arg)).not.toContain("ATTACKER");
    expect((arg.extras as Row).usage_context).toBe("commuting (server)");
  });

  it("別の言語の共有の解説は、読む人の行に混ぜない", async () => {
    const db = fakeDb({
      owns: true,
      word: { ...sharedWord, extras: { explain_lang: "ja", mnemonic: "足で踏む車" } },
      receipts: [receipt()],
    });
    const { deps: d, save } = deps(db);
    await applyWordExtrasUpdate(d, "u", req());
    const extras = ((save.mock.calls[0] as unknown[])[0] as Row).extras as Row;
    expect(extras.mnemonic).toBeUndefined();
    expect(extras.explain_lang).toBe("en");
  });

  it("同じ言語の共有の解説が見えていた語は、見えていた項目を残す（R14）", async () => {
    const db = fakeDb({
      owns: true,
      word: {
        ...sharedWord,
        extras: { explain_lang: "en", usage_context: "shown before", mnemonic: "" },
      },
      receipts: [
        receipt({
          card: {
            meaning_ja: "bicycle",
            extras: { usage_context: "new text", mnemonic: "pedal car" },
          },
        }),
      ],
    });
    const { deps: d, save } = deps(db);
    await applyWordExtrasUpdate(d, "u", req());
    const extras = ((save.mock.calls[0] as unknown[])[0] as Row).extras as Row;
    expect(extras.usage_context).toBe("shown before");
    expect(extras.mnemonic).toBe("pedal car");
    // 共有の行: 空だった mnemonic だけ足す。
    expect(db.updates).toEqual([
      { extras: { explain_lang: "en", usage_context: "shown before", mnemonic: "pedal car" } },
    ]);
  });

  it("鍵の合う控えが無ければ、共有の行にも読む人の行にも書かない", async () => {
    const db = fakeDb({
      owns: true,
      word: sharedWord,
      // 別の鍵（日本語で読む人）のカードと、鍵の無い候補だけ。
      receipts: [
        receipt({ explain_lang: "ja", l1: "ja" }),
        receipt({ kind: "candidate", explain_lang: "", l1: "" }),
      ],
    });
    const { deps: d, save } = deps(db);
    const r = await applyWordExtrasUpdate(d, "u", req({ patch: { example_sentence: "ATTACKER" } }));
    expect(r).toEqual({ ok: true, saved: false });
    expect(db.updates).toEqual([]);
    expect(save).not.toHaveBeenCalled();
  });

  it("控えの表がまだ無い環境だけ、前の動き（送られた物で空の所だけ）", async () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    const db = fakeDb({ owns: true, word: sharedWord, receipts: "missing" });
    const { deps: d, save } = deps(db);
    await applyWordExtrasUpdate(
      d,
      "u",
      req({
        patch: { meaning_ja: "bicycle", example_sentence: "我騎腳踏車。", level: "TOCFL-9" },
        reader_meaning: "bicycle",
      }),
    );
    expect(db.updates).toEqual([{ example_sentence: "我騎腳踏車。" }]);
    expect(save).toHaveBeenCalledWith(
      expect.objectContaining({ explain_lang: "en", l1: "en", meaning: "bicycle" }),
    );
    warn.mockRestore();
  });

  it("人が確かめた語は、共有の列を空でも書かない（解説の空の項目と読む人の行は置く）", async () => {
    const db = fakeDb({
      owns: true,
      word: { ...sharedWord, source: "verified", extras: { explain_lang: "en" } },
      receipts: [receipt()],
    });
    const { deps: d, save } = deps(db);
    await applyWordExtrasUpdate(d, "u", req({ patch: { example_sentence: "x" } }));
    expect(db.updates).toHaveLength(1);
    expect(db.updates[0]).not.toHaveProperty("example_sentence");
    expect((db.updates[0].extras as Row).usage_context).toBe("commuting (server)");
    expect(save).toHaveBeenCalledTimes(1);
  });

  it("言語の符号でない鍵の解説は、何も書く前に断る", async () => {
    const db = fakeDb({ owns: true, word: sharedWord, receipts: [receipt()] });
    const { deps: d, save } = deps(db);
    const bad = req();
    (bad.extras as Record<string, unknown>).explain_lang = "<script>";
    await expect(applyWordExtrasUpdate(d, "u", bad)).rejects.toThrow();
    expect(db.updates).toEqual([]);
    expect(save).not.toHaveBeenCalled();
  });
});

describe("upsertWord（新しい語の行はサーバの中身だけ — M3 / M4）", () => {
  const word = (over: Partial<WordUpsertInput> = {}): WordUpsertInput =>
    ({
      headword: "腳踏車",
      meaning_ja: "ATTACKER MEANING",
      reading_zhuyin: "ATTACKER",
      level: "TOCFL-9",
      part_of_speech: "名詞",
      category_key: "vehicle",
      example_sentence: "ATTACKER EXAMPLE",
      extras: BoundedExtrasSchema.parse({ explain_lang: "en", usage_context: "ATTACKER" }),
      ...over,
    }) as WordUpsertInput;

  it("控えがあれば、その中身で行を作る（送られた文は入れない）", async () => {
    const db = fakeDb({ receipts: [receipt()] });
    adminMock.current = db.admin;
    const id = await upsertWord(db.user, "u", word(), "zh-TW");
    expect(id).toBe("new");
    expect(db.inserts).toHaveLength(1);
    const row = db.inserts[0];
    expect(row).toMatchObject({
      language: "zh-TW",
      headword: "腳踏車",
      meaning_ja: "bicycle (server)",
      example_sentence: "我騎腳踏車上學。",
      level: "TOCFL-2",
      reading_zhuyin: null,
      created_by: "u",
      source: "ai",
    });
    expect(JSON.stringify(row)).not.toContain("ATTACKER");
    // 誤答の作り置きにも、共有の行に入れた意味を渡す。
    expect(distractors).toHaveBeenCalledWith(
      db.user,
      "u",
      "new",
      "腳踏車",
      "bicycle (server)",
      expect.any(String),
      "zh-TW",
    );
  });

  it("控えが無ければ辞書から（読む人の言語の意味・読み・品詞）", async () => {
    const db = fakeDb({
      receipts: [],
      dictionary: [
        {
          headword: "腳踏車",
          zhuyin: "ㄐㄧㄠˇ ㄊㄚˋ ㄔㄜ",
          pinyin: "jiǎotàchē",
          meaning_ja: "自転車",
          meanings: { en: "bicycle", ja: "自転車" },
          pos: "N",
        },
      ],
    });
    adminMock.current = db.admin;
    await upsertWord(db.user, "u", word(), "zh-TW");
    expect(db.inserts[0]).toMatchObject({
      meaning_ja: "bicycle",
      reading_zhuyin: "ㄐㄧㄠˇ ㄊㄚˋ ㄔㄜ",
      pinyin: "jiǎotàchē",
      part_of_speech: "N",
      example_sentence: null,
      level: null,
      extras: {},
    });
    expect(JSON.stringify(db.inserts[0])).not.toContain("ATTACKER");
  });

  it("どちらも無ければ見出しだけの行（後からサーバの生成が埋める）。誤答は作らない", async () => {
    const db = fakeDb({ receipts: [] });
    adminMock.current = db.admin;
    await upsertWord(db.user, "u", word(), "zh-TW");
    expect(db.inserts[0]).toMatchObject({
      headword: "腳踏車",
      meaning_ja: "",
      reading_zhuyin: null,
      example_sentence: null,
      extras: {},
    });
    expect(distractors).not.toHaveBeenCalled();
  });

  it("控えの表がまだ無い環境だけ、前の動き（送られた中身）", async () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    const db = fakeDb({ receipts: "missing" });
    adminMock.current = db.admin;
    await upsertWord(db.user, "u", word({ meaning_ja: "自転車", example_sentence: "" }), "zh-TW");
    expect(db.inserts[0]).toMatchObject({ meaning_ja: "自転車", level: "TOCFL-9" });
    warn.mockRestore();
  });

  it("同じ新しい語を2人が同時に作った（一意の制約）→ 探し直してその行を使う", async () => {
    const db = fakeDb({
      receipts: [receipt()],
      insertError: { code: "23505", message: "duplicate key value violates unique constraint" },
      afterRaceId: "theirs",
    });
    adminMock.current = db.admin;
    await expect(upsertWord(db.user, "u", word(), "zh-TW")).resolves.toBe("theirs");
    expect(distractors).not.toHaveBeenCalled();
  });

  it("一意の制約以外の失敗は今までどおり投げる", async () => {
    const db = fakeDb({ receipts: [receipt()], insertError: { message: "boom" } });
    adminMock.current = db.admin;
    await expect(upsertWord(db.user, "u", word(), "zh-TW")).rejects.toThrow("boom");
  });
});

describe("upsertWord（既に在る語に、キャッチの解説を足す）", () => {
  const word = (extras: Record<string, unknown>): WordUpsertInput =>
    ({
      headword: "腳踏車",
      meaning_ja: "悪意のある意味",
      category_key: "vehicle",
      extras: BoundedExtrasSchema.parse(extras),
    }) as WordUpsertInput;

  it("埋まっている共有の解説の項目は上書きせず、空の項目だけ**控えの中身で**足す", async () => {
    const db = fakeDb({
      existingId: "w1",
      word: { extras: { explain_lang: "zh-TW", usage_context: "上學" } },
      receipts: [
        receipt({
          explain_lang: "zh-TW",
          l1: "zh-TW",
          card: {
            meaning_ja: "自行車",
            extras: { explain_lang: "zh-TW", usage_context: "伺服器", mnemonic: "腳踩的車" },
          },
        }),
      ],
    });
    adminMock.current = db.admin;
    const id = await upsertWord(
      db.user,
      "u",
      word({ explain_lang: "zh-TW", usage_context: "書き換え", mnemonic: "ATTACKER" }),
      "zh-TW",
    );
    expect(id).toBe("w1");
    expect(db.updates).toHaveLength(1);
    const extras = db.updates[0].extras as Record<string, unknown>;
    expect(extras.usage_context).toBe("上學");
    expect(extras.mnemonic).toBe("腳踩的車");
    // 共有の意味などの列には触らない。
    expect(Object.keys(db.updates[0])).toEqual(["extras"]);
  });

  it("控えが無ければ、送られた解説は書かない", async () => {
    const db = fakeDb({
      existingId: "w1",
      word: { extras: { explain_lang: "zh-TW" } },
      receipts: [],
    });
    adminMock.current = db.admin;
    await upsertWord(db.user, "u", word({ explain_lang: "zh-TW", mnemonic: "ATTACKER" }), "zh-TW");
    expect(db.updates).toEqual([]);
  });

  it("足す物が無ければ書きに行かない", async () => {
    const db = fakeDb({
      existingId: "w1",
      word: { extras: { explain_lang: "zh-TW", usage_context: "上學" } },
      receipts: [
        receipt({
          card: { meaning_ja: "x", extras: { explain_lang: "ja", mnemonic: "x" } },
        }),
      ],
    });
    adminMock.current = db.admin;
    await upsertWord(db.user, "u", word({ explain_lang: "ja", mnemonic: "x" }), "zh-TW");
    expect(db.updates).toEqual([]);
  });
});

describe("sharedColumnsFromCard", () => {
  it("共有の列の空でない文字列だけ", () => {
    expect(
      sharedColumnsFromCard({
        meaning_ja: " 自転車 ",
        pinyin: "",
        level: 3,
        source: "verified",
        example_sentence: "我騎車。",
      }),
    ).toEqual({ meaning_ja: "自転車", example_sentence: "我騎車。" });
    expect(sharedColumnsFromCard(null)).toEqual({});
  });
});

describe("fillReaderExplanation（読む人ごとの解説の行も空の所だけ — H2）", () => {
  const incoming = {
    meaning: "bicycle",
    example_translation: "I ride to school.",
    extras: { explain_lang: "en", usage_context: "commuting", mnemonic: "pedal car" },
  };

  it("行が無ければ置く", () => {
    expect(fillReaderExplanation(null, incoming, "en")).toEqual({ kind: "insert", row: incoming });
  });

  it("人が確かめた行は触らない", () => {
    expect(fillReaderExplanation({ source: "verified", meaning: "" }, incoming, "en")).toEqual({
      kind: "skip",
      reason: "verified",
    });
  });

  it("埋まっている意味・訳・項目は上書きしない。空の項目だけ足す", () => {
    const w = fillReaderExplanation(
      {
        source: "ai",
        meaning: "bike",
        example_translation: "To school by bike.",
        extras: { explain_lang: "en", usage_context: "going to school" },
      },
      incoming,
      "en",
    );
    expect(w).toEqual({
      kind: "update",
      patch: {
        extras: { explain_lang: "en", usage_context: "going to school", mnemonic: "pedal car" },
      },
    });
  });

  it("読む人の言語で書かれていない意味（昔写した共有の意味）と訳は埋め直す", () => {
    const w = fillReaderExplanation(
      { source: "ai", meaning: "自転車", example_translation: "自転車で通学する。", extras: {} },
      incoming,
      "en",
    );
    expect(w.kind).toBe("update");
    if (w.kind === "update") {
      expect(w.patch.meaning).toBe("bicycle");
      expect(w.patch.example_translation).toBe("I ride to school.");
      expect(w.patch.extras).toEqual(incoming.extras);
    }
  });

  it("別の言語の解説が載った壊れた行は、解説を入れ替える", () => {
    const w = fillReaderExplanation(
      {
        source: "ai",
        meaning: "bicycle",
        example_translation: "I ride to school.",
        extras: { explain_lang: "ja", usage_context: "通学" },
      },
      incoming,
      "en",
    );
    expect(w).toEqual({
      kind: "update",
      patch: { extras: { explain_lang: "en", usage_context: "commuting", mnemonic: "pedal car" } },
    });
  });

  it("解説（note）の無い関連語は空とみなして埋める（keepShownFields と同じ）", () => {
    const w = fillReaderExplanation(
      {
        source: "ai",
        meaning: "bicycle",
        example_translation: "I ride to school.",
        extras: { explain_lang: "en", related_words: [{ word: "單車", note: "" }] },
      },
      {
        ...incoming,
        extras: { explain_lang: "en", related_words: [{ word: "單車", note: "casual" }] },
      },
      "en",
    );
    expect(w).toEqual({
      kind: "update",
      patch: { extras: { explain_lang: "en", related_words: [{ word: "單車", note: "casual" }] } },
    });
  });

  it("足す物が無ければ書かない", () => {
    expect(
      fillReaderExplanation(
        {
          source: "ai",
          meaning: "bicycle",
          example_translation: "I ride to school.",
          extras: incoming.extras,
        },
        { ...incoming, meaning: "ATTACKER" },
        "en",
      ),
    ).toEqual({ kind: "skip", reason: "nothing" });
  });
});
