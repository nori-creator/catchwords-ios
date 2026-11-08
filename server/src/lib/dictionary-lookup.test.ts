import { describe, expect, it } from "vitest";
import {
  LookupReplySchema,
  alignChars,
  lookupQueryLine,
  normalizeLookup,
  normalizeLookupUsage,
  type ReaderChecks,
} from "./dictionary-lookup";

const japanese: ReaderChecks = {
  meaning: (t) => /[ぁ-んァ-ヶー一-龯]/.test(t) && !/[a-zA-Z]{3,}/.test(t),
  note: (t) => /[ぁ-んァ-ヶ]/.test(t),
  target: (t) => !/[ぁ-んァ-ヶ]/.test(t),
};
const keep = <T,>(_h: string, item: T) => item;
const other = () => "other";

function run(raw: unknown, query = "傘", mode: "learning" | "display" | "display_first" = "display") {
  return normalizeLookup(LookupReplySchema.parse(raw), {
    query,
    mode,
    targetLanguage: "zh-TW",
    checks: japanese,
    fixReading: keep,
    category: other,
  });
}

const umbrella = {
  headword: "雨傘",
  pinyin: "yǔ sǎn",
  reading_zhuyin: "ㄩˇ ㄙㄢˇ",
  gloss: "傘",
  senses: ["雨がさ", "傘"],
  proper: false,
  usage: "everyday",
  nuance: "陽傘は日よけ用。雨の日はこちら",
  chars: [
    { char: "雨", meaning: "あめ" },
    { char: "傘", meaning: "かさ" },
  ],
  why: "雨をよける傘で、雨傘になる",
  example: "外面下雨，記得帶雨傘。",
  example_translation: "外は雨だから、傘を忘れずに。",
  image_query: "umbrella",
  category_key: "daily",
};

describe("normalizeLookup", () => {
  it("keeps a well-formed entry and reads each character from the checked reading", () => {
    const [e] = run({ entries: [umbrella, { ...umbrella, headword: "陽傘", gloss: "日傘" }] });
    expect(e.headword).toBe("雨傘");
    expect(e.chars).toEqual([
      { char: "雨", pinyin: "yǔ", meaning: "あめ" },
      { char: "傘", pinyin: "sǎn", meaning: "かさ" },
    ]);
    expect(e.why).toContain("雨");
    expect(e.example).toBe("外面下雨，記得帶雨傘。");
    // 短い意味と同じ物は意味の広がりに重ねない
    expect(e.senses).toEqual(["雨がさ"]);
  });

  it("drops headwords not written in the learning language and duplicates", () => {
    const out = run({
      entries: [umbrella, { ...umbrella }, { ...umbrella, headword: "かさ" }, { ...umbrella, headword: "umbrella" }],
    });
    expect(out.map((e) => e.headword)).toEqual(["雨傘"]);
  });

  it("drops an entry whose short meaning is not in the reader's language", () => {
    const out = run({ entries: [{ ...umbrella, gloss: "umbrella" }] });
    expect(out).toEqual([]);
  });

  it("drops the character breakdown when it does not match the headword, and the why with it", () => {
    const [e] = run({ entries: [{ ...umbrella, chars: [{ char: "雨", meaning: "あめ" }] }] });
    expect(e.chars).toEqual([]);
    expect(e.why).toBe("");
  });

  it("drops an example that does not contain the headword or is too long", () => {
    const [a] = run({ entries: [{ ...umbrella, example: "外面下雨。" }] });
    expect(a.example).toBe("");
    expect(a.example_translation).toBe("");
    const [b] = run({ entries: [{ ...umbrella, example: "外面下雨，記得帶雨傘，因為氣象局說今天下午到晚上都會一直下很大的雨。" }] });
    expect(b.example).toBe("");
  });

  it("puts the typed word first when it was typed in the learning language", () => {
    const out = run(
      { entries: [{ ...umbrella, headword: "陽傘", gloss: "日傘" }, umbrella] },
      "雨傘",
      "learning",
    );
    expect(out[0].headword).toBe("雨傘");
  });

  it("shows no comparison when there is only one entry", () => {
    const [e] = run({ entries: [umbrella] });
    expect(e.nuance).toBe("");
  });

  it("reads a broken reply as no entries instead of failing", () => {
    expect(run({ entries: "oops" })).toEqual([]);
    expect(run({})).toEqual([]);
  });

  it("drops an image query that is not short English", () => {
    const [e] = run({ entries: [{ ...umbrella, image_query: "雨傘" }] });
    expect(e.image_query).toBe("");
  });
});

describe("alignChars", () => {
  it("needs two characters or more", () => {
    expect(alignChars("傘", [{ char: "傘", meaning: "かさ" }], "sǎn")).toEqual([]);
  });
  it("leaves the reading empty when the reading cannot be split", () => {
    const out = alignChars(
      "雨傘",
      [
        { char: "雨", meaning: "あめ" },
        { char: "傘", meaning: "かさ" },
      ],
      "",
    );
    expect(out.map((c) => c.pinyin)).toEqual(["", ""]);
  });
});

describe("normalizeLookupUsage", () => {
  it("maps loose labels onto the five places", () => {
    expect(normalizeLookupUsage("colloquial")).toBe("spoken");
    expect(normalizeLookupUsage("signage")).toBe("sign");
    expect(normalizeLookupUsage("formal")).toBe("written");
    expect(normalizeLookupUsage(undefined)).toBe("everyday");
  });
});

describe("lookupQueryLine", () => {
  it("asks for the typed word itself first when it is in the learning language", () => {
    expect(
      lookupQueryLine({ query: "雨傘", mode: "learning", targetName: "台湾華語", readerName: "日本語" }),
    ).toContain("1つ目に「雨傘」");
  });
  it("lets a reading be typed", () => {
    expect(
      lookupQueryLine({ query: "yusan", mode: "display", targetName: "台湾華語", readerName: "日本語" }),
    ).toContain("拼音");
  });
});
