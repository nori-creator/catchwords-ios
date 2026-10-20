import { normalizeCategory, shareCategoryWithinGroups } from "./category";
import { applyObjectLabels, finalizeNameRegisters } from "./candidate-register";
import { alignRowMeanings, ensureBasicLevel, rowTagOf } from "./basic-level";
import { fitSuggestionsToReader } from "./first-catch-meaning";
import { shortMeaning } from "./meaning-rule";
import { readerText } from "./note-language";
import { detectQueryLang } from "./text-query-lang";
import { DEFAULT_TARGET_LANGUAGE } from "./target-lang";
import type { UiLang } from "./i18n";

/** 写真の候補1つ（`suggestWords` の生成の形のうち、ここで読む欄）。 */
export type PhotoSuggestion = {
  headword: string;
  meaning_ja: string;
  reading_zhuyin?: string;
  pinyin?: string;
  distinction?: string;
  category_key?: string;
  register?: string | null;
  label?: string | null;
  group?: number | null;
};

/** 読みを検める関数（`tw-reading.server.ts` の `correctTaiwanReading`。試験では素通しを渡す）。 */
export type ReadingCheck = <T extends { pinyin?: string; reading_zhuyin?: string }>(
  language: string,
  headword: string,
  item: T,
) => T;

/**
 * **写真の候補を、画面に出す順・形にする**（本番の `suggestWords` と「固定の写真で試す」で同じ。学習言語の語だけに
 * した後 — `keepTargetHeadwords` — に呼ぶ）。AI は呼ばない。
 *
 * 1. 全部の候補に印を付け、物ごとに 一般的 → 口語 → より詳しい → 学術的 → 固有名詞 に並べる（`finalizeNameRegisters`）。
 * 2. 物の1つ目は基本の名詞（波斯菊 → 花、草莓蛋糕 → 蛋糕。`ensureBasicLevel`、2026-10-15）。
 * 3. 意味は読む人の言語・語の長さに。読みを検め、分類は見出し語の規則で直し、同じ物の別の呼び方から借りる。
 * 4. 表の基本の語の意味は、その語の物の意味だけ（貓 に「犬」と返ってきても「猫」。`alignRowMeanings`、2026-10-15）。
 * 5. タグ（`object_label`）は物の1つ目の候補の本当の意味の言い方。1つ目が表の基本の語なら表の名前（猫 / cat / 貓。
 *    `applyObjectLabels` + `rowTagOf`）。**細かい語の意味は書き換えない。**
 */
export function finishPhotoCandidates<T extends PhotoSuggestion>(
  usable: readonly T[],
  reader: UiLang,
  targetLanguage: string,
  correctReading: ReadingCheck,
) {
  const basic = ensureBasicLevel(finalizeNameRegisters(usable), targetLanguage, reader);
  const fitted = fitSuggestionsToReader(basic, reader, targetLanguage).map((s) => ({
    // 候補の読みも検める（`tw-reading.server.ts`）。
    ...correctReading(targetLanguage, s.headword, s),
    // 候補の意味も語の長さに（R17「湯咖哩の英語の単語の候補…が長すぎる」）。
    meaning_ja: shortMeaning(s.meaning_ja),
    category_key: normalizeCategory(s.headword, s.category_key),
  }));
  // 基本の語の意味を表で確かめる（別の物の名前・細かい名前・空 → 表の名前。細かい語は別の物の名前なら空）。
  const aligned = alignRowMeanings(fitted, reader, targetLanguage);
  // 同じ物の別の呼び方から分類を借りる（波斯菊が "other" でも、同じ物の 花 が flower なら flower）。
  const categorized = shareCategoryWithinGroups(aligned);
  return applyObjectLabels(
    categorized,
    (text, common) => isReaderTagText(text, reader, common.headword),
    (common) => rowTagOf(common.headword, reader, targetLanguage),
  );
}

const HAN_ONLY = /^\p{Script=Han}+$/u;

/**
 * タグ（表示言語の名前）として出してよい言葉か。読む人の言語の言葉で、見出し語の写しでない物。
 * ただし日本語で読む人には、見出し語と同じ字でも日本語の語なら出す（花・花瓶・椅子 — 台湾の字にしか無い形
 * 「貓」「腳」を含む物は写し）。前はこれも写しとして落とし、タグが空になっていた（画面は見出し語を出していた）。
 */
export function isReaderTagText(text: string, reader: UiLang, headword: string): boolean {
  if (readerText(text, reader, headword)) return true;
  const t = (text ?? "").trim();
  return (
    reader === "ja" &&
    !!t &&
    t === (headword ?? "").trim() &&
    HAN_ONLY.test(t) &&
    detectQueryLang(t, DEFAULT_TARGET_LANGUAGE) !== "target"
  );
}
