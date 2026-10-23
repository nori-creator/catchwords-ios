import { describe, expect, it } from "vitest";
import { bandDescription, grammarAllowance, levelRuleText } from "./level-instruction";
import { CEFR_SCALE, LEVEL_INDEXES, TOCFL_SCALE, type LevelIndex } from "./level-scale";
import { GRAMMAR_ITEMS, grammarAtOrBelow } from "./grammar-profile";

/**
 * ここで守っているのは「**英語の学習者に華語の級の話が渡らない**」こと。
 *
 * この文は AI へ渡るだけで**画面には出ない**ので、間違っていても
 * 出来上がったカードを読むまで誰も気づかない。しかも AI は言われた
 * とおりに従うので、静かに中身が壊れる。
 */

describe("bandDescription — 体系ごとに別の説明", () => {
  it("6段とも埋まっている(空の指示を渡さない)", () => {
    for (const scale of [TOCFL_SCALE, CEFR_SCALE]) {
      for (const i of LEVEL_INDEXES) {
        expect(bandDescription(scale, i).trim(), `${scale.id}-${i}`).not.toBe("");
      }
    }
  });

  it("**TOCFL と CEFR で中身が違う**(同じなら分ける意味が無い)", () => {
    for (const i of LEVEL_INDEXES) {
      expect(bandDescription(TOCFL_SCALE, i)).not.toBe(bandDescription(CEFR_SCALE, i));
    }
  });

  it("**英語の説明に華語の級の言葉が混ざっていない**", () => {
    // 「準備級」「注音」「把構文」は華語の話。英語の学習者に渡ると、
    // AI が英語のカードに華語の級の話を書き始める。
    for (const i of LEVEL_INDEXES) {
      const text = bandDescription(CEFR_SCALE, i);
      for (const word of ["準備級", "注音", "把構文", "成語", "TOCFL"]) {
        expect(text.includes(word), `CEFR-${i} に「${word}」`).toBe(false);
      }
    }
  });

  it("**華語の説明に英語の級の言葉が混ざっていない**", () => {
    for (const i of LEVEL_INDEXES) {
      const text = bandDescription(TOCFL_SCALE, i);
      for (const word of ["CEFR", "現在完了", "関係代名詞"]) {
        expect(text.includes(word), `TOCFL-${i} に「${word}」`).toBe(false);
      }
    }
  });
});

describe("grammarAllowance — CEFR-J の文法項目", () => {
  it("**華語の級には付けない**(英語の文法の表なので)", () => {
    for (const i of LEVEL_INDEXES) expect(grammarAllowance(TOCFL_SCALE, i)).toBe("");
  });

  it("英語の級には付く", () => {
    expect(grammarAllowance(CEFR_SCALE, 1)).not.toBe("");
  });

  it("**上の級ほど項目が増える**(級が上がっても同じなら効いていない)", () => {
    const counts = [1, 2, 3, 4].map((i) => grammarAtOrBelow(i).length);
    for (let i = 1; i < counts.length; i++) {
      expect(counts[i], `段${i + 1}`).toBeGreaterThan(counts[i - 1]);
    }
  });

  it("出典を必ず名乗る(CEFR-J は明記が利用の条件)", () => {
    expect(grammarAllowance(CEFR_SCALE, 3)).toContain("CEFR-J");
    expect(grammarAllowance(CEFR_SCALE, 3)).toContain("投野由紀夫研究室");
  });

  it("**長くなりすぎない**(プロンプトが伸びるほど他の指示が効かなくなる)", () => {
    for (const i of LEVEL_INDEXES) {
      expect(grammarAllowance(CEFR_SCALE, i).length, `段${i}`).toBeLessThan(1200);
    }
  });

  it("落とした分は「ほか N 項目」と言う(黙って捨てない)", () => {
    const text = grammarAllowance(CEFR_SCALE, 4, 5);
    expect(text).toMatch(/ほか\d+項目/);
  });

  it("C1/C2 には CEFR-J の項目が無いので B2 までと同じ(作り話をしない)", () => {
    // CEFR-J は B2 (段4) までしか無い。段5・6で項目が増えたら、
    // それは出典に無い物を足している。
    expect(grammarAtOrBelow(5).length).toBe(GRAMMAR_ITEMS.length);
    expect(grammarAtOrBelow(6).length).toBe(GRAMMAR_ITEMS.length);
  });
});

