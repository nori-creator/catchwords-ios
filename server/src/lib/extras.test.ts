import { describe, it, expect } from "vitest";
import {
  emptyExtras,
  normalizeExtras,
  hasExtrasContent,
  mergeExtras,
  withoutMeasureWords,
  usableCollocations,
  chunkSpeechText,
  refineUsageChunks,
  chunkMentionsHeadword,
  MAX_CHUNKS,
  RegenUsageChunksSchema,
} from "./extras";
import fs from "node:fs";
import path from "node:path";

/**
 * 単語カードの「中身」(用例・関連語・台湾での言い方…)の正規化と合流。
 *
 * ## なぜここを守るか
 * このアプリで**同じ不具合を何度も踏んだ**のがここ。
 * 「キャッチした語の解説が全部消える」「単語詳細のセクションがまた出ない」
 * — どちらも、後から届いた空の extras が保存済みの中身を上書きしたのが原因。
 *
 * 空で上書きしない、という規則さえ守られていれば起きない。だから規則を
 * 文章ではなくテストに置く。
 */

describe("normalizeExtras", () => {
  it("オブジェクトでないものは null", () => {
    expect(normalizeExtras(null)).toBeNull();
    expect(normalizeExtras(undefined)).toBeNull();
    expect(normalizeExtras("なにか")).toBeNull();
    expect(normalizeExtras(42)).toBeNull();
  });

  it("空のオブジェクトは「空だが有効」として通す", () => {
    expect(normalizeExtras({})).not.toBeNull();
  });

  it("知らない鍵が混ざっていても落とさない", () => {
    // AIの出力は形が揺れる。1つ余計な鍵があっただけで解説が丸ごと
    // 消えるのでは、あまりに脆い。
    const e = normalizeExtras({ collocations: ["喝咖啡"], 未知の鍵: 1 });
    expect(e).not.toBeNull();
    expect(e?.collocations).toEqual(["喝咖啡"]);
  });
});

describe("hasExtrasContent", () => {
  it("null と空は「中身なし」", () => {
    expect(hasExtrasContent(null)).toBe(false);
    expect(hasExtrasContent(undefined)).toBe(false);
    expect(hasExtrasContent(emptyExtras())).toBe(false);
  });

  it("配列が1つでも埋まっていれば「中身あり」", () => {
    expect(hasExtrasContent({ collocations: ["喝咖啡"] })).toBe(true);
  });

  it("空白だけの文字列は中身とみなさない", () => {
    expect(hasExtrasContent({ taiwan_note: "   " })).toBe(false);
    expect(hasExtrasContent({ taiwan_note: "台湾ではこう言う" })).toBe(true);
  });

  it("explain_lang / explain_l1 は中身に数えない", () => {
    // これは「何語で書かれた解説か」の目印であって、解説そのものではない。
    // 数えてしまうと、目印だけ入った空の extras が「中身あり」になり、
    // 保存済みの本物を上書きしてしまう。
    expect(hasExtrasContent({ explain_lang: "ja", explain_l1: "ja" })).toBe(false);
  });
});

describe("mergeExtras", () => {
  it("空の側で埋まっている側を消さない", () => {
    // これがこのファイルの本題。何度も踏んだ不具合そのもの。
    const saved = { collocations: ["喝咖啡"], taiwan_note: "台湾ではこう言う" };
    const merged = mergeExtras(saved, { collocations: [], taiwan_note: "" });
    expect(merged.collocations).toEqual(["喝咖啡"]);
    expect(merged.taiwan_note).toBe("台湾ではこう言う");
  });

  it("新しく届いた中身は古いものに勝つ", () => {
    const merged = mergeExtras({ collocations: ["古い"] }, { collocations: ["新しい"] });
    expect(merged.collocations).toEqual(["新しい"]);
  });

  it("保存済みが空でも、届いた中身はちゃんと入る", () => {
    const merged = mergeExtras(null, { collocations: ["喝咖啡"] });
    expect(merged.collocations).toEqual(["喝咖啡"]);
  });

  it("両方 null でも落ちず、空の形を返す", () => {
    expect(hasExtrasContent(mergeExtras(null, null))).toBe(false);
  });

  it("元のオブジェクトを書き換えない", () => {
    const saved = { collocations: ["喝咖啡"] };
    const before = JSON.stringify(saved);
    mergeExtras(saved, { collocations: ["新しい"] });
    expect(JSON.stringify(saved)).toBe(before);
  });
});

