import { normalizeTargetLanguage } from "./target-lang";

/**
 * **その文がその学習言語で書かれているか。**
 *
 * オーナー報告 2026-08-26（絵つき）:
 * > 「学習言語英語なのに単語の詳細の例文が台湾華語で表示される。
 * >  学習言語しか表示しないようにして。」
 *
 * 届いた絵では `ceiling` の例文が
 * 「這間咖啡廳的 ceiling 很高，感覺很舒服。」だった。英語の語を
 * 中国語の文に埋め込んだもので、**英語の例文ではない**。
 * 学習言語の写しが既定へ戻る隙間に作られたカードがこうなる。
 *
 * ## なぜ画面の側で落とすのか
 * 保存された文をこちらで訳し直すことはできないし、オーナーは
 * Supabase に直接触れないので行を消す手立ても無い。
 * **間違った例文を出し続けるより、出さないほうがいい** —
 * 空いた節は裏の生成（`auto-fill.ts`）が作り直しに来る。
 *
 * ## 判定は文字の種類だけで決める
 * 言語判定の道具を持ち込まない。この app が扱う2言語は使う文字が
 * 重ならないので、それで足りる:
 *
 * - 台湾華語の文 … 漢字を含む
 * - 英語の文 … ラテン文字を含み、**漢字を含まない**
 *
 * 固有名詞が混ざる文（「Jay Chou can play the piano...」）は
 * 漢字を含まないので英語として通る。逆に中国語の文に英単語が1つ
 * 混ざっていても、漢字が在るので英語としては通らない。
 */

const HAN = /[一-鿿㐀-䶿]/;
const LATIN = /[A-Za-z]/;
/** かな。日本語の文を「中国語の文」として通さないための番人。 */
const KANA = /[぀-ヿ]/;

/**
 * その文をその学習言語の文として出してよいか。
 *
 * **判定できないものは通す。** 空文字・記号だけ・数字だけの文を
 * 落とすと、正しい中身まで消える。落とすのは「別の言語だと
 * はっきり分かる」ときだけ。
 */
export function looksLikeTargetLanguage(
  text: string | null | undefined,
  targetLanguage: string | null | undefined,
): boolean {
  const s = (text ?? "").trim();
  if (!s) return true;
  const lang = normalizeTargetLanguage(targetLanguage);
  const han = HAN.test(s);
  const latin = LATIN.test(s);

  if (lang === "ja") {
    // 日本語(2026-10-01)。**かなが在れば日本語の文。** 日本語の文はほぼ必ず
    // 助詞・活用語尾のかなを含む。漢字だけのまとまった文は中国語の写しとみなす
    // (短い物は名詞句のことがあるので通す)。ハングルが在れば日本語ではない。
    if (/[가-힯]/.test(s)) return false;
    if (KANA.test(s)) return true;
    if (han) return s.replace(/[^一-鿿㐀-䶿々]/g, "").length < 5;
    return !latin;
  }
  if (lang === "en") {
    // 漢字が在れば英語の文ではない。ラテン文字が1つも無くても同じ。
    if (han) return false;
    if (KANA.test(s)) return false;
    return latin || !/[^\W\d_]/u.test(s);
  }
  // 台湾華語。**かなを先に見る** — 「この部屋の天井は高いです」は
  // 漢字を含むが日本語なので、漢字の有無だけで見ると通ってしまう。
  if (KANA.test(s)) return false;
  if (han) return true;
  // 漢字もかなも無く、ラテン文字だけの文は中国語ではない。
  return !latin;
}