describe("levelRuleText — 渡す文まるごと", () => {
  const authority = (id: string) => (id === "CEFR" ? "CEFR-J Wordlist" : "TOCFL公式語彙表");
  const build = (scale = CEFR_SCALE, cur = "A1", goal = "B1") =>
    levelRuleText(scale, cur, goal, authority(scale.id));

  it("級の名前をその体系の書き方で出す", () => {
    expect(build(CEFR_SCALE, "A1", "B1")).toContain("CEFR B1");
    expect(build(TOCFL_SCALE, "TOCFL-1", "TOCFL-3")).toContain("TOCFL 3");
  });

  it("**別の体系の表記が混ざらない**", () => {
    expect(build(CEFR_SCALE, "A1", "B1")).not.toContain("TOCFL");
    expect(build(TOCFL_SCALE, "TOCFL-1", "TOCFL-3")).not.toContain("CEFR ");
  });

  it("**前の言語の級を渡されても、その体系の表記に載せ替える**", () => {
    // 台湾華語で2級だった人が英語に切り替えた直後。DB には "TOCFL-2"。
    const text = build(CEFR_SCALE, "TOCFL-1", "TOCFL-2");
    expect(text).toContain("CEFR A2");
    expect(text).not.toContain("TOCFL-2");
  });

  it("読めない級は既定の段に落とす(未知の級のまま生成させない)", () => {
    for (const bad of ["", "  ", "級外", "unknown", "TOCFL-9"]) {
      const text = build(CEFR_SCALE, bad, bad);
      expect(text, bad).toContain("CEFR A2");
    }
  });

  it("現在は目標より上にしない(i+1 の帯が逆さまにならない)", () => {
    // 目標 A2、現在 C2 と入れても、現在の級はそのまま出る。
    // ここは「入っている値を出す」のが仕事で、直すのは設定の側。
    const text = build(CEFR_SCALE, "C2", "A2");
    expect(text).toContain("CEFR A2");
  });

  it("語彙表の名前を必ず名乗る(どの表かを言わないと効かない)", () => {
    expect(build(CEFR_SCALE)).toContain("CEFR-J Wordlist");
    expect(build(TOCFL_SCALE, "TOCFL-1", "TOCFL-2")).toContain("TOCFL公式語彙表");
  });

  it("**どの段でも文が組める**(落ちる組み合わせが無い)", () => {
    for (const scale of [TOCFL_SCALE, CEFR_SCALE]) {
      for (const i of LEVEL_INDEXES) {
        const v = scale.toStored(i as LevelIndex);
        expect(
          levelRuleText(scale, v, v, authority(scale.id)).length,
          `${scale.id}-${i}`,
        ).toBeGreaterThan(50);
      }
    }
  });
});

describe("exampleLevelRule（例文1文の目安、2026-10-15）", () => {
  it("現在の級の目安を狙い、目標の級までを上限にし、見出し語は言い換えない", async () => {
    const { exampleLevelRule } = await import("./level-instruction");
    const { TOCFL_SCALE } = await import("./level-scale");
    const r = exampleLevelRule(TOCFL_SCALE, "TOCFL-1", "TOCFL-4", "珍珠奶茶");
    expect(r).toMatch(/8〜12字/);
    expect(r).toMatch(/把・被・複文・補語は使わない/);
    expect(r).toMatch(/25〜30字/);
    expect(r).toMatch(/見出し語「珍珠奶茶」はレベルに関係なくそのまま使う/);
    // 2026-10-15 オーナー「最も重要なのはネイティブが最も自然に使う例文」— 級は目安、自然さが決まり。
    expect(r).toMatch(/いちばん大事なのは「ネイティブがその場面で最も自然に言う一文」/);
    expect(r).toMatch(/自然な文のまま書く/);
    expect(r).not.toMatch(/それより上の語彙・文法は使わない/);
  });

  it("体系ごとに別の表（英語の学習者に華語の字数を渡さない）", async () => {
    const { exampleLevelRule } = await import("./level-instruction");
    const { CEFR_SCALE, JLPT_SCALE } = await import("./level-scale");
    const en = exampleLevelRule(CEFR_SCALE, "A1", "A1", "umbrella");
    expect(en).toMatch(/5〜8語/);
    expect(en).not.toMatch(/字/);
    expect(exampleLevelRule(JLPT_SCALE, "JLPT-N5", "JLPT-N5", "傘")).toMatch(/です・ます/);
  });
});