/**
 * 量詞は「量詞」の欄で読む。「使い方」で同じ物をもう一度読ませない。
 * ただし量詞の型そのものを禁じると、使い方が動詞と目的語だけに戻る。
 * その線引きをここに置く。
 */
describe("withoutMeasureWords", () => {
  const mw = [{ word: "一張" }];
  const chunk = (...texts: string[]) => ({
    parts: texts.map((text) => ({ text, pos: "" })),
    ja: "",
  });

  it("量詞と見出し語しか無い型は落とす", () => {
    expect(withoutMeasureWords([chunk("一張", "衛生紙")], mw, "衛生紙")).toEqual([]);
  });

  it("数を落とした素の量詞でも同じ物と見なす", () => {
    expect(withoutMeasureWords([chunk("張", "衛生紙")], mw, "衛生紙")).toEqual([]);
  });

  it("**動詞が付いていても落とす**(量詞が出た時点で重なっている)", () => {
    expect(withoutMeasureWords([chunk("拿", "一張", "衛生紙")], mw, "衛生紙")).toEqual([]);
  });

  it("量詞の一覧に無くても、品詞が M なら落とす", () => {
    const list = [
      {
        parts: [
          { text: "杯", pos: "M" },
          { text: "咖啡", pos: "N" },
        ],
        ja: "",
      },
    ];
    expect(withoutMeasureWords(list, [], "咖啡")).toEqual([]);
  });

  it("量詞と関係ない型はそのまま残る", () => {
    const list = [chunk("用", "衛生紙", "擦")];
    expect(withoutMeasureWords(list, mw, "衛生紙")).toEqual(list);
  });

  it("見出し語がその札の量詞と同じ字でも、型を全部落とさない", () => {
    const list = [chunk("一", "張", "紙")];
    expect(withoutMeasureWords(list, [{ word: "張" }], "張")).toEqual(list);
  });

  it("量詞が無いカードは素通し", () => {
    const list = [chunk("拿", "衛生紙")];
    expect(withoutMeasureWords(list, [], "衛生紙")).toEqual(list);
    expect(withoutMeasureWords(list, null, "衛生紙")).toEqual(list);
  });

  it("空のパーツしか無い型は落とす(描いても何も出ない)", () => {
    expect(withoutMeasureWords([chunk("", " ")], mw, "衛生紙")).toEqual([]);
  });

  it("null / undefined でも落ちない", () => {
    expect(withoutMeasureWords(null, mw, "衛生紙")).toEqual([]);
    expect(withoutMeasureWords(undefined, undefined, "")).toEqual([]);
  });
});

describe("usableCollocations", () => {
  it("文になっている物と長すぎる物を落とす", () => {
    expect(usableCollocations(["喝珍奶", "我今天喝了一杯珍珠奶茶。"], "zh-TW")).toEqual(["喝珍奶"]);
    expect(usableCollocations(["put on socks", "Is it big?"], "en")).toEqual(["put on socks"]);
  });

  it("重複と空白だけを落とし、上限で切る", () => {
    const many = ["a b", "a b", "c d", "e f", "g h", "i j", "k l", "  "];
    expect(usableCollocations(many, "en")).toEqual(["a b", "c d", "e f", "g h", "i j"]);
  });

  it("空でも落ちない", () => {
    expect(usableCollocations(null, "en")).toEqual([]);
    expect(usableCollocations(undefined, "zh-TW")).toEqual([]);
  });
});

describe("chunkSpeechText", () => {
  it("英語は空白で継ぐ(`put onsocks` にしない)", () => {
    const c = {
      parts: [
        { text: "put on", pos: "v" },
        { text: "socks", pos: "n" },
      ],
      ja: "",
    };
    expect(chunkSpeechText(c, "en")).toBe("put on socks");
  });

  it("漢字は継ぎ目を入れない", () => {
    const c = {
      parts: [
        { text: "喝", pos: "V" },
        { text: "珍奶", pos: "N" },
      ],
      ja: "",
    };
    expect(chunkSpeechText(c, "zh-TW")).toBe("喝珍奶");
  });
});

