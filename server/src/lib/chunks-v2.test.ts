import { describe, expect, it } from "vitest";
import {
  candidateToChunk,
  coreKey,
  finishCandidate,
  fitsOneLine,
  frameKey,
  gateChunksV2,
  headPlace,
  mergeByAgreement,
  orderForReader,
  poolCandidates,
  rankAndSelect,
  readJudgeRanks,
  repairChunkText,
  sentenceLength,
  type ChunkCandidate,
  type UsageChunkV2,
} from "./chunks-v2";

const ZH = { headword: "筆袋", language: "zh-TW" };

/** 書く段の返事 1 つ（中国語だけ・軽い形）。 */
function ai(over: Partial<Record<string, unknown>> = {}) {
  return {
    sentence: "我把原子筆放進筆袋裡了。",
    text: "把原子筆放進筆袋裡",
    key: "放進",
    pattern: "coverb",
    slot: "原子筆",
    alts: ["鉛筆", "橡皮擦", "尺"],
    ...over,
  };
}

function cand(text: string, key: string, over: Partial<ChunkCandidate> = {}): ChunkCandidate {
  return { text, sentence: `${text}。`, key, pattern: "", slot: null, alts: [], ...over };
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
  it("ネイティブの一文から切り出した塊はそのまま通る（中国語だけ・入れ替えの字と候補つき）", () => {
    const r = gateChunksV2([ai()], ZH);
    expect(r.dropped).toEqual([]);
    expect(r.kept).toEqual([{ text: "把原子筆放進筆袋裡", sentence: "我把原子筆放進筆袋裡了。", key: "放進", pattern: "coverb", slot: "原子筆", alts: ["鉛筆", "橡皮擦", "尺"] }]);
  });

  it("見出し語の無い塊・見出し語だけの塊は落ちる", () => {
    expect(gateChunksV2([ai({ text: "放進去", sentence: "我放進去了。" })], ZH).dropped[0].reason).toBe("headword_missing");
    expect(gateChunksV2([ai({ text: "筆袋", sentence: "這是筆袋。" })], ZH).dropped[0].reason).toBe("headword_only");
  });

  it("文の部分文字列でない塊（AI が文と別の物を書いた）は落ちる", () => {
    expect(gateChunksV2([ai({ sentence: "筆袋在桌上。" })], ZH).dropped[0].reason).toBe("not_in_sentence");
  });

  it("句読点のある塊、長すぎる文は落ちる", () => {
    expect(gateChunksV2([ai({ text: "把原子筆放進筆袋裡，" })], ZH).dropped[0].reason).toBe("punctuation");
    const long = "我今天早上出門之前先把原子筆放進筆袋裡然後才去學校上課了";
    expect(gateChunksV2([ai({ sentence: long })], ZH).dropped[0].reason).toBe("sentence_long");
  });

  it("見出し語の直前が数・指示の語＋量詞なら量詞の型（別の欄）として落ちる", () => {
    expect(gateChunksV2([ai({ text: "借我一個筆袋", sentence: "借我一個筆袋好嗎？", key: "借" })], ZH).dropped[0].reason).toBe("measure_phrase");
    expect(gateChunksV2([ai({ text: "這個筆袋多少錢", sentence: "這個筆袋多少錢？", key: "多少錢" })], ZH).dropped[0].reason).toBe("measure_phrase");
    // 數＋量詞が見出し語の直前でなければ塊は残る。
    expect(gateChunksV2([ai({ text: "筆袋裡有三支筆", sentence: "我的筆袋裡有三支筆。", key: "有" })], ZH).kept).toHaveLength(1);
  });

  it("入れ替えの所は、塊の中の字・見出し語を含まない・代名詞でない・候補 2 つ以上の時だけ残す（だめなら入れ替え無しの塊）", () => {
    const keep = (over: Record<string, unknown>) => gateChunksV2([ai(over)], ZH).kept[0];
    expect(keep({ slot: "筆袋" }).slot).toBeNull();
    expect(keep({ slot: "鉛筆" }).slot).toBeNull(); // 塊の中に無い
    expect(keep({ slot: "原子筆", alts: ["鉛筆"] }).slot).toBeNull(); // 候補 1 つ
    expect(keep({ text: "借我筆袋", sentence: "借我筆袋一下。", slot: "我", alts: ["他", "朋友"] }).slot).toBeNull(); // 代名詞
    // 候補は重複・見出し語・入れ替えの字そのものを除いて 6 個まで。
    expect(keep({ alts: ["鉛筆", "鉛筆", "原子筆", "筆袋", "尺", "a", "b", "c", "d", "e"] }).alts).toEqual(["鉛筆", "尺", "a", "b", "c", "d"]);
  });

  it("同じ型（入れ替えの所を ＿ にした字）は 1 つだけ", () => {
    const r = gateChunksV2([ai(), ai({ sentence: "我把鉛筆放進筆袋裡。", text: "把鉛筆放進筆袋裡", slot: "鉛筆", alts: ["原子筆", "尺"] })], ZH);
    expect(r.kept).toHaveLength(1);
    expect(r.dropped[0].reason).toBe("duplicate");
  });
});

