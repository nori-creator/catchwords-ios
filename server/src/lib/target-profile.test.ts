import { describe, it, expect } from "vitest";
import {
  EN_PROFILE,
  JA_PROFILE,
  ZH_TW_PROFILE,
  defaultReading,
  hasSection,
  targetProfile,
  type ProfileSection,
} from "./target-profile";
import { RETIRED_SECTIONS, SECTION_IDS } from "./card-sections";
import { DEFAULT_TARGET_LANGUAGE } from "./target-lang";
import fs from "node:fs";
import path from "node:path";

/**
 * 学習言語ごとの違いを1つの表に集めた所の門。
 *
 * オーナー指示「アプリ内の**すべての項目**について…**他にあるはず**」。
 * ここで一番怖いのは**取りこぼし** — 英語版の画面に量詞の欄が出ても、
 * 型でもビルドでも落ちない。数えて押さえる。
 */

describe("targetProfile", () => {
  it("学習言語からプロフィールを引く", () => {
    expect(targetProfile("zh-TW").code).toBe("zh-TW");
  });

  it("**知らない値は既定に落とす**(項目が1つも無いカードを作らない)", () => {
    for (const bad of [null, undefined, "", "  ", "kl-KL", "xx"]) {
      const p = targetProfile(bad);
      expect(p.code).toBe(DEFAULT_TARGET_LANGUAGE);
      expect(p.sections.length).toBeGreaterThan(0);
      expect(p.speechLang).toBeTruthy();
    }
  });
});

describe("どちらの言語も形が揃っている", () => {
  const all = [ZH_TW_PROFILE, EN_PROFILE];

  it("**空の欄を持たない**(画面が空文字で喋らない)", () => {
    for (const p of all) {
      expect(p.code).toBeTruthy();
      expect(p.speechLang).toBeTruthy();
      expect(p.scriptLang).toBeTruthy();
      expect(p.readings.length).toBeGreaterThan(0);
      expect(p.sections.length).toBeGreaterThan(0);
      expect(p.chunkRoles.length).toBeGreaterThan(0);
      expect(p.levels.labels).toHaveLength(6);
    }
  });

  it("項目に重複が無い(同じ欄が2回出ない)", () => {
    for (const p of all) {
      expect(new Set(p.sections).size).toBe(p.sections.length);
    }
  });

  it("読みの表記に重複が無い", () => {
    for (const p of all) {
      expect(new Set(p.readings).size).toBe(p.readings.length);
    }
  });

  it("**どちらにも意味と例文がある**(これが無いとカードにならない)", () => {
    for (const p of all) {
      expect(hasSection(p, "meaning")).toBe(true);
      expect(hasSection(p, "example")).toBe(true);
    }
  });
});

describe("言語で違う項目 — オーナー指摘の本体", () => {
  it("**量詞は台湾華語だけ**(英語に量詞は無い)", () => {
    expect(hasSection(ZH_TW_PROFILE, "measure_words")).toBe(true);
    expect(hasSection(EN_PROFILE, "measure_words")).toBe(false);
  });

  it("**活用は英語だけ**(中国語は語形が変わらない)", () => {
    expect(hasSection(EN_PROFILE, "forms")).toBe(true);
    expect(hasSection(ZH_TW_PROFILE, "forms")).toBe(false);
  });

  it("**冠詞・可算は英語だけ**(中国語に冠詞が無い＝最大の誤り)", () => {
    expect(hasSection(EN_PROFILE, "countability")).toBe(true);
    expect(hasSection(ZH_TW_PROFILE, "countability")).toBe(false);
  });

  it("**強勢は英語だけ**(通じるかどうかを最も左右する)", () => {
    expect(hasSection(EN_PROFILE, "stress")).toBe(true);
    expect(hasSection(ZH_TW_PROFILE, "stress")).toBe(false);
  });

  it("句動詞は英語だけ", () => {
    expect(hasSection(EN_PROFILE, "phrasal_verbs")).toBe(true);
    expect(hasSection(ZH_TW_PROFILE, "phrasal_verbs")).toBe(false);
  });

  it("**文化の一言は名前ごと入れ替える**(台湾メモ → culture_note)", () => {
    expect(hasSection(ZH_TW_PROFILE, "taiwan_note")).toBe(true);
    expect(hasSection(EN_PROFILE, "taiwan_note")).toBe(false);
    expect(hasSection(EN_PROFILE, "culture_note")).toBe(true);
    expect(hasSection(ZH_TW_PROFILE, "culture_note")).toBe(false);
  });

  it("読みの表記が入れ替わる(注音/拼音 ↔ 米/英のIPA)", () => {
    expect(defaultReading(ZH_TW_PROFILE)).toBe("zhuyin");
    // オーナー決定 2026-08-24「アメリカ英語を既定」。
    expect(defaultReading(EN_PROFILE)).toBe("ipa-us");
  });

  it("級の体系が入れ替わる", () => {
    expect(ZH_TW_PROFILE.levels.id).toBe("TOCFL");
    expect(EN_PROFILE.levels.id).toBe("CEFR");
  });

  it("チャンクの役割が入れ替わる(量詞 ↔ 冠詞)", () => {
    expect(ZH_TW_PROFILE.chunkRoles).toContain("M");
    expect(EN_PROFILE.chunkRoles).toContain("Det");
    expect(EN_PROFILE.chunkRoles).not.toContain("M");
  });

  it("読み上げの言語が入れ替わる", () => {
    expect(ZH_TW_PROFILE.speechLang).toBe("zh-TW");
    expect(EN_PROFILE.speechLang).toBe("en-US");
  });
});

