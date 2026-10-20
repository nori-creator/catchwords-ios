/**
 * サーバが作った語の中身の控え（監査 2026-10-03 H2 / M3、`generated-cards.ts`）。
 */
import { afterEach, describe, expect, it, vi } from "vitest";
import {
  GENERATED_CARD_TTL_MS,
  fillSharedWordFromCard,
  findGeneratedCard,
  isMissingGeneratedCardsTable,
  pickGeneratedCard,
  recordGeneratedCards,
  trustedCardFrom,
  type GeneratedCardRow,
} from "./generated-cards";

afterEach(() => vi.restoreAllMocks());

const NOW = Date.parse("2026-10-03T12:00:00Z");
const iso = (msAgo: number) => new Date(NOW - msAgo).toISOString();

describe("trustedCardFrom（控えに残す所だけ）", () => {
  it("知られた文字列の欄と extras だけを残す", () => {
    expect(
      trustedCardFrom({
        meaning_ja: " 自転車 ",
        pinyin: "jiǎotàchē",
        level: "",
        distinction: "足でこぐ",
        new_shelf: { key: "x" },
        extras: { usage_context: "通学" },
        source: "verified",
        example_sentence: 3,
      }),
    ).toEqual({ meaning_ja: "自転車", pinyin: "jiǎotàchē", extras: { usage_context: "通学" } });
  });

  it("形の違う物は空", () => {
    expect(trustedCardFrom(null)).toEqual({});
    expect(trustedCardFrom([1])).toEqual({});
    expect(trustedCardFrom({ extras: [1] })).toEqual({});
  });
});

describe("pickGeneratedCard", () => {
  const row = (over: Partial<GeneratedCardRow>): GeneratedCardRow => ({
    language: "zh-TW",
    headword: "腳踏車",
    explain_lang: "ja",
    l1: "ja",
    kind: "card",
    card: { meaning_ja: "自転車" },
    created_at: iso(1000),
    ...over,
  });

  it("鍵が無ければ、カード全体を候補より優先する（候補の方が新しくても）", () => {
    const picked = pickGeneratedCard(
      [
        row({
          kind: "candidate",
          explain_lang: "",
          l1: "",
          card: { meaning_ja: "候補" },
          created_at: iso(10),
        }),
        row({ card: { meaning_ja: "カード" }, created_at: iso(5000) }),
      ],
      { now: NOW },
    );
    expect(picked).toEqual({ card: { meaning_ja: "カード" }, kind: "card" });
  });

  it("カード同士なら、呼んだ人の解説の言語のカードを先に（古くても）", () => {
    const picked = pickGeneratedCard(
      [
        row({ explain_lang: "en", l1: "en", card: { meaning_ja: "bicycle" }, created_at: iso(10) }),
        row({ card: { meaning_ja: "自転車" }, created_at: iso(5000) }),
      ],
      { now: NOW, preferExplainLang: "ja" },
    );
    expect(picked?.card.meaning_ja).toBe("自転車");
  });

  it("同じ種類なら新しい方", () => {
    const picked = pickGeneratedCard(
      [
        row({
          explain_lang: "en",
          l1: "zh-TW",
          card: { meaning_ja: "old" },
          created_at: iso(5000),
        }),
        row({ card: { meaning_ja: "new" }, created_at: iso(10) }),
      ],
      { now: NOW },
    );
    expect(picked?.card.meaning_ja).toBe("new");
  });

  it("鍵を渡したら、その鍵のカード全体だけ（候補・別の鍵は使わない）", () => {
    const rows = [
      row({ kind: "candidate", explain_lang: "", l1: "", card: { meaning_ja: "候補" } }),
      row({ explain_lang: "en", l1: "en", card: { meaning_ja: "bicycle" } }),
    ];
    expect(pickGeneratedCard(rows, { explainLang: "ja", l1: "ja", now: NOW })).toBeNull();
    expect(
      pickGeneratedCard(rows, { explainLang: "en", l1: "en", now: NOW })?.card.meaning_ja,
    ).toBe("bicycle");
  });

  it("期限を過ぎた控えは使わない", () => {
    expect(
      pickGeneratedCard([row({ created_at: iso(GENERATED_CARD_TTL_MS + 1) })], { now: NOW }),
    ).toBeNull();
  });
});

