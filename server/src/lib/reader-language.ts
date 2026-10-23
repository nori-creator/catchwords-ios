import { L1_ORDER, l1ChoicesFor, type L1Code } from "./l1";
import { normalizeTargetLanguage } from "./target-lang";

/**
 * **読む人の言語を1つに統合する。**
 *
 * オーナー指示 2026-08-25:
 * > 「母語と表示言語を統合して、日本語、英語、台湾華語にして」
 *
 * これまで設定には2つ在った:
 *
 * - `ui_language` … 画面の文字と、AI が解説を書く言語
 * - `native_language` … 発音のコツ・添削で「どこで転ぶか」を決める母語
 *
 * ほとんどの人にとってこの2つは**同じ物**で、別々に選ばせる理由が無い。
 * `L1_ORDER` と `UI_LANGS` は既に同じ3つ(`ja` / `en` / `zh-TW`)なので、
 * 選択肢の集合も揃っている。
 *
 * ## 1つだけ揃わない場合がある
 * 表示言語に**学習している言語そのもの**を選ぶことはできてしまう
 * (英語を学びながら解説も英語で読む)。そのとき母語を「英語」と
 * 見なすと、「英語話者が英語のここで転ぶ」という**成り立たない指示**が
 * プロンプトに入る。`l1ChoicesFor` が選択肢から学習言語を外しているのは
 * まさにこれを避けるため。
 *
 * だから統合しても、**その1点だけは別に決める**:
 *
 * 1. 表示言語が学習言語と違う → 表示言語がそのまま母語
 * 2. 同じ → 前に保存されていた母語(学習言語と違うなら)
 * 3. それも無い → その学習言語で選べる先頭
 *
 * DB の `native_language` の列は**残す**(追記のみの決めごと)。
 * 設定からは消えるが、2. の手掛かりとして読み続ける。
 */
export function readerL1(input: {
  /** 統合後の設定。画面の文字・解説の言語。 */
  uiLanguage: string | null | undefined;
  /** 統合前に保存されていた母語。まだ読む。 */
  nativeLanguage?: string | null;
  /** 学習している言語。 */
  targetLanguage: string | null | undefined;
}): L1Code {
  const target = normalizeTargetLanguage(input.targetLanguage);
  const choices = l1ChoicesFor(target);
  const ui = (input.uiLanguage ?? "").trim() as L1Code;
  if (choices.includes(ui)) return ui;
  // 表示言語が学習言語と同じ(または知らない値)のとき。
  const native = (input.nativeLanguage ?? "").trim() as L1Code;
  if (choices.includes(native)) return native;
  return choices[0] ?? L1_ORDER[0];
}
