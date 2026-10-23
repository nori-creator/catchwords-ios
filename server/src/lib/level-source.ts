import {
  LEVEL_OUT,
  parseLevelStep,
  type LevelIndex,
  type LevelScale,
  type LevelStep,
} from "./level-scale";

/**
 * その語の級を**どこから採るか**を決める唯一の場所。
 *
 * ## オーナー指摘 2026-08-27 ⑭
 * > 「単語の詳細の TOCFL や TOEFL のレベル、正しいのか検証して。
 * >  これらの検定の単語以外の単語も勝手にレベルが表示されてる気がする。
 * >  また TOCFL の外の単語の場合どのように分類表示するか考えて。」
 *
 * ## 気のせいではなかった
 * カードを作る指示文はこう書いてある:
 *
 *   `- level: TOCFL のレベル（TOCFL-1 / … / TOCFL-6 のいずれか）`
 *
 * **6つのどれかを選ばせている。**「この語は TOCFL に無い」と答える口が
 * どこにも無いので、検定の語彙表に載っていない語にも必ず級が付く。
 * `LEVEL_OUT`(級外)は目盛りにも段々の絵にも最初から在るのに、
 * **作る側にだけ無かった**。
 *
 * しかも本番の辞書には、級の分かっている語が
 * 英語 7,009 / 台湾華語 4,496 も入っている。カードを作るときに
 * そこを一度も見ずに AI に当てさせていた — 答えが手元にあるのに、
 * お金を払って当て推量を買っていたことになる。
 *
 * ## 順番
 * 1. **辞書にその語があり、級も入っている** → その級（`"dictionary"`）
 * 2. **辞書にその語はあるが、級が空** → **級外**（`"dictionary-out"`）
 *    検定の語彙表から作った辞書なので、載っているのに級が無い＝
 *    検定の範囲外、という意味になる
 * 3. **辞書に無い語** → AI の答えを読む（`"ai"`）。AI が級外と答えたら
 *    級外（`"ai-out"`）。読めない答えは**級外**に落とす（`"unknown-out"`）—
 *    分からないものに級を付けるのが、この指摘そのものだから
 *
 * ここには外の世界に触れるものを入れないこと。
 */

/** その級がどこから来たか。画面が出所を出せるようにしておく。 */
export type LevelSource = "dictionary" | "dictionary-out" | "ai" | "ai-out" | "unknown-out";

export type ResolveLevelInput = {
  /** その学習言語の目盛り（TOCFL / CEFR）。 */
  scale: LevelScale;
  /**
   * 辞書の行の級（`dictionary_entries.level_step`）。
   * **`undefined` = その語が辞書に無い**、`null` = 在るが級が空。
   * この2つを混ぜると、辞書の取りこぼしと本当の級外が同じ扱いになる。
   */
  dictStep?: number | null;
  /** AI が返した級（保存する形の文字列）。 */
  aiLevel?: string | null;
};

export type ResolvedLevel = {
  /** `words.level` に保存する文字列。 */
  stored: string;
  /** 読み返した段。級外は `"out"`。 */
  step: LevelStep;
  source: LevelSource;
};

function out(scale: LevelScale, source: LevelSource): ResolvedLevel {
  return { stored: scale.outStored, step: LEVEL_OUT, source };
}

export function resolveLevel(input: ResolveLevelInput): ResolvedLevel {
  const { scale, dictStep, aiLevel } = input;

  // 1〜2: 辞書にその語が在る。**そこが正**。
  if (dictStep !== undefined) {
    const step = parseLevelStep(dictStep);
    if (step != null && step !== LEVEL_OUT) {
      return { stored: scale.toStored(step as LevelIndex), step, source: "dictionary" };
    }
    return out(scale, "dictionary-out");
  }

  // 3: 辞書に無い語。AI の答えを読む。
  const step = parseLevelStep(aiLevel);
  if (step != null && step !== LEVEL_OUT) {
    return { stored: scale.toStored(step as LevelIndex), step, source: "ai" };
  }
  // AI が級外と答えた（`TOCFL-0` / `CEFR-0`）のと、
  // 読めない答え（空・`"不明"`）を分けて憶えておく。直す所が違う。
  return out(scale, step === LEVEL_OUT ? "ai-out" : "unknown-out");
}

/** 級外か（`source` の綴りを呼ぶ側に書かせない）。 */
export function isOutOfScale(resolved: ResolvedLevel): boolean {
  return resolved.step === LEVEL_OUT;
}
