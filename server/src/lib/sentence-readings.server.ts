import { pinyin } from "pinyin-pro";
import { Converter } from "opencc-js/t2cn";
import { formatPinyin, parsePinyin, syllableToZhuyin, type Syllable } from "./pinyin-zhuyin";
import { taiwanPositions } from "./tw-reading.server";

/**
 * **例文の漢字すべてに読み（拼音・注音）を付ける**（2026-10-22 オーナー「例文の漢字にピンインまたは注音をすべて
 * 書いて、書き方、大きさはアプリ内の書き方に統一して」）。
 *
 * AI は呼ばない（速さとお金のため。読みは辞書で決まる）。見出しの読みの検めと同じ道具で決める
 * （`tw-reading.server.ts`）:
 *
 * 1. 文ごと `pinyin-pro` に通す。語で区切って引くので、多音字も前後の字で読み分ける（還沒 hái・銀行 háng）。
 *    繁体字は `opencc-js` で字ごとに簡体字へ写してから引く（字数が変わる写し方は使わない）。
 * 2. **台湾の読み**（`TW_WORDS` / `TW_CHARS`、教育部《重編國語辭典修訂本》）をその位置に当てる。
 * 3. 最後に、その単語のカードが持つ読み（見出し・型の札。検め済み）を、文の中のその語の位置に当てる。
 *
 * 漢字でない字（句読点・英字・数字）は読み無し。読めなかった漢字も読み無し（**分からない物は書かない**）。
 * サーバー専用（辞書が大きい）。
 */

export type SentenceUnit = { char: string; pinyin: string | null; zhuyin: string | null };
export type KnownReading = { text: string; pinyin: string };

const HAN = /\p{Script=Han}/u;

let toSimplified: ((s: string) => string) | null = null;
function simplifiedChars(chars: readonly string[]): string[] {
  toSimplified ??= Converter({ from: "tw", to: "cn" });
  const whole = [...toSimplified(chars.join(""))];
  if (whole.length === chars.length) return whole;
  return chars.map((c) => {
    const one = [...toSimplified!(c)];
    return one.length === 1 ? one[0] : c;
  });
}

function syllable(raw: string | undefined): Syllable | null {
  const list = parsePinyin(raw ?? "", 1);
  return list && list.length === 1 ? list[0] : null;
}

/** 文の字ごとの読み。 */
export function readSentence(
  sentence: string,
  known: ReadonlyArray<KnownReading> = [],
): SentenceUnit[] {
  const chars = [...(sentence ?? "")];
  if (chars.length === 0) return [];
  const simp = simplifiedChars(chars);
  const whole = pinyin(simp.join(""), { type: "all" });
  const byChar =
    whole.length === chars.length
      ? whole.map((r) => (r.isZh ? r.pinyin : ""))
      : simp.map((c) => pinyin(c, { type: "all" })[0]?.pinyin ?? "");
  const list: Array<Syllable | null> = chars.map((c, i) =>
    HAN.test(c) ? syllable(byChar[i]) : null,
  );

  // 台湾の読み。
  for (const [i, s] of taiwanPositions(chars)) if (HAN.test(chars[i])) list[i] = s;

  // その単語のカードが持つ読み（見出し・型の札）。短い語から当てて、長い語で上書きする（長い語の読みが勝つ）。
  const text = chars.join("");
  const words = [...known]
    .map((k) => ({ chars: [...(k.text ?? "").trim()], pinyin: k.pinyin ?? "" }))
    .filter((k) => k.chars.length > 0 && k.chars.every((c) => HAN.test(c)))
    .sort((a, b) => a.chars.length - b.chars.length);
  for (const w of words) {
    const syls = parsePinyin(w.pinyin, w.chars.length);
    if (!syls || syls.length !== w.chars.length) continue;
    const word = w.chars.join("");
    let from = text.indexOf(word);
    while (from >= 0) {
      const start = [...text.slice(0, from)].length;
      syls.forEach((s, k) => (list[start + k] = s));
      from = text.indexOf(word, from + word.length);
    }
  }

  return chars.map((char, i) => {
    const s = list[i];
    return s
      ? { char, pinyin: formatPinyin(s), zhuyin: syllableToZhuyin(s) }
      : { char, pinyin: null, zhuyin: null };
  });
}