describe("refineUsageChunks", () => {
  // 品詞は書かない（「帶＋雨傘」を名詞＋名詞にすると、1語として合わさる — C7）。
  const chunk = (...texts: string[]) => ({
    parts: texts.map((text) => ({ text, pos: "" })),
    ja: "",
  });

  it("**句点の付いた物は文**(オーナー指摘 2026-08-27 ②「文章のようになってる」)", () => {
    expect(refineUsageChunks([chunk("我", "去", "了", "。")], [], "去", "zh-TW")).toEqual([]);
    expect(refineUsageChunks([chunk("Is", "it", "big?")], [], "big", "en")).toEqual([]);
  });

  it("句点が無ければ同じ語数でも残る(文かどうかだけで分けている)", () => {
    expect(refineUsageChunks([chunk("我", "去", "了")], [], "去", "zh-TW")).toHaveLength(1);
  });

  it("長すぎる型を落とす(例文になってしまう)", () => {
    const short = chunk("帶", "雨傘");
    const long = chunk("今天", "下雨", "所以", "我帶了雨傘");
    expect(refineUsageChunks([short, long], [], "雨傘")).toEqual([short]);
  });

  it("パーツが多すぎる型を落とす", () => {
    const many = chunk("我", "今天", "早上", "帶了", "雨傘");
    expect(refineUsageChunks([many], [], "雨傘")).toEqual([]);
  });

  it("「+」だけの札を除いてから数える（牛蒡 [+] 炒 → 牛蒡 炒。保存済みの語にも効く）", () => {
    const out = refineUsageChunks(
      [chunk("炒", "+", "牛蒡"), chunk("牛蒡＋湯"), chunk("煮", "＋", "牛蒡")],
      [],
      "牛蒡",
      "zh-TW",
    );
    expect(out.map((c) => c.parts.map((p) => p.text))).toEqual([
      ["炒", "牛蒡"],
      ["牛蒡", "湯"],
      ["煮", "牛蒡"],
    ]);
  });

  it("「+」と見出し語だけの型は、見出し語だけの型として落とす", () => {
    expect(refineUsageChunks([chunk("牛蒡", "+")], [], "牛蒡", "zh-TW")).toEqual([]);
  });

  it("見出し語しか無い型を落とす(その語を見れば分かる)", () => {
    expect(refineUsageChunks([chunk("雨傘")], [], "雨傘")).toEqual([]);
  });

  it("同じ文字列の型は1つだけ残す", () => {
    const a = { ...chunk("帶", "雨傘"), ja: "傘を持つ" };
    const b = { ...chunk("帶", "雨傘"), ja: "かさを持参する" };
    expect(refineUsageChunks([a, b], [], "雨傘")).toEqual([a]);
  });

  it(`${MAX_CHUNKS}個で切る(生成側は頻度の高い順に並べるので後ろから)`, () => {
    const many = Array.from({ length: 12 }, (_, i) => chunk(`用${i}`, "雨傘"));
    const got = refineUsageChunks(many, [], "雨傘");
    expect(got).toHaveLength(MAX_CHUNKS);
    expect(got[0]).toEqual(many[0]);
  });

  it("量詞と丸ごと重なる型は今までどおり落ちる", () => {
    const echo = chunk("一把", "雨傘");
    const real = chunk("帶", "雨傘");
    expect(refineUsageChunks([echo, real], [{ word: "一把" }], "雨傘")).toEqual([real]);
  });

  it("空・null で落ちない", () => {
    expect(refineUsageChunks(null, null, "雨傘")).toEqual([]);
    expect(refineUsageChunks([], [], "雨傘")).toEqual([]);
    expect(refineUsageChunks([chunk("")], [], "雨傘")).toEqual([]);
  });

  /**
   * オーナー報告 2026-08-26（3度目）:
   * > 「単語のチャンク型の項目が生成されてない。」
   *
   * 生成はされていた。**8文字の物差しを英語に当てて、全部こちらが
   * 落としていた。** 届いた絵の `socks` に「使い方」の欄が無いのがそれ。
   */
  describe("refineUsageChunks — 英語の型を落とさない", () => {
    const en = (...words: string[]) => ({
      parts: words.map((text) => ({ text, pos: "" })),
      ja: "",
    });

    it("**`put on socks` が通る**（8文字の物差しなら落ちていた）", () => {
      const c = en("put on", "socks");
      expect(refineUsageChunks([c], [], "socks", "en")).toEqual([c]);
    });

    it("台湾華語の目盛りでは同じ型が落ちる（＝これが報告の中身）", () => {
      expect(refineUsageChunks([en("put on", "socks")], [], "socks", "zh-TW")).toEqual([]);
      // **学習言語を渡し忘れても同じ穴に落ちる。** 呼び出し側が渡すこと。
      expect(refineUsageChunks([en("put on", "socks")], [], "socks")).toEqual([]);
    });

    it("`a pair of socks` のような冠詞つきの型も通る", () => {
      const c = en("a", "pair of", "socks");
      expect(refineUsageChunks([c], [], "socks", "en")).toEqual([c]);
    });

    it("**長すぎる英語の型は落とす**（型ではなく文になっている）", () => {
      // 5語。`MAX_CHUNK_WORDS_EN` は 4。
      expect(refineUsageChunks([en("I", "need", "to", "buy", "socks")], [], "socks", "en")).toEqual(
        [],
      );
    });

    it("見出し語だけの型は英語でも落とす", () => {
      expect(refineUsageChunks([en("socks")], [], "socks", "en")).toEqual([]);
    });

    it("同じ型は英語でも1つに畳む（継ぎ目の違いで二重に数えない）", () => {
      const a = en("wear", "socks");
      const b = en("wear", "socks");
      expect(refineUsageChunks([a, b], [], "socks", "en")).toEqual([a]);
    });

    it("台湾華語の型は今までどおり（**この直しで1つも変わらない**）", () => {
      const short = {
        parts: [
          { text: "帶", pos: "V" },
          { text: "雨傘", pos: "N" },
        ],
        ja: "",
      };
      expect(refineUsageChunks([short], [], "雨傘", "zh-TW")).toEqual([short]);
      expect(refineUsageChunks([short], [], "雨傘")).toEqual([short]);
    });
  });

  it("分けた1語（芒果＋冰）は型として出さない。札1つの古い型は残す（C7）", () => {
    const split = {
      parts: [
        { text: "芒果", pos: "N" },
        { text: "冰", pos: "N" },
      ],
      ja: "",
    };
    const real = {
      parts: [
        { text: "芒果", pos: "N" },
        { text: "很", pos: "Adv" },
        { text: "甜", pos: "Vs" },
      ],
      ja: "",
    };
    expect(refineUsageChunks([split, real], [], "芒果", "zh-TW")).toEqual([real]);
    const old = { parts: [{ text: "切芒果", pos: "" }], ja: "" };
    expect(refineUsageChunks([old], [], "芒果", "zh-TW")).toEqual([old]);
  });
});

