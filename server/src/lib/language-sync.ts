import { isExplainLang } from "./explain-languages";
import { isUiLang } from "./i18n";

/**
 * **一度選んだ言語を、あとから勝手に戻さない。**
 *
 * オーナー報告 2026-08-26（2度目）:
 * > 「学習言語英語、表示言語台湾華語にしてるのに、設定のページに行ったら、
 * >  設定の画面が学習言語台湾華語、表示言語日本語になってる。
 * >  **一度設定を保存したらその後キープして。**」
 *
 * ## これまでの直し方が足りなかった理由
 * 1度目は「置き場所の行（`partial`）で上書きしない」「言語だけ単独で保存する」
 * の2つを直した。どちらも正しいが、どちらも **サーバに正しい値が入っている
 * こと** を前提にしている。実際にはサーバ側の1列が値を撥ねているなど、
 * こちらから見えない理由で保存が届かないことがあり、そのときは
 * 「画面を開く → サーバの古い値を読む → 端末の写しごと戻る」が起きる。
 *
 * ## だから端末の写しを正とする
 * その人が選んだ事実が残っているのは **端末** のほう。サーバの値は
 * 持ち歩くための控えにすぎない（写真の見せ方や表記の設定と同じ扱い）。
 *
 * - 端末に選択が無い … サーバの値を使う（初めてその端末で開いた人）
 * - 端末に選択が在る … **端末が勝つ**。そのうえでサーバへ書き戻して揃える
 *
 * 書き戻すので、放っておいても2つは同じ値へ寄っていく。
 * 別の端末で選び直した人は、その端末が最後に選んだ値を持ち歩く
 * （最後に選んだ端末が勝つ）。
 */

export type LanguageReconcile = {
  /** 画面と端末で使う値。 */
  value: string;
  /** サーバの値がこれと違うので、書き戻しが要るか。 */
  pushToServer: boolean;
};

/**
 * 端末の選択とサーバの値を突き合わせる。
 *
 * @param stored 端末に憶えている値。**選んだことが無ければ `null`**
 *   （空文字も「無い」として扱う — 消えかけた値で上書きしない）
 * @param server プロフィールの値。読めなかったときは `null`
 * @param fallback どちらも無いときの既定
 */
export function reconcileLanguage(input: {
  stored: string | null | undefined;
  server: string | null | undefined;
  fallback: string;
}): LanguageReconcile {
  const stored = (input.stored ?? "").trim();
  const server = (input.server ?? "").trim();

  // まだ一度も選んでいない端末。サーバの値をそのまま受ける。
  if (!stored) {
    return { value: server || input.fallback, pushToServer: false };
  }
  // 選んである。**端末が勝つ。** 違っていればサーバへ書き戻す。
  return { value: stored, pushToServer: server !== stored };
}

/**
 * **表示言語の突き合わせ。** `reconcileLanguage` に1つだけ例外を足した物。
 *
 * サーバの値が **Web の画面に無い表示言語**（スペイン語・韓国語・ベトナム語 — iOS で選べる。
 * `explain-languages.ts`）なら、**サーバが勝ち、書き戻さない。** Web はその言語で画面を描けないので
 * 英語で描くが（`normalizeUiLang`）、端末の写しは Web の言語しか持てない。端末を勝たせると、
 * iOS で選んだスペイン語が Web を開いただけで日本語・英語に塗り替わる（その人の解説も
 * 塗り替わった言語で作られる）。Web の設定で言語を選び直したときだけ変わる（設定の保存）。
 */
export function reconcileUiLanguage(input: {
  stored: string | null | undefined;
  server: string | null | undefined;
  fallback: string;
}): LanguageReconcile {
  const server = (input.server ?? "").trim();
  if (isExplainLang(server) && !isUiLang(server)) return { value: server, pushToServer: false };
  return reconcileLanguage(input);
}
