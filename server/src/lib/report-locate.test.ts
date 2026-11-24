import { describe, expect, it } from "vitest";
import {
  pickCorrectHeadword,
  pickReportedItem,
  pickReportedItems,
  readerViewOfWord,
  reportContext,
  reportGuidance,
} from "./report-locate";

describe("報告から間違っている項目を決める", () => {
  const cands = ["pronunciation", "meaning", "example"] as const;
  it("画面に在る項目だけを採る", () => {
    expect(pickReportedItem({ item: "example" }, cands)).toBe("example");
    expect(pickReportedItem({ item: " meaning " }, cands)).toBe("meaning");
  });
  it("「なし」・画面に無い項目・壊れた答えは採らない", () => {
    expect(pickReportedItem({ item: "none" }, cands)).toBeNull();
    expect(pickReportedItem({ item: "etymology" }, cands)).toBeNull();
    expect(pickReportedItem("example", cands)).toBeNull();
    expect(pickReportedItem(null, cands)).toBeNull();
  });
  it("語の中身を項目ごとに短く並べる", () => {
    const text = reportContext(cands, {
      reading_zhuyin: "ㄋㄞˇ ㄔㄚˊ",
      meaning: "ミルクティー",
      extras: { example: "x".repeat(900) },
    });
    expect(text).toContain("[pronunciation] ㄋㄞˇ ㄔㄚˊ");
    expect(text).toContain("[meaning] ミルクティー");
    expect(text.split("\n")[2].length).toBeLessThan(520);
  });
});

describe("報告で直す項目を全部決める（2026-11-24）", () => {
  const cands = ["meaning", "taiwan_note", "example", "headword"] as const;
  it("複数の項目を順に、候補に無い物・重なりは落とす", () => {
    expect(pickReportedItems({ items: ["meaning", "taiwan_note", "meaning", "etymology"] }, cands)).toEqual([
      "meaning",
      "taiwan_note",
    ]);
  });
  it("古い形（item 1つ）も読む・空なら直さない", () => {
    expect(pickReportedItems({ item: "example" }, cands)).toEqual(["example"]);
    expect(pickReportedItems({ items: [] }, cands)).toEqual([]);
    expect(pickReportedItems(null, cands)).toEqual([]);
  });
  it("見出し語が違えば、見出し語だけ（付け替えた先の語の中身はその語の物）", () => {
    expect(pickReportedItems({ items: ["meaning", "headword"] }, cands)).toEqual(["headword"]);
  });
  it("上限は3つ", () => {
    const many = ["a", "b", "c", "d"] as const;
    expect(pickReportedItems({ items: ["a", "b", "c", "d"] }, many)).toHaveLength(3);
  });
});

describe("見出し語の直しの答え", () => {
  it("違う時だけ、別の語を採る", () => {
    expect(pickCorrectHeadword({ wrong: true, headword: " 玉米脆片 " }, "玉米片")).toBe("玉米脆片");
    expect(pickCorrectHeadword({ wrong: false, headword: "牛奶" }, "鮮乳")).toBeNull();
    expect(pickCorrectHeadword({ wrong: true, headword: "鮮乳" }, "鮮乳")).toBeNull();
    expect(pickCorrectHeadword({ wrong: true, headword: "" }, "鮮乳")).toBeNull();
    expect(pickCorrectHeadword("牛奶", "鮮乳")).toBeNull();
  });
});

describe("学習者の画面に出ている語（共有の行に、その人の言語の行と帯の行を重ねる）", () => {
  const shared = {
    headword: "玉米片",
    meaning_ja: "トルティーヤチップス",
    example_sentence: "共有の例文",
    extras: { taiwan_note: "共有の台湾メモ", usage_chunks: [{ a: 1 }] },
  };
  it("その人の言語の行が画面に出る物（共有の行が直っていても、画面は古い行を出す — 玉米片）", () => {
    const v = readerViewOfWord(
      shared,
      { meaning: "コーンフレーク", extras: { taiwan_note: "シリアルの話", measure_words: [] } },
      null,
    );
    expect(v.meaning_ja).toBe("コーンフレーク");
    const ex = v.extras as Record<string, unknown>;
    expect(ex.taiwan_note).toBe("シリアルの話");
    // 空の物では上書きしない（共有の行の物が出る）。
    expect(ex.usage_chunks).toEqual([{ a: 1 }]);
    expect(reportContext(["meaning", "taiwan_note"], v)).toContain("[meaning] コーンフレーク");
  });
  it("例文・チャンクは帯の行が出る", () => {
    const v = readerViewOfWord(shared, null, {
      example_sentence: "帯の例文",
      extras: { usage_chunks: [{ b: 2 }] },
    });
    expect(v.example_sentence).toBe("帯の例文");
    expect((v.extras as Record<string, unknown>).usage_chunks).toEqual([{ b: 2 }]);
    // 共有の行そのものは変えない。
    expect(shared.example_sentence).toBe("共有の例文");
  });
  it("項目名 meaning は語の列 meaning_ja を見る（前は空を見せていた）", () => {
    expect(reportContext(["meaning"], { meaning_ja: "牛乳" })).toBe("[meaning] 牛乳");
    expect(reportContext(["example"], { example_sentence: "我喝鮮奶。", example_translation: "牛乳を飲む。" })).toBe(
      "[example] 我喝鮮奶。 / 牛乳を飲む。",
    );
  });
});

describe("作り直しに渡す学習者の報告", () => {
  it("今の内容と報告を足し、そのまま写さないよう頼む", () => {
    const g = reportGuidance("鮮乳とは台湾人あまり言わないけど", "[taiwan_note] 台湾では「鮮乳」が一般的");
    expect(g).toContain("鮮乳とは台湾人あまり言わないけど");
    expect(g).toContain("今の内容: [taiwan_note]");
    expect(g).toContain("そのまま写さない");
  });
  it("報告が空なら何も足さない", () => {
    expect(reportGuidance("  ", "x")).toBe("");
  });
});
