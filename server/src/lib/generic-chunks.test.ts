import { describe, it, expect } from "vitest";
import { isGenericChunk, withoutGenericChunks } from "./generic-chunks";

/**
 * 汎用の組み合わせを型として教えない（オーナー指示 2026-08-28 ③）。
 *
 * 難しいのは**落としすぎ**のほう。「很+状態動詞」のような、
 * どんな語にも付くが**それこそが公式**という型を落とすと、
 * この欄そのものが要らない物になる。両側から縛る。
 */

const parts = (...ws: string[]) => ws.map((text) => ({ text }));

describe("isGenericChunk — 落とすべきもの", () => {
  it("**買・喜歡はどんな名詞にも付く**(オーナーが名指しした2つ)", () => {
    expect(isGenericChunk(parts("買", "珍珠奶茶"), "珍珠奶茶")).toBe(true);
    expect(isGenericChunk(parts("喜歡", "珍珠奶茶"), "珍珠奶茶")).toBe(true);
  });

  it("骨組みが混ざっていても落とす（我要買{語}）", () => {
    expect(isGenericChunk(parts("我", "要", "買", "手機"), "手機")).toBe(true);
  });

  it("骨組みしか残らない型は**落とさない**（「了」の位置がこの型の中身）", () => {
    // ここを落とすと文法の型が全部消える（実際に既存の試験が捕まえた）。
    expect(isGenericChunk(parts("我", "去", "了"), "去")).toBe(false);
    expect(isGenericChunk(parts("我", "的", "手機"), "手機")).toBe(false);
  });

  it("英語も同じ（buy/like は落とし、put on は残す）", () => {
    expect(isGenericChunk(parts("buy", "socks"), "socks", "en")).toBe(true);
    expect(isGenericChunk(parts("I", "like", "socks"), "socks", "en")).toBe(true);
    expect(isGenericChunk(parts("put on", "socks"), "socks", "en")).toBe(false);
  });

  it("**表は短く保つ**（相手の決まっている動詞を落とさない）", () => {
    // 帶雨傘 / take a photo / get a haircut — どれも「どの名詞にも付く」
    // ように見えて、実は相手が決まっている。落とすと型の欄が空になる。
    expect(isGenericChunk(parts("帶", "雨傘"), "雨傘")).toBe(false);
    expect(isGenericChunk(parts("take", "a", "photo"), "photo", "en")).toBe(false);
    expect(isGenericChunk(parts("用", "雨傘"), "雨傘")).toBe(false);
  });

  it("大小・前後の飾りに惑わされない", () => {
    expect(isGenericChunk(parts("Buy", "socks."), "socks", "en")).toBe(true);
  });
});

describe("isGenericChunk — 残すべきもの", () => {
  it("**その語にだけ付く動詞は残す**(喝は飲み物にしか付かない)", () => {
    expect(isGenericChunk(parts("喝", "珍珠奶茶"), "珍珠奶茶")).toBe(false);
  });

  it("**很+状態動詞は落とさない**(台湾華語で最初に覚える公式)", () => {
    expect(isGenericChunk(parts("很", "好喝"), "好喝")).toBe(false);
  });

  it("その語ならではの言い方は残す", () => {
    for (const p of [parts("半糖", "少冰"), parts("加", "珍珠"), parts("珍珠奶茶", "店")]) {
      expect(isGenericChunk(p, "珍珠奶茶")).toBe(false);
    }
  });

  it("軽い語が1つ混ざっていても、他に中身があれば残す", () => {
    expect(isGenericChunk(parts("買", "一送一"), "買")).toBe(false);
  });

  it("空・壊れた入力で落ちない（**ここでは落とさない**。空は別の門の仕事）", () => {
    // 空の型は `refineUsageChunks` が長さで落とす。ここで重ねて落とすと、
    // 「なぜ消えたか」が2箇所に散る。
    expect(isGenericChunk(null, "手機")).toBe(false);
    expect(isGenericChunk([], "手機")).toBe(false);
    expect(isGenericChunk(parts("", "  "), "手機")).toBe(false);
  });
});

describe("withoutGenericChunks", () => {
  it("汎用だけを落として、順番は変えない", () => {
    const chunks = [
      { parts: parts("買", "珍珠奶茶") },
      { parts: parts("喝", "珍珠奶茶") },
      { parts: parts("喜歡", "珍珠奶茶") },
      { parts: parts("半糖", "少冰") },
    ];
    expect(withoutGenericChunks(chunks, "珍珠奶茶").map((c) => c.parts[0].text)).toEqual([
      "喝",
      "半糖",
    ]);
  });

  it("全部が汎用なら空になる（**無理に残さない**）", () => {
    const chunks = [{ parts: parts("買", "手機") }, { parts: parts("有", "手機") }];
    expect(withoutGenericChunks(chunks, "手機")).toEqual([]);
  });

  it("空・null でも落ちない", () => {
    expect(withoutGenericChunks(null, "手機")).toEqual([]);
    expect(withoutGenericChunks([], "手機")).toEqual([]);
  });

  it("**言語を渡さないと台湾華語の表で測る**(英語の型が素通りする)", () => {
    // 渡さなければ英語の軽い語は表に無いので残る。渡せば落ちる。
    const chunks = [{ parts: parts("buy", "socks") }];
    expect(withoutGenericChunks(chunks, "socks")).toHaveLength(1);
    expect(withoutGenericChunks(chunks, "socks", "en")).toHaveLength(0);
  });
});

describe("isGenericChunk — この・その（指示語+量詞）だけの型（2026-09-30 保溫瓶）", () => {
  it("`這款 + 保溫瓶` は落とす", () => {
    expect(isGenericChunk(parts("這款", "保溫瓶"), "保溫瓶", "zh-TW")).toBe(true);
    expect(isGenericChunk(parts("那個", "保溫瓶"), "保溫瓶", "zh-TW")).toBe(true);
  });

  it("指示語のほかに中身があれば残す", () => {
    expect(isGenericChunk(parts("裝", "咖啡", "在", "保溫瓶"), "保溫瓶", "zh-TW")).toBe(false);
    expect(isGenericChunk(parts("這款", "保溫瓶", "很", "保溫"), "保溫瓶", "zh-TW")).toBe(false);
  });

  it("量詞の無い 這・那 と 這麼 は落とさない（決まった言い方を作る）", () => {
    expect(isGenericChunk(parts("那", "時候"), "時候", "zh-TW")).toBe(false);
    expect(isGenericChunk(parts("這麼", "好吃"), "好吃", "zh-TW")).toBe(false);
  });

  it("英語には当てない（this morning / so that）", () => {
    expect(isGenericChunk(parts("this", "morning"), "morning", "en")).toBe(false);
  });
});
