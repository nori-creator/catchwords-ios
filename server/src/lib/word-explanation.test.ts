import { describe, it, expect } from "vitest";
import {
  LEGACY_KEY,
  explanationKey,
  needsGeneration,
  pickExplanation,
  sameKey,
  resolveDisplayWord,
  shouldWriteSharedColumns,
  readerMeaningWriteTarget,
  reviewNeedsReaderExplanation,
  type ExplanationRow,
} from "./word-explanation";
import { emptyExtras } from "./extras";

/**
 * 「開くたびに解説を作り直して上書きし合う」を止めた所の門。
 *
 * ここで一番怖いのは**作り直しが復活すること** — 直っているように見えて、
 * 実際には利用者が増えるほど遅く・高くなる。型でもビルドでも落ちないので、
 * 試験で押さえる。
 */

const full = { ...emptyExtras(), mnemonic: "覚え方", usage_context: "よく見る" };

function row(over: Partial<ExplanationRow> = {}): ExplanationRow {
  return {
    explain_lang: "ja",
    l1: "ja",
    meaning: "自転車",
    extras: full,
    source: "ai",
    ...over,
  };
}

describe("explanationKey", () => {
  it("そのまま使う", () => {
    expect(explanationKey("zh-TW", "zh")).toEqual({ explainLang: "zh-TW", l1: "zh" });
  });

  it("**空・null は旧データの既定に落とす**(日本語話者向けの日本語)", () => {
    expect(explanationKey(null, null)).toEqual(LEGACY_KEY);
    expect(explanationKey("", "")).toEqual(LEGACY_KEY);
    expect(explanationKey(undefined, undefined)).toEqual(LEGACY_KEY);
  });

  it("前後の空白を落とす(空白違いで別の解説にしない)", () => {
    expect(explanationKey(" en ", " zh ")).toEqual({ explainLang: "en", l1: "zh" });
  });
});

describe("sameKey", () => {
  it("3つ揃いで1つ", () => {
    expect(sameKey({ explainLang: "ja", l1: "ja" }, { explainLang: "ja", l1: "ja" })).toBe(true);
    expect(sameKey({ explainLang: "ja", l1: "ja" }, { explainLang: "ja", l1: "ko" })).toBe(false);
    expect(sameKey({ explainLang: "en", l1: "ja" }, { explainLang: "ja", l1: "ja" })).toBe(false);
  });
});

describe("pickExplanation", () => {
  it("ぴったり合う物を選ぶ", () => {
    const rows = [row({ l1: "ko", meaning: "한국어" }), row({ l1: "ja", meaning: "自転車" })];
    expect(pickExplanation(rows, { explainLang: "ja", l1: "ja" })?.meaning).toBe("自転車");
  });

  it("**母語が違っても、読める言語の物には落ちる**", () => {
    const rows = [row({ l1: "ko", meaning: "日本語で書いた韓国語話者向け" })];
    const got = pickExplanation(rows, { explainLang: "ja", l1: "ja" });
    expect(got?.explain_lang).toBe("ja");
  });

  it("**読めない言語の解説には落ちない**(何も出さないほうがまし)", () => {
    const rows = [row({ explain_lang: "zh-TW", l1: "zh", meaning: "腳踏車" })];
    expect(pickExplanation(rows, { explainLang: "ja", l1: "ja" })).toBeNull();
  });

  it("言語だけ合う物が複数あれば、**人が確かめた物を先に**", () => {
    const rows = [
      row({ l1: "ko", source: "ai", meaning: "AI" }),
      row({ l1: "vi", source: "verified", meaning: "確認済み" }),
    ];
    expect(pickExplanation(rows, { explainLang: "ja", l1: "ja" })?.meaning).toBe("確認済み");
  });

  it("空・null でも落ちない", () => {
    expect(pickExplanation([], LEGACY_KEY)).toBeNull();
    expect(pickExplanation(null, LEGACY_KEY)).toBeNull();
    expect(pickExplanation(undefined, LEGACY_KEY)).toBeNull();
  });
});

