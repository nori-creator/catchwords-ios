import { describe, expect, it } from "vitest";
import { GetNativeProsodyInput, SaveNativeProsodyInput, nativeAudioPath, toRecordings } from "./pronunciation";

const syllable = (base: number) => ({
  pitch: Array.from({ length: 10 }, (_, k) => base + k * 0.4),
  loudness: Array.from({ length: 10 }, (_, k) => -k),
  duration: 0.25,
  meanLoudness: -4,
  start: 0.1,
  end: 0.35,
});
const take = (n: number) => ({ syllables: Array.from({ length: n }, (_, i) => syllable(i)), pitchPercentiles: [-2, 3, 8] });

describe("native prosody", () => {
  it("returns only well-formed rows with the asked number of syllables", () => {
    const rows = [
      { speaker: "A", headword: "學校", range_low: -4, range_high: 10, take: take(2) },
      { speaker: "B", headword: "學校", range_low: -4, range_high: 10, take: take(3) },
      { speaker: "C", headword: "學校", range_low: 5, range_high: 6, take: take(2) },
      { speaker: "D", headword: "學校", range_low: -4, range_high: 10, take: { syllables: [] } },
    ];
    const out = toRecordings(rows, 2);
    expect(out.map((r) => r.speaker)).toEqual(["A"]);
    expect(out[0].range).toEqual({ low: -4, high: 10 });
    // 名前・音声の場所・誰が録ったかは形に無い
    expect(Object.keys(out[0]).sort()).toEqual(["headword", "range", "speaker", "take"]);
  });

  it("asks for a tone pattern only in the dictionary's form", () => {
    expect(GetNativeProsodyInput.safeParse({ headword: "學校", pattern: "2-4", syllables: 2 }).success).toBe(true);
    expect(GetNativeProsodyInput.safeParse({ headword: "學校", pattern: "2 4", syllables: 2 }).success).toBe(false);
    expect(GetNativeProsodyInput.safeParse({ headword: "學校", pattern: "6-4", syllables: 2 }).success).toBe(false);
  });

  it("saves only with the speaker's consent, a code for a name, and one syllable per character", () => {
    const ok = {
      speaker: "tw01",
      gender: "female",
      headword: "學校",
      pattern: "2-4",
      range: { low: -2, high: 12 },
      take: take(2),
      consent: true,
    };
    expect(SaveNativeProsodyInput.safeParse(ok).success).toBe(true);
    expect(SaveNativeProsodyInput.safeParse({ ...ok, consent: false }).success).toBe(false);
    expect(SaveNativeProsodyInput.safeParse({ ...ok, speaker: "王小明" }).success).toBe(false);
    expect(SaveNativeProsodyInput.safeParse({ ...ok, headword: "學" }).success).toBe(false);
    expect(SaveNativeProsodyInput.safeParse({ ...ok, pattern: "2-4-1" }).success).toBe(false);
  });

  it("keeps each speaker's audio under their code", () => {
    expect(nativeAudioPath("A", "x")).toBe("A/x.wav");
  });
});
