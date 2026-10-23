import { describe, expect, it } from "vitest";
import { choice, choiceProb, noul, parseJevAnswers, score } from "./jev";

describe("Jev の問いの形（公式 SDK と同じ）", () => {
  it("noul / choice / score を SDK と同じ形で作る", () => {
    expect(noul("Is it billing?")).toEqual({ type: "noul", instructions: "Is it billing?" });
    expect(choice("Which?", { a: null, b: "desc" })).toEqual({
      type: "choice",
      instructions: "Which?",
      criteria: { a: null, b: "desc" },
    });
    expect(score("How?", ["low", "high"])).toEqual({
      type: "score",
      instructions: "How?",
      criteria: ["low", "high"],
    });
  });

  it("score の段階が2つ未満なら作らない（API が弾く形を送らない）", () => {
    expect(() => score("x", ["only"])).toThrow();
  });
});

describe("Jev の答えは確かめてから使う", () => {
  it("正しい形の答えを読む", () => {
    const got = parseJevAnswers({
      model: "jev-1",
      answers: {
        yes: { type: "noul", noul: 0.8 },
        cat: { type: "choice", choice: "b", confidence: 0.7, probabilities: { a: 0.3, b: 0.7 } },
        lvl: {
          type: "score",
          score: 1.4,
          confidence: 0.5,
          probabilities: { "0": 0.2, "1": 0.3, "2": 0.5 },
        },
      },
    });
    expect(got.yes).toEqual({ type: "noul", noul: 0.8 });
    expect(choiceProb(got.cat, "b")).toBe(0.7);
    expect(got.lvl.type).toBe("score");
  });

  it("**形の違う答えは捨てる**（壊れた確率で並べ替えない）", () => {
    const got = parseJevAnswers({
      answers: {
        bad1: { type: "noul", noul: 1.7 },
        bad2: { type: "noul" },
        bad3: { type: "choice", choice: "z", probabilities: { a: 1 } },
        bad4: { type: "choice", choice: "a", probabilities: { a: "0.9" } },
        bad5: null,
        ok: { type: "noul", noul: 0 },
      },
    });
    expect(Object.keys(got)).toEqual(["ok"]);
  });

  it("答えが1つも無い・形が違う本文は空で返す", () => {
    expect(parseJevAnswers(null)).toEqual({});
    expect(parseJevAnswers({})).toEqual({});
    expect(parseJevAnswers({ answers: "nope" })).toEqual({});
  });

  it("choice 以外から確率は取れない", () => {
    expect(choiceProb({ type: "noul", noul: 0.9 }, "a")).toBeNull();
    expect(choiceProb(undefined, "a")).toBeNull();
  });
});
