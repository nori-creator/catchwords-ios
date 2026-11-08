/**
 * **しらべる（辞書）** — 打った言葉から、学習言語の語の見出しを引く（オーナー指示 2026-11-08
 * 「検索とかその辞書みたいに文字を検索して、単語カードが作れたり…辞書の代わりになるようにしたい」
 * 「ただ辞書を表示するだけだったら、その辞書を使えばいい…AI にしかできない、学習者にとって役立つ情報を」）。
 *
 * カメラの「違う単語を入力」（写真の物の名前を打つ道、`suggestWordCandidates`）とは別の道。
 * ここは**写真の無い、辞書としての引き方**:
 *
 * - 打てる物: 表示言語の語（傘）・学習言語の字（雨傘）・読み（拼音は声調なしも yusan、注音 ㄩˇ ㄙㄢˇ）。
 * - 1語ずつ返す物（辞書の土台）: 見出し・読み・短い意味・意味の広がり（1〜3つ）・固有名詞かどうか・使う場。
 * - **AI にしか書けない物**（学習者の困りごと）:
 *   - `chars` / `why`: 字ごとの意味と、**なぜその組み合わせでその意味になるか**（丸暗記にしない）。
 *   - `nuance`: 候補が割れる時、**ほかの候補と比べて**どれを使うか（辞書は1語ずつしか説明しない）。
 *   - `example`: 台湾でそのまま使える短い一文（学習者のレベル、24 字以内）。
 *
 * ここは表と純粋な関数だけ（試験から読む）。AI を呼ぶのは `dictionary.functions.ts`。
 */
import { z } from "zod";
import { coerceTargetHeadword, isTargetHeadword } from "./target-language";
import { parsePinyin, syllablesToPinyin } from "./pinyin-zhuyin";

/** 1回に返す見出しの数の上限（一対一の語は1つ）。 */
export const LOOKUP_MAX_ENTRIES = 6;
/** 例文の字数の上限（`CLAUDE.md`: 例文は 24 字以内。句読点のぶん少し見る）。 */
export const LOOKUP_EXAMPLE_MAX = 28;
/** 打てる長さ。 */
export const LOOKUP_QUERY_MAX = 60;

/**
 * 使う場（どこで聞く・見る言葉か）。画面は短い札で出す。
 * - everyday ふだんの会話でも文章でも / spoken 話し言葉 / written 書き言葉・ニュース /
 *   technical 専門の言葉 / sign 看板・メニュー・表示の言葉
 */
export const LOOKUP_USAGES = ["everyday", "spoken", "written", "technical", "sign"] as const;
export type LookupUsage = (typeof LOOKUP_USAGES)[number];

export function normalizeLookupUsage(raw: unknown): LookupUsage {
  const v = typeof raw === "string" ? raw.trim().toLowerCase() : "";
  if ((LOOKUP_USAGES as readonly string[]).includes(v)) return v as LookupUsage;
  if (/^(both|common|general|neutral|standard)/.test(v)) return "everyday";
  if (/^(casual|colloquial|informal|slang)/.test(v)) return "spoken";
  if (/^(formal|literary|news)/.test(v)) return "written";
  if (/^(academic|professional|scientific|special)/.test(v)) return "technical";
  if (/^(signage|menu|label|notice)/.test(v)) return "sign";
  return "everyday";
}

const str = (max: number) =>
  z
    .unknown()
    .transform((v) => (typeof v === "string" ? v.trim().slice(0, max) : ""))
    .catch("");

/** AI の返事の形（読めない所は空にして、1語ごとに後で検める）。 */
export const LookupReplySchema = z.object({
  entries: z
    .array(
      z.object({
        headword: str(40),
        pinyin: str(80),
        reading_zhuyin: str(80),
        gloss: str(60),
        senses: z
          .array(str(80))
          .catch([])
          .default([]),
        proper: z.unknown().transform((v) => v === true || v === "true").catch(false),
        usage: z.unknown().transform(normalizeLookupUsage).catch("everyday" as LookupUsage),
        nuance: str(120),
        chars: z
          .array(z.object({ char: str(4), meaning: str(40) }).passthrough())
          .catch([])
          .default([]),
        why: str(160),
        example: str(60),
        example_translation: str(160),
        image_query: str(80),
        category_key: str(40),
      }),
    )
    .catch([])
    .default([]),
});
export type LookupReply = z.infer<typeof LookupReplySchema>;
export type LookupReplyEntry = LookupReply["entries"][number];

export type LookupChar = { char: string; pinyin: string; meaning: string };

/** 画面へ返す1語。 */
export type LookupEntry = {
  headword: string;
  pinyin: string;
  reading_zhuyin: string;
  gloss: string;
  senses: string[];
  proper: boolean;
  usage: LookupUsage;
  nuance: string;
  chars: LookupChar[];
  why: string;
  example: string;
  example_translation: string;
  image_query: string;
  category_key: string;
};

/** 打った言葉をどう読んだか（`typedQueryMode` と同じ物差し）。 */
export type LookupMode = "learning" | "display" | "display_first";

/** 文字の数え方（サロゲートの字も1字）。 */
export function charsOf(text: string): string[] {
  return Array.from(text);
}

/** 見出しの字の列と AI の字ごとの意味を合わせる。字が合わなければ全部捨てる（ずれた説明は出さない）。 */
export function alignChars(
  headword: string,
  given: ReadonlyArray<{ char: string; meaning: string }>,
  pinyin: string,
): LookupChar[] {
  const chars = charsOf(headword);
  if (chars.length < 2 || given.length !== chars.length) return [];
  if (!given.every((g, i) => g.char === chars[i] && g.meaning.trim())) return [];
  // 字の読みは、検めた後の見出しの読みから1音節ずつ取る（AI の字ごとの読みは使わない）。
  const syllables = parsePinyin(pinyin, chars.length);
  const readings =
    syllables && syllables.length === chars.length
      ? syllables.map((s) => syllablesToPinyin([s]))
      : chars.map(() => "");
  return chars.map((c, i) => ({ char: c, pinyin: readings[i], meaning: given[i].meaning.trim() }));
}

