import { describe, expect, it } from "vitest";
import { detectQueryLang } from "./text-query-lang";
import {
  decideTextSearch,
  legacyUsageOf,
  normalizeRegister,
  normalizeUsage,
  peelReady,
  PEEL_READY_MAX_WAIT_MS,
  WordCandidatesSchema,
  type TextCandidate,
} from "./text-search-flow";

const cand = (headword: string, extra: Partial<TextCandidate> = {}): TextCandidate => ({
  headword,
  reading_zhuyin: "",
  pinyin: "x",
  meaning_ja: "意味",
  distinction: "",
  register: "common",
  style: null,
  scene: "",
  usage: null,
  image_query: "",
  ...extra,
});

describe("detectQueryLang（打った語は何語か）", () => {
  it("かなが在れば母語", () => {
    expect(detectQueryLang("ティッシュ", "zh-TW")).toBe("native");
    expect(detectQueryLang("けしごむ", "zh-TW")).toBe("native");
    expect(detectQueryLang("食べる", "zh-TW")).toBe("native");
  });
  it("台湾の字にしか無い形が在れば学習言語", () => {
    expect(detectQueryLang("貓", "zh-TW")).toBe("target");
    expect(detectQueryLang("麵包", "zh-TW")).toBe("target");
    expect(detectQueryLang("臺灣", "zh-TW")).toBe("target");
    expect(detectQueryLang("鐵路", "zh-TW")).toBe("target");
  });
  it("日本の新字体にしか無い形が在れば母語", () => {
    expect(detectQueryLang("駅", "zh-TW")).toBe("native");
    expect(detectQueryLang("猫", "zh-TW")).toBe("native");
    expect(detectQueryLang("鉄道", "zh-TW")).toBe("native");
  });
  it("漢字だけで決まらない語は AI に任せる", () => {
    expect(detectQueryLang("電車", "zh-TW")).toBe("ambiguous");
    expect(detectQueryLang("蓮藕", "zh-TW")).toBe("ambiguous");
    expect(detectQueryLang("衛生紙", "zh-TW")).toBe("ambiguous");
    expect(detectQueryLang("台北", "zh-TW")).toBe("ambiguous");
  });
  it("漢字の無い語（英語で打った）は学習言語ではない", () => {
    expect(detectQueryLang("pencil", "zh-TW")).toBe("native");
  });
  it("英語を学ぶ人: 英語はそのまま、かな・漢字は母語", () => {
    expect(detectQueryLang("pencil", "en")).toBe("target");
    expect(detectQueryLang("鉛筆", "en")).toBe("native");
    expect(detectQueryLang("えんぴつ", "en")).toBe("native");
  });
});

describe("WordCandidatesSchema（語を引いた返事の形）", () => {
  it("古い形（usage・image_query・query_is_target 無し）も読める", () => {
    const r = WordCandidatesSchema.parse({ candidates: [{ headword: "貓" }] });
    expect(r.candidates[0]).toMatchObject({ headword: "貓", pinyin: "", meaning_ja: "" });
    expect(r.query_is_target).toBeUndefined();
  });
  it("新しい欄を読む", () => {
    const r = WordCandidatesSchema.parse({
      query_is_target: false,
      candidates: [{ headword: "火車", usage: "local", image_query: "train" }],
    });
    expect(r.query_is_target).toBe(false);
    expect(r.candidates[0].usage).toBe("local");
  });
  it("形が崩れても0件で受ける（画面は見つからないと言える）", () => {
    expect(WordCandidatesSchema.parse({}).candidates).toEqual([]);
  });
});

describe("normalizeUsage", () => {
  it("知っている印と言い換えを直す", () => {
    expect(normalizeUsage("common")).toBe("common");
    expect(normalizeUsage("Casual")).toBe("colloquial");
    expect(normalizeUsage("written")).toBe("formal");
    expect(normalizeUsage("technical")).toBe("academic");
    expect(normalizeUsage("taiwan")).toBe("local");
  });
  it("知らない値・空は札を出さない", () => {
    expect(normalizeUsage("")).toBeNull();
    expect(normalizeUsage("weird")).toBeNull();
    expect(normalizeUsage(undefined)).toBeNull();
  });
});

