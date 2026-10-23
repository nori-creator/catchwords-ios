import { DEFAULT_TARGET_LANGUAGE } from "./target-lang";

/**
 * **辞書の1行を、読む人の言語で読み直す。**
 *
 * ## なぜ要るのか
 * `dictionary_entries` には**名前に言語が入った古い列**と、
 * **どの言語でも正しい新しい列**の2組がある:
 *
 *   古い: `zhuyin` / `pinyin` / `meaning_ja` / `tocfl_level`
 *   新しい: `reading_primary` / `reading_alt` / `meanings` / `level_step`
 *
 * 英語の行は**新しい列にしか入らない**(`admin.functions.ts` の注 —
 * `zhuyin` に IPA を入れると、それを注音として出す画面ができる)。
 * ところが引く側は古い列しか見ていなかったので、**英語の語を引いても
 * 読みも意味も空**で返っていた。辞書だけでカードを出す道が、
 * 英語では丸ごと死んでいたということ。
 *
 * 直し方は「引く側で読み直す」。画面はこれまでどおり `zhuyin` /
 * `meaning_ja` という名前で受け取れるので、**画面側を1つも変えずに**
 * 英語が通るようになる。
 *
 * ## 意味は「読む人の言語」で選ぶ
 * `meanings` の鍵は**解説を書いた言語**。日本語の人に中文の語釈を出す
 * のは「無いよりまし」ではなく**間違い**なので、鍵が合わないときは
 * 何も返さない(呼ぶ側が AI に落ちる)。
 *
 * 古い `meaning_ja` は名前のとおり日本語なので、読む人が日本語のときだけ
 * 受け皿にする。
 */
export type RawDictionaryRow = {
  zhuyin?: string | null;
  pinyin?: string | null;
  meaning_ja?: string | null;
  tocfl_level?: number | null;
  reading_primary?: string | null;
  reading_alt?: string | null;
  meanings?: Record<string, string> | null;
  level_step?: number | null;
};

export type ResolvedDictionaryFields = {
  /** 既定の読み。台湾華語は注音、英語はアメリカ英語の IPA。 */
  reading: string | null;
  /** 第二の読み。台湾華語は拼音、英語はイギリス英語寄りの IPA。 */
  readingAlt: string | null;
  /** 読む人の言語での意味。**合う言語が無ければ空**。 */
  meaning: string;
  /** CEFR / TOCFL の段。**`null` は級外**(級が付いていない語)。 */
  levelStep: number | null;
};

const clean = (v: string | null | undefined): string | null => {
  const s = (v ?? "").trim();
  return s ? s : null;
};

/** その行を、解説の言語で読み直す。 */
export function resolveDictionaryFields(
  row: RawDictionaryRow,
  explainLang: string,
): ResolvedDictionaryFields {
  // **新しい列を先に見る。** 古い列は既定の言語にしか入っていない。
  const reading = clean(row.reading_primary) ?? clean(row.zhuyin);
  const readingAlt = clean(row.reading_alt) ?? clean(row.pinyin);

  const byLang = row.meanings ?? {};
  const meaning =
    clean(byLang[explainLang]) ?? (explainLang === "ja" ? clean(row.meaning_ja) : null) ?? "";

  // 段も新しい列が先。**0 を段として扱わない** — 級外は `null` で表す。
  const rawStep = row.level_step ?? row.tocfl_level ?? null;
  const levelStep =
    typeof rawStep === "number" && Number.isInteger(rawStep) && rawStep >= 1 && rawStep <= 6
      ? rawStep
      : null;

  return { reading, readingAlt, meaning, levelStep };
}

/**
 * 引く行に要る列。**1箇所に書く** — `select` の並びと読み直しが
 * 別々の場所にあると、列を1つ足したときに片方だけ直る。
 */
export const DICTIONARY_SELECT =
  "headword, zhuyin, pinyin, meaning_ja, pos, tocfl_level, " +
  "reading_primary, reading_alt, meanings, level_step, " +
  "audio_path, source, entry_type";

/** 既定の言語(台湾華語)かどうか。古い列に中身があるのはこの言語だけ。 */
export function usesLegacyColumns(language: string): boolean {
  return language === DEFAULT_TARGET_LANGUAGE;
}
