import { describe, it, expect } from "vitest";
import fs from "node:fs";
import path from "node:path";
import {
  L1_ORDER,
  L1_TABLE,
  formatL1Rule,
  isL1Code,
  l1ChoicesFor,
  l1Info,
  pickL1,
  type L1RuleKind,
} from "./l1";
import { CHINESE_EXPLANATION_LANGUAGE } from "./target-lang";

/**
 * 母語干渉の表の門。
 *
 * ## なぜ「現物と突き合わせる」形なのか
 * 2026-08-24 に、整形の見出しを関数の中から表へ出した(英語版で
 * 【量詞】が【冠詞・可算】に変わるため)。この手の書き換えは
 * **型でもビルドでも落ちない**。見出しが1つ抜けても、節の順が入れ替わっても、
 * 動くプロンプトが出てくるだけ。出てくる文字列が変わったかどうかは、
 * 変える前の現物と比べる以外に見る手が無い。
 *
 * `__fixtures__/l1-prompts.zh-TW.json` は**書き換える前**に採った48通り
 * (12母語 × 4用途)の出力そのもの。ここが1文字でも動いたら落ちる。
 *
 * ## 台湾華語の中身を直したくなったら
 * **現物を採り直してよい。** ただし採り直した差分を必ず目で見ること。
 * 「通らないから採り直す」を無言でやると、この門は何も守らなくなる。
 */

const KINDS: L1RuleKind[] = ["pronunciation", "grammar", "wordorder", "both"];
/** 台湾華語話者は英語を学ぶ。他は台湾華語を学ぶ。 */
const targetFor = (code: string) => (code === CHINESE_EXPLANATION_LANGUAGE ? "en" : undefined);
const FIXTURE = path.join("src", "lib", "__fixtures__", "l1-prompts.zh-TW.json");

describe("formatL1Rule — 台湾華語の出力が動いていない", () => {
  const golden = JSON.parse(fs.readFileSync(FIXTURE, "utf8")) as Record<string, string>;

  it("母語 × 用途のぶんだけ現物がある(数が減っていない)", () => {
    expect(Object.keys(golden)).toHaveLength(L1_ORDER.length * KINDS.length);
  });

  for (const code of L1_ORDER) {
    it(`${code} の4用途が現物と1文字も違わない`, () => {
      for (const kind of KINDS) {
        expect(formatL1Rule(l1Info(code), kind, targetFor(code))).toBe(golden[`${code}/${kind}`]);
      }
    });
  }

  it("学習言語を明に渡しても同じ(既定を渡しただけ)", () => {
    for (const kind of KINDS) {
      expect(formatL1Rule(l1Info("ja"), kind, "zh-TW")).toBe(golden[`ja/${kind}`]);
    }
  });

  it("**知らない学習言語でも見出しが空にならない**", () => {
    const got = formatL1Rule(l1Info("ja"), "both", "kl-KL");
    expect(got).toBe(golden["ja/both"]);
    expect(got).not.toMatch(/【】/);
  });
});

describe("用途ごとに要る節だけ入る", () => {
  const info = l1Info("ja");

  it("発音のコツに文法の節を送らない(注意が散る・字数が無駄)", () => {
    const got = formatL1Rule(info, "pronunciation");
    expect(got).toContain("【声調】");
    expect(got).not.toContain("【量詞】");
  });

  it("文法の解説に音韻の節を送らない", () => {
    const got = formatL1Rule(info, "grammar");
    expect(got).toContain("【量詞】");
    expect(got).not.toContain("【声調】");
  });

  it("語順に絞ると3つだけ", () => {
    const got = formatL1Rule(info, "wordorder");
    expect(got).toContain("【語順】");
    expect(got).toContain("【助詞・的/得/地】");
    expect(got).toContain("【崩れやすい構文】");
    expect(got).not.toContain("【量詞】");
    expect(got).not.toContain("【否定】");
  });

  it("添削は両方入る", () => {
    const got = formatL1Rule(info, "both");
    expect(got).toContain("【声調】");
    expect(got).toContain("【量詞】");
  });

  it("**どの用途でもつまずく順と学習言語の事情は落とさない**", () => {
    for (const kind of KINDS) {
      const got = formatL1Rule(info, kind);
      expect(got).toContain("が特につまずく順】");
      expect(got).toContain("【台湾華語の事情】");
    }
  });
});

describe("表そのもの", () => {
  it("設定に並ぶ母語は全部中身を持っている(空の欄でプロンプトを作らない)", () => {
    for (const code of L1_ORDER) {
      const info = L1_TABLE[code];
      expect(info.code).toBe(code);
      expect(info.labelJa).toBeTruthy();
      expect(info.labelEn).toBeTruthy();
      expect(info.speakerJa).toBeTruthy();
      expect(info.priority.length).toBeGreaterThan(0);
      for (const v of Object.values(info.phonology)) expect(v.trim()).toBeTruthy();
      for (const v of Object.values(info.grammar)) expect(v.trim()).toBeTruthy();
      expect(info.taiwan.trim()).toBeTruthy();
    }
  });

  it("**知らない母語は日本語に落とす**(母語不明でプロンプトを空にしない)", () => {
    for (const bad of [null, undefined, "", "  ", "kl", "zz"]) {
      expect(l1Info(bad).code).toBe("ja");
    }
  });

  it("保存前の検証は一覧の外を弾く", () => {
    expect(isL1Code("ja")).toBe(true);
    expect(isL1Code("zz")).toBe(false);
    expect(isL1Code(null)).toBe(false);
    expect(isL1Code(3)).toBe(false);
  });
});

