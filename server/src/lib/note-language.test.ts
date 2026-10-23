import { describe, it, expect } from "vitest";
import {
  looksLikeTargetNote,
  dropForeignNote,
  scrubForeignNotes,
  MIN_SUSPECT_CHARS,
} from "./note-language";

/**
 * オーナー報告「量詞の説明が台湾華語になってる」の受け皿。
 *
 * ここで一番怖いのは**正しい和文を落とすこと**なので、
 * 落とす側より「落とさない」側の試験を厚くする。
 */

describe("looksLikeTargetNote — 落とす", () => {
  it("漢字だけのまとまった文は中国語とみなす", () => {
    expect(looksLikeTargetNote("用於扁平的物品", "ja")).toBe(true);
    expect(looksLikeTargetNote("表示數量的單位詞", "ja")).toBe(true);
  });

  it("空白を詰めてから数える", () => {
    expect(looksLikeTargetNote("用於 扁平 的 物品", "ja")).toBe(true);
  });
});

describe("looksLikeTargetNote — 落とさない", () => {
  it("かなが1文字でもあれば日本語", () => {
    expect(looksLikeTargetNote("平らな物に使う", "ja")).toBe(false);
    expect(looksLikeTargetNote("紙や写真などに", "ja")).toBe(false);
    // 助詞だけでも守られる
    expect(looksLikeTargetNote("扁平的物品に", "ja")).toBe(false);
  });

  it(`**${MIN_SUSPECT_CHARS}文字未満の漢字だけの注記は守る**（「書類用」など）`, () => {
    expect(looksLikeTargetNote("書類用", "ja")).toBe(false);
    expect(looksLikeTargetNote("平面物", "ja")).toBe(false);
    expect(looksLikeTargetNote("紙類", "ja")).toBe(false);
  });

  it("欧文が混じるものは判定しない", () => {
    expect(looksLikeTargetNote("A4の紙に使う", "ja")).toBe(false);
    expect(looksLikeTargetNote("MRT的車票", "ja")).toBe(false);
  });

  it("空・null・undefined は落とさない(そもそも中身が無い)", () => {
    expect(looksLikeTargetNote("", "ja")).toBe(false);
    expect(looksLikeTargetNote(null, "ja")).toBe(false);
    expect(looksLikeTargetNote(undefined, "ja")).toBe(false);
    expect(looksLikeTargetNote("   ", "ja")).toBe(false);
  });

  it("**解説が英語のときは何も落とさない**(取り違えようが無い)", () => {
    expect(looksLikeTargetNote("用於扁平的物品", "en")).toBe(false);
    expect(looksLikeTargetNote("Used for flat things", "en")).toBe(false);
  });

  it("漢字が1文字も無ければ落とさない", () => {
    expect(looksLikeTargetNote("・・・・・・", "ja")).toBe(false);
    expect(looksLikeTargetNote("123456", "ja")).toBe(false);
  });
});

describe("dropForeignNote", () => {
  it("落とすときは空文字にする(書き換えない)", () => {
    expect(dropForeignNote("用於扁平的物品", "ja")).toBe("");
  });

  it("残すときはそのまま返す", () => {
    expect(dropForeignNote("平らな物に使う", "ja")).toBe("平らな物に使う");
  });

  it("null は空文字にして返す(呼ぶ側で分岐を増やさない)", () => {
    expect(dropForeignNote(null, "ja")).toBe("");
    expect(dropForeignNote(undefined, "ja")).toBe("");
  });
});

describe("scrubForeignNotes", () => {
  const zh = "用於扁平的物品";
  const ja = "平らな物に使う";

  it("量詞・関連語・チャンクの注記をまとめて落とす", () => {
    const got = scrubForeignNotes(
      {
        measure_words: [{ note: zh }, { note: ja }],
        related_words: [{ note: zh }],
        usage_chunks: [{ ja: zh }, { ja }],
      },
      "ja",
    );
    expect(got.measure_words).toEqual([{ note: "" }, { note: ja }]);
    expect(got.related_words).toEqual([{ note: "" }]);
    expect(got.usage_chunks).toEqual([{ ja: "" }, { ja }]);
  });

  it("**元の物を書き換えない**(呼ぶ側が同じ物を2回使っても壊れない)", () => {
    const src = { measure_words: [{ note: zh }] };
    const got = scrubForeignNotes(src, "ja");
    expect(src.measure_words[0].note).toBe(zh);
    expect(got.measure_words![0].note).toBe("");
  });

  it("解説が英語なら丸ごとそのまま", () => {
    const src = { measure_words: [{ note: zh }] };
    expect(scrubForeignNotes(src, "en")).toBe(src);
  });

  it("項目が無くても落ちない", () => {
    expect(() => scrubForeignNotes({}, "ja")).not.toThrow();
    expect(() => scrubForeignNotes({ measure_words: null }, "ja")).not.toThrow();
    expect(() => scrubForeignNotes({ usage_chunks: undefined }, "ja")).not.toThrow();
  });
});

import { looksWrongForReader } from "./note-language";

describe("looksWrongForReader（訳が読む人の言語か。2026-09-29 小腿の例文の訳が中文）", () => {
  const zh = "這名馬拉松選手因為小腿抽筋，不得不停下來休息。";
  it("例文そのままの写しは、どの言語でも落とす", () => {
    expect(looksWrongForReader("這名馬拉松選手因為小腿抽筋，不得不停下來休息。", "ja", zh)).toBe(
      true,
    );
    expect(looksWrongForReader(zh, "zh-TW", zh)).toBe(true);
  });
  it("日本語で読む人に中文・英文は出さない。和文は出す", () => {
    expect(looksWrongForReader("這名選手因為小腿抽筋", "ja")).toBe(true);
    expect(looksWrongForReader("The runner had a cramp in his calf", "ja")).toBe(true);
    expect(looksWrongForReader("その選手はふくらはぎがつって休んだ。", "ja")).toBe(false);
    expect(looksWrongForReader("書類用", "ja")).toBe(false);
  });
  it("英語で読む人に漢字・かなの文は出さない", () => {
    expect(looksWrongForReader("その選手はふくらはぎがつった", "en")).toBe(true);
    expect(looksWrongForReader("The runner had a cramp in his calf.", "en")).toBe(false);
  });
  it("台湾華語で読む人に日本語・英文は出さない。中文は出す", () => {
    expect(looksWrongForReader("ふくらはぎがつった", "zh-TW")).toBe(true);
    expect(looksWrongForReader("I bought a new umbrella today", "zh-TW")).toBe(true);
    expect(looksWrongForReader("我今天買了一把新雨傘。", "zh-TW")).toBe(false);
  });
});
