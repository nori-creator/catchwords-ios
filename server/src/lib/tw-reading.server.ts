/**
 * **台湾華語の読み（拼音・注音）を、AI の答えのまま通さない**
 * （2026-10-03、本番で「拿鐵」が「nálǎtiě」と出た件）。
 *
 * 単語カード・最初の1枚・候補の読みは AI が書く。ここで保存・表示の前に検める:
 *
 * 1. 拼音の音節の数 = 見出しの漢字の数。
 * 2. 各音節がその字の**ありうる読み**（多音字の読みのどれか）。
 *    軽声は2字目以降なら認める。「一」「不」の変調も認める。
 * 3. 合わなければ、注音のほうが合っていればそれを使い、どちらも駄目なら
 *    **辞書の読み**に差し替える。辞書は `pinyin-pro`（MIT）。繁体字の語は
 *    `opencc-js`（Apache-2.0, 台湾正体 → 簡体）で字ごとに写してから引く
 *    （繁体字のままだと「銀行」を yín xíng と読む）。
 * 4. **台湾の読み**が大陸と違う字・語は、下の表（`TW_WORDS` / `TW_CHARS`）で
 *    決め打ちにする。AI が大陸の読みを返しても、その位置だけ台湾の読みに直す。
 * 5. 注音は、決まった拼音から作る（`pinyin-zhuyin.ts`）。AI の注音が同じ読みなら
 *    書かれたまま残し、違えば作った物に替える。
 *
 * 触らない物: 台湾華語以外の学習言語（英語・日本語）、漢字以外の字（英字・数字）が
 * 混ざる見出し（「T恤」「2個」）。辞書でも読めなかったときは AI の答えを残す
 * （**直せないなら悪くしない**）。
 *
 * サーバー専用（辞書が大きいので画面の束に入れない）。
 */

import { pinyin } from "pinyin-pro";
import { Converter } from "opencc-js/t2cn";
import {
  parsePinyin,
  parseZhuyin,
  sameSyllables,
  syllablesToPinyin,
  syllablesToZhuyin,
  type Syllable,
} from "./pinyin-zhuyin";
import { targetProfile, ZH_TW_PROFILE } from "./target-profile";

/**
 * **台湾の読み（語）**。教育部《重編國語辭典修訂本》の読み。大陸の普通話と違う物だけ。
 * 見出しの中に含まれていれば（「垃圾車」）その位置に当てる。
 */
export const TW_WORDS: Readonly<Record<string, string>> = {
  垃圾: "lè sè",
  頭髮: "tóu fǎ",
  法國: "fà guó",
  認識: "rèn shì",
  知識: "zhī shì",
  意識: "yì shì",
  品質: "pǐn zhí",
  性質: "xìng zhí",
};

/**
 * **台湾の読み（字）**。台湾では**その読みしか無い**字だけを置く
 * （「識」「質」のように別の読みも持つ字は、上の語の表で扱う）。
 */
export const TW_CHARS: Readonly<Record<string, string>> = {
  期: "qí", // 星期 xīng qí・期待 qí dài
  企: "qì", // 企鵝 qì é・企業 qì yè
  液: "yì",
  危: "wéi",
  微: "wéi",
  暫: "zhàn",
  擁: "yǒng",
  帆: "fán",
  綜: "zòng",
};

const HAN = /[㐀-䶿一-鿿豈-﫿]/u;
/** 読みを持たない区切り（空白・句読点）。見出しに混ざっていても数えない。 */
const IGNORABLE = /[\p{Z}\p{P}]/u;

let toSimplified: ((s: string) => string) | null = null;
function simplified(text: string): string {
  toSimplified ??= Converter({ from: "tw", to: "cn" });
  const out = toSimplified(text);
  // 字ごとに対応させて使うので、字数が変わる写し方は使わない。
  return [...out].length === [...text].length ? out : text;
}

function one(raw: string): Syllable | null {
  const list = parsePinyin(raw, 1);
  return list && list.length === 1 ? list[0] : null;
}

/** その字のありうる読み（繁体字のまま・簡体字に写した字・台湾の表）。 */
function readingsOf(char: string, simp: string): Syllable[] {
  const raw = new Set<string>([
    ...pinyin(char, { multiple: true, type: "array" }),
    ...pinyin(simp, { multiple: true, type: "array" }),
  ]);
  if (TW_CHARS[char]) raw.add(TW_CHARS[char]);
  for (const [word, reading] of Object.entries(TW_WORDS)) {
    const at = [...word].indexOf(char);
    if (at >= 0) raw.add(reading.split(" ")[at]);
  }
  return [...raw].map(one).filter((s): s is Syllable => s !== null);
}

/** 台湾の表で決まる位置（位置 → 読み）。語の表を先に、字の表で残りを埋める。 */
function taiwanPositions(chars: readonly string[]): Map<number, Syllable> {
  const fixed = new Map<number, Syllable>();
  const text = chars.join("");
  for (const [word, reading] of Object.entries(TW_WORDS)) {
    const syls = parsePinyin(reading, [...word].length);
    if (!syls) continue;
    let from = text.indexOf(word);
    while (from >= 0) {
      const start = [...text.slice(0, from)].length;
      syls.forEach((s, k) => fixed.set(start + k, s));
      from = text.indexOf(word, from + word.length);
    }
  }
  chars.forEach((c, i) => {
    const r = TW_CHARS[c];
    const s = r ? one(r) : null;
    if (s && !fixed.has(i)) fixed.set(i, s);
  });
  return fixed;
}

