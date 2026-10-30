import { describe, expect, it } from "vitest";
import {
  applyJudge,
  finalChunks,
  fitsOneLine,
  frameKey,
  gateChunksV2,
  headPlace,
  mergeByAgreement,
  orderForReader,
  readJudgeVerdicts,
  sentenceLength,
  type UsageChunkV2,
} from "./chunks-v2";

const ZH = { headword: "筆袋", language: "zh-TW", readerLang: "ja" };

function ai(over: Partial<Record<string, unknown>> = {}) {
  return {
    sentence: "我把原子筆放進筆袋裡了。",
    sentence_ja: "ボールペンをペンケースに入れたよ。",
    text: "把原子筆放進筆袋裡",
    blocks: [
      { text: "把", pos: "Ptc" },
      { text: "原子筆", pos: "N", slot: true, ja: "ボールペン", alts: [{ text: "鉛筆", ja: "鉛筆" }, { text: "橡皮擦", ja: "消しゴム" }] },
      { text: "放進", pos: "V" },
      { text: "筆袋裡", pos: "N" },
    ],
    pattern: "coverb",
    ja: "ボールペンをペンケースに入れる",
    note: "物を入れ物に入れる時の、いちばん普通の言い方。",
    ...over,
  };
}

function chunk(text: string, blocks: Array<{ text: string; slot?: boolean }>, over: Partial<UsageChunkV2> = {}): UsageChunkV2 {
  return {
    text,
    blocks: blocks.map((b) => ({ text: b.text, pos: "", ...(b.slot ? { slot: true, alts: [{ text: "x", ja: "" }, { text: "y", ja: "" }] } : {}) })),
    head: null,
    pattern: "",
    ja: "訳",
    sentence: text,
    sentence_ja: "",
    frequency: null,
    ...over,
  };
}

describe("形だけの門（gateChunksV2）", () => {
  it("ネイティブの一文から切り出した塊はそのまま通り、見出し語の場所は block の中の字の範囲", () => {
    const r = gateChunksV2([ai()], ZH);
    expect(r.dropped).toEqual([]);
    expect(r.kept).toHaveLength(1);
    const c = r.kept[0];
    expect(c.text).toBe("把原子筆放進筆袋裡");
    // 筆袋裡 は 1 つの block のまま（ネイティブは分けて考えない）。青く塗るのは字の範囲。
    expect(c.blocks.map((b) => b.text)).toEqual(["把", "原子筆", "放進", "筆袋裡"]);
    expect(c.head).toEqual({ block: 3, start: 0, length: 2 });
    expect(c.blocks[1].slot).toBe(true);
    expect(c.pattern).toBe("coverb");
    expect(c.note).toBeTruthy();
  });

  it("見出し語の無い塊・見出し語だけの塊は落ちる", () => {
    expect(gateChunksV2([ai({ text: "放進去", blocks: [{ text: "放進去", pos: "V" }], sentence: "我放進去了。" })], ZH).dropped[0].reason).toBe("headword_missing");
    expect(gateChunksV2([ai({ blocks: [{ text: "筆袋", pos: "N" }], sentence: "這是筆袋。" })], ZH).dropped[0].reason).toBe("headword_only");
  });

  it("文の部分文字列でない塊（AI が文と別の物を書いた）は落ちる", () => {
    const r = gateChunksV2([ai({ sentence: "筆袋在桌上。" })], ZH);
    expect(r.dropped[0].reason).toBe("not_in_sentence");
  });

  it("句読点のある塊、長すぎる文は落ちる", () => {
    expect(gateChunksV2([ai({ blocks: [{ text: "把原子筆放進筆袋裡，", pos: "" }] })], ZH).dropped[0].reason).toBe("punctuation");
    const long = "我今天早上出門之前先把原子筆放進筆袋裡然後才去學校上課了";
    expect(gateChunksV2([ai({ sentence: long })], ZH).dropped[0].reason).toBe("sentence_long");
  });

  it("入れ替えは 1 か所まで。見出し語の block の slot と、候補の無い slot は外す（塊は残す）", () => {
    const two = ai({
      blocks: [
        { text: "把", pos: "Ptc" },
        { text: "原子筆", pos: "N", slot: true, alts: [{ text: "鉛筆", ja: "" }, { text: "橡皮擦", ja: "" }] },
        { text: "放進", pos: "V", slot: true, alts: [{ text: "收進", ja: "" }, { text: "裝進", ja: "" }] },
        { text: "筆袋裡", pos: "N" },
      ],
    });
    expect(gateChunksV2([two], ZH).dropped[0].reason).toBe("two_slots");
    const headSlot = ai({
      blocks: [
        { text: "打開", pos: "V" },
        { text: "筆袋", pos: "N", slot: true, alts: [{ text: "書包", ja: "" }, { text: "抽屜", ja: "" }] },
      ],
      text: "打開筆袋",
      sentence: "幫我打開筆袋。",
    });
    const kept = gateChunksV2([headSlot], ZH).kept[0];
    expect(kept.blocks[1].slot).toBeUndefined();
    expect(kept.blocks[1].alts).toBeUndefined();
    const oneAlt = ai({
      blocks: [
        { text: "把", pos: "Ptc" },
        { text: "原子筆", pos: "N", slot: true, alts: [{ text: "鉛筆", ja: "" }] },
        { text: "放進", pos: "V" },
        { text: "筆袋裡", pos: "N" },
      ],
    });
    expect(gateChunksV2([oneAlt], ZH).kept[0].blocks[1].slot).toBeUndefined();
  });

  it("訳が読む人の言語でない物は落ちる（言語を混ぜない）。繁體中文で読む人は訳が無くてよい", () => {
    expect(gateChunksV2([ai({ ja: "Put the pen into the pencil case" })], ZH).dropped[0].reason).toBe("translation_language");
    expect(gateChunksV2([ai({ ja: "", sentence_ja: "" })], { ...ZH, readerLang: "zh-TW" }).kept).toHaveLength(1);
  });

  it("同じ型は 1 つだけ。block の無い返事は 1 つの block として読む", () => {
    const r = gateChunksV2([ai(), ai({ sentence: "我把鉛筆放進筆袋裡。", text: "把鉛筆放進筆袋裡", blocks: [{ text: "把", pos: "" }, { text: "鉛筆", pos: "N", slot: true, alts: [{ text: "原子筆", ja: "" }, { text: "尺", ja: "" }] }, { text: "放進", pos: "" }, { text: "筆袋裡", pos: "" }] })], ZH);
    expect(r.kept).toHaveLength(1);
    expect(r.dropped[0].reason).toBe("duplicate");
    const bare = gateChunksV2([ai({ blocks: [], text: "打開筆袋", sentence: "幫我打開筆袋。" })], ZH);
    expect(bare.kept[0].blocks.map((b) => b.text)).toEqual(["打開筆袋"]);
    expect(bare.kept[0].head).toEqual({ block: 0, start: 2, length: 2 });
  });
});