describe("normalizeRegister（どの候補も同じ物差しの文体で — 2026-10-09）", () => {
  it("新しい印をそのまま・言い換えを直す", () => {
    expect(normalizeRegister("spoken")).toBe("spoken");
    expect(normalizeRegister("Written")).toBe("written");
    expect(normalizeRegister("both")).toBe("both");
    expect(normalizeRegister("technical")).toBe("technical");
    expect(normalizeRegister("signage")).toBe("signage");
    expect(normalizeRegister("colloquial")).toBe("spoken");
    expect(normalizeRegister("informal")).toBe("spoken");
    expect(normalizeRegister("formal")).toBe("written");
    expect(normalizeRegister("academic")).toBe("technical");
    expect(normalizeRegister("menu")).toBe("signage");
  });
  it("文体が無い古い返事は usage から読む。土地の印は札にしない", () => {
    expect(normalizeRegister(undefined, "common")).toBe("both");
    expect(normalizeRegister(null, "colloquial")).toBe("spoken");
    expect(normalizeRegister("", "formal")).toBe("written");
    expect(normalizeRegister(undefined, "academic")).toBe("technical");
    expect(normalizeRegister(undefined, "local")).toBeNull();
    expect(normalizeRegister("taiwan")).toBeNull();
    expect(normalizeRegister(undefined, undefined)).toBeNull();
  });
  it("古い iOS の印は文体から作る（土地の印はもう作らない）", () => {
    expect(legacyUsageOf("spoken")).toBe("colloquial");
    expect(legacyUsageOf("written")).toBe("formal");
    expect(legacyUsageOf("both")).toBe("common");
    expect(legacyUsageOf("technical")).toBe("academic");
    expect(legacyUsageOf("signage")).toBe("common");
    expect(legacyUsageOf(null)).toBeNull();
  });
  it("新しい欄（register・scene）を読み、無くても読める", () => {
    const r = WordCandidatesSchema.parse({
      candidates: [
        { headword: "嘴邊肉", register: "spoken", scene: "屋台で注文するとき" },
        { headword: "豬頰肉" },
      ],
    });
    expect(r.candidates[0]).toMatchObject({ register: "spoken", scene: "屋台で注文するとき" });
    expect(r.candidates[1].register).toBeUndefined();
  });
});

describe("2026-10-09: 漢字だけの語は母語として引く（「桃」をそのまま剥がさない）", () => {
  /**
   * オーナー報告: 「桃と日本語で検索したら、そのまま表示された。台湾華語では水蜜桃とか、
   * 桃子っていう言い方もあるよね？なぜ単語の候補を出さずに直接そのまま表示したの？」
   * AI が `query_is_target: true` と言い、その語1つで剥がしていた。
   */
  const peach = [
    cand("桃子", { style: "spoken" }),
    cand("水蜜桃", { register: "specific", style: "both" }),
    cand("桃", { register: "specific", style: "written" }),
  ];
  it("桃・杯・電車は手元では決まらない", () => {
    expect(detectQueryLang("桃", "zh-TW")).toBe("ambiguous");
    expect(detectQueryLang("杯", "zh-TW")).toBe("ambiguous");
    expect(detectQueryLang("電車", "zh-TW")).toBe("ambiguous");
  });
  it("桃: AI が「学習言語」と言っても、言い方が割れたら選ばせる", () => {
    const d = decideTextSearch({
      query: "桃",
      local: detectQueryLang("桃", "zh-TW"),
      queryIsTarget: true,
      candidates: peach,
      targetLanguage: "zh-TW",
    });
    expect(d.kind).toBe("choose");
    if (d.kind === "choose")
      expect(d.candidates.map((c) => c.headword)).toEqual(["桃子", "水蜜桃", "桃"]);
  });
  it("杯: 杯子（単独で言う形）と並べて選ばせる", () => {
    const d = decideTextSearch({
      query: "杯",
      local: detectQueryLang("杯", "zh-TW"),
      queryIsTarget: true,
      candidates: [cand("杯子"), cand("杯")],
      targetLanguage: "zh-TW",
    });
    expect(d.kind).toBe("choose");
  });
  it("電車: AI が「学習言語」と言っても、電車・捷運・火車を並べる", () => {
    const d = decideTextSearch({
      query: "電車",
      local: detectQueryLang("電車", "zh-TW"),
      queryIsTarget: true,
      candidates: [cand("電車"), cand("捷運"), cand("火車")],
      targetLanguage: "zh-TW",
    });
    expect(d.kind).toBe("choose");
  });
  it("漢字だけの語でも、候補が1つならそのまま剥がす", () => {
    const d = decideTextSearch({
      query: "蓮藕",
      local: "ambiguous",
      queryIsTarget: true,
      candidates: [cand("蓮藕", { pinyin: "liánǒu" })],
      targetLanguage: "zh-TW",
    });
    expect(d).toMatchObject({ kind: "peel", pick: { headword: "蓮藕", pinyin: "liánǒu" } });
  });
  it("貓（台湾の字）は候補が割れてもそのまま", () => {
    const d = decideTextSearch({
      query: "貓",
      local: detectQueryLang("貓", "zh-TW"),
      queryIsTarget: null,
      candidates: [cand("貓"), cand("貓咪")],
      targetLanguage: "zh-TW",
    });
    expect(d).toMatchObject({ kind: "peel", via: "target", pick: { headword: "貓" } });
  });
  it("ねこ（かな）は母語: 候補が割れたら選ばせる", () => {
    const d = decideTextSearch({
      query: "ねこ",
      local: detectQueryLang("ねこ", "zh-TW"),
      queryIsTarget: true,
      candidates: [cand("貓"), cand("貓咪")],
      targetLanguage: "zh-TW",
    });
    expect(d.kind).toBe("choose");
  });
});

