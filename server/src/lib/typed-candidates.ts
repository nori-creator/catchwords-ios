/**
 * **打って調べた語の候補**（`suggestWordCandidates`）の決め事。AI は呼ばない — 返事を並べ直して形をそろえる。
 *
 * オーナー指示 2026-10-15:
 * > 写真で取れなかった物を文字で調べた時も、写真と同じように候補を出して選ばせて（いきなりキャッチしない）。
 * > 日本語で「犬」と打ったら、まず日本語として読む。台湾華語のふだんの言い方（狗）を一般的な言い方にして、
 * > 同じ字の「犬」は本当に使う時だけ、使われ方の印（警犬・導盲犬の犬 → 学術的・より詳しい）を付けて並べる。
 * > 漢字だからというだけで、打った字をそのまま台湾華語の見出し語にしない。
 *
 * 返事の形は写真の候補と同じ（`register` / `object_label` / `category_key`）に、`gloss`（表示言語の短い意味）を足す。
 * 画面（iOS・Web）は**必ず候補の一覧を出して選ばせる**。候補が1つでも、そのままキャッチに進めない。
 */
import { detectQueryLang, type QueryLang } from "./text-query-lang";
import { BASIC_LEVEL_ZH_TW, basicLevelTable } from "./basic-level";
import { firstGloss, type NameRegister } from "./candidate-register";
import type { UiLang } from "./i18n";

/**
 * 打った語をどう読むか。
 * - `learning` … 学習言語の語として打った（台湾の字にしか無い形・英語を学ぶ人の英語）。その語を返す。
 * - `display` … 表示言語（または別の言語）で打った（かな・新字体・英字）。学習言語の言い方に直す。
 * - `display_first` … 漢字だけで、表示言語（日本語）の語としても学習言語の語としても読める（「犬」「電車」）。
 *   **まず表示言語の語として読む**。打った字そのものは、学習言語で本当に使う時だけ印を付けて並べる。
 */
export type TypedQueryMode = "learning" | "display" | "display_first";

export function typedQueryMode(
  query: string,
  targetLanguage: string,
  reader: UiLang,
  given?: QueryLang,
): TypedQueryMode {
  const lang = given ?? detectQueryLang(query, targetLanguage);
  if (lang === "target") return "learning";
  if (lang === "native") return "display";
  // 漢字の言語でない学習言語（英語）で決まらない語は、別の言語で打った語として引く。
  if (!targetLanguage.toLowerCase().startsWith("zh")) return "display";
  // 漢字だけで決まらない語。表示言語が漢字の言語（日本語）で、学習言語と別なら表示言語として先に読む。
  // 英語・繁體中文で読む人が漢字だけを打ったら、それは学習言語（台湾華語）の字。
  const readerUsesHan = reader === "ja";
  const sameAsTarget = reader.split("-")[0] === targetLanguage.toLowerCase().split("-")[0];
  return readerUsesHan && !sameAsTarget ? "display_first" : "learning";
}

type TypedCandidate = {
  headword: string;
  reading_zhuyin: string;
  pinyin: string;
  meaning_ja: string;
  distinction: string;
  register: NameRegister;
  style: string | null;
  scene: string;
  usage: string | null;
  image_query: string;
  category_key: string;
};

const EVERYDAY_STYLES = new Set(["spoken", "both"]);
const BOOKISH_STYLES = new Set(["written", "technical"]);

/**
 * **一般的な言い方は、ふだんの会話で言う語**。1つ目（common）の文体が書き言葉・専門（written / technical）で、
 * 会話の語（spoken / both）が他に在れば、それを1つ目にする。下げた語は 専門 → academic、書き言葉 → specific。
 */
export function preferEverydayCommon<T extends TypedCandidate>(list: readonly T[]): T[] {
  if (list.length < 2) return [...list];
  const [first, ...rest] = list;
  if (first.register !== "common" || !BOOKISH_STYLES.has(first.style ?? "")) return [...list];
  const k = rest.findIndex((c) => EVERYDAY_STYLES.has(c.style ?? ""));
  if (k < 0) return [...list];
  const promoted = { ...rest[k], register: "common" as NameRegister };
  const demoted = {
    ...first,
    register: (first.style === "technical" ? "academic" : "specific") as NameRegister,
  };
  const others = rest.filter((_, i) => i !== k);
  return [promoted, demoted, ...others] as T[];
}

/**
 * 表示言語の語が、表の基本の語の表示言語の名前そのものなら（犬・ケーキ・パン）、その基本の語（狗・蛋糕・麵包）を
 * 一般的な言い方として先頭に置く（無ければ足す）。打った字そのもの（犬）が別の語として在れば、一般的な言い方から下げる。
 * 「下着」のように学習言語の言い方が割れる語（內褲・內衣）は表に任せない（AI の並びのまま）。
 */