describe("needsGeneration — ここが作り直しを止める所", () => {
  it("**その組み合わせの解説があれば、何度開いても作らない**", () => {
    const picked = row();
    expect(needsGeneration(picked, { explainLang: "ja", l1: "ja" })).toBe(false);
  });

  it("**母語が違う人が開いても、その人向けの解説があれば作らない**", () => {
    // 直したかった不具合そのもの: 前はここが true で、開くたびに作り直していた。
    const picked = row({ l1: "ko" });
    expect(needsGeneration(picked, { explainLang: "ja", l1: "ko" })).toBe(false);
  });

  it("その人向けが無く、言語だけ合う物で間に合わせているなら作る", () => {
    const picked = row({ l1: "ko" });
    expect(needsGeneration(picked, { explainLang: "ja", l1: "ja" })).toBe(true);
  });

  it("1つも無ければ作る", () => {
    expect(needsGeneration(null, LEGACY_KEY)).toBe(true);
  });

  it("**半端な解説は「在る」と数えない**(途中で失敗した回を固定しない)", () => {
    expect(needsGeneration(row({ meaning: "" }), LEGACY_KEY)).toBe(true);
    expect(needsGeneration(row({ meaning: "   " }), LEGACY_KEY)).toBe(true);
    expect(needsGeneration(row({ extras: emptyExtras() }), LEGACY_KEY)).toBe(true);
    expect(needsGeneration(row({ extras: null }), LEGACY_KEY)).toBe(true);
  });
});

describe("shouldWriteSharedColumns", () => {
  it("**共有の列が揃っていれば書きに行かない**(他人のカードを書き換えない)", () => {
    expect(
      shouldWriteSharedColumns({ meaning: "自転車", reading: "ㄐㄧㄠˇ", example: "我騎腳踏車" }),
    ).toBe(false);
  });

  it("どれか1つでも欠けていれば書く", () => {
    expect(shouldWriteSharedColumns({ meaning: "", reading: "ㄐ", example: "文" })).toBe(true);
    expect(shouldWriteSharedColumns({ meaning: "自転車", reading: "", example: "文" })).toBe(true);
    expect(shouldWriteSharedColumns({ meaning: "自転車", reading: "ㄐ", example: "" })).toBe(true);
  });

  it("空白だけは「在る」と数えない", () => {
    expect(shouldWriteSharedColumns({ meaning: "  ", reading: "ㄐ", example: "文" })).toBe(true);
  });

  it("null・undefined でも落ちない", () => {
    expect(shouldWriteSharedColumns({})).toBe(true);
    expect(shouldWriteSharedColumns({ meaning: null, reading: null, example: null })).toBe(true);
  });
});

describe("resolveDisplayWord", () => {
  // `extras` は目印(`explain_lang`)を持つ物になった。中身は問わないので、
  // 見分けが付く印だけ入れておく。
  const shared = {
    meaning: "共有の意味",
    exampleTranslation: "共有の訳",
    extras: { tag: "共有" } as { tag: string; explain_lang?: string },
  };

  it("**共有キャッシュがあればそちらを出す**", () => {
    const got = resolveDisplayWord(shared, {
      meaning: "キャッシュの意味",
      example_translation: "キャッシュの訳",
      extras: { tag: "キャッシュ" },
    });
    expect(got).toEqual({
      meaning: "キャッシュの意味",
      exampleTranslation: "キャッシュの訳",
      extras: { tag: "キャッシュ" },
    });
  });

  it("**キャッシュに無ければ古い列に落ちる**(移行前でも動く)", () => {
    expect(resolveDisplayWord(shared, null)).toEqual({
      meaning: "共有の意味",
      exampleTranslation: "共有の訳",
      extras: { tag: "共有" },
    });
  });

  it("意味が空のキャッシュでは古い列に落ちる(空の意味を出さない)", () => {
    const got = resolveDisplayWord(shared, {
      meaning: "",
      example_translation: null,
      extras: { tag: "キャッシュ" },
    });
    expect(got.meaning).toBe("共有の意味");
    expect(got.exampleTranslation).toBe("共有の訳");
  });

  it("**解説は行が在れば空でもそちら**(裏で埋めている途中を古い物で潰さない)", () => {
    const got = resolveDisplayWord(shared, {
      meaning: "キャッシュの意味",
      example_translation: null,
      extras: { tag: "" },
    });
    expect(got.extras).toEqual({ tag: "" });
  });

  it("空白だけの意味は「在る」と数えない", () => {
    const got = resolveDisplayWord(shared, {
      meaning: "   ",
      example_translation: "  ",
      extras: { tag: "キャッシュ" },
    });
    expect(got.meaning).toBe("共有の意味");
    expect(got.exampleTranslation).toBe("共有の訳");
  });

  it("共有の側も空なら空で返す(落ちない)", () => {
    const got = resolveDisplayWord({ extras: null }, null);
    expect(got).toEqual({ meaning: "", exampleTranslation: null, extras: null });
  });
});

