import { z } from "zod";

/**
 * **発音コーチの「ネイティブの範囲」の数値**（2026-11-29、オーナー「本物の発音から分析して、この範囲で高さ・長さ・強さ
 * などの要素で総合的に判定したい」）。設計は `docs/pronunciation-coach.md`。
 *
 * 台湾の人（オーナーの彼女・友達）が開発者の端末の「ネイティブの発音を録音」で読んだ単語を、**端末が分析した数値**で
 * 預かる。分析の手順は iOS の `ProsodyAnalyzer`（学習者・ネイティブ・AI 音声を同じ手順で測る）。サーバは測り直さない。
 *
 * - `take`: 音節ごとに、10 か所の高さ（100 Hz からの半音）・強さ（その録音の一番大きい所からの dB）・長さ（秒）。
 * - `range`: その人の声の範囲（一番低い声〜一番高い声の「あー」の 5〜95%、半音）。学習者も同じはかり方なので、
 *   声の高い人・低い人を 1〜5 の同じ目盛りで比べられる（話者正規化）。
 * - 学習者のアプリへ返すのは数値と話者の記号だけ。音声・名前・誰が録ったかは返さない。
 */

export const PROSODY_POINTS = 10;
export const MAX_SYLLABLES = 8;

const finite = z.number().finite();

export const SyllableProsody = z.object({
  pitch: z.array(finite.min(-40).max(60)).length(PROSODY_POINTS),
  loudness: z.array(finite.min(-120).max(1)).length(PROSODY_POINTS),
  duration: finite.positive().max(5),
  meanLoudness: finite.min(-120).max(1),
  start: finite.min(0).max(60),
  end: finite.min(0).max(60),
});

export const ProsodyTake = z.object({
  syllables: z.array(SyllableProsody).min(1).max(MAX_SYLLABLES),
  pitchPercentiles: z.array(finite.min(-40).max(60)).length(3),
});
export type ProsodyTake = z.infer<typeof ProsodyTake>;

export const SpeakerRange = z
  .object({ low: finite.min(-40).max(60), high: finite.min(-40).max(60) })
  .refine((r) => r.high - r.low >= 3, "range too narrow");

/** 声調の並び（2-4）。一・不 を含む語は iOS が送らない（次の字で声調が変わるので、同じ並びの語で代えられない）。 */
export const TonePattern = z.string().regex(/^[1-5](-[1-5]){0,7}$/);

/** 話者の記号（A・B・tw01 …）。名前や連絡先は入れない。 */
export const SpeakerCode = z.string().regex(/^[A-Za-z0-9_-]{1,16}$/);

export const GetNativeProsodyInput = z.object({
  headword: z.string().trim().min(1).max(16),
  pattern: TonePattern.optional(),
  syllables: z.number().int().min(1).max(MAX_SYLLABLES),
});

export const SaveNativeProsodyInput = z
  .object({
    speaker: SpeakerCode,
    gender: z.enum(["female", "male", "other", "unknown"]).default("unknown"),
    headword: z.string().trim().min(1).max(16),
    zhuyin: z.string().max(80).optional(),
    pattern: TonePattern.optional(),
    range: SpeakerRange,
    take: ProsodyTake,
    /** 話者が「発音の手本を作るために声を保存する」ことに同意した（同意なしでは保存しない）。 */
    consent: z.literal(true),
    /** 16 kHz・16 bit の WAV（分析をやり直すためだけに置く）。12 秒まで。 */
    audio_wav_base64: z.string().max(560_000).optional(),
  })
  .refine((v) => !v.pattern || v.pattern.split("-").length === v.take.syllables.length, "pattern length")
  .refine((v) => [...v.headword].length === v.take.syllables.length, "one syllable per character");

export type NativeProsodyRow = {
  speaker: string;
  headword: string;
  range_low: number;
  range_high: number;
  take: unknown;
};

export type NativeProsodyRecording = {
  speaker: string;
  headword: string;
  range: { low: number; high: number };
  take: ProsodyTake;
};

/** DB の行 → アプリへ返す形。形の崩れた行（古い版・手で入れた行）は捨てる。 */
export function toRecordings(rows: NativeProsodyRow[] | null | undefined, syllables: number): NativeProsodyRecording[] {
  const out: NativeProsodyRecording[] = [];
  for (const r of rows ?? []) {
    const take = ProsodyTake.safeParse(r.take);
    if (!take.success || take.data.syllables.length !== syllables) continue;
    const range = SpeakerRange.safeParse({ low: r.range_low, high: r.range_high });
    if (!range.success) continue;
    out.push({ speaker: r.speaker, headword: r.headword, range: range.data, take: take.data });
  }
  return out;
}

/** 録音の置き場所（`native-audio` バケット、非公開）。 */
export function nativeAudioPath(speaker: string, id: string): string {
  return `${speaker}/${id}.wav`;
}
