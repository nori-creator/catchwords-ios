import { describe, expect, it } from "vitest";
import { containsChunk, exampleLength, EXAMPLE_MAX_HAN, pickExamplePatterns } from "./example-patterns";
import { gateUsageChunks } from "./chunk-quality";

/** オーナー 2026-10-25: 例文は必ず2行以内（24字まで）・型を字のまま含む例文を先に・ひと言解説は訳の言い直しにしない。 */
describe("例文の厳しい決まり", () => {
  const base = { situation: "", scene: "友達と話す時", scene_fits: true, translation: "訳", chunks: [] as { text: string; pos: string }[] };
  const opts = { headword: "水晶手鍊", language: "zh-TW", readerLang: "ja" };
  it("字数は句読点を数えない", () => {
    expect(exampleLength("我每天都戴水晶手鍊，聽說可以帶來好運。")).toBe(17);
    expect(EXAMPLE_MAX_HAN).toBe(24);
  });
  it("24字以内の文があれば、それより長い文は使わない", () => {
    const long = { ...base, share: 90, sentence: "我昨天在夜市看到一條很漂亮的水晶手鍊所以就決定買下來送給我媽媽當生日禮物" };
    const short = { ...base, share: 10, sentence: "我每天都戴水晶手鍊，聽說可以帶來好運。" };
    const out = pickExamplePatterns([long, short], opts);
    expect(out.map((e) => e.sentence)).toEqual([short.sentence]);
  });
  it("短い文が無ければ、長い文でも短い順に残す（例文が空になるよりよい）", () => {
    const a = { ...base, share: 50, sentence: "我昨天在夜市看到一條很漂亮的水晶手鍊所以就決定買下來送給我媽媽當生日禮物" };
    expect(pickExamplePatterns([a], opts)).toHaveLength(1);
  });
  it("型を字のまま含む文を先にする（入れ替えの候補でもよい）", () => {
    const chunks = [{ parts: [{ text: "水晶手鍊" }, { text: "招財", alts: [{ text: "招桃花" }] }] }, { parts: [{ text: "戴" }, { text: "水晶手鍊" }] }];
    expect(containsChunk("老闆說這條水晶手鍊招桃花喔", chunks)).toBe(true);
    expect(containsChunk("我想買水晶手鍊", chunks)).toBe(false);
    const plain = { ...base, share: 80, sentence: "我想買一條水晶手鍊送朋友。" };
    const withChunk = { ...base, share: 20, sentence: "我每天都戴水晶手鍊，感覺很好。" };
    const out = pickExamplePatterns([plain, withChunk], { ...opts, chunks });
    expect(out[0].sentence).toBe(withChunk.sentence);
  });
});

describe("ひと言解説の門", () => {
  const ctx = { headword: "水晶手鍊", meaning: "水晶ブレスレット", language: "zh-TW", readerLang: "ja" };
  const chunk = (note: string) => ({ parts: [{ text: "戴", pos: "V" }, { text: "水晶手鍊", pos: "N" }], ja: "水晶ブレスレットをつける", note, fits: true, why: "" });
  it("訳の言い直しだけの解説は保存しない", () => {
    expect(gateUsageChunks([chunk("水晶ブレスレットをつける。")], ctx).kept[0].note).toBeUndefined();
  });
  it("長すぎる解説（1文の約束を破った物）は保存しない", () => {
    expect(gateUsageChunks([chunk("あ".repeat(81))], ctx).kept[0].note).toBeUndefined();
  });
  it("ふつうの解説は残す", () => {
    expect(gateUsageChunks([chunk("戴 は身につける物ぜんぶに使う。服と靴だけは 穿。")], ctx).kept[0].note).toContain("穿");
  });
});