describe("headwordOk — 母語のまま図鑑に入れない", () => {
  it("台湾華語は漢字だけ通す", () => {
    expect(ZH_TW_PROFILE.headwordOk("腳踏車")).toBe(true);
    expect(ZH_TW_PROFILE.headwordOk("文旦")).toBe(true);
  });

  it("**かなや欧文が混ざる物は通さない**(「シャーペン」が図鑑に入った前例)", () => {
    expect(ZH_TW_PROFILE.headwordOk("シャーペン")).toBe(false);
    expect(ZH_TW_PROFILE.headwordOk("けしごむ")).toBe(false);
    expect(ZH_TW_PROFILE.headwordOk("pencil")).toBe(false);
    expect(ZH_TW_PROFILE.headwordOk("シャーペンpen")).toBe(false);
  });

  it("英語はラテン文字を通す", () => {
    expect(EN_PROFILE.headwordOk("bicycle")).toBe(true);
    expect(EN_PROFILE.headwordOk("night market")).toBe(true);
  });

  it("**英語版に漢字やかなを通さない**(同じ間違いの裏返し)", () => {
    expect(EN_PROFILE.headwordOk("腳踏車")).toBe(false);
    expect(EN_PROFILE.headwordOk("じてんしゃ")).toBe(false);
  });

  it("空・記号だけはどちらも通さない", () => {
    for (const p of [ZH_TW_PROFILE, EN_PROFILE]) {
      expect(p.headwordOk("")).toBe(false);
      expect(p.headwordOk("   ")).toBe(false);
      expect(p.headwordOk("、。！")).toBe(false);
    }
  });
});

describe("いまの画面と食い違っていない", () => {
  /**
   * ## 第2段からの引き継ぎ
   * ここは以前「台湾華語の項目 == `SECTION_IDS` **完全一致**」と
   * 「英語だけの項目は `SECTION_IDS` に**まだ無い**」を見ていた。
   * 第2段の約束が「見た目を1つも変えない」だったからで、
   * その時点では正しい門だった。
   *
   * 第4段(2026-08-25)で英語の項目を実際に足したので、両方とも
   * **意味が反転する**。完全一致は成り立たない(`SECTION_IDS` の方が
   * 英語の5項目ぶん多い)。見るべき不変は「**どちらにも在る**」
   * — プロフィールに在るのに描けない項目、描けるのにどの言語からも
   * 参照されない項目、のどちらも作らないこと。
   */
  it("**台湾華語の項目は、全部 `card-sections.ts` に在る**(在るのに描けない物を作らない)", () => {
    for (const s of ZH_TW_PROFILE.sections) {
      expect((SECTION_IDS as readonly string[]).includes(s), s).toBe(true);
    }
  });

  it("**英語の項目も、全部 `card-sections.ts` に在る**", () => {
    for (const s of EN_PROFILE.sections) {
      expect((SECTION_IDS as readonly string[]).includes(s), s).toBe(true);
    }
  });

  it("**英語だけの5項目は、台湾華語のカードには出ない**", () => {
    const enOnly: ProfileSection[] = [
      "forms",
      "countability",
      "stress",
      "phrasal_verbs",
      "culture_note",
    ];
    for (const s of enOnly) {
      expect(EN_PROFILE.sections, s).toContain(s);
      expect(ZH_TW_PROFILE.sections, s).not.toContain(s);
    }
  });

  it("**台湾華語だけの2項目は、英語のカードには出ない**", () => {
    // 量詞は英語に無い。台湾メモの位置には `culture_note` が入る。
    for (const s of ["measure_words", "taiwan_note"] as ProfileSection[]) {
      expect(ZH_TW_PROFILE.sections, s).toContain(s);
      expect(EN_PROFILE.sections, s).not.toContain(s);
    }
  });

  it("**`SECTION_IDS` に、どちらからも参照されない項目が無い**(死んだ節を作らない)", () => {
    const used = new Set([
      ...ZH_TW_PROFILE.sections,
      ...EN_PROFILE.sections,
      ...JA_PROFILE.sections,
    ]);
    for (const id of SECTION_IDS) {
      if (RETIRED_SECTIONS.includes(id)) continue;
      expect([...used], id).toContain(id);
    }
  });
});