describe("母語は3つ（オーナー決定 2026-08-25）", () => {
  /**
   * 12 → 3 に絞った理由は速さ。解説の共有キャッシュは
   * `(語 × 解説の言語 × 母語)` で引くので、母語が減るほど
   * 「誰かが既に払った解説」に当たりやすくなる。
   * **戻ってきたら落とす** — 数を数える以外に止める手が無い。
   */
  it("日本語・英語・台湾華語の3つだけ", () => {
    expect(L1_ORDER).toEqual(["ja", "en", CHINESE_EXPLANATION_LANGUAGE]);
  });

  it("**消した10言語が戻っていない**", () => {
    for (const gone of ["ko", "vi", "th", "id", "es", "fr", "de", "ru", "pt", "tl"]) {
      expect(isL1Code(gone)).toBe(false);
      expect(L1_TABLE[gone as keyof typeof L1_TABLE]).toBeUndefined();
    }
  });

  it("消した言語を選んでいた人でも壊れない(日本語に落ちる)", () => {
    for (const gone of ["ko", "vi", "tl"]) {
      expect(l1Info(gone).code).toBe("ja");
      expect(formatL1Rule(l1Info(gone), "both")).toBeTruthy();
    }
  });
});

describe("台湾華語話者は英語を学ぶ — 見出しが入れ替わる", () => {
  const zh = l1Info(CHINESE_EXPLANATION_LANGUAGE);

  it("**英語の見出しになる**(量詞ではなく冠詞・可算)", () => {
    const got = formatL1Rule(zh, "grammar", "en");
    expect(got).toContain("【冠詞・可算】");
    expect(got).toContain("【前置詞】");
    expect(got).toContain("【時制・動詞の形】");
    expect(got).not.toContain("【量詞】");
    expect(got).not.toContain("【助詞・的/得/地】");
  });

  it("**音の見出しも入れ替わる**(声調ではなく強勢、韻母ではなく母音)", () => {
    const got = formatL1Rule(zh, "pronunciation", "en");
    expect(got).toContain("【強勢】");
    expect(got).toContain("【母音】");
    expect(got).not.toContain("【声調】");
    expect(got).not.toContain("【韻母】");
  });

  it("**学習言語そのものの事情の見出しが入れ替わる**", () => {
    const got = formatL1Rule(zh, "both", "en");
    expect(got).toContain("【英語の事情】");
    expect(got).not.toContain("【台湾華語の事情】");
  });

  it("台湾華語を学ぶほうの見出しは変わっていない(日本語話者)", () => {
    const got = formatL1Rule(l1Info("ja"), "grammar");
    expect(got).toContain("【量詞】");
    expect(got).not.toContain("【冠詞・可算】");
  });

  it("**中身が英語の話になっている**(台湾華語の干渉を書いていない)", () => {
    const got = formatL1Rule(zh, "both", "en");
    expect(got).toContain("冠詞");
    expect(got).toContain("θ/ð");
    // そり舌・注音は「英語を学ぶ人」の難所ではない。
    expect(got).not.toContain("そり舌の練習");
  });

  it("**有利な点を必ず持っている**(自信を持たせる材料)", () => {
    expect(zh.phonology.advantages).toContain("有気");
    expect(formatL1Rule(zh, "pronunciation", "en")).toContain("この母語だから有利な点");
  });
});

describe("選べる母語 — 学習言語と同じものは出さない", () => {
  it("台湾華語を学ぶ人には日本語と英語", () => {
    expect(l1ChoicesFor(CHINESE_EXPLANATION_LANGUAGE)).toEqual(["ja", "en"]);
  });

  it("英語を学ぶ人には日本語と台湾華語", () => {
    expect(l1ChoicesFor("en")).toEqual(["ja", CHINESE_EXPLANATION_LANGUAGE]);
  });

  it("**一覧が空にならない**(母語を選べない画面を作らない)", () => {
    for (const t of [null, undefined, "", "  ", "kl-KL"]) {
      expect(l1ChoicesFor(t).length).toBeGreaterThan(0);
    }
  });
});

describe("pickL1 — 消した言語を選んでいた人の画面", () => {
  it("選べる値ならそのまま", () => {
    expect(pickL1("en", CHINESE_EXPLANATION_LANGUAGE)).toBe("en");
  });

  it("**一覧に無い値は落とす**(どれも選ばれていない見た目にしない)", () => {
    for (const gone of ["ko", "vi", "tl", "", null, undefined, "こわれた"]) {
      expect(l1ChoicesFor(CHINESE_EXPLANATION_LANGUAGE)).toContain(
        pickL1(gone, CHINESE_EXPLANATION_LANGUAGE),
      );
    }
  });

  it("**学習言語と同じ母語も落とす**", () => {
    expect(pickL1("en", "en")).not.toBe("en");
    expect(pickL1(CHINESE_EXPLANATION_LANGUAGE, CHINESE_EXPLANATION_LANGUAGE)).not.toBe(
      CHINESE_EXPLANATION_LANGUAGE,
    );
  });

  it("返す値は必ず保存できる(`isL1Code` を通る)", () => {
    for (const t of [CHINESE_EXPLANATION_LANGUAGE, "en", "kl-KL", null]) {
      for (const saved of ["ko", "ja", "", null]) {
        expect(isL1Code(pickL1(saved, t))).toBe(true);
      }
    }
  });
});
