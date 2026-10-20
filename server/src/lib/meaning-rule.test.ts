import { describe, expect, it } from "vitest";
import { meaningRule, distinctionRule, NO_PADDING } from "./meaning-rule";

describe("meaningRule — 1対1なら訳語だけ", () => {
  it("「1対1なら1語だけ」と言い切る", () => {
    const r = meaningRule("英語", "繁體中文");
    expect(r).toContain("1対1で対応する語");
    expect(r).toContain("その語だけ");
  });

  it("説明してよい2つの場合を明示する", () => {
    const r = meaningRule("英語", "日本語");
    expect(r).toContain("意味が分かれてしまう");
    expect(r).toContain("対応する語が無い");
  });

  it("解説の言語名を必ず書き込む", () => {
    expect(meaningRule("英語", "繁體中文")).toContain("繁體中文");
    expect(meaningRule("台湾華語", "日本語")).toContain("日本語");
  });
});

describe("distinctionRule — 区別が要るときだけ", () => {
  it("学習言語の名前と例を差し込む", () => {
    const r = distinctionRule("英語", "shrimp / prawn");
    expect(r).toContain("英語");
    expect(r).toContain("shrimp / prawn");
  });

  it("迷いようがない語は空文字にさせる", () => {
    expect(distinctionRule("英語", "x")).toContain("空文字");
  });
});

describe("言い換え禁止は**両方**に入る", () => {
  it("同じ一節を共有している(片方だけ古くならない)", () => {
    // 同じ原則を2箇所の散文に書くと、必ず片方だけ古くなる。
    expect(meaningRule("英語", "日本語")).toContain(NO_PADDING);
    expect(distinctionRule("英語", "x")).toContain(NO_PADDING);
  });

  it("「迷ったら書かない」が抜けていない", () => {
    // ここが抜けると、AI は全部の行を埋めにいく。
    expect(NO_PADDING).toContain("迷ったら書かない");
    expect(NO_PADDING).toContain("無いより悪い");
  });
});

import { shortMeaning } from "./meaning-rule";

describe("shortMeaning（意味は語の長さに）", () => {
  it("説明文で返った意味を最初の区切りまでに縮める（湯咖哩）", () => {
    expect(
      shortMeaning(
        "Soup curry, a Japanese-style curry dish served in a thin, broth-like sauce often containing large pieces of vegetables",
      ),
    ).toBe("Soup curry");
    expect(shortMeaning("スープカレー。北海道発祥の、さらさらしたスープ状のカレー料理")).toBe(
      "スープカレー",
    );
  });
  it("短い意味・区切りの無い意味は触らない", () => {
    expect(shortMeaning("タピオカミルクティー")).toBe("タピオカミルクティー");
    expect(shortMeaning("umbrella")).toBe("umbrella");
    expect(shortMeaning("")).toBe("");
  });
});

import { withShortMeaning, MEANING_LENGTH_RULE_EN } from "./meaning-rule";
import { quizPromptMeaning } from "./review-explain";

describe("長すぎる意味（オーナー報告 2026-10-05 の復習の4択）", () => {
  const LONG =
    "ゴキブリ駆除用の毒餌（ベイト剤）。ゴキブリが好む成分と殺虫剤を混ぜ、食べさせて巣ごと駆除するための薬剤。";

  it("最初の区切りまでに縮める", () => {
    expect(shortMeaning(LONG)).toBe("ゴキブリ駆除用の毒餌");
  });

  it("区切りが無い長い意味は上限で切って「…」を付ける", () => {
    const s = shortMeaning("あ".repeat(40));
    expect(Array.from(s).length).toBeLessThanOrEqual(20);
    expect(s.endsWith("…")).toBe(true);
    const en = shortMeaning(
      "an extremely long english gloss that never uses any punctuation at all whatsoever",
    );
    expect(en.length).toBeLessThanOrEqual(40);
    expect(en.endsWith("…")).toBe(true);
  });

  it("区切りの手前がまだ長い時も上限に収める", () => {
    const s = shortMeaning(`${"い".repeat(30)}。説明`);
    expect(Array.from(s).length).toBeLessThanOrEqual(20);
  });

  it("4択の問いの「」には縮めた意味が入る", () => {
    expect(quizPromptMeaning({ shared: LONG, headword: "蟑螂藥", lang: "ja" })).toBe(
      "ゴキブリ駆除用の毒餌",
    );
    // 短い意味は1字も変えない
    expect(quizPromptMeaning({ shared: "傘", headword: "雨傘", lang: "ja" })).toBe("傘");
  });

  it("保存前に縮め、削れた説明は空の使い方の欄へ移す（元の文を捨てない）", () => {
    const card = withShortMeaning({ meaning_ja: LONG, extras: { usage_context: "" } });
    expect(card.meaning_ja).toBe("ゴキブリ駆除用の毒餌");
    expect(card.extras.usage_context).toBe(LONG);
    const kept = withShortMeaning({ meaning_ja: LONG, extras: { usage_context: "台所で" } });
    expect(kept.extras.usage_context).toBe("台所で");
    const same = { meaning_ja: "傘", extras: { usage_context: "" } };
    expect(withShortMeaning(same)).toBe(same);
  });

  it("チュートリアルの AI への指示にも長さの上限がある", () => {
    expect(MEANING_LENGTH_RULE_EN).toMatch(/15 characters/);
    expect(MEANING_LENGTH_RULE_EN).toMatch(/4 words/);
  });
});