describe("塊の字を文に合わせて直す（repairChunkText）", () => {
  it("字が少し違う塊は、文の中でその字が順に入る最短の範囲に", () => {
    expect(repairChunkText("開電風扇", "你去開一下電風扇好不好", "電風扇")).toBe("開一下電風扇");
    expect(repairChunkText("手扶梯壞了", "手扶梯壞掉了，走樓梯吧", "手扶梯")).toBe("手扶梯壞掉了");
    expect(repairChunkText("紙箱拿去回收", "記得把紙箱要拿去回收", "紙箱")).toBe("紙箱要拿去回收");
  });
  it("見出し語を外して切った塊は、隣の見出し語まで広げる（間に 1 字まで）", () => {
    expect(repairChunkText("借我撐一下", "雨傘借我撐一下好嗎", "雨傘")).toBe("雨傘借我撐一下");
    expect(repairChunkText("掉到桌子底下", "馬克杯掉到桌子底下了", "馬克杯")).toBe("馬克杯掉到桌子底下");
    expect(repairChunkText("站右邊", "搭手扶梯要站右邊", "手扶梯")).toBe("手扶梯要站右邊");
    expect(repairChunkText("借我撐一下", "下雨了，雨傘呢，借我撐一下", "雨傘")).toBeNull();
  });
  it("余分の字が多い・句読点をまたぐ・見つからない時は null", () => {
    expect(repairChunkText("開電風扇", "你先去開一下那台很舊的電風扇", "電風扇")).toBeNull();
    expect(repairChunkText("開電風扇", "你去開，電風扇在那邊", "電風扇")).toBeNull();
    expect(repairChunkText("關電風扇", "你去開一下電風扇", "電風扇")).toBeNull();
  });
  it("門は直した字で通す", () => {
    const r = gateChunksV2([ai({ text: "開電風扇", sentence: "你去開一下電風扇好不好", key: "開", slot: null, alts: [] })], { headword: "電風扇", language: "zh-TW" });
    expect(r.kept.map((c) => c.text)).toEqual(["開一下電風扇"]);
    const h = gateChunksV2([ai({ text: "借我撐一下", sentence: "雨傘借我撐一下好嗎", key: "撐", slot: null, alts: [] })], { headword: "雨傘", language: "zh-TW" });
    expect(h.kept.map((c) => c.text)).toEqual(["雨傘借我撐一下"]);
  });
});

describe("鍵（frameKey / coreKey）", () => {
  it("型の字は入れ替えの所を ＿ に。候補でも保存した塊でも作れる", () => {
    expect(frameKey(cand("把原子筆放進筆袋裡", "放進", { slot: "原子筆" }))).toBe("把＿放進筆袋裡");
    expect(frameKey(chunk("把原子筆放進筆袋裡", [{ text: "把" }, { text: "原子筆", slot: true }, { text: "放進" }, { text: "筆袋裡" }]))).toBe("把＿放進筆袋裡");
  });
  it("中心の語の鍵は 了/過/著・一下 を除く。無ければ型の字", () => {
    expect(coreKey(cand("打開筆袋", "打開"))).toBe("K:打開");
    expect(coreKey(cand("筆袋壞了", "壞了"))).toBe("K:壞");
    expect(coreKey(cand("洗一下筆袋", "洗一下"))).toBe("K:洗");
    expect(coreKey(cand("筆袋的拉鍊", ""))).toBe("F:筆袋的拉鍊");
  });
});