describe("decideTextSearch（そのまま剥がす / 選ばせる / 見つからない）", () => {
  it("学習言語で打った語は、候補が割れても選ばせずにその語で剥がす", () => {
    const d = decideTextSearch({
      query: "貓",
      local: "target",
      queryIsTarget: null,
      candidates: [cand("貓", { pinyin: "māo" }), cand("貓咪")],
      targetLanguage: "zh-TW",
    });
    expect(d).toMatchObject({
      kind: "peel",
      via: "target",
      pick: { headword: "貓", pinyin: "māo" },
    });
  });
  it("漢字だけの語は AI が学習言語と言えばそのまま（読みが無ければ空で — カードが補う）", () => {
    const d = decideTextSearch({
      query: "蓮藕",
      local: "ambiguous",
      queryIsTarget: true,
      candidates: [],
      targetLanguage: "zh-TW",
    });
    expect(d).toMatchObject({
      kind: "peel",
      via: "target",
      pick: { headword: "蓮藕", pinyin: "" },
    });
  });
  it("漢字だけの語で AI が母語と言えば候補を出す", () => {
    const d = decideTextSearch({
      query: "電車",
      local: "ambiguous",
      queryIsTarget: false,
      candidates: [cand("電車"), cand("火車"), cand("捷運")],
      targetLanguage: "zh-TW",
    });
    expect(d.kind).toBe("choose");
    if (d.kind === "choose")
      expect(d.candidates.map((c) => c.headword)).toEqual(["電車", "火車", "捷運"]);
  });
  it("かなで打った語は、AI が何と言っても母語として扱う", () => {
    const d = decideTextSearch({
      query: "ねこ",
      local: "native",
      queryIsTarget: true,
      candidates: [cand("貓")],
      targetLanguage: "zh-TW",
    });
    expect(d).toMatchObject({ kind: "peel", via: "single", pick: { headword: "貓" } });
  });
  it("一対一なら選ばせない", () => {
    const d = decideTextSearch({
      query: "レンコン",
      local: "native",
      queryIsTarget: false,
      candidates: [cand("蓮藕")],
      targetLanguage: "zh-TW",
    });
    expect(d).toMatchObject({ kind: "peel", via: "single" });
  });
  it("学習言語で通らない候補は落とし、同じ語は1つに、最大5つ", () => {
    const d = decideTextSearch({
      query: "ティッシュ",
      local: "native",
      queryIsTarget: false,
      candidates: [
        cand("衛生紙"),
        cand("ティッシュ"),
        cand("衛生紙"),
        cand("面紙 (pocket)"),
        cand("紙巾"),
        cand("抽取式衛生紙"),
        cand("捲筒衛生紙"),
        cand("餐巾紙"),
      ],
      targetLanguage: "zh-TW",
    });
    expect(d.kind).toBe("choose");
    if (d.kind === "choose") {
      expect(d.candidates.map((c) => c.headword)).toEqual([
        "衛生紙",
        "面紙",
        "紙巾",
        "抽取式衛生紙",
        "捲筒衛生紙",
      ]);
    }
  });
  it("使える候補が無ければ見つからない（母語のまま札を作らない）", () => {
    const d = decideTextSearch({
      query: "シャーペン",
      local: "native",
      queryIsTarget: false,
      candidates: [cand("シャーペン")],
      targetLanguage: "zh-TW",
    });
    expect(d.kind).toBe("none");
  });
});

describe("peelReady（札は絵と発音がそろってから）", () => {
  const base = { hasCard: true, imageSettled: true, speech: "ready" as const, waitedMs: 0 };
  it("そろえば出す", () => expect(peelReady(base)).toBe(true));
  it("絵がまだなら待つ", () => expect(peelReady({ ...base, imageSettled: false })).toBe(false));
  it("発音を取っている間は待つ", () =>
    expect(peelReady({ ...base, speech: "loading" })).toBe(false));
  it("発音が取れないと分かったら待たない", () =>
    expect(peelReady({ ...base, speech: "failed" })).toBe(true));
  it("カードが無ければ上限を過ぎても出さない", () =>
    expect(peelReady({ ...base, hasCard: false, waitedMs: 99999 })).toBe(false));
  it("上限を過ぎたら、そろった物で出す", () =>
    expect(
      peelReady({
        ...base,
        imageSettled: false,
        speech: "loading",
        waitedMs: PEEL_READY_MAX_WAIT_MS,
      }),
    ).toBe(true));
});
