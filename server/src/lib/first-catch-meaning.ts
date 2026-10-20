import { fitsReaderLanguage } from "./meaning-language";
import type { UiLang } from "./i18n";

/**
 * **チュートリアルの意味・訳は、必ず表示言語で**（実物確認 2026-10-03 run 37105477674）。
 *
 * 表示言語 繁體中文 × 学習言語 英語の WebKit の回で、撮った後の候補に
 * 「flower 花。植物の生殖器官。」— **日本語の意味**が出た（同じ組み合わせの Chromium の回は
 * 「latte 拿鐵（一種咖啡飲料…）」で正しかった）。
 *
 * ## 原因
 * 候補の意味は AI の返事（`meaning_ja`）をそのまま画面に出していた。指示文には
 * 「意味は繁體中文で」と書いてあるが、JSON の鍵の名前が `meaning_ja` で、見本の値も
 * `"..."` だけだった。モデル（回によって答える AI が違う — 1番手が詰まると2番手）が
 * 鍵の名前に引かれて日本語で書く回があり、**返事の言語を誰も検めていなかった**。
 * カード（`card`）と解説（`lesson`）も同じ形で、カードは共有の控え（`generated_cards`、
 * 鍵は表示言語）にもそのまま残っていた。
 *
 * ## 直し方（ここは通信しない段取りだけ）
 * - 表示言語に合わない意味は、辞書（`dictionary_entries.meanings[表示言語]`）に在ればそれに
 *   置き換える（通知の意味と同じ道、`nearby.functions.ts` の `readerMeanings`）
 * - 無ければ**空にする** — 別の言語の意味を出すより、意味なしの方がよい
 * - 判定は文字の種類だけ（`fitsReaderLanguage`）。判定できない物は通す
 */

const HAN = /[㐀-䶿一-鿿々]/;
const KANA = /[ぁ-ゟァ-ヺー]/;
const LATIN = /[A-Za-z]/;

type Suggestion = { headword: string; meaning_ja: string; distinction?: string };

/** 表示言語に合わない意味の見出し（辞書を引く物）。 */
export function misfitHeadwords(items: readonly Suggestion[], reader: UiLang): string[] {
  return items.filter((s) => !fitsReaderMeaning(s.meaning_ja, reader)).map((s) => s.headword);
}

/**
 * 意味（短い語）が表示言語か。`fitsReaderLanguage` と同じ考えだが、日本語の読み手には
 * 漢字だけの意味を長さで落とさない（「自動販売機」を中国語と見なして消さない）。
 * - 英語 … 漢字もかなも無い
 * - 繁體中文 … かなが無く、漢字が在る（ラテン文字だけは英語）
 * - 日本語 … ラテン文字だけの意味（英語）でなければ通す
 */
export function fitsReaderMeaning(text: string | null | undefined, reader: UiLang): boolean {
  const s = (text ?? "").replace(/\s+/g, "");
  if (!s) return true;
  if (reader === "ja") return HAN.test(s) || KANA.test(s) || !LATIN.test(s);
  return fitsReaderLanguage(s, reader);
}

/** 意味1つを表示言語に揃える。合わなければ辞書の意味、それも無ければ空。 */
export function readerMeaning(
  text: string | null | undefined,
  reader: UiLang,
  dictionary?: string | null,
): string {
  const own = (text ?? "").trim();
  if (fitsReaderMeaning(own, reader)) return own;
  const dict = (dictionary ?? "").trim();
  return dict && fitsReaderMeaning(dict, reader) ? dict : "";
}

/**
 * 注記・訳・説明（長めの文）が表示言語で書かれているか。意味（短い語）より緩い —
 * 文の中に学習言語の語を引くことがある（英語の説明に「咖啡」、中文の説明に「latte」）。
 * はっきり別の言語の文だけを落とす:
 * - 英語の読み手 … ラテン文字が1つも無く、漢字・かなだけの文
 * - 繁體中文の読み手 … かなが在る文（学習言語が日本語の時は除く）、またはラテン文字だけの文
 * - 日本語の読み手 … `fitsReaderLanguage` と同じ（かなが在れば通す）
 */