describe("読む人の言語で書かれていない解説は出さない", () => {
  /**
   * オーナー報告 2026-08-26(絵つき)
   * 「学習言語英語、表示言語台灣華語なのに、言語が混ざってる」。
   *
   * 届いた絵では、例文の訳は繁体字なのに**追加例文の訳だけ日本語**。
   * その人向けの解説がまだ出来ていない間、日本語で書かれた古い行を
   * そのまま出していた。
   */
  const shared = {
    meaning: "共有の意味",
    exampleTranslation: "共有の訳",
    extras: { tag: "古い", explain_lang: "ja" } as { tag: string; explain_lang?: string },
  };

  it("**言語が違えば解説を出さない**(「まだ無い」と描く)", () => {
    expect(resolveDisplayWord(shared, null, "zh-TW").extras).toBeNull();
  });

  it("言語が合っていれば出す", () => {
    expect(resolveDisplayWord(shared, null, "ja").extras).toEqual(shared.extras);
  });

  it("**目印が無い解説は出す**(落とすには根拠が要る)", () => {
    const noTag = {
      ...shared,
      extras: { tag: "印なし" } as { tag: string; explain_lang?: string },
    };
    expect(resolveDisplayWord(noTag, null, "zh-TW").extras).toEqual(noTag.extras);
  });

  it("読む人の言語を渡さなければ今までどおり", () => {
    expect(resolveDisplayWord(shared, null).extras).toEqual(shared.extras);
    expect(resolveDisplayWord(shared, null, "").extras).toEqual(shared.extras);
  });

  it("意味は別の列から来る（読む人の言語なら出す）。例文の訳は読む人の言語の物だけ", () => {
    // 解説だけが古い言語で、意味は共有キャッシュの正しい言語、という
    // 組み合わせが実際に起きている(届いた絵がその形)。
    const got = resolveDisplayWord(shared, null, "zh-TW");
    // 共有の意味が日本語なら、台湾華語で読む人には出さない（2026-09-29）。台湾華語なら出す。
    expect(got.meaning).toBe("");
    expect(resolveDisplayWord({ ...shared, meaning: "珍珠奶茶" }, null, "zh-TW").meaning).toBe(
      "珍珠奶茶",
    );
    // 2026-09-29「例文の訳は母語（表示言語）にして」: 台湾華語で読む人に日本語の訳は出さない。
    expect(got.exampleTranslation).toBeNull();
    const zhShared = { ...shared, exampleTranslation: "這名選手因為小腿抽筋而休息。" };
    expect(resolveDisplayWord(zhShared, null, "zh-TW").exampleTranslation).toBe(
      "這名選手因為小腿抽筋而休息。",
    );
  });

  it("例文そのままの写し（2026-09-29 小腿）は訳として出さず、読む人の言語の訳へ落ちる", () => {
    const sentence = "這名馬拉松選手因為小腿抽筋，不得不停下來休息。";
    const got = resolveDisplayWord(
      {
        ...shared,
        exampleSentence: sentence,
        exampleTranslation: "選手はふくらはぎがつって休んだ。",
      },
      { meaning: "", example_translation: sentence, extras: null },
      "ja",
    );
    expect(got.exampleTranslation).toBe("選手はふくらはぎがつって休んだ。");
  });
});

