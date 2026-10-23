/**
 * 読み上げの**声の選び方**を、学習言語ごとに1箇所で持つ。
 *
 * ## なぜ切り出したか
 * `tts.functions.ts` に台湾華語の声が3箇所、別々の形で直に書いてあった:
 *
 *   const GOOGLE_TTS_VOICE = "cmn-TW-Wavenet-A"
 *   voice: { languageCode: "cmn-TW", … }
 *   TTS_INSTRUCTIONS = "Speak naturally in Taiwan Mandarin (zh-TW) …"
 *
 * 英語を学習言語に足した日(2026-08-25、第4段)から、**英語の語が
 * 台湾華語の声で読まれる**。しかも `instructions` に
 * 「大陸の発音にするな」と書いてあるので、モデルは英語の語を
 * 中国語として読もうとする。
 *
 * server の中に置いたままだと試験から触れないので、純粋な物として出す。
 * ここは**表を引くだけ**で、外の世界には触れない。
 *
 * ## 声を「近いもの」で埋めない
 * 発音の正しさはこのアプリの致命傷にあたる所。知らない言語が来たら
 * 既定(台湾華語)に落とすが、**別の言語の声を当てはしない** —
 * 落とす先が既定なのは `normalizeTargetLanguage` の決めごとで、
 * ここで独自に近い言語を探しに行かない。
 */

import { DEFAULT_TARGET_LANGUAGE, normalizeTargetLanguage } from "./target-lang";

export type TtsVoice = {
  /**
   * Google Cloud TTS の言語コード。
   * **BCP-47 そのままではない** — 中国語は `cmn-TW`(ISO 639-3)で、
   * `zh-TW` を渡すと通らない。だから学習言語から機械的に作れない。
   */
  googleLanguageCode: string;
  /** Google Cloud TTS の声の名前。 */
  googleVoice: string;
  /**
   * OpenAI 互換の合成に渡す言い方の指示。
   *
   * **その言語のことだけを言う。** 台湾華語の指示に
   * 「大陸の発音にするな」と書いてあるのは正しいが、英語の語に
   * 掛けると、モデルは英語を中国語として読もうとする。
   */
  instructions: string;
};

const VOICES: Record<string, TtsVoice> = {
  // 台湾華語。端末に依らない一貫した台湾の発音(§4.3)。
  "zh-TW": {
    googleLanguageCode: "cmn-TW",
    googleVoice: "cmn-TW-Wavenet-A",
    instructions:
      "Speak naturally in Taiwan Mandarin (zh-TW) with a warm, friendly tone. " +
      "Use authentic Taiwanese pronunciation, not mainland Mandarin.",
  },
  // 英語。オーナー決定 2026-08-24「アメリカ英語を既定」。
  // TOEFL もアメリカ英語なので、学習の目標とも揃う。
  en: {
    googleLanguageCode: "en-US",
    googleVoice: "en-US-Wavenet-F",
    instructions:
      "Speak naturally in American English (en-US) with a warm, friendly tone. " +
      "Use a standard General American accent at a clear, unhurried pace.",
  },
  // 日本語(2026-10-01)。東京の標準語のアクセントで読む — 高低アクセントの節と
  // 同じ型で聞こえないと、カードの説明と音が食い違う。
  ja: {
    googleLanguageCode: "ja-JP",
    googleVoice: "ja-JP-Wavenet-B",
    instructions:
      "Speak naturally in standard Japanese (ja-JP) with a warm, friendly tone. " +
      "Use the standard Tokyo pitch accent at a clear, unhurried pace.",
  },
};

/**
 * その学習言語の声。**知らない値は既定に落とす** —
 * 未知の言語コードをそのまま合成に渡すと、API がエラーを返して
 * 読み上げが丸ごと黙る。
 */
export function ttsVoiceFor(language: string | null | undefined): TtsVoice {
  return VOICES[normalizeTargetLanguage(language)] ?? VOICES[DEFAULT_TARGET_LANGUAGE];
}

/**
 * 環境変数で声だけ差し替える口。
 *
 * `GOOGLE_TTS_VOICE` は台湾華語の声を差し替えるために既にあった。
 * **既定の言語にだけ効かせる** — 1つの変数で全言語の声を上書きすると、
 * 台湾華語の声を変えたつもりで英語まで中国語の声になる。
 */
export function withVoiceOverride(
  voice: TtsVoice,
  language: string | null | undefined,
  override: string | undefined,
): TtsVoice {
  const isDefault = normalizeTargetLanguage(language) === DEFAULT_TARGET_LANGUAGE;
  return isDefault && override ? { ...voice, googleVoice: override } : voice;
}
