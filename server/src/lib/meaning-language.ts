import { explainScript, latinLanguageOf, type ExplainLang } from "./explain-languages";
import { CHINESE_EXPLANATION_LANGUAGE } from "./target-lang";

/**
 * **意味・訳・注記がその読み手の言語で書かれているか**（オーナー報告
 * 2026-09-27「復習の4択と解説に別の言語が混ざる」）。
 *
 * ## どこで混ざっていたか
 * 4択の誤答は3つの池から取る — 自分の図鑑の他の語の意味・AI が前もって
 * 作った誤答・最後の受け皿。どれも**作った日の表示言語で保存されている**。
 * 表示言語を変えた人、英語と日本語の両方で集めた人の4択には、
 * 日本語と英語が並ぶ。しかも受け皿は日本語で決め打ちだった
 * （`quiz-choices.ts` の `FALLBACK_MEANINGS`）。
 *
 * 1つだけ言語の違う選択肢は、**読まなくても消せる**ので問題として壊れる。
 *
 * ## 判定は文字の種類（`text-language.ts` と同じ考え）。言語は書く文字で分かれる
 * - 欧文の言語（英語・スペイン語・ベトナム語）… 漢字もかなもハングルも無い。そのうえで、
 *   **別の欧文の言語だとはっきり分かる**物（"the … of"、"de … que"、đ ơ ư）は通さない
 *   （`latinLanguageOf`）
 * - 日本語 … かなが在る。**漢字だけの短い語も通す**（「鶏肉」「書類用」）
 * - 繁體中文 … かなもハングルも無く、漢字が在る
 * - 韓国語 … かなも漢字も無く、ハングルが在る
 *
 * 判定できない物（空・記号・数字）は通す。落とすのは「別の言語だと
 * はっきり分かる」ときだけ。
 */

const HAN = /[㐀-䶿一-鿿々]/;
const KANA = /[ぁ-ゟァ-ヺー]/;
const LATIN = /[A-Za-z]/;
const HANGUL = /[가-힯ᄀ-ᇿ]/;

/** 日本語で「漢字だけ」を通す長さの上限。長い漢字だけの文は中国語とみなす。 */
const JA_HAN_ONLY_MAX = 4;

export function fitsReaderLanguage(
  text: string | null | undefined,
  reader: ExplainLang | string,
): boolean {
  const s = (text ?? "").replace(/\s+/g, "");
  if (!s) return true;
  const han = HAN.test(s);
  const kana = KANA.test(s);
  const latin = LATIN.test(s);
  const hangul = HANGUL.test(s);
  switch (explainScript(reader)) {
    case "latin": {
      if (han || kana || hangul) return false;
      const other = latinLanguageOf(text);
      return !other || other === reader;
    }
    case "kana":
      if (kana) return true;
      if (hangul) return false;
      if (han) return s.replace(/[^㐀-䶿一-鿿々]/g, "").length <= JA_HAN_ONLY_MAX;
      return !latin;
    case "hangul":
      if (kana || han) return false;
      if (hangul) return true;
      return !latin;
    default:
      // 繁體中文
      if (kana || hangul) return false;
      if (han) return true;
      return !latin;
  }
}

/**
 * 4択の選択肢を**どの言語で揃えるか**。
 *
 * ふつうは読み手の言語。ただ正解そのもの（`meaning_ja`）が別の言語で
 * 保存されている古い語では、読み手の言語で誤答を揃えると**正解だけが
 * 違う言語**になり、見ただけで当たる。そのときは正解の言語に揃える
 * 正解そのものが別の言語で残っている件は、ここでは直さない（揃えるだけ）。
 */
export function quizMeaningLanguage(correct: string, reader: ExplainLang): ExplainLang {
  if (fitsReaderLanguage(correct, reader)) return reader;
  const s = correct.replace(/\s+/g, "");
  if (KANA.test(s)) return "ja";
  if (HAN.test(s)) return reader === "ja" ? "ja" : CHINESE_EXPLANATION_LANGUAGE;
  if (HANGUL.test(s)) return "ko";
  // 欧文: はっきり分かる言語、分からなければ英語。
  const latin = latinLanguageOf(correct);
  return latin === "es" || latin === "vi" ? latin : "en";
}

/** 読み手の言語に合わない注記を空にする。**書き換えず、落とすだけ。** */
export function keepReaderLanguage(
  text: string | null | undefined,
  reader: ExplainLang | string,
): string {
  const s = text ?? "";
  return fitsReaderLanguage(s, reader) ? s : "";
}