export function ensureTypedBasic<T extends TypedCandidate>(
  list: readonly T[],
  query: string,
  mode: TypedQueryMode,
  reader: UiLang,
  targetLanguage: string,
): T[] {
  if (mode === "learning") return [...list];
  const q = query.trim();
  const entry = basicLevelTable(targetLanguage).find(
    (e) => e.label[reader] === q && e.headword !== q && e.typedFromReader,
  );
  if (!entry) return [...list];
  // 基本の語の後ろでは、どれも一般的な言い方にしない（1つ目だけが common）。打った字そのもの（犬）は、
  // 専門の文体なら学術的な言い方、それ以外はより詳しい言い方。
  const demote = (c: T): T =>
    c.register === "common"
      ? ({
          ...c,
          register: (c.headword === q && c.style === "technical"
            ? "academic"
            : "specific") as NameRegister,
        } as T)
      : c;
  const k = list.findIndex((c) => c.headword === entry.headword);
  if (k === 0) return list.map((c, i) => (i === 0 ? c : demote(c)));
  if (k > 0) {
    const promoted = { ...list[k], register: "common" as NameRegister };
    return [promoted, ...list.filter((_, i) => i !== k).map(demote)] as T[];
  }
  const basic = {
    ...(list[0] ?? {}),
    headword: entry.headword,
    reading_zhuyin: entry.reading_zhuyin,
    pinyin: entry.pinyin,
    meaning_ja: entry.label[reader],
    distinction: "",
    register: "common",
    style: "spoken",
    scene: "",
    usage: "common",
    image_query: entry.label.en,
    category_key: entry.category,
  } as T;
  return [basic, ...list.map(demote)];
}

/**
 * 打った物の**表示言語の名前**（写真のタグと同じ `object_label`）。表示言語で打ったなら打った語そのもの
 * （表示言語の言葉として読める時）、学習言語で打ったなら1つ目の候補の意味の最初の言い方 — 1つ目が表の基本の語
 * なら表の名前（`rowTag`: 貓 → 猫。写真のタグと同じ `rowTagOf`）。
 */
export function typedObjectLabel(
  query: string,
  mode: TypedQueryMode,
  common: { meaning_ja?: string; headword: string } | undefined,
  isReaderText: (text: string, headword: string) => boolean,
  rowTag?: string | null,
): string {
  const q = query.trim().slice(0, 40);
  if (mode !== "learning" && q && isReaderText(q, common?.headword ?? "")) return q;
  if (rowTag?.trim()) return rowTag.trim();
  const gloss = firstGloss(common?.meaning_ja ?? "");
  return gloss && isReaderText(gloss, common?.headword ?? "") ? gloss : "";
}

/** 返事の候補1つ（`suggestWordCandidates` の `candidates[]`）。古い欄はそのまま、新しい欄を足す。 */
export type TypedCandidateOut<T> = T & {
  /** 表示言語の短い意味（`meaning_ja` の最初の言い方）。 */
  gloss: string;
  /** 打った物の表示言語の名前（全部の候補に同じ値。写真の候補と同じ欄）。 */
  object_label: string;
};

/** 候補に `gloss` と `object_label` を付ける。 */
export function withTypedLabels<T extends { meaning_ja: string }>(
  list: readonly T[],
  objectLabel: string,
): Array<TypedCandidateOut<T>> {
  return list.map((c) => ({ ...c, gloss: firstGloss(c.meaning_ja), object_label: objectLabel }));
}

/** 打った語の候補の指示文の、打った語の読み方の行。 */
export function typedQueryLine(opts: {
  query: string;
  mode: TypedQueryMode;
  targetName: string;
  readerName: string;
}): string {
  const { query, mode, targetName, readerName } = opts;
  if (mode === "learning") {
    return (
      `「${query}」は${targetName}の語として打たれている。query_is_target は true。` +
      `candidates の1つ目はその語（読み・意味）。その語がふだんの言い方でなければ（書き言葉・専門の形）、` +
      `ふだんの言い方も後ろに並べてよい。`
    );
  }
  if (mode === "display") {
    return `「${query}」は学習者の表示言語（${readerName}）か別の言語で打たれている。${targetName}でどう言うかを並べる。query_is_target は false。`;
  }
  return (
    `「${query}」は漢字だけで、${readerName}の語としても${targetName}の語としても読める。` +
    `**まず${readerName}の語として読む**（学習者は${readerName}で考えて打った）。その語が指す物・意味を${targetName}で` +
    `**実際にどう言うか**を並べ、**ふだんの会話で言う語を1つ目（common）にする**（例: 犬 → 狗、桃 → 桃子）。` +
    `打った字そのもの（犬）は、${targetName}で本当にその形で使う時だけ候補に入れ、使われ方の印を付ける` +
    `（例: 犬 → academic「警犬・導盲犬・犬科のような複合語・書き言葉で使う」）。` +
    `**漢字だから・字が同じだからという理由で、打った字を1つ目や見出し語にしない。**` +
    `打った字がそのまま${targetName}のふだんの言い方でもある時（花・花束）だけ、その語を common にする。query_is_target は false。`
  );
}

/** 基本の語の表で、打った表示言語の語から引いてよい物（犬 → 狗・ケーキ → 蛋糕）。テストが読む。 */
export const TYPED_BASIC_HEADWORDS: readonly string[] = BASIC_LEVEL_ZH_TW.filter(
  (e) => e.typedFromReader,
).map((e) => e.headword);