function applyTaiwan(list: Syllable[], fixed: Map<number, Syllable>): Syllable[] {
  return list.map((s, i) => fixed.get(i) ?? s);
}

/** 辞書の読み（台湾の表を当てた後）。読めなければ `null`。 */
function dictionaryReading(chars: readonly string[], simp: readonly string[]): Syllable[] | null {
  const raw = pinyin(simp.join(""), { type: "array" });
  if (raw.length !== chars.length) return null;
  const list = raw.map(one);
  if (list.some((s) => s === null)) return null;
  return applyTaiwan(list as Syllable[], taiwanPositions(chars));
}

/** AI の読みが字ごとにありうるか。 */
function plausible(
  list: readonly Syllable[],
  chars: readonly string[],
  simp: readonly string[],
): boolean {
  if (list.length !== chars.length) return false;
  return list.every((s, i) => {
    const options = readingsOf(chars[i], simp[i]);
    const sameBase = options.filter((o) => o.base === s.base);
    if (sameBase.length === 0) return false;
    if (sameBase.some((o) => o.tone === s.tone)) return true;
    // 2字目以降の軽声（「覺得」jué de）。1字目の声調なしは書き落としとみる。
    if (s.tone === 5 && i > 0) return true;
    // 「一」「不」は後ろの字で声調が変わる（yí gè・bú yào）。
    return chars[i] === "一" || chars[i] === "不";
  });
}

export type ReadingCheck = {
  pinyin: string;
  zhuyin: string;
  /** 何を直したか（直していなければ空）。 */
  fixed: Array<"pinyin" | "zhuyin">;
  /** 拼音を差し替えたときの理由。 */
  reason?: "count" | "syllable" | "taiwan";
  /** 差し替えの元（注音から起こした・辞書から引いた）。 */
  source?: "ai_zhuyin" | "dictionary";
};

/**
 * 見出しと AI の読みを検め、必要なら直した読みを返す（純粋な関数）。
 * 検められない見出し（漢字以外が混ざる・辞書でも読めない）はそのまま返す。
 */
export function checkTaiwanReading(
  headword: string,
  aiPinyin: string,
  aiZhuyin: string,
): ReadingCheck {
  const untouched: ReadingCheck = { pinyin: aiPinyin, zhuyin: aiZhuyin, fixed: [] };
  const all = [...(headword ?? "").trim()].filter((c) => !IGNORABLE.test(c));
  if (all.length === 0 || !all.every((c) => HAN.test(c))) return untouched;
  const chars = all;
  const simp = [...simplified(chars.join(""))];
  const n = chars.length;
  const fixed = taiwanPositions(chars);

  const fromPinyin = parsePinyin(aiPinyin, n);
  let final: Syllable[] | null = null;
  let reason: ReadingCheck["reason"];
  let source: ReadingCheck["source"];
  if (fromPinyin && plausible(fromPinyin, chars, simp)) {
    final = fromPinyin;
  } else {
    reason = !fromPinyin || fromPinyin.length !== n ? "count" : "syllable";
    const fromZhuyin = parseZhuyin(aiZhuyin, n);
    if (fromZhuyin && plausible(fromZhuyin, chars, simp)) {
      final = fromZhuyin;
      source = "ai_zhuyin";
    } else {
      final = dictionaryReading(chars, simp);
      source = "dictionary";
    }
  }
  if (!final) return untouched;

  const taiwan = applyTaiwan(final, fixed);
  const pinyinKept = fromPinyin !== null && sameSyllables(taiwan, fromPinyin);
  if (pinyinKept) {
    reason = undefined;
    source = undefined;
  } else if (!reason) {
    reason = "taiwan";
  }
  const zhuyinFromAi = parseZhuyin(aiZhuyin, n);
  const zhuyinKept = zhuyinFromAi !== null && sameSyllables(taiwan, zhuyinFromAi);
  const zhuyin = zhuyinKept ? aiZhuyin : syllablesToZhuyin(taiwan);
  if (zhuyin === null) return untouched;
  const out: ReadingCheck = {
    pinyin: pinyinKept ? aiPinyin : syllablesToPinyin(taiwan),
    zhuyin,
    fixed: [
      ...(pinyinKept ? [] : (["pinyin"] as const)),
      ...(zhuyinKept ? [] : (["zhuyin"] as const)),
    ],
  };
  if (reason) out.reason = reason;
  if (source) out.source = source;
  return out;
}

/**
 * 呼び出し口。台湾華語の語だけ検め、`pinyin` / `reading_zhuyin` を直した物を返す。
 * 他の言語・直す所が無いときは**同じ物**を返す。
 */
export function correctTaiwanReading<T extends { pinyin?: string; reading_zhuyin?: string }>(
  language: string | null | undefined,
  headword: string,
  item: T,
): T {
  if (targetProfile(language).code !== ZH_TW_PROFILE.code) return item;
  const r = checkTaiwanReading(headword, item.pinyin ?? "", item.reading_zhuyin ?? "");
  if (r.fixed.length === 0) return item;
  // 直したことは**見える所に残す**（AI の読みが外れる頻度を後で数えられるように）。
  console.warn("tw-reading: AI の読みを直した", {
    headword,
    from: { pinyin: item.pinyin, zhuyin: item.reading_zhuyin },
    to: { pinyin: r.pinyin, zhuyin: r.zhuyin },
    reason: r.reason ?? "zhuyin",
    source: r.source,
  });
  return { ...item, pinyin: r.pinyin, reading_zhuyin: r.zhuyin };
}
