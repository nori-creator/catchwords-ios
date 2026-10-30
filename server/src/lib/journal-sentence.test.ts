import { describe, expect, it } from "vitest";
import { cleanSentenceCheck, composeFeedback } from "./journal.functions";

const raw = (issues: Array<{ wrong: string; fix: string; kind: string; explain: string }>, natural = "", ok = false) => ({
  ok,
  issues,
  natural,
  natural_note: natural ? "note" : "",
});

describe("cleanSentenceCheck（1文ずつの添削の答えを画面に出せる形に）", () => {
  const s = "我買了三個芒果。";

  it("文に書かれている部分の間違いだけを残す（下線を引ける物）", () => {
    const c = cleanSentenceCheck(
      s,
      raw([
        { wrong: "個", fix: "顆", kind: "measure", explain: "芒果は顆で数える" },
        { wrong: "我們", fix: "我", kind: "word", explain: "文に無い" },
      ]),
    );
    expect(c.issues.map((i) => i.wrong)).toEqual(["個"]);
    expect(c.issues[0].kind).toBe("measure");
    expect(c.ok).toBe(false);
  });

  it("直しが同じ・重複・知らない種類は落とすか直す", () => {
    const c = cleanSentenceCheck(
      s,
      raw([
        { wrong: "芒果", fix: "芒果", kind: "word", explain: "" },
        { wrong: "個", fix: "顆", kind: "量詞", explain: "" },
        { wrong: "個", fix: "顆", kind: "measure", explain: "" },
      ]),
    );
    expect(c.issues).toHaveLength(1);
    expect(c.issues[0].kind).toBe("other");
  });

  it("間違いが残らなければ ok。自然な言い換えが元と同じなら出さない", () => {
    const c = cleanSentenceCheck(s, raw([], "我買了三個芒果", true));
    expect(c.ok).toBe(true);
    expect(c.natural).toBe("");
    expect(c.natural_note).toBe("");
  });

  it("違う自然な言い方はそのまま出す", () => {
    const c = cleanSentenceCheck("我去公園了玩。", raw([{ wrong: "了玩", fix: "玩了", kind: "order", explain: "" }], "我去公園玩了。"));
    expect(c.natural).toBe("我去公園玩了。");
    expect(c.natural_note).toBe("note");
  });

  it("多くても4個まで", () => {
    const issues = "我買了三個芒果".split("").map((ch) => ({ wrong: ch, fix: ch + "x", kind: "word", explain: "" }));
    expect(cleanSentenceCheck(s, raw(issues)).issues).toHaveLength(4);
  });
});

describe("composeFeedback（講評・間違い・傾向を1つの文に残す）", () => {
  it("講評のあとに見出し付きの一覧", () => {
    const t = composeFeedback(
      "よく書けました。",
      [{ wrong: "三個芒果", fix: "三顆芒果", explain: "果物の量詞" }],
      ["量詞を個で済ませがち"],
      { mistakes: "今日の間違い", tendencies: "間違えやすいところ" },
    );
    expect(t).toBe("よく書けました。\n\n今日の間違い\n・三個芒果 → 三顆芒果：果物の量詞\n\n間違えやすいところ\n・量詞を個で済ませがち");
  });

  it("一覧が無ければ講評だけ", () => {
    expect(composeFeedback("OK", [], [], { mistakes: "m", tendencies: "t" })).toBe("OK");
  });
});