describe("2 社の照合（mergeByAgreement）", () => {
  const A = [cand("把原子筆放進筆袋裡", "放進", { slot: "原子筆" }), cand("打開筆袋", "打開"), cand("裝進筆袋", "裝進")];
  const B = [cand("打開筆袋", "打開"), cand("把鉛筆放進筆袋裡", "放進", { slot: "鉛筆" }), cand("筆袋的拉鍊", "拉鍊")];

  it("同じ型（原子筆 と 鉛筆 は同じ型）は一致。片方だけの物は審査へ", () => {
    const r = mergeByAgreement(A, B);
    expect(r.agreed.map((c) => c.text)).toEqual(["把原子筆放進筆袋裡", "打開筆袋"]);
    expect(r.onlyA.map((c) => c.text)).toEqual(["裝進筆袋"]);
    expect(r.onlyB.map((c) => c.text)).toEqual(["筆袋的拉鍊"]);
  });

  it("片方の型がもう片方を含む時は一致とみなし、長い方を採る（切れ端より完全な形）", () => {
    const short = [cand("放進筆袋裡", "放進")];
    const full = [cand("把原子筆放進筆袋裡", "放進", { slot: "原子筆" })];
    expect(mergeByAgreement(short, full).agreed.map((c) => c.text)).toEqual(["把原子筆放進筆袋裡"]);
    expect(mergeByAgreement(full, short).agreed.map((c) => c.text)).toEqual(["把原子筆放進筆袋裡"]);
  });

  it("同じ中心の語で字が違う（關掉電風扇 と 把電風扇關掉）も一致。両方を候補に残し、審査の順位で 1 つにする", () => {
    const r = mergeByAgreement([cand("關掉電風扇", "關掉")], [cand("把電風扇關掉", "關掉")]);
    expect(r.agreed.map((c) => c.text)).toEqual(["關掉電風扇", "把電風扇關掉"]);
    expect(r.onlyA).toEqual([]);
    expect(r.onlyB).toEqual([]);
    const pool = poolCandidates(r);
    const picked = rankAndSelect(pool, [{ i: 1, natural: true, rank: 2 }, { i: 2, natural: true, rank: 1 }], null);
    expect(picked.selected.map((c) => c.text)).toEqual(["把電風扇關掉"]);
    expect(picked.rejected).toEqual([{ ...cand("關掉電風扇", "關掉"), by: "agreement", reason: "duplicate" }]);
  });

  it("並びは A・B の順位の平均", () => {
    const a = [cand("甲筆袋", "甲"), cand("乙筆袋", "乙")];
    const b = [cand("乙筆袋", "乙"), cand("甲筆袋", "甲")];
    expect(mergeByAgreement(a, b).agreed.map((c) => c.text)).toEqual(["甲筆袋", "乙筆袋"]);
    const b2 = [cand("乙筆袋", "乙"), cand("丙", "丙"), cand("甲筆袋", "甲")];
    expect(mergeByAgreement(a, b2).agreed.map((c) => c.text)).toEqual(["乙筆袋", "甲筆袋"]);
  });
});