describe("2 社の照合（mergeByAgreement）", () => {
  const A = [
    chunk("把原子筆放進筆袋裡", [{ text: "把" }, { text: "原子筆", slot: true }, { text: "放進" }, { text: "筆袋裡" }]),
    chunk("打開筆袋", [{ text: "打開" }, { text: "筆袋" }]),
    chunk("裝進筆袋", [{ text: "裝進" }, { text: "筆袋" }]),
  ];
  const B = [
    chunk("打開筆袋", [{ text: "打開" }, { text: "筆袋" }]),
    chunk("把鉛筆放進筆袋裡", [{ text: "把" }, { text: "鉛筆", slot: true }, { text: "放進" }, { text: "筆袋裡" }]),
    chunk("筆袋的拉鍊", [{ text: "筆袋" }, { text: "的" }, { text: "拉鍊" }]),
  ];

  it("入れ替えの所を ＿ にした型で比べる（原子筆 と 鉛筆 は同じ型）", () => {
    expect(frameKey(A[0])).toBe("把＿放進筆袋裡");
    const r = mergeByAgreement(A, B);
    // 把…: A の 1 番目と B の 2 番目（順位の平均 0.5）、打開: A の 2 番目と B の 1 番目（0.5）→ 同点は A の順。
    expect(r.agreed.map((c) => c.text)).toEqual(["把原子筆放進筆袋裡", "打開筆袋"]);
    expect(r.agreed.every((c) => c.by === "agreement")).toBe(true);
    expect(r.onlyA.map((c) => c.text)).toEqual(["裝進筆袋"]);
    expect(r.onlyB.map((c) => c.text)).toEqual(["筆袋的拉鍊"]);
  });

  it("片方の型がもう片方を含む時は一致とみなし、長い方を採る（切れ端より完全な形）", () => {
    const short = [chunk("放進筆袋裡", [{ text: "放進" }, { text: "筆袋裡" }])];
    const full = [chunk("把原子筆放進筆袋裡", [{ text: "把" }, { text: "原子筆", slot: true }, { text: "放進" }, { text: "筆袋裡" }])];
    expect(mergeByAgreement(short, full).agreed.map((c) => c.text)).toEqual(["把原子筆放進筆袋裡"]);
    expect(mergeByAgreement(full, short).agreed.map((c) => c.text)).toEqual(["把原子筆放進筆袋裡"]);
  });

  it("並びは A・B の順位の平均", () => {
    const a = [chunk("甲筆袋", [{ text: "甲筆袋" }]), chunk("乙筆袋", [{ text: "乙筆袋" }])];
    const b = [chunk("乙筆袋", [{ text: "乙筆袋" }]), chunk("甲筆袋", [{ text: "甲筆袋" }])];
    // 甲: (0+1)/2 = 0.5, 乙: (1+0)/2 = 0.5 → 安定な並び（A の順）。
    expect(mergeByAgreement(a, b).agreed.map((c) => c.text)).toEqual(["甲筆袋", "乙筆袋"]);
    const b2 = [chunk("乙筆袋", [{ text: "乙筆袋" }]), chunk("丙", [{ text: "丙" }]), chunk("甲筆袋", [{ text: "甲筆袋" }])];
    expect(mergeByAgreement(a, b2).agreed.map((c) => c.text)).toEqual(["乙筆袋", "甲筆袋"]);
  });
});