import { chunkTranslation } from "./extras";

describe("chunkTranslation（チャンクの右は訳だけ。オーナー指示 2026-09-23）", () => {
  it("訳だけならそのまま", () => {
    expect(chunkTranslation("タピオカミルクティーを飲む")).toBe("タピオカミルクティーを飲む");
  });
  it("括弧書きの注釈・2文目・見出し・矢印の左は落とす", () => {
    expect(chunkTranslation("タピオカを頼む（注文の定番）。店でよく使う")).toBe("タピオカを頼む");
    expect(chunkTranslation("よく使う型: タピオカを飲む")).toBe("タピオカを飲む");
    expect(chunkTranslation("喝+珍珠奶茶 → タピオカを飲む")).toBe("タピオカを飲む");
    expect(chunkTranslation("drink bubble tea (casual)")).toBe("drink bubble tea");
  });
  it("空は空", () => {
    expect(chunkTranslation("")).toBe("");
    expect(chunkTranslation(undefined)).toBe("");
  });
});

/**
 * オーナー報告 2026-10-01「チャンクに学ぶべき単語の芒果がない」。
 * 型は「その語をどう使うか」なので、学ぶ語そのもの（活用形も可）が入っていない型は出さない。
 */
describe("chunkMentionsHeadword / refineUsageChunks drops chunks without the word", () => {
  const c = (...texts: string[]) => ({ parts: texts.map((text) => ({ text, pos: "" })), ja: "" });

  it("台湾華語: 「芒果」の型に「很+甜」だけは出さない", () => {
    expect(chunkMentionsHeadword("很 甜", "芒果", "zh-TW")).toBe(false);
    expect(chunkMentionsHeadword("芒果 冰", "芒果", "zh-TW")).toBe(true);
    const kept = refineUsageChunks(
      [c("很", "甜"), c("芒果", "冰"), c("吃", "芒果")],
      [],
      "芒果",
      "zh-TW",
    );
    expect(kept.map((k) => k.parts.map((p) => p.text).join(""))).toEqual(["芒果冰", "吃芒果"]);
  });

  it("英語: 規則的な語形変化は同じ語、短い語は丸ごと一致だけ", () => {
    expect(chunkMentionsHeadword("very sweet", "mango", "en")).toBe(false);
    expect(chunkMentionsHeadword("ripe mangoes", "mango", "en")).toBe(true);
    expect(chunkMentionsHeadword("making friends", "make", "en")).toBe(true);
    expect(chunkMentionsHeadword("carried it home", "carry", "en")).toBe(true);
    expect(chunkMentionsHeadword("look it up", "look up", "en")).toBe(true);
    expect(chunkMentionsHeadword("mankind", "man", "en")).toBe(false);
  });

  it("日本語: 活用しても語幹があればよい", () => {
    expect(chunkMentionsHeadword("傘をさす", "傘", "ja")).toBe(true);
    expect(chunkMentionsHeadword("ご飯を食べた", "食べる", "ja")).toBe(true);
    expect(chunkMentionsHeadword("高くない", "高い", "ja")).toBe(true);
    expect(chunkMentionsHeadword("とても甘い", "マンゴー", "ja")).toBe(false);
  });
});