/** 読む人の言語で書けているかの確かめ（呼ぶ側が渡す。試験では偽物）。 */
export type ReaderChecks = {
  /** 短い意味（`fitsReaderMeaning`）。 */
  meaning: (text: string) => boolean;
  /** 地の文（`fitsReaderNote`）。 */
  note: (text: string) => boolean;
  /** 学習言語の文か（`looksLikeTargetLanguage`）。 */
  target: (text: string) => boolean;
};

/**
 * AI の返事を画面に出せる形にする:
 * - 見出しは学習言語の語だけ（注釈を外して直せる物は直す）。同じ見出しは1つ。
 * - 意味・使い分け・成り立ち・訳は読む人の言語の物だけ（混ざった物は空にする — `docs/language-rules.md`）。
 *   短い意味が読む人の言語でない語は出さない（見出しだけ出しても引けたことにならない）。
 * - 例文は学習言語の文で、見出しを含み、長すぎない物だけ。訳が読む人の言語でなければ例文ごと外す。
 * - 学習言語の字で打った語は、その語を先頭に置く（引いた語が1つ目に来ないと辞書にならない）。
 */
export function normalizeLookup(
  raw: LookupReply,
  opts: {
    query: string;
    mode: LookupMode;
    targetLanguage: string;
    checks: ReaderChecks;
    /** 読みを検める（`correctTaiwanReading`）。 */
    fixReading: <T extends { pinyin?: string; reading_zhuyin?: string }>(
      headword: string,
      item: T,
    ) => T;
    /** 分類の鍵を直す（`normalizeCategory`）。 */
    category: (headword: string, key: string) => string;
  },
): LookupEntry[] {
  const { checks } = opts;
  const seen = new Set<string>();
  const out: LookupEntry[] = [];
  for (const e of raw.entries) {
    const headword = coerceTargetHeadword(e.headword, opts.targetLanguage) ?? "";
    if (!headword || !isTargetHeadword(headword, opts.targetLanguage) || seen.has(headword)) continue;
    const gloss = e.gloss.trim();
    if (!gloss || !checks.meaning(gloss)) continue;
    seen.add(headword);
    const read = opts.fixReading(headword, { pinyin: e.pinyin, reading_zhuyin: e.reading_zhuyin });
    const pinyin = (read.pinyin ?? "").trim();
    const zhuyin = (read.reading_zhuyin ?? "").trim();
    const senses = e.senses
      .map((s) => s.trim())
      .filter((s) => s && s !== gloss && checks.meaning(s))
      .slice(0, 3);
    const nuance = e.nuance && checks.note(e.nuance) ? e.nuance : "";
    const chars = alignChars(
      headword,
      e.chars.filter((c) => checks.meaning(c.meaning)),
      pinyin,
    );
    const why = chars.length > 0 && e.why && checks.note(e.why) ? e.why : "";
    const exampleOk =
      e.example.length > 0 &&
      charsOf(e.example).length <= LOOKUP_EXAMPLE_MAX &&
      e.example.includes(headword) &&
      checks.target(e.example) &&
      e.example_translation.length > 0 &&
      checks.note(e.example_translation);
    out.push({
      headword,
      pinyin,
      reading_zhuyin: zhuyin,
      gloss,
      senses,
      proper: e.proper,
      usage: e.usage,
      nuance,
      chars,
      why,
      example: exampleOk ? e.example : "",
      example_translation: exampleOk ? e.example_translation : "",
      image_query: /^[\x20-\x7E]{2,80}$/.test(e.image_query) ? e.image_query : "",
      category_key: opts.category(headword, e.category_key),
    });
    if (out.length >= LOOKUP_MAX_ENTRIES) break;
  }
  // 学習言語で打った語は、引いた語そのものを先頭に（AI が関連の語を先に並べても）。
  if (opts.mode === "learning") {
    const typed = opts.query.trim();
    const i = out.findIndex((e) => e.headword === typed);
    if (i > 0) out.unshift(...out.splice(i, 1));
  }
  // 候補が1つなら、比べる相手がいないので使い分けは出さない。
  if (out.length === 1) out[0] = { ...out[0], nuance: "" };
  return out;
}

/** 打った言葉の読み方を、AI への一行にする。 */
export function lookupQueryLine(opts: {
  query: string;
  mode: LookupMode;
  targetName: string;
  readerName: string;
}): string {
  const q = opts.query;
  switch (opts.mode) {
    case "learning":
      return `「${q}」は${opts.targetName}の語として書かれた。1つ目に「${q}」そのものの見出しを置く（実在する語なら）。続けて、学習者が一緒に知るべき語（よく一緒に使う複合語・意味の近い語で使い分けが要る物）を最大3つ。`;
    case "display_first":
      return `「${q}」はまず${opts.readerName}の語として読み、その意味の${opts.targetName}の語を挙げる。同じ字の${opts.targetName}の語があり、意味か使い方が違うなら、それも挙げて違いを nuance に書く。`;
    default:
      return `「${q}」は${opts.readerName}の語、または${opts.targetName}の読み（拼音は声調なし・数字の声調も、注音も）として書かれた。読みとして読めるならその読みの語をよく使う順に、${opts.readerName}の語ならその意味の${opts.targetName}の語を挙げる。`;
  }
}