describe("意味も読む人の言語の物だけ（2026-09-29 の言語の検査）", () => {
  it("英語で読む人に日本語の意味は出さない。漢字だけの和文は日本語の人に出す", () => {
    const shared = { meaning: "タピオカミルクティー", exampleTranslation: null, extras: null };
    expect(resolveDisplayWord(shared, null, "en").meaning).toBe("");
    expect(resolveDisplayWord({ ...shared, meaning: "台湾高速鉄道" }, null, "ja").meaning).toBe(
      "台湾高速鉄道",
    );
    expect(
      resolveDisplayWord(
        shared,
        { meaning: "bubble tea", example_translation: null, extras: null },
        "en",
      ).meaning,
    ).toBe("bubble tea");
  });
});

describe("readerMeaningWriteTarget — 足りない意味をどの行に書くか（2026-10-02）", () => {
  const row = (lang: string, l1: string, source = "ai"): ExplanationRow => ({
    explain_lang: lang,
    l1,
    meaning: "ノート",
    extras: null,
    source,
  });
  const want = explanationKey("en", "en");

  it("その言語の行が1つも無ければ、新しく作る", () => {
    expect(readerMeaningWriteTarget([], want)).toEqual({ kind: "insert" });
    expect(readerMeaningWriteTarget([row("ja", "ja")], want)).toEqual({ kind: "insert" });
  });

  it("ぴったり合う行があれば、その行の意味を書き換える", () => {
    const exact = row("en", "en");
    expect(readerMeaningWriteTarget([row("en", "ja"), exact], want)).toEqual({
      kind: "update",
      row: exact,
    });
  });

  it("言語だけ合う行しか無ければ、**画面が出している方**へ（新しい空の行で解説を隠さない）", () => {
    const other = row("en", "ja");
    expect(readerMeaningWriteTarget([other], want)).toEqual({ kind: "update", row: other });
  });

  it("**人が確かめた行には書かない**", () => {
    expect(readerMeaningWriteTarget([row("en", "en", "verified")], want)).toEqual({
      kind: "skip",
    });
  });
});

describe("reviewNeedsReaderExplanation — 復習で解説を作りに行くか（2026-10-02）", () => {
  const want = explanationKey("en", "en");
  const full: ExplanationRow = {
    explain_lang: "en",
    l1: "en",
    meaning: "notebook",
    extras: { ...emptyExtras(), usage_context: "at school", explain_lang: "en" },
    source: "ai",
  };
  const base = { loaded: true, unavailable: false, picked: null, want, sharedMeaning: "ノート" };

  it("英語の人で、その人向けの解説が無く、共有の意味が日本語なら作る", () => {
    expect(reviewNeedsReaderExplanation(base)).toBe(true);
  });

  it("繁體中文の人も同じ", () => {
    expect(reviewNeedsReaderExplanation({ ...base, want: explanationKey("zh-TW", "zh-TW") })).toBe(
      true,
    );
  });

  it("**日本語の表示で日本語の語は作らない**（共有の解説のまま。今の見え方を変えない）", () => {
    expect(reviewNeedsReaderExplanation({ ...base, want: explanationKey("ja", "ja") })).toBe(false);
  });

  it("その人向けの解説に中身があれば作らない", () => {
    expect(reviewNeedsReaderExplanation({ ...base, picked: full })).toBe(false);
  });

  it("問い合わせが返る前・表が無い環境では作らない", () => {
    expect(reviewNeedsReaderExplanation({ ...base, loaded: false })).toBe(false);
    expect(reviewNeedsReaderExplanation({ ...base, unavailable: true })).toBe(false);
  });
});