/**
 * 項目の作り直しで、入れ替える所の候補（`alts`）と意味（`ja`）が消えた（2026-10-07）。
 * `runSectionRegen` の形が `{text,pos,slot}` だけを書き出していたので、zod が黙って落とした。
 */
describe("RegenUsageChunksSchema — 作り直しでも入れ替えの候補を落とさない", () => {
  it("部品の ja と alts が残る", () => {
    const out = RegenUsageChunksSchema.parse({
      usage_chunks: [
        {
          parts: [
            { text: "跟", pos: "Ptc" },
            {
              text: "男朋友",
              pos: "O",
              slot: true,
              ja: "彼氏",
              alts: [
                { text: "女朋友", ja: "彼女" },
                { text: "朋友", ja: "友だち" },
              ],
            },
            { text: "吵架", pos: "V" },
          ],
          ja: "彼氏とけんかする",
        },
      ],
    });
    const slot = out.usage_chunks[0].parts[1];
    expect(slot.ja).toBe("彼氏");
    expect(slot.alts).toEqual([
      { text: "女朋友", ja: "彼女" },
      { text: "朋友", ja: "友だち" },
    ]);
  });

  it("空の答えは今までどおり断る（作り直しを失敗として扱う）", () => {
    expect(RegenUsageChunksSchema.safeParse({ usage_chunks: [] }).success).toBe(false);
  });

  it("`runSectionRegen` はこの形を使う（部品の形を書き出さない）", () => {
    const src = fs.readFileSync(path.join(__dirname, "ai.functions.ts"), "utf8");
    expect(src).toMatch(/schema: RegenUsageChunksSchema/);
  });
});

describe("image_query（画像検索用の英語。オーナー報告 2026-10-08）", () => {
  it("保存の正規化で落とさない・型違いは空", () => {
    expect(normalizeExtras({ image_query: "burdock root" })?.image_query).toBe("burdock root");
    expect(normalizeExtras({ image_query: 5 })?.image_query).toBe("");
  });

  it("読む中身ではないので「中身がある」に数えない", () => {
    expect(hasExtrasContent({ image_query: "burdock root" })).toBe(false);
  });
});

describe("口語/書面の札は退役（オーナー決定 2026-10-15「中立・書き言葉・話し言葉を無くす」）", () => {
  it("保存済みの値は消さない（スキーマに残る）が、画面・iOS へ返す形からは外す", async () => {
    const { publicExtras, withoutRetiredExtras } = await import("./extras");
    const stored = normalizeExtras({
      register_tag: "口語・書面",
      register_scale: 0,
      usage_context: "x",
    });
    expect(stored?.register_tag).toBe("口語・書面");
    const shown = publicExtras({
      register_tag: "口語・書面",
      register_scale: 0,
      usage_context: "x",
    });
    expect(shown?.register_tag).toBe("");
    expect(shown?.register_scale).toBeNull();
    expect(shown?.usage_context).toBe("x");
    expect(withoutRetiredExtras(null)).toBeNull();
    // mergeExtras は空で上書きしないので、返した形を保存し直しても値は消えない。
    expect(mergeExtras(stored, shown).register_tag).toBe("口語・書面");
  });

});