describe("recordGeneratedCards", () => {
  function fakeAdmin(error: { message: string; code?: string } | null = null) {
    const upserts: Array<{ rows: Array<Record<string, unknown>>; opts: unknown }> = [];
    const admin = {
      from: (t: string) => {
        expect(t).toBe("generated_cards");
        return {
          upsert: async (rows: Array<Record<string, unknown>>, opts: unknown) => {
            upserts.push({ rows, opts });
            return { error };
          },
          delete: () => ({ lt: async () => ({ error: null }) }),
        };
      },
    };
    return { admin, upserts };
  }

  it("見出しごとに1行。同じ鍵は1つ。候補は鍵を持たない", async () => {
    vi.spyOn(Math, "random").mockReturnValue(0.5);
    const { admin, upserts } = fakeAdmin();
    const ok = await recordGeneratedCards(
      admin,
      [
        {
          language: "zh-TW",
          headword: "腳踏車",
          explainLang: "ja",
          l1: "ja",
          kind: "card",
          card: { meaning_ja: "自転車" },
        },
        {
          language: "zh-TW",
          headword: " 腳踏車 ",
          explainLang: "ja",
          l1: "ja",
          kind: "card",
          card: { meaning_ja: "自転車" },
        },
        {
          language: "zh-TW",
          headword: "單車",
          explainLang: "en",
          l1: "en",
          kind: "candidate",
          card: { meaning_ja: "bike" },
        },
        { language: "zh-TW", headword: "", kind: "card", card: { meaning_ja: "x" } },
        { language: "zh-TW", headword: "空", kind: "card", card: {} },
      ],
      new Date(NOW),
    );
    expect(ok).toBe(true);
    expect(upserts).toHaveLength(1);
    expect(upserts[0].opts).toEqual({ onConflict: "language,headword,explain_lang,l1" });
    expect(upserts[0].rows.map((r) => [r.headword, r.explain_lang, r.l1, r.kind])).toEqual([
      ["腳踏車", "ja", "ja", "card"],
      ["單車", "", "", "candidate"],
    ]);
  });

  it("表が無い・書けない時は投げずに false", async () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    const { admin } = fakeAdmin({ message: 'relation "public.generated_cards" does not exist' });
    await expect(
      recordGeneratedCards(admin, [
        { language: "en", headword: "bike", kind: "candidate", card: { meaning_ja: "自転車" } },
      ]),
    ).resolves.toBe(false);
    expect(warn).toHaveBeenCalled();
  });
});

describe("findGeneratedCard", () => {
  const admin = (result: { data: unknown; error: unknown } | Error) => ({
    from: () => ({
      select: () => ({
        eq: () => ({
          eq: () => ({
            gte: async () => {
              if (result instanceof Error) throw result;
              return result;
            },
          }),
        }),
      }),
    }),
  });

  it("表が無ければ available: false（呼ぶ側は前の動きに戻る）", async () => {
    expect(
      await findGeneratedCard(admin({ data: null, error: { code: "PGRST205", message: "x" } }), {
        language: "en",
        headword: "bike",
      }),
    ).toEqual({ available: false });
  });

  it("読めない時は available: true・中身なし（画面の文に戻らない）", async () => {
    vi.spyOn(console, "warn").mockImplementation(() => {});
    expect(
      await findGeneratedCard(admin({ data: null, error: { message: "timeout" } }), {
        language: "en",
        headword: "bike",
      }),
    ).toEqual({ available: true, card: null, kind: null });
    expect(
      await findGeneratedCard(admin(new Error("network")), { language: "en", headword: "bike" }),
    ).toEqual({ available: true, card: null, kind: null });
  });

  it("控えがあればそれ", async () => {
    const r = await findGeneratedCard(
      admin({
        data: [
          {
            language: "en",
            headword: "bike",
            explain_lang: "ja",
            l1: "ja",
            kind: "card",
            card: { meaning_ja: "自転車" },
            created_at: iso(10),
          },
        ],
        error: null,
      }),
      { language: "en", headword: "bike", now: NOW },
    );
    expect(r).toEqual({ available: true, card: { meaning_ja: "自転車" }, kind: "card" });
  });

  it("表が無いことの見分け", () => {
    expect(isMissingGeneratedCardsTable({ code: "42P01" })).toBe(true);
    expect(
      isMissingGeneratedCardsTable({
        message: "Could not find the table 'public.generated_cards'",
      }),
    ).toBe(true);
    expect(isMissingGeneratedCardsTable({ message: "timeout" })).toBe(false);
    expect(isMissingGeneratedCardsTable(null)).toBe(false);
  });
});

describe("fillSharedWordFromCard（既に在る語の空の所だけ）", () => {
  function fakeWords(rows: Array<Record<string, unknown>>) {
    const updates: Array<{ id: string; row: Record<string, unknown> }> = [];
    const admin = {
      from: (t: string) => {
        expect(t).toBe("words");
        return {
          select: () => ({ eq: () => ({ in: async () => ({ data: rows, error: null }) }) }),
          update: (row: Record<string, unknown>) => ({
            eq: async (_k: string, id: string) => {
              updates.push({ id, row });
              return { error: null };
            },
          }),
        };
      },
    };
    return { admin, updates };
  }

  it("空の列と空の解説だけを埋める。埋まっている列・人が確かめた語の列は触らない", async () => {
    const { admin, updates } = fakeWords([
      { id: "a", source: "ai", meaning_ja: "自転車", example_sentence: null, extras: {} },
      {
        id: "v",
        source: "verified",
        meaning_ja: "",
        extras: { explain_lang: "ja", mnemonic: "x" },
      },
    ]);
    const n = await fillSharedWordFromCard(admin, {
      language: "zh-TW",
      headwords: ["腳踏車", "腳踏車", ""],
      card: {
        meaning_ja: "書き換え",
        example_sentence: "我騎腳踏車。",
        extras: { explain_lang: "ja", usage_context: "通学" },
      },
    });
    expect(n).toBe(2);
    expect(updates).toEqual([
      {
        id: "a",
        row: {
          example_sentence: "我騎腳踏車。",
          extras: { explain_lang: "ja", usage_context: "通学" },
        },
      },
      // 人が確かめた語は、意味が空でも列は書かない。解説（AI の付け足し）の空の項目だけ。
      {
        id: "v",
        row: { extras: { explain_lang: "ja", mnemonic: "x", usage_context: "通学" } },
      },
    ]);
  });
});