export function fitsReaderNote(
  text: string | null | undefined,
  reader: UiLang,
  target: string,
): boolean {
  const s = (text ?? "").replace(/\s+/g, "");
  if (!s) return true;
  const han = HAN.test(s);
  const kana = KANA.test(s);
  const latin = LATIN.test(s);
  if (reader === "en") return latin || (!han && !kana);
  if (reader === "ja") return fitsReaderLanguage(s, "ja");
  // 繁體中文
  if (kana && target !== "ja") return false;
  return han || kana || !latin;
}

/** 注記・訳など（辞書で置き換えない物）。合わなければ空。 */
function keep(text: string | null | undefined, reader: UiLang, target: string): string {
  const s = text ?? "";
  return fitsReaderNote(s, reader, target) ? s : "";
}

/** 撮った後の候補の意味と使い分けの一言を、表示言語に揃える。 */
export function fitSuggestionsToReader<T extends Suggestion>(
  items: readonly T[],
  reader: UiLang,
  target: string,
  dictionary: ReadonlyMap<string, string> = new Map(),
): T[] {
  return items.map((s) => ({
    ...s,
    meaning_ja: readerMeaning(s.meaning_ja, reader, dictionary.get(s.headword)),
    ...(s.distinction !== undefined ? { distinction: keep(s.distinction, reader, target) } : {}),
  }));
}

type CardLike = {
  headword_zh: string;
  meaning_ja: string;
  example_translation?: string;
  extras?: unknown;
};

/** カードの意味・例文の訳・使い方の訳を、表示言語に揃える。 */
export function fitCardToReader<T extends CardLike>(
  card: T,
  reader: UiLang,
  target: string,
  dictionary?: string | null,
): T {
  const extras =
    card.extras && typeof card.extras === "object" && !Array.isArray(card.extras)
      ? (card.extras as Record<string, unknown>)
      : null;
  const fitList = (v: unknown) =>
    Array.isArray(v)
      ? v.map((item) =>
          item && typeof item === "object" && typeof (item as { ja?: unknown }).ja === "string"
            ? { ...item, ja: keep((item as { ja: string }).ja, reader, target) }
            : item,
        )
      : v;
  return {
    ...card,
    meaning_ja: readerMeaning(card.meaning_ja, reader, dictionary),
    ...(card.example_translation !== undefined
      ? { example_translation: keep(card.example_translation, reader, target) }
      : {}),
    ...(extras
      ? {
          extras: {
            ...extras,
            usage_chunks: fitList(extras.usage_chunks),
            examples_extra: fitList(extras.examples_extra),
            ...(typeof extras.usage_context === "string"
              ? { usage_context: keep(extras.usage_context, reader, target) }
              : {}),
          },
        }
      : {}),
  };
}

type LessonLike = {
  senses: Array<{ meaning: string; note: string }>;
  examples: Array<{
    sentence: string;
    translation: string;
    situation: string;
    explanation: string;
  }>;
};

/**
 * 解説の意味・注記・訳を表示言語に揃える。意味が表示言語で無い意味の行は落とす。
 * 1つも残らなければ null（呼ぶ側は「返事の形が使えない」として扱う）。
 */
export function fitLessonToReader<T extends LessonLike>(
  lesson: T,
  reader: UiLang,
  target: string,
): T | null {
  const senses = lesson.senses
    // 意味の行は文になることがある（「作為飲品的咖啡」）ので、注記と同じ緩い判定。
    .filter((s) => s.meaning.trim() && fitsReaderNote(s.meaning, reader, target))
    .map((s) => ({ ...s, note: keep(s.note, reader, target) }));
  if (!senses.length) return null;
  return {
    ...lesson,
    senses,
    examples: lesson.examples.map((e) => ({
      ...e,
      translation: keep(e.translation, reader, target),
      situation: keep(e.situation, reader, target),
      explanation: keep(e.explanation, reader, target),
    })),
  };
}
