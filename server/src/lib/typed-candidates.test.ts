import fs from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import {
  ensureTypedBasic,
  preferEverydayCommon,
  typedObjectLabel,
  typedQueryLine,
  typedQueryMode,
  withTypedLabels,
} from "./typed-candidates";
import { isReaderTagText } from "./photo-candidates";
import type { NameRegister } from "./candidate-register";

const c = (headword: string, register: NameRegister, style: string | null, meaning = "") => ({
  headword,
  reading_zhuyin: "",
  pinyin: "",
  meaning_ja: meaning,
  distinction: "",
  register,
  style,
  scene: "",
  usage: null,
  image_query: "",
  category_key: "other",
});

describe("打って調べた語は、まず表示言語の語として読む（オーナー指示 2026-10-15）", () => {
  it("漢字だけの語を日本語で読む人が打ったら display_first（犬・桃・電車）", () => {
    expect(typedQueryMode("犬", "zh-TW", "ja")).toBe("display_first");
    expect(typedQueryMode("桃", "zh-TW", "ja")).toBe("display_first");
    expect(typedQueryMode("電車", "zh-TW", "ja")).toBe("display_first");
    // かな・新字体は表示言語、台湾の字にしか無い形は学習言語。
    expect(typedQueryMode("ケーキ", "zh-TW", "ja")).toBe("display");
    expect(typedQueryMode("駅", "zh-TW", "ja")).toBe("display");
    expect(typedQueryMode("貓", "zh-TW", "ja")).toBe("learning");
    // 英語・繁體中文で読む人が漢字だけを打ったら、それは学習言語（台湾華語）の字。
    expect(typedQueryMode("花", "zh-TW", "en")).toBe("learning");
    expect(typedQueryMode("花", "zh-TW", "zh-TW")).toBe("learning");
    expect(typedQueryMode("dog", "zh-TW", "en")).toBe("display");
    // 英語を学ぶ人: かな・漢字は表示言語、英語の語は学習言語。
    expect(typedQueryMode("犬", "en", "ja")).toBe("display");
    expect(typedQueryMode("dog", "en", "ja")).toBe("learning");
    // 画面が見分けを送ってきたら、それを使う（ambiguous は上と同じ読み方）。
    expect(typedQueryMode("犬", "zh-TW", "ja", "target")).toBe("learning");
    expect(typedQueryMode("犬", "zh-TW", "ja", "ambiguous")).toBe("display_first");
  });

  it("日本語の「犬」→ 狗 が一般的な言い方。同じ字の 犬 はより詳しい／学術的な言い方に下げる", () => {
    expect(
      ensureTypedBasic(
        [c("犬", "common", "written", "犬"), c("狗", "specific", "spoken", "犬")],
        "犬",
        "display_first",
        "ja",
        "zh-TW",
      ).map((x) => [x.headword, x.register]),
    ).toEqual([
      ["狗", "common"],
      ["犬", "specific"],
    ]);
    expect(
      ensureTypedBasic(
        [c("犬", "common", "technical", "犬")],
        "犬",
        "display_first",
        "ja",
        "zh-TW",
      ).map((x) => [x.headword, x.register, x.meaning_ja, x.category_key]),
    ).toEqual([
      ["狗", "common", "犬", "animal"],
      ["犬", "academic", "犬", "other"],
    ]);
  });

  it("ケーキと打ったら 蛋糕 が1つ目。学習言語で打った語・表に無い語はそのまま", () => {
    expect(
      ensureTypedBasic(
        [c("草莓蛋糕", "common", "spoken"), c("蛋糕", "specific", "spoken")],
        "ケーキ",
        "display",
        "ja",
        "zh-TW",
      ).map((x) => [x.headword, x.register]),
    ).toEqual([
      ["蛋糕", "common"],
      ["草莓蛋糕", "specific"],
    ]);
    const learning = [c("犬", "common", "written")];
    expect(ensureTypedBasic(learning, "犬", "learning", "ja", "zh-TW")).toEqual(learning);
    // 下着は学習言語の言い方が割れる（內褲・內衣）ので表に任せない。
    const underwear = [c("內衣", "common", "both"), c("內褲", "specific", "both")];
    expect(ensureTypedBasic(underwear, "下着", "display", "ja", "zh-TW")).toEqual(underwear);
  });

  it("一般的な言い方は会話の語（書き言葉・専門の形を1つ目にしない）", () => {
    expect(
      preferEverydayCommon([c("犬隻", "common", "written"), c("狗", "specific", "spoken")]).map(
        (x) => [x.headword, x.register],
      ),
    ).toEqual([
      ["狗", "common"],
      ["犬隻", "specific"],
    ]);
    expect(
      preferEverydayCommon([c("犬科", "common", "technical"), c("狗", "specific", "both")]).map(
        (x) => [x.headword, x.register],
      ),
    ).toEqual([
      ["狗", "common"],
      ["犬科", "academic"],
    ]);
    const fine = [c("花", "common", "both"), c("花朵", "specific", "written")];
    expect(preferEverydayCommon(fine)).toEqual(fine);
  });

  it("打った物の表示言語の名前（object_label）と、候補ごとの短い意味（gloss）", () => {
    const tag = (
      q: string,
      mode: Parameters<typeof typedObjectLabel>[1],
      common: string,
      m: string,
    ) =>
      typedObjectLabel(q, mode, { headword: common, meaning_ja: m }, (t, h) =>
        isReaderTagText(t, "ja", h),
      );
    expect(tag("犬", "display_first", "狗", "犬")).toBe("犬");
    expect(tag("ボクサーパンツ", "display", "四角褲", "ボクサーパンツ")).toBe("ボクサーパンツ");
    expect(tag("貓", "learning", "貓", "猫、ネコ")).toBe("猫");
    // 字が同じ日本語の語（花）も名前として出す。
    expect(tag("花", "display_first", "花", "花")).toBe("花");
    const out = withTypedLabels([c("狗", "common", "spoken", "犬、イヌ")], "犬");
    expect(out[0]).toMatchObject({ gloss: "犬", object_label: "犬" });
  });

  it("指示文: 表示言語を先に読み、漢字だからと打った字を見出し語にしない", () => {
    const line = typedQueryLine({
      query: "犬",
      mode: "display_first",
      targetName: "台湾華語(繁体字)",
      readerName: "日本語",
    });
    expect(line).toMatch(/まず日本語の語として読む/);
    expect(line).toMatch(/犬 → 狗/);
    expect(line).toMatch(/academic/);
    expect(line).toMatch(/漢字だから・字が同じだからという理由で/);
    expect(line).toMatch(/query_is_target は false/);
  });

  it("サーバの返事の形: 候補は写真の候補と同じ欄（register・object_label・category_key）に gloss。古い欄はそのまま", () => {
    const ai = fs.readFileSync(path.join(__dirname, "ai.functions.ts"), "utf8");
    const fn = ai.slice(
      ai.indexOf("export const suggestWordCandidates"),
      ai.indexOf("function sameLanguage"),
    );
    expect(fn).toMatch(
      /typedQueryMode\(data\.query, data\.targetLanguage, reader, data\.queryLang\)/,
    );
    expect(fn).toMatch(
      /category_key: normalizeCategory\(c\.headword, coerceCategoryKey\(c\.category_key\)\)/,
    );
    expect(fn).toMatch(/const registered = finalizeNameRegisters\(fitted\)/);
    expect(fn).toMatch(
      /ensureTypedBasic\(\s*mode === "learning" \? registered : preferEverydayCommon\(registered\)/,
    );
    expect(fn).toMatch(/const candidates = withTypedLabels\(ranked, objectLabel\)/);
    expect(fn).toMatch(/query_lang: mode === "learning"/);
    expect(fn).toMatch(/object_label: objectLabel/);
    expect(fn).toMatch(/return \{\s*candidates,\s*query_is_target,/);
  });
});
