import type { UiLang } from "./i18n";
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
 * ## 判定は文字の種類だけ（`text-language.ts` と同じ考え）
 * - 英語 … 漢字もかなも無い
 * - 日本語 … かなが在る。**漢字だけの短い語も通す**（「鶏肉」「書類用」）
 * - 繁體中文 … かなが無く、漢字が在る
 *
 * 判定できない物（空・記号・数字）は通す。落とすのは「別の言語だと
 * はっきり分かる」ときだけ。
 */

const HAN = /[㐀-䶿一-鿿々]/;
const KANA = /[ぁ-ゟァ-ヺー]/;
const LATIN = /[A-Za-z]/;

/** 日本語で「漢字だけ」を通す長さの上限。長い漢字だけの文は中国語とみなす。 */
const JA_HAN_ONLY_MAX = 4;

export function fitsReaderLanguage(text: string | null | undefined, reader: UiLang): boolean {
  const s = (text ?? "").replace(/\s+/g, "");
  if (!s) return true;
  const han = HAN.test(s);
  const kana = KANA.test(s);
  const latin = LATIN.test(s);
  if (reader === "en") return !han && !kana;
  if (reader === "ja") {
    if (kana) return true;
    if (han) return s.replace(/[^㐀-䶿一-鿿々]/g, "").length <= JA_HAN_ONLY_MAX;
    return !latin;
  }
  // 繁體中文
  if (kana) return false;
  if (han) return true;
  return !latin;
}

/**
 * 4択の選択肢を**どの言語で揃えるか**。
 *
 * ふつうは読み手の言語。ただ正解そのもの（`meaning_ja`）が別の言語で
 * 保存されている古い語では、読み手の言語で誤答を揃えると**正解だけが
 * 違う言語**になり、見ただけで当たる。そのときは正解の言語に揃える
 * 正解そのものが別の言語で残っている件は、ここでは直さない（揃えるだけ）。
 */
export function quizMeaningLanguage(correct: string, reader: UiLang): UiLang {
  if (fitsReaderLanguage(correct, reader)) return reader;
  const s = correct.replace(/\s+/g, "");
  if (KANA.test(s)) return "ja";
  if (HAN.test(s)) return reader === "ja" ? "ja" : CHINESE_EXPLANATION_LANGUAGE;
  return "en";
}

/** 読み手の言語に合わない注記を空にする。**書き換えず、落とすだけ。** */
export function keepReaderLanguage(text: string | null | undefined, reader: UiLang): string {
  const s = text ?? "";
  return fitsReaderLanguage(s, reader) ? s : "";
}