describe("審査と並べ替え（readJudgeRanks / rankAndSelect）", () => {
  it("文字列の true・数字も読み、範囲外の i は捨てる。same は範囲内で自分以外の番号だけ", () => {
    const v = readJudgeRanks({ verdicts: [{ i: 1, natural: "true", rank: "2", same: null }, { i: 2, natural: false, rank: null, same: 1 }, { i: 9, natural: true, rank: 1 }, "x"] }, 2);
    expect(v).toEqual([
      { i: 1, natural: true, rank: 2 },
      { i: 2, natural: false, rank: null, same: 1 },
    ]);
    expect(readJudgeRanks({ verdicts: [{ i: 1, natural: true, rank: 1, same: 1 }, { i: 2, natural: true, rank: 2, same: "9" }] }, 2)).toEqual([
      { i: 1, natural: true, rank: 1 },
      { i: 2, natural: true, rank: 2 },
    ]);
    expect(readJudgeRanks(null, 2)).toEqual([]);
  });

  it("審査が「同じ言い方」と言った塊は 1 つ（順位の良い方を残す。どちらかの会社が言えば同じ）", () => {
    const pool = poolCandidates({ agreed: [], onlyA: [cand("把雨衣穿起來", "穿起來"), cand("把雨衣穿上", "穿上"), cand("把雨衣脫掉", "脫掉")], onlyB: [] });
    const ranksA = [
      { i: 1, natural: true, rank: 2 },
      { i: 2, natural: true, rank: 1, same: 1 },
      { i: 3, natural: true, rank: 3 },
    ];
    const r = rankAndSelect(pool, ranksA, null);
    expect(r.selected.map((c) => c.text)).toEqual(["把雨衣穿上", "把雨衣脫掉"]);
    expect(r.rejected.map((c) => [c.text, c.reason])).toEqual([["把雨衣穿起來", "duplicate"]]);
  });

  it("A の塊は B が自然と言った物だけ、B の塊は A が言った物だけ、一致はどちらかが自然と言えば通る。並びは 2 社の順位の平均", () => {
    const pool = poolCandidates({
      agreed: [cand("打開筆袋", "打開")],
      onlyA: [cand("裝進筆袋", "裝進"), cand("收好筆袋", "收好")],
      onlyB: [cand("買新的筆袋", "買")],
    });
    // 候補の並び: 1 打開（一致）2 裝進（A）3 收好（A）4 買（B）
    const ranksA = [
      { i: 1, natural: true, rank: 2 },
      { i: 2, natural: true, rank: 1 },
      { i: 3, natural: true, rank: 3 },
      { i: 4, natural: true, rank: 4 }, // A は B の塊を自然と言った
    ];
    const ranksB = [
      { i: 1, natural: true, rank: 1 },
      { i: 2, natural: false, rank: null }, // B は A の 裝進 を不自然と言った → 落ちる
      { i: 3, natural: true, rank: 2 },
      { i: 4, natural: true, rank: 3 },
    ];
    const r = rankAndSelect(pool, ranksA, ranksB);
    // 打開 (2+1)/2=1.5, 收好 (3+2)/2=2.5, 買 (4+3)/2=3.5
    expect(r.selected.map((c) => c.text)).toEqual(["打開筆袋", "收好筆袋", "買新的筆袋"]);
    expect(r.selected.map((c) => c.by)).toEqual(["agreement", "judge", "judge"]);
    expect(r.rejected.map((c) => [c.text, c.reason])).toEqual([["裝進筆袋", "unnatural"]]);
  });

  it("一致した塊でも、答えた審査が全部「不自然」なら落ちる（2 社が同じ汎用の文を書いた時の網）", () => {
    const pool = poolCandidates({ agreed: [cand("筆袋多少錢", "多少錢")], onlyA: [], onlyB: [] });
    expect(rankAndSelect(pool, [{ i: 1, natural: false, rank: null }], [{ i: 1, natural: false, rank: null }]).selected).toEqual([]);
    expect(rankAndSelect(pool, [{ i: 1, natural: false, rank: null }], [{ i: 1, natural: true, rank: 1 }]).selected).toHaveLength(1);
  });

  it("逆の会社の審査が無ければ自分の会社の審査で決め、どちらも無ければ通す。順位が無ければ候補の並び", () => {
    const pool = poolCandidates({ agreed: [], onlyA: [cand("打開筆袋", "打開"), cand("裝進筆袋", "裝進")], onlyB: [] });
    expect(rankAndSelect(pool, null, null).selected.map((c) => c.text)).toEqual(["打開筆袋", "裝進筆袋"]);
    // B の審査が時間切れ → A 自身の審査が「裝進 は不自然」と言えば落とす。
    const r = rankAndSelect(pool, [{ i: 1, natural: true, rank: 1 }, { i: 2, natural: false, rank: null }], null);
    expect(r.selected.map((c) => c.text)).toEqual(["打開筆袋"]);
    expect(r.rejected[0].reason).toBe("unnatural");
  });

  it("同じ中心の語の塊は 1 つ、上限 4。省いた物は理由つき", () => {
    const pool = poolCandidates({ agreed: [cand("把電風扇打開", "打開"), cand("打開電風扇", "打開")], onlyA: [], onlyB: [] });
    const r = rankAndSelect(pool, null, null);
    expect(r.selected.map((c) => c.text)).toEqual(["把電風扇打開"]);
    expect(r.rejected.map((c) => c.reason)).toEqual(["duplicate"]);
    const many = poolCandidates({ agreed: ["甲", "乙", "丙", "丁", "戊"].map((x) => cand(`${x}筆袋`, x)), onlyA: [], onlyB: [] });
    const m = rankAndSelect(many, null, null);
    expect(m.selected).toHaveLength(4);
    expect(m.rejected.map((c) => c.reason)).toEqual(["over_max"]);
  });
});

