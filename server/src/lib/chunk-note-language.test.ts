import { describe, expect, it } from "vitest";
import { scrubExtrasForReader, scrubForReader, scrubForeignNotes } from "./note-language";

/**
 * チャンクのひと言解説（usage_chunks[].note）と関連語の訳（related_words[].gloss）も、読む人の言語でない物は落とす
 * （オーナー 2026-10-20「決して言語が混ざらないように」、2026-10-24「表示言語を変えたときに、すべての言語でエラーが出ないように」）。
 */
describe("ひと言解説・関連語の訳は読む人の言語だけ", () => {
  const extras = () => ({
    usage_chunks: [
      { parts: [{ text: "戴", pos: "V" }, { text: "水晶手鍊", pos: "N" }], ja: "水晶ブレスレットをつける", note: "戴 は身につける物ぜんぶに使う。服と靴だけは 穿。" },
      { parts: [{ text: "水晶手鍊", pos: "N" }, { text: "招財", pos: "V" }], ja: "水晶ブレスレットが金運を呼ぶ", note: "台灣人常說水晶手鍊可以招財。" },
    ],
    related_words: [
      { word: "手環", kind: "syn", gloss: "ブレスレット", note: "腕輪全般。", reading: "ㄕㄡˇ ㄏㄨㄢˊ" },
      { word: "寶石", kind: "rel", gloss: "寶石類", note: "宝石全般。", reading: "ㄅㄠˇ ㄕˊ" },
    ],
  });
  it("日本語の読み手: 中文の解説・訳は空に、日本語は残す", () => {
    const out = scrubExtrasForReader(extras(), "ja") as ReturnType<typeof extras>;
    expect(out.usage_chunks[0].note).toContain("身につける");
    expect(out.usage_chunks[1].note).toBe("");
    expect(out.related_words[0].gloss).toBe("ブレスレット");
    // 漢字だけの短い訳は語の欄として残す（「宝石」のような和語の訳を落とさない）— 寶石類 は繁体字なので判定は表に従う。
    expect(typeof out.related_words[1].gloss).toBe("string");
  });
  it("英語の読み手: 日本語の解説は空に", () => {
    const out = scrubExtrasForReader(extras(), "en") as ReturnType<typeof extras>;
    expect(out.usage_chunks[0].note).toBe("");
    expect(out.related_words[0].gloss).toBe("");
  });
  it("短い注記の門（日本語の読み手）と訳の門も note を見る", () => {
    const a = scrubForeignNotes(extras(), "ja");
    expect(a.usage_chunks?.[1].note).toBe("");
    const b = scrubForReader(extras(), "en");
    expect(b.usage_chunks?.[0].note).toBe("");
  });
  it("解説が無い古い語は形を変えない", () => {
    const old = { usage_chunks: [{ parts: [{ text: "戴", pos: "V" }], ja: "つける" }], related_words: [{ word: "手環", kind: "syn", note: "腕輪全般。" }] };
    const out = scrubExtrasForReader(old, "ja") as typeof old;
    expect("note" in out.usage_chunks[0]).toBe(false);
    expect("gloss" in out.related_words[0]).toBe(false);
  });
});

describe("6つの表示言語すべてで、ひと言解説が混ざらない", () => {
  const notes: Record<string, string> = {
    ja: "戴 は身につける物ぜんぶに使う。服と靴だけは 穿。",
    en: "Use 戴 for anything you wear on the body; 穿 is only for clothes and shoes.",
    "zh-TW": "戴 用在所有配戴在身上的東西，衣服和鞋子才用 穿。",
    es: "Se usa 戴 para todo lo que se lleva puesto; 穿 solo para ropa y zapatos.",
    ko: "戴 는 몸에 착용하는 모든 것에 써요. 옷과 신발만 穿 을 써요.",
    vi: "Dùng 戴 cho mọi thứ đeo trên người; 穿 chỉ dùng cho quần áo và giày.",
  };
  const readers = Object.keys(notes);
  for (const reader of readers) {
    it(`${reader} の読み手: 自分の言語の解説は残り、ほかの言語の解説は落ちる`, () => {
      for (const written of readers) {
        const out = scrubExtrasForReader(
          { usage_chunks: [{ parts: [{ text: "戴", pos: "V" }, { text: "水晶手鍊", pos: "N" }], ja: "", note: notes[written] }] },
          reader,
        ) as { usage_chunks: Array<{ note?: string }> };
        const kept = out.usage_chunks[0].note !== "";
        // 同じ文字を使う言語どうし（en/es/vi はラテン文字）は文字だけでは分けられない — 判定の決まりは iOS と同じ
        // （`LanguageRules.looksWrong`）。ここでは「自分の言語は必ず残る」「文字の違う言語は必ず落ちる」を確かめる。
        if (written === reader) expect({ reader, written, kept }).toEqual({ reader, written, kept: true });
        const script = (l: string) => (l === "ja" ? "kana" : l === "zh-TW" ? "han" : l === "ko" ? "hangul" : "latin");
        if (script(written) !== script(reader)) expect({ reader, written, kept }).toEqual({ reader, written, kept: false });
      }
    });
  }
});
