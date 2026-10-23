import { describe, it, expect } from "vitest";
import {
  cleanWordbookEntries,
  wordbookTitle,
  wordbookProgress,
  MAX_ENTRIES_PER_PHOTO,
  MAX_TITLE_CHARS,
} from "./wordbook";

describe("cleanWordbookEntries", () => {
  it("空白を潰し、読みと意味を持ち越す", () => {
    expect(
      cleanWordbookEntries([
        { headword: " 雨傘 ", reading_zhuyin: " ㄩˇ ㄙㄢˇ ", meaning_ja: "  傘 " },
      ]),
    ).toEqual([{ headword: "雨傘", reading_zhuyin: "ㄩˇ ㄙㄢˇ", pinyin: null, meaning_ja: "傘" }]);
  });

  it("**漢字が1文字も無い行は捨てる**(ページ番号・記号・欧文の見出し)", () => {
    const got = cleanWordbookEntries([
      { headword: "12" },
      { headword: "———" },
      { headword: "Unit 3" },
      { headword: "雨傘" },
    ]);
    expect(got.map((e) => e.headword)).toEqual(["雨傘"]);
  });

  it("同じ語は1つにまとめ、**あとの行で空欄を埋める**", () => {
    // 単語帳は「語」と「意味」が別の列に並ぶので、片方だけの行が2つ来る。
    const got = cleanWordbookEntries([
      { headword: "雨傘", reading_zhuyin: "ㄩˇ ㄙㄢˇ" },
      { headword: "雨傘", meaning_ja: "傘" },
    ]);
    expect(got).toHaveLength(1);
    expect(got[0]).toMatchObject({ reading_zhuyin: "ㄩˇ ㄙㄢˇ", meaning_ja: "傘" });
  });

  it("先に入った値を、あとの行で上書きしない", () => {
    const got = cleanWordbookEntries([
      { headword: "雨傘", meaning_ja: "傘" },
      { headword: "雨傘", meaning_ja: "まちがい" },
    ]);
    expect(got[0].meaning_ja).toBe("傘");
  });

  it("上限で切る", () => {
    const many = Array.from({ length: 200 }, (_, i) => ({ headword: `雨${i}傘` }));
    expect(cleanWordbookEntries(many)).toHaveLength(MAX_ENTRIES_PER_PHOTO);
    expect(cleanWordbookEntries(many, 5)).toHaveLength(5);
    expect(cleanWordbookEntries(many, 0)).toHaveLength(0);
  });

  it("上限に達したあとでも、すでに入った語の空欄は埋まる", () => {
    const got = cleanWordbookEntries(
      [{ headword: "雨傘" }, { headword: "夜市" }, { headword: "雨傘", meaning_ja: "傘" }],
      1,
    );
    expect(got).toHaveLength(1);
    expect(got[0].meaning_ja).toBe("傘");
  });

  it("何も無くても落ちない", () => {
    expect(cleanWordbookEntries(null)).toEqual([]);
    expect(cleanWordbookEntries(undefined)).toEqual([]);
    expect(cleanWordbookEntries([])).toEqual([]);
    expect(cleanWordbookEntries([{ headword: "" }, { headword: "   " }])).toEqual([]);
  });
});

describe("wordbookTitle", () => {
  it("AI の名前を使う", () => {
    expect(wordbookTitle("TOCFL 2級 第3課", "2026-08-20")).toBe("TOCFL 2級 第3課");
  });

  it("**名前の無い本を作らない**", () => {
    expect(wordbookTitle(null, "2026-08-20")).toBe("2026-08-20");
    expect(wordbookTitle("   ", "2026-08-20")).toBe("2026-08-20");
    expect(wordbookTitle(null, "")).toBe("単語帳");
  });

  it("長すぎる名前は切る", () => {
    const long = "あ".repeat(MAX_TITLE_CHARS + 20);
    expect(wordbookTitle(long, "x")).toHaveLength(MAX_TITLE_CHARS);
  });
});

describe("wordbookProgress", () => {
  const now = Date.parse("2026-08-20T12:00:00Z");
  const iso = (ms: number) => new Date(ms).toISOString();

  it("今日出す数と覚えた数を分けて数える", () => {
    const got = wordbookProgress(
      [
        { due_at: iso(now - 86400000), repetitions: 0 },
        { due_at: iso(now + 86400000), repetitions: 5 },
        { due_at: iso(now + 86400000), repetitions: 1 },
      ],
      now,
    );
    expect(got).toEqual({ total: 3, due: 1, learned: 1 });
  });

  it("期限が無い語は今日出す(取り込んだばかりの語)", () => {
    expect(wordbookProgress([{ due_at: null, repetitions: 0 }], now).due).toBe(1);
  });

  it("壊れた日付でも落ちず、出す側に倒す", () => {
    expect(wordbookProgress([{ due_at: "こわれた", repetitions: 0 }], now).due).toBe(1);
  });

  it("空の本は 0", () => {
    expect(wordbookProgress([], now)).toEqual({ total: 0, due: 0, learned: 0 });
  });
});