describe("仕上げ（finishCandidate / candidateToChunk）", () => {
  const c = { ...cand("把原子筆放進筆袋裡", "放進", { slot: "原子筆", alts: ["鉛筆", "橡皮擦"], pattern: "coverb", sentence: "我把原子筆放進筆袋裡了。" }), by: "agreement" as const };
  const ctx = { headword: "筆袋", language: "zh-TW", readerLang: "ja" };

  it("block と品詞・訳・入れ替えの候補の意味が付き、見出し語の場所は block の中の字の範囲", () => {
    const out = finishCandidate(
      c,
      { blocks: [{ text: "把", pos: "Prep" }, { text: "原子筆", pos: "N" }, { text: "放進", pos: "V" }, { text: "筆袋裡", pos: "N" }], ja: "ボールペンをペンケースに入れる", sentence_ja: "ボールペンをペンケースに入れたよ。", note: "物を入れる時のいちばん普通の言い方。", slot_ja: "ボールペン", alts_ja: ["鉛筆", "消しゴム"] },
      ctx,
    );
    expect(out.blocks.map((b) => `${b.text}/${b.pos}`)).toEqual(["把/Prep", "原子筆/N", "放進/V", "筆袋裡/N"]);
    expect(out.blocks[1]).toMatchObject({ slot: true, ja: "ボールペン", alts: [{ text: "鉛筆", ja: "鉛筆" }, { text: "橡皮擦", ja: "消しゴム" }] });
    expect(out.head).toEqual({ block: 3, start: 0, length: 2 });
    expect(out.ja).toBe("ボールペンをペンケースに入れる");
    expect(out.note).toBe("物を入れる時のいちばん普通の言い方。");
    expect(out.by).toBe("agreement");
    expect(out.pattern).toBe("coverb");
  });

  it("block をつないで塊と違えば block 1 つに。入れ替えの字が大きい block の中にあれば割る", () => {
    const bad = finishCandidate(c, { blocks: [{ text: "把原子筆", pos: "" }, { text: "放進筆袋", pos: "" }], ja: "やく" }, ctx);
    // つながらない返事は捨て、塊 1 つにしてから入れ替えの字で割る。
    expect(bad.blocks.map((b) => b.text)).toEqual(["把", "原子筆", "放進筆袋裡"]);
    const host = finishCandidate(c, { blocks: [{ text: "把原子筆", pos: "" }, { text: "放進", pos: "V" }, { text: "筆袋裡", pos: "N" }], ja: "やく" }, ctx);
    expect(host.blocks.map((b) => b.text)).toEqual(["把", "原子筆", "放進", "筆袋裡"]);
    expect(host.blocks[1].slot).toBe(true);
  });

  it("訳が読む人の言語でなければ訳を付けない（言語を混ぜない）。繁體中文で読む人は訳なし", () => {
    const en = finishCandidate(c, { blocks: [], ja: "Put the pen into the pencil case", sentence_ja: "I put it in.", slot_ja: "pen", alts_ja: ["pencil", "eraser"] }, ctx);
    expect(en.ja).toBe("");
    expect(en.sentence_ja).toBe("");
    expect(en.blocks.find((b) => b.slot)?.alts?.map((a) => a.ja)).toEqual(["", ""]);
    const zh = finishCandidate(c, { blocks: [], ja: "やく" }, { ...ctx, readerLang: "zh-TW" });
    expect(zh.ja).toBe("");
  });

  it("仕上げが無い時は block 1 つ・訳なし（中国語は書庫に残る）", () => {
    const out = candidateToChunk(c, "筆袋", "zh-TW");
    expect(out.blocks.map((b) => b.text)).toEqual(["把", "原子筆", "放進筆袋裡"]);
    expect(out.ja).toBe("");
    expect(out.head).toEqual({ block: 2, start: 2, length: 2 });
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
