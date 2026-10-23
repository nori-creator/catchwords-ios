/**
 * 学んでいる言語の**決め打ちを1箇所に集める**(指摘⑬ の下ごしらえ)。
 *
 * オーナー: 「英語を学ぶ台湾人向けの版」も作りたい。
 *
 * ## なぜ先に集めるのか
 * `"zh-TW"` という文字列が **42箇所**に直に書かれていた。言語をもう1つ
 * 増やすとき、この42箇所を1つずつ見つけて直すことになる。**見落としても
 * 型でもビルドでも落ちない** — 落ちるのは、英語版の利用者の画面に
 * 台湾華語の声が出たときだけ。
 *
 * ここは**値を変えない**。いまと同じ `"zh-TW"` を返すだけの入れ替えなので、
 * この回では見た目も動きも1つも変わらない。変わるのは「次に言語を足す人が
 * 見る場所が1つになる」こと。
 *
 * ## 役割ごとに分けて持つ — 同じ値でも混ぜない
 * いま `"zh-TW"` が使われている所は、実は**3種類**ある:
 *
 *   1. **学んでいる言語**   … 見出し語・カード生成・辞書の絞り込み
 *   2. **読み上げの言語**   … `SpeechSynthesisUtterance.lang` / TTS
 *   3. **地図の表示言語**   … 地名をどの言語で返してもらうか
 *
 * いまはたまたま3つとも `"zh-TW"` だが、**英語版では全部ばらける**
 * (学ぶ言語 = 英語 / 読み上げ = `en-US` / 地図 = 台湾の人が読む `zh-TW`)。
 * 1つの定数にまとめると、そのとき3つを解きほぐす作業が発生する。
 * 最初から別の名前で持つ。
 *
 * 外の世界に触れるものをここに入れないこと。
 */

/**
 * いま選べる学習言語。増えたらここに足す。
 *
 * **2026-08-25 に英語を足した**(オーナー要望「英語を学ぶ台湾人向けの版」)。
 * 足すのはこの1行だが、効くのはここだけではない — カードの項目
 * (`target-profile.ts` の `sections`)、級の目盛り(TOCFL / CEFR)、
 * 見出し語の受け入れ(`headwordOk`)、読み(注音・拼音 / IPA)、
 * 読み上げの言語が、**全部この値から引かれる**。
 * `if (lang === …)` を書き足す形にしなかったのはそのため。
 */
export const TARGET_LANGUAGES = ["zh-TW", "en", "ja"] as const;
export type TargetLanguage = (typeof TARGET_LANGUAGES)[number];

/**
 * **Web の画面で選べる**学習言語。
 *
 * 2026-10-01 に日本語(`"ja"`)をサーバ側の学習言語に足した。iOS 版が先に
 * 出すので、Web の選択肢にはまだ並べない(オーナー方針「iOS が先」)。
 * サーバ関数・カード生成・読み上げは `TARGET_LANGUAGES` を回すので
 * 日本語でも動く — 隠すのは**選ぶ入口だけ**。
 *
 * `TARGET_LANGUAGES` を画面で直に回すと、ここに足した日に Web の設定にも
 * 「日本語」が出てしまう。選ぶ入口はこちらを回すこと。
 */
export const WEB_TARGET_CHOICES = ["zh-TW", "en"] as const satisfies readonly TargetLanguage[];

/**
 * Web の選択肢に並べる学習言語。**いま選ばれている値は必ず残す。**
 *
 * iOS 版で日本語を選んだ人が Web の設定を開くと、`WEB_TARGET_CHOICES` だけでは
 * 選択が空に見え、別の項目を保存した拍子に学習言語まで書き換わりかねない。
 * 選べる入口は増やさず、その人の今の値だけは見える形で並べる。
 */
export function webTargetChoices(current?: string | null): TargetLanguage[] {
  const list: TargetLanguage[] = [...WEB_TARGET_CHOICES];
  const v = (current ?? "").trim();
  if ((TARGET_LANGUAGES as readonly string[]).includes(v) && !list.includes(v as TargetLanguage)) {
    list.push(v as TargetLanguage);
  }
  return list;
}

/** 既定の学習言語。 */
export const DEFAULT_TARGET_LANGUAGE: TargetLanguage = "zh-TW";

/** 知らない値が来たら既定に落とす。**黙って未知の言語で動かさない。** */
export function normalizeTargetLanguage(raw: string | null | undefined): TargetLanguage {
  const v = (raw ?? "").trim();
  return (TARGET_LANGUAGES as readonly string[]).includes(v)
    ? (v as TargetLanguage)
    : DEFAULT_TARGET_LANGUAGE;
}

/**
 * 読み上げに渡す BCP-47 のタグ。
 *
 * 学習言語と**同じとは限らない**。いまは一致しているが、名前を分けておく
 * ことで、英語版を足すときにここだけ見れば済む。
 */
export function speechLangOf(target: string = DEFAULT_TARGET_LANGUAGE): string {
  // **`normalizeTargetLanguage` をそのまま返さない。** 英語を足した日
  // (2026-08-25)まではたまたま一致していたが、`"en"` を読み上げに渡すと
  // 端末は地域を自分で決める — イギリスの声で読む端末が出る。
  // オーナー決定「アメリカ英語を既定」がここまで届くように、表で持つ。
  const SPEECH: Record<TargetLanguage, string> = {
    "zh-TW": DEFAULT_TARGET_LANGUAGE,
    en: "en-US",
    // 地域まで付ける。`ja` だけでも日本の声になる端末が多いが、
    // 英語で起きた「地域を端末任せにする」穴を最初から塞いでおく。
    ja: "ja-JP",
  };
  return SPEECH[normalizeTargetLanguage(target)];
}

/**
 * **聞き取り**(SpeechRecognition)に渡す言語のタグ。
 *
 * 読み上げのタグと**別物**。台湾華語の聞き取りは `cmn-Hant-TW` で、
 * `zh-TW` を渡すと端末によっては簡体字で結果を返す。
 * これも `"cmn-Hant-TW"` として2つの画面に直に書かれていた
 * (`PronunciationPanel` と `InputCatchSheet`)。英語を足した日から、
 * **英語を喋っているのに中国語として聞き取られる**状態になる。
 */
export function sttLangOf(target: string = DEFAULT_TARGET_LANGUAGE): string {
  const STT: Record<TargetLanguage, string> = {
    "zh-TW": "cmn-Hant-TW",
    en: "en-US",
    ja: "ja-JP",
  };
  return STT[normalizeTargetLanguage(target)];
}

/**
 * 地図に地名を返してもらう言語。
 *
 * **学習言語ではない。** 台湾で撮った地名は、日本語の学習者にも
 * 台湾の人にも `zh-TW` で返ってくるのが正しい(「Shilin Night Market」より
 * 「士林夜市」のほうが、その場所の名前として通じる)。
 * 学習言語が英語になっても、ここは付いていかない。
 */
/**
 * **中文で書かれた解説の言語。**
 *
 * 上の3つに続く4つ目の使われ方(2026-08-25、英語の種辞書を入れるときに出た)。
 * ECDICT の語釈は中文で、それを台湾の学習者に出すために正体字へ直す。
 * このとき `meanings` の鍵に入るのは**解説を書いた言語**であって、
 * 学習言語ではない — 英語版では「学習言語=en / 解説の言語=zh-TW」になる。
 * 同じ定数にすると、英語のカードの中文語釈が `en` の鍵に入る。
 */
export const CHINESE_EXPLANATION_LANGUAGE = "zh-TW";

export const MAP_DISPLAY_LANGUAGE = "zh-TW";
