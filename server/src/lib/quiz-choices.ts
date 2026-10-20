import type { UiLang } from "./i18n";

/**
 * 4択の選択肢を組む所。
 *
 * ## なぜ切り出したか
 * ここは「必ず4つ出す」という**数の約束**が要る。約束が破れても画面は
 * エラーを出さない — ボタンが3つ並ぶだけで、当たる確率が上がったことに
 * 誰も気づかない。サーバ関数の中に埋めたままでは試せないので、
 * 純粋な関数として出す。
 */

/**
 * 誤答が1つも作れないときの最後の受け皿(意味の側)。
 *
 * **4つある事に意味がある。** 出題語の意味がここのどれかと偶然一致すると
 * その1つは使えない。3つしか無いと、その瞬間に誤答が2つになり、
 * 選択肢が3つの問題が出る。4つあれば、1つ潰れても3つ残る。
 */
export const FALLBACK_MEANINGS: readonly string[] = [
  "別の物体",
  "場所の名前",
  "人物の役職",
  "時間の言い方",
];

/**
 * 受け皿を**読み手の言語ごと**に持つ（オーナー報告 2026-09-27「復習の4択に
 * 別の言語が混ざる」）。日本語の1組しか無かったので、英語で読む人が
 * 撮った語の少ないうちは、4択の3つが日本語になっていた。
 */
export const FALLBACK_MEANINGS_BY_LANG: Readonly<Record<UiLang, readonly string[]>> = {
  ja: FALLBACK_MEANINGS,
  en: ["another object", "a place name", "a job title", "a way to say a time"],
  "zh-TW": ["別的東西", "地方的名字", "職稱", "時間的說法"],
};

/**
 * 同じく、見出し語の側の受け皿。台湾で日常的に見る語を選ぶ
 * (誤答があからさまに場違いだと、消去法で当てられてしまう)。
 * こちらは**衝突が現実に起きる** — 林檎やバスを撮る学習者は普通にいる。
 */
export const FALLBACK_HEADWORDS: readonly string[] = ["蘋果", "公車", "雨傘", "便當"];

/** 受け皿の語の読み(4択に注音・拼音を出すため)。 */
export const FALLBACK_HEADWORD_READINGS: Readonly<
  Record<string, { zhuyin: string; pinyin: string }>
> = {
  蘋果: { zhuyin: "ㄆㄧㄥˊ ㄍㄨㄛˇ", pinyin: "píngguǒ" },
  公車: { zhuyin: "ㄍㄨㄥ ㄔㄜ", pinyin: "gōngchē" },
  雨傘: { zhuyin: "ㄩˇ ㄙㄢˇ", pinyin: "yǔsǎn" },
  便當: { zhuyin: "ㄅㄧㄢˋ ㄉㄤ", pinyin: "biàndāng" },
};

/** Fisher-Yates。元の配列は触らない。 */
export function shuffle<T>(arr: readonly T[]): T[] {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

/**
 * 誤答を `want` 個選ぶ。前の池ほど優先(その学習者の頭の中で実際に
 * 混ざる誤答から先に使う)。正解と同じ物、既に選んだ物は飛ばす。
 *
 * 最後の池に**空でない受け皿**を渡せば、池が全部空でも数は揃う。
 * 受け皿の大きさが `want + 1` 以上なら、正解と1つ衝突しても揃う
 * (証明: 受け皿を見る前に k 個選べていて、受け皿の大きさが F、
 *  うち1つが正解と同じ、d 個が既出だとすると d ≤ k なので
 *  k + (F - 1 - d) ≥ F - 1 ≥ want)。
 */
export function pickDistractors(
  correct: string,
  pools: ReadonlyArray<readonly string[]>,
  want = 3,
): string[] {
  const out: string[] = [];
  for (const pool of pools) {
    for (const cand of pool) {
      if (!cand || cand === correct || out.includes(cand)) continue;
      out.push(cand);
      if (out.length >= want) return out;
    }
  }
  return out;
}

/**
 * 正解を混ぜた選択肢の並びを返す。正解の位置は毎回変わる。
 * 返る数は `want + 1`(池が痩せていれば、それ未満になり得る —
 * 呼ぶ側は必ず受け皿を最後に渡すこと)。
 */
export function buildChoices(
  correct: string,
  pools: ReadonlyArray<readonly string[]>,
  want = 3,
): string[] {
  return shuffle([correct, ...pickDistractors(correct, pools, want)]);
}
