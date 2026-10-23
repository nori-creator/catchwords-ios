import { describe, expect, it } from "vitest";
import { explainOf, pickReviewExplain, quizPromptMeaning } from "./review-explain";

/**
 * 復習の問いの意味と答え合わせ（オーナー報告 2026-10-02、絵つき。表示言語が英語・繁體中文で
 * 「Which one means “グラタンマカロニ”?」、答え合わせの訳が1つも出ない）。
 */
describe("quizPromptMeaning — 4択の問いの「」に入れる意味", () => {
  it("**日本語の表示で日本語の意味は、そのまま**（今と1字も変わらない）", () => {
    expect(
      quizPromptMeaning({
        shared: "グラタンマカロニ",
        explanation: "マカロニグラタン（オーブン料理）",
        cached: "別の意味",
        lang: "ja",
      }),
    ).toBe("グラタンマカロニ");
  });

  it("英語の人に日本語の意味を出さない — その人向けの解説の意味を使う", () => {
    expect(
      quizPromptMeaning({
        shared: "グラタンマカロニ",
        explanation: "macaroni gratin",
        lang: "en",
      }),
    ).toBe("macaroni gratin");
  });

  it("繁體中文の人も同じ（かなの入った意味は出さない）", () => {
    expect(quizPromptMeaning({ shared: "ノート", explanation: "筆記本", lang: "zh-TW" })).toBe(
      "筆記本",
    );
  });

  it("解説の意味が無ければ、図鑑と同じ覚え置きを使う", () => {
    expect(
      quizPromptMeaning({ shared: "ノート", explanation: "", cached: "notebook", lang: "en" }),
    ).toBe("notebook");
  });

  it("解説の意味も別の言語（共有の意味を写した古い行）なら、そこも飛ばす", () => {
    expect(
      quizPromptMeaning({
        shared: "ノート",
        explanation: "ノート",
        cached: "notebook",
        lang: "en",
      }),
    ).toBe("notebook");
  });

  it("**どれも無ければ空** — 呼ぶ側は写真で問う（別の言語の意味は出さない）", () => {
    expect(quizPromptMeaning({ shared: "ノート", lang: "en" })).toBe("");
    expect(quizPromptMeaning({ shared: "ノート", lang: "zh-TW" })).toBe("");
  });

  it("長い説明文で返った意味は語の長さに縮める（図鑑と同じ）", () => {
    expect(
      quizPromptMeaning({
        shared: "ノート",
        explanation:
          "Notebook, a bound set of blank pages used for writing notes in class or at work",
        lang: "en",
      }),
    ).toBe("Notebook");
  });

  it("**答えそのものを含む意味は使わない**（繁體中文で台湾華語を学ぶ人の「筆記本」）", () => {
    expect(
      quizPromptMeaning({
        shared: "ノート",
        headword: "筆記本",
        explanation: "筆記本",
        cached: "記事用的本子",
        lang: "zh-TW",
      }),
    ).toBe("記事用的本子");
    expect(
      quizPromptMeaning({
        shared: "ノート",
        headword: "筆記本",
        explanation: "筆記本",
        lang: "zh-TW",
      }),
    ).toBe("");
  });

  it("英語の表示で、共有の意味がもう英語ならそのまま", () => {
    expect(quizPromptMeaning({ shared: "umbrella", explanation: "雨傘", lang: "en" })).toBe(
      "umbrella",
    );
  });
});

describe("explainOf — 答え合わせの解説（server と画面で同じ物）", () => {
  const extras = {
    explain_lang: "en",
    usage_chunks: [
      {
        parts: [
          { text: "寫", pos: "V" },
          { text: "筆記本", pos: "N" },
        ],
        ja: "write in a notebook",
      },
    ],
    related_words: [{ word: "本子", kind: "syn", note: "notebook (casual)" }],
    measure_words: [{ word: "本", note: "for bound things" }],
  };

  it("その人向けの解説（英語）から組むと、訳が残る", () => {
    const ex = explainOf(extras, "筆記本", "zh-TW", "en");
    expect(ex?.chunks[0].ja).toBe("write in a notebook");
    expect(ex?.related[0].note).toBe("notebook (casual)");
    expect(ex?.measures[0].note).toBe("for bound things");
  });

  it("読む人の言語でない訳は落とす（日本語の解説を英語の人へ）", () => {
    const ja = {
      ...extras,
      usage_chunks: [
        {
          parts: [
            { text: "寫", pos: "V" },
            { text: "筆記本", pos: "N" },
          ],
          ja: "ノートに書く",
        },
      ],
    };
    expect(explainOf(ja, "筆記本", "zh-TW", "en")?.chunks[0].ja).toBe("");
  });

  it("中身が無ければ null", () => {
    expect(explainOf({ explain_lang: "en" }, "筆記本", "zh-TW", "en")).toBeNull();
    expect(explainOf(null, "筆記本", "zh-TW", "en")).toBeNull();
  });
});

describe("pickReviewExplain", () => {
  const server = { chunks: [], related: [], measures: [], note: "server" };
  const reader = { chunks: [], related: [], measures: [], note: "reader" };
  it("その人向けの解説があればそちら、無ければ server の物", () => {
    expect(pickReviewExplain(server, reader)).toBe(reader);
    expect(pickReviewExplain(server, null)).toBe(server);
    expect(pickReviewExplain(null, undefined)).toBeNull();
  });
});
