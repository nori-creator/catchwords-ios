import { DEFAULT_TARGET_LANGUAGE, normalizeTargetLanguage } from "./target-lang";
import { isTargetHeadword } from "./target-language";

/**
 * **学習言語で「見えるもの」を絞る**ときの条件。
 *
 * オーナー指示 2026-08-25:
 * >「学習言語によって、アルバムや図鑑に表示されるものをすべて区別して。
 * > 混ぜないで。いまあるものは学習言語が台湾華語だから、アプリの表示言語を
 * > 変えたときのみ言語を変更して、**学習言語を変更したらアルバムや図鑑に
 * > 表示されるものを全て変更して**」
 *
 * つまり2つの設定は別の物を決める:
 *
 * | 設定 | 決めるもの |
 * |---|---|
 * | 学習言語 | **どの語が見えるか**（アルバム・図鑑・単語帳・復習・ホーム） |
 * | 表示言語 | **解説が何語で書かれるか**（見える語は変わらない） |
 *
 * ## なぜ `null` を既定の言語として数えるのか
 * `words.language` は後から足した列で、**それ以前に保存された語は
 * 空のことがある**。空を「どの言語でもない」として扱うと、
 * 台湾華語を学んでいる人の図鑑から既存の語が丸ごと消える —
 * 一番やってはいけない壊し方(集めた物が消える画面)。
 *
 * 逆に空を「全部の言語」として扱うと、英語に切り替えた人の図鑑に
 * 台湾華語が混ざる — オーナーが「混ぜないで」と言っている物そのもの。
 *
 * だから**空は既定の言語(台湾華語)の行として数える**。実際そうなので
 * 嘘にならないし、どちらの側も壊れない。
 *
 * ## PostgREST に渡す形
 * 埋め込んだ `words` に掛けるので `.or(…, { referencedTable: "words" })`
 * と一緒に使う。文字列を組み立てるだけなので、ここは外の世界に触れない。
 */
export function wordLanguageFilter(targetLanguage: string | null | undefined): string {
  const lang = normalizeTargetLanguage(targetLanguage);
  // `,` が or の区切りなので、言語コードに `,` が混ざると条件が壊れる。
  // `normalizeTargetLanguage` が知っている値しか通さないので実際には
  // 起きないが、**通ってしまったときに黙って壊れない**ようにしておく。
  if (lang.includes(",") || lang.includes(")")) return `language.eq.${DEFAULT_TARGET_LANGUAGE}`;
  return lang === DEFAULT_TARGET_LANGUAGE
    ? `language.eq.${lang},language.is.null`
    : `language.eq.${lang}`;
}

/**
 * 取ってきた行を**同じ規則で**絞る。
 *
 * サーバの絞り込みが（列がまだ無い環境などで）効かなかったときの受け皿。
 * **DB と画面で違う規則を書かない**ためにここに置く — この作業場で
 * 何度も起きているのは「同じ判断が2箇所にあって片方だけ直る」事故。
 */
export function matchesTargetLanguage(
  wordLanguage: string | null | undefined,
  targetLanguage: string | null | undefined,
): boolean {
  const lang = normalizeTargetLanguage(targetLanguage);
  const raw = (wordLanguage ?? "").trim();
  if (!raw) return lang === DEFAULT_TARGET_LANGUAGE;
  return raw === lang;
}

/**
 * **見出し語の字が、学習言語の字か。**（オーナー報告 2026-10-02）
 *
 * 英語の図鑑に「ノート」が出て、復習では「拿鐵」の繁體中文の4択が
 * 3.5秒出てから英語の4択に替わった。どちらの行も `words.language` は
 * `'en'` — 保存の道が字を見ずに入れていた（`upsertWord` の関所で塞いだ）。
 * ところが**既に入った行**は言語の列だけ見ても見分けが付かない。
 * 見せる側でも見出し語の字を見る。
 *
 * 判定は保存の関所と同じ `isTargetHeadword` ただ1つ（正規表現を写さない）。
 * 見出し語が空の行は判定しない（材料が無いのに隠さない）。
 */
export function headwordMatchesTarget(
  headword: string | null | undefined,
  targetLanguage: string | null | undefined,
): boolean {
  const head = (headword ?? "").trim();
  if (!head) return true;
  return isTargetHeadword(head, normalizeTargetLanguage(targetLanguage));
}

/**
 * **その語を、この学習言語の一覧（図鑑・復習）に出してよいか。**
 * 言語の列（`matchesTargetLanguage`）と見出し語の字（`headwordMatchesTarget`）の両方。
 */
export function wordBelongsToTarget(
  word: { language?: string | null; headword?: string | null } | null | undefined,
  targetLanguage: string | null | undefined,
): boolean {
  if (!word) return false;
  return (
    matchesTargetLanguage(word.language, targetLanguage) &&
    headwordMatchesTarget(word.headword, targetLanguage)
  );
}