describe("headwordOk — 文字の判定は1箇所しかない", () => {
  it("**`target-language.ts` は自前の正規表現を持っていない**(正は1つ)", () => {
    // 判定を写すのではなく、この表を呼んでいること。文字列で確かめる
    // のは乱暴だが、「同じ結果が出るか」で見ると**両方に同じ写しが
    // 在る**状態も通ってしまい、食い違いを止められない。
    const src = fs.readFileSync(path.join("src", "lib", "target-language.ts"), "utf8");
    expect(src).not.toMatch(/ぁ-ゟ/);
    expect(src).not.toMatch(/㐀-䶿/);
    expect(src).toContain("target-profile");
  });

  it("**キリル文字・ハングルも通さない**(欧文だけを見ていた版の穴)", () => {
    expect(ZH_TW_PROFILE.headwordOk("Привет")).toBe(false);
    expect(ZH_TW_PROFILE.headwordOk("안녕")).toBe(false);
    expect(EN_PROFILE.headwordOk("Привет")).toBe(false);
    expect(EN_PROFILE.headwordOk("안녕")).toBe(false);
  });

  it("英語は飾りを落としてから見る(2語・アポストロフィ・ハイフン)", () => {
    expect(EN_PROFILE.headwordOk("night market")).toBe(true);
    expect(EN_PROFILE.headwordOk("don't")).toBe(true);
    expect(EN_PROFILE.headwordOk("well-known")).toBe(true);
  });
});

describe("撮る道のプロンプトが言語で分岐しない（2026-08-25）", () => {
  /**
   * `ai.functions.ts` は
   * `targetLanguage === DEFAULT_TARGET_LANGUAGE ? 40行の指示 : 1行`
   * という形だった。台湾華語にはカテゴリの規則も「上位の分類語に逃げない」も
   * 在るのに、それ以外は
   *
   *   「画像から en の学習対象として有用な名詞を5つ選び、
   *     headword(en)、日本語の意味、カテゴリを返してください。」
   *
   * に落ちる。**撮る道を学習言語に繋いだ日から、英語の学習者が実際に
   * ここに当たる。** カテゴリは other だらけになり、`en` というコードが
   * そのままプロンプトに出る。
   *
   * 画面には出ない文なので、出来上がったカードを読むまで気づけない。
   */
  const src = fs.readFileSync("src/lib/ai.functions.ts", "utf8");

  it("**学習言語で分岐していない**", () => {
    expect(src.includes("data.targetLanguage === DEFAULT_TARGET_LANGUAGE")).toBe(false);
  });

  it("**言語のコードをそのままプロンプトに書いていない**(`en` と出る)", () => {
    // `${data.targetLanguage}` を文中に埋めると、読める名前ではなく
    // `en` `zh-TW` というコードが AI に渡る。呼び名は `promptName`。
    expect(src.includes("${data.targetLanguage}")).toBe(false);
  });

  it("どちらの言語も、撮る道の指示が全部そろっている", () => {
    for (const p of [ZH_TW_PROFILE, EN_PROFILE]) {
      expect(p.capture.scriptRule.trim(), p.code).not.toBe("");
      expect(p.capture.specificity.length, p.code).toBe(3);
      for (const sp of p.capture.specificity) expect(sp.trim(), p.code).not.toBe("");
      expect(p.capture.distinctionExamples.trim(), p.code).not.toBe("");
      expect(p.capture.posRule.trim(), p.code).not.toBe("");
      expect(p.capture.readingRule.trim(), p.code).not.toBe("");
      expect(p.capture.pronunciationFocus.trim(), p.code).not.toBe("");
    }
  });

  it("**言語ごとに中身が違う**(使い回すと片方が的外れになる)", () => {
    const a = ZH_TW_PROFILE.capture;
    const b = EN_PROFILE.capture;
    expect(a.scriptRule).not.toBe(b.scriptRule);
    expect(a.posRule).not.toBe(b.posRule);
    expect(a.readingRule).not.toBe(b.readingRule);
    expect(a.pronunciationFocus).not.toBe(b.pronunciationFocus);
    expect(a.distinctionExamples).not.toBe(b.distinctionExamples);
    for (let i = 0; i < 3; i++) expect(a.specificity[i]).not.toBe(b.specificity[i]);
  });

  it("**英語の指示に華語だけの話が混ざっていない**", () => {
    const c = EN_PROFILE.capture;
    const text = [
      c.scriptRule,
      ...c.specificity,
      c.distinctionExamples,
      c.posRule,
      c.readingRule,
      c.pronunciationFocus,
    ].join(" ");
    // 注音・拼音・繁体字・簡体字・声調・量詞は華語の話。
    for (const word of ["注音", "拼音", "繁体字", "簡体字", "声調", "量詞"]) {
      // `readingRule` は「注音は空」と**書かないと**モデルが埋めようとするので、
      // 「空文字」と一緒に出てくる分だけは許す。
      const bad = text.includes(word) && !c.readingRule.includes(word);
      expect(bad, `英語の指示に「${word}」`).toBe(false);
    }
  });

  it("**華語の指示に英語だけの話が混ざっていない**", () => {
    const c = ZH_TW_PROFILE.capture;
    const text = [c.scriptRule, ...c.specificity, c.posRule, c.pronunciationFocus].join(" ");
    for (const word of ["IPA", "強勢", "アメリカ英語"]) {
      expect(text.includes(word), `華語の指示に「${word}」`).toBe(false);
    }
  });
});
