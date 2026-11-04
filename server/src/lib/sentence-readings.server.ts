import { pinyin } from "pinyin-pro";
import { Converter } from "opencc-js/t2cn";
import { formatPinyin, parsePinyin, syllableToZhuyin, type Syllable } from "./pinyin-zhuyin";
import { ownReading, taiwanAt, taiwanFixes } from "./tw-reading.server";

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

/** 字に読みが2つ以上あるか（簡体字に写した字も見る）。 */
function polyphonic(char: string): boolean {
  const simp = simplifiedChars([char])[0];
  const all = new Set([
    ...pinyin(char, { multiple: true, type: "array" }),
    ...pinyin(simp, { multiple: true, type: "array" }),
  ]);
  return all.size > 1;
}

/** 名詞の終わりの「子」を軽声で読む語（辞書が zǐ と読む物）。 */
const NEUTRAL_ZI = new Set(
  "包鞋杯椅桌盤筷帽褲裙房孩兒妻日餃粽橘李梨柿瓶盒袋箱鏡剪刷梳毯被墊釘鉗勺叉碟罐籃鍋板夾繩鼻肚脖嗓鬍辮院屋車本樣句例位鴿獅猴兔蚊蝦柚栗椰茄竹葉褂襪領扣棍蓋簾櫃爐桃".split(""),
);
/** 「得」の後がこの字なら děi ではない（得到・得了・得過・得分・得獎・得病）。 */
const DE_NOT_DEI = new Set("到了過分獎病意出知罪".split(""));
/** 「得」の前がこの字で、後に動詞が来るなら「〜しなければならない」の děi。 */
const DEI_BEFORE = new Set("我你他她它們也就還都".split(""));
/** 文の終わりの語気の字（軽声）。喔 は台湾の ㄛ。 */
const PARTICLES: Readonly<Record<string, string>> = { 啦: "la", 嘛: "ma", 耶: "ye", 喔: "ō", 囉: "luo", 吧: "ba" };

const syl = (raw: string): Syllable | null => syllable(raw);

/** 前後の字で読みが決まる所を直す（その場で書き換える）。 */
function fixContext(chars: readonly string[], list: Array<Syllable | null>): void {
  const isHan = (i: number) => i >= 0 && i < chars.length && HAN.test(chars[i]);
  chars.forEach((c, i) => {
    if (!list[i]) return;
    const prev = chars[i - 1] ?? "";
    const next = chars[i + 1] ?? "";
    // 決定 10B（2026-11-03）: 「一」「不」は辞書の形（yī・bù）。変調した声調は書かない。軽声はそのまま。
    if (c === "一" && list[i]!.tone !== 5) list[i] = syl("yī");
    if (c === "不" && list[i]!.tone !== 5) list[i] = syl("bù");
    // 名詞の終わりの「子」。
    if (c === "子" && i > 0 && NEUTRAL_ZI.has(prev)) list[i] = syl("zi");
    // 「慢慢地」「好好地」: 重ねた字の後の「地」は de。
    if (c === "地" && i >= 2 && chars[i - 1] === chars[i - 2]) list[i] = syl("de");
    // 「我得去」: 主語・副詞の後で、後に動詞が続く「得」は děi。
    if (c === "得" && DEI_BEFORE.has(prev) && isHan(i + 1) && !DE_NOT_DEI.has(next)) list[i] = syl("děi");
    // 「還書」「還錢」「還給」は返す（huán）。
    if (c === "還" && "書錢給".includes(next) && next !== "") list[i] = syl("huán");
    // 文の終わり（句読点の前・文末）の語気の字。
    if (PARTICLES[c] && (i === chars.length - 1 || !isHan(i + 1))) list[i] = syl(PARTICLES[c]);
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
  const list: Array<Syllable | null> = chars.map((c, i) => {
    const s = HAN.test(c) ? syllable(byChar[i]) : null;
    return s ? ownReading(c, s) : null;
  });

  // 辞書の読み分けで外れる所（2026-11-03 点検 S10・S5）。台湾の語の表より先（幹嘛 の 嘛 は語の読み）。
  fixContext(chars, list);

  // 台湾の読み。
  for (const [i, f] of taiwanFixes(chars)) if (HAN.test(chars[i])) list[i] = taiwanAt(list[i], f, i);

  // その単語のカードが持つ読み（見出し・型の札）。短い語から当てて、長い語で上書きする（長い語の読みが勝つ）。
  // 1字の見出しは、その字に読みが1つしか無い時だけ（「還 huán」のカードの例文の「還沒」を huán にしない — 点検 M35）。
  const text = chars.join("");
  const words = [...known]
    .map((k) => ({ chars: [...(k.text ?? "").trim()], pinyin: k.pinyin ?? "" }))
    .filter((k) => k.chars.length > 0 && k.chars.every((c) => HAN.test(c)))
    .filter((k) => k.chars.length > 1 || !polyphonic(k.chars[0]))
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