describe("審査（readJudgeVerdicts / applyJudge）", () => {
  it("文字列の true・数字も読み、範囲外の i は捨てる", () => {
    const v = readJudgeVerdicts({ verdicts: [{ i: 1, natural: "true", frequency: "4" }, { i: 2, natural: false, frequency: 5 }, { i: 9, natural: true, frequency: 5 }, "x"] }, 2);
    expect(v).toEqual([
      { i: 1, natural: true, frequency: 4 },
      { i: 2, natural: false, frequency: 5 },
    ]);
    expect(readJudgeVerdicts(null, 2)).toEqual([]);
  });

  it("自然で頻度 3 以上の物だけ、頻度の高い順に", () => {
    const pending = [chunk("甲筆袋", [{ text: "甲筆袋" }]), chunk("乙筆袋", [{ text: "乙筆袋" }]), chunk("丙筆袋", [{ text: "丙筆袋" }]), chunk("丁筆袋", [{ text: "丁筆袋" }])];
    const out = applyJudge(pending, [
      { i: 1, natural: true, frequency: 3 },
      { i: 2, natural: true, frequency: 5 },
      { i: 3, natural: false, frequency: 5 },
      { i: 4, natural: true, frequency: 2 },
    ]);
    expect(out.map((c) => c.text)).toEqual(["乙筆袋", "甲筆袋"]);
    expect(out[0].by).toBe("judge");
    expect(out[0].frequency).toBe(5);
  });

  it("最後の並びは一致 → 審査、型の重複なし、上限 4", () => {
    const agreed = [chunk("甲筆袋", [{ text: "甲筆袋" }]), chunk("乙筆袋", [{ text: "乙筆袋" }])];
    const judged = [chunk("甲筆袋", [{ text: "甲筆袋" }]), chunk("丙筆袋", [{ text: "丙筆袋" }]), chunk("丁筆袋", [{ text: "丁筆袋" }]), chunk("戊筆袋", [{ text: "戊筆袋" }])];
    expect(finalChunks(agreed, judged).map((c) => c.text)).toEqual(["甲筆袋", "乙筆袋", "丙筆袋", "丁筆袋"]);
  });
});

describe("読む人のレベルで並べ替え（orderForReader）", () => {
  const simple = chunk("用筆袋", [{ text: "用" }, { text: "筆袋" }]);
  const strong1 = chunk("把原子筆放進筆袋裡", [{ text: "把" }, { text: "原子筆", slot: true }, { text: "放進" }, { text: "筆袋裡" }]);
  const strong2 = chunk("打開筆袋", [{ text: "打開" }, { text: "筆袋" }]);

  it("目標 1・2 級はそのまま", () => {
    expect(orderForReader([simple, strong1], { levelGoal: "TOCFL-2", headword: "筆袋", language: "zh-TW" }).map((c) => c.text)).toEqual(["用筆袋", "把原子筆放進筆袋裡"]);
  });
  it("目標 3 級以上: 汎用の動詞だけの塊は、他に 2 つあれば外し、無ければ最後へ", () => {
    expect(orderForReader([simple, strong1, strong2], { levelGoal: "TOCFL-4", headword: "筆袋", language: "zh-TW" }).map((c) => c.text)).toEqual(["把原子筆放進筆袋裡", "打開筆袋"]);
    expect(orderForReader([simple, strong1], { levelGoal: "TOCFL-4", headword: "筆袋", language: "zh-TW" }).map((c) => c.text)).toEqual(["把原子筆放進筆袋裡", "用筆袋"]);
  });
});

describe("小さな道具", () => {
  it("句読点を除いた字数", () => {
    expect(sentenceLength("我把原子筆放進筆袋裡了。")).toBe(11);
  });
  it("見出し語の場所は block の中の字の範囲、割れていれば null", () => {
    expect(headPlace([{ text: "打開", pos: "" }, { text: "筆袋", pos: "" }], "筆袋")).toEqual({ block: 1, start: 0, length: 2 });
    expect(headPlace([{ text: "筆", pos: "" }, { text: "袋", pos: "" }], "筆袋")).toBeNull();
  });
  it("1 行に入るかの見積もり（最小 0.52 倍）", () => {
    expect(fitsOneLine("把原子筆放進筆袋裡", { widthPt: 240, fontPt: 22 })).toBe(true);
    expect(fitsOneLine("把原子筆放進筆袋裡然後再把橡皮擦也放進去一起帶走", { widthPt: 240, fontPt: 22 })).toBe(false);
  });
});
