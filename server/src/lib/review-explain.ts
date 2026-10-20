import { keepReaderLanguage } from "./meaning-language";
import { normalizeExtras, refineUsageChunks, type ChunkPart } from "./extras";
import { readerMeaning } from "./note-language";
import { shortMeaning } from "./meaning-rule";
import type { UiLang } from "./i18n";

/**
 * 復習の答え合わせに出す解説を組む所（外の世界に触れない）。
 *
 * ## なぜ server の外に出したか（オーナー報告 2026-10-02、英語と繁體中文の両方）
 * > 表示言語を英語にすると、答え合わせの「よく使う形」「一緒に覚える語」「量詞」に
 * > 訳が1つも出ない。日本語の表示なら出る。
 *
 * server は共有の `words.extras`（最初に作った人の言語）から組んで、読む人の言語で
 * ない訳を落としていた — 日本語で作られた語を英語・繁體中文で読む人には、訳が全部
 * 落ちる。単語の詳細は**その人向けの解説**（`word_explanations`）を出しているので、
 * 復習も同じ解説から組み直したい。それは画面の側で届くので、組む関数を両方から
 * 呼べる所に置いた。
 */

/** 答え合わせに出す解説(スピーキングで使える塊を優先して並べる)。 */
export type ReviewExplain = {
  /** ネイティブがよく使う型。parts は品詞つきなので色分けして見せる。 */
  chunks: Array<{ parts: ChunkPart[]; ja: string }>;
  /** 一緒に/近い意味で使う語。 */
  related: Array<{ word: string; kind: "syn" | "ant" | "rel"; note: string }>;
  /** 量詞(名詞のときだけ)。 */
  measures: Array<{ word: string; note: string }>;
  /** 知っておくと得な一言。 */
  note: string;
};

/**
 * 答え合わせで見せる解説一式。
 *
 * 復習の目的は「その場で口から出せるようになる」ことなので、辞書的な説明では
 * なく**そのまま言える塊**を先に出す:
 *  - chunks   : ネイティブがよく使う型(品詞で色分けして見せる)
 *  - related  : 一緒に/近い意味で使う語
 *  - measures : 量詞(名詞のときだけ)
 *  - note     : 知っておくと得な一言
 * 量は絞る — 4択の答え合わせは一瞬で読めることが最優先。
 */
export function explainOf(
  rawExtras: unknown,
  headword: string,
  language?: string | null,
  /**
   * 読み手の言語。**合わない訳・注記は落とす**（オーナー報告 2026-09-27
   * 「解説に別の言語が混ざる」）。表示言語を変える前に作った語は、
   * 訳と注記が前の言語のまま残っている。
   */
  reader?: UiLang,
): ReviewExplain | null {
  const ex = normalizeExtras(rawExtras);
  if (!ex) return null;
  const fit = (s: string | null | undefined) =>
    reader ? keepReaderLanguage(s, reader) : (s ?? "");
  // 量詞は measures の行で読むので、そこと重なるだけの型は落とす。
  const chunks = refineUsageChunks(ex.usage_chunks, ex.measure_words, headword, language)
    .filter((c) => (c.parts?.length ?? 0) > 0)
    .slice(0, 3)
    .map((c) => ({ parts: c.parts, ja: fit(c.ja) }));
  const related = (ex.related_words ?? [])
    .filter((r) => !!r.word?.trim())
    .slice(0, 4)
    .map((r) => ({ word: r.word, kind: r.kind, note: fit(r.note) }));
  const measures = (ex.measure_words ?? [])
    .filter((m) => !!m.word?.trim())
    .slice(0, 2)
    .map((m) => ({ word: m.word, note: fit(m.note) }));
  const note = fit((ex.taiwan_note || ex.usage_context || "").trim());
  if (!chunks.length && !related.length && !measures.length && !note) return null;
  return { chunks, related, measures, note };
}

/**
 * 答え合わせに出す解説を**1つに決める**。
 *
 * その人向けの解説（単語の詳細と同じ行）が届いていて中身があれば、そちらから組む。
 * 無ければ server が共有の解説から組んだ物（今まで通り。日本語の表示で日本語の語は
 * 何も変わらない）。
 */
export function pickReviewExplain(
  server: ReviewExplain | null | undefined,
  reader: ReviewExplain | null | undefined,
): ReviewExplain | null {
  return reader ?? server ?? null;
}

/**
 * 4択の問いの「」に入れる意味を決める（オーナー報告 2026-10-02、絵つき
 * 「Which one means “グラタンマカロニ”?」— 英語・繁體中文の表示で日本語の意味が出ていた）。
 *
 * 1. 共有の意味（`meaning_ja`）が読む人の言語で書かれていれば、**そのまま**
 *    （日本語の表示で日本語の語は今と1字も変わらない）
 * 2. 違えば、その人向けの解説の意味（単語の詳細と同じ行 → 図鑑と同じ覚え置き）
 * 3. どれも無ければ "" — 呼ぶ側は別の言語の意味を出さず、写真で問う
 *
 * 2 は長い説明文で返ることがあるので、語の長さに縮める（`shortMeaning`、図鑑と同じ）。
 * 2 で**見出し語そのものを含む意味は使わない** — 繁體中文で台湾華語を学ぶ人には、意味が
 * 「筆記本」のように答えそのものになることがある（問いが答えを言ってしまう）。
 */
export function quizPromptMeaning(opts: {
  shared: string | null | undefined;
  /** 答えの語。これを含む意味は 2 で使わない。 */
  headword?: string | null;
  /** その人向けの解説の意味（`word_explanations`）。 */
  explanation?: string | null;
  /** 図鑑と同じ覚え置き（`reader-meanings.ts`）。 */
  cached?: string | null;
  lang: UiLang;
}): string {
  const shared = (opts.shared ?? "").trim();
  // 共有の意味も**語の長さに**（2026-10-05 オーナー報告: 説明文の意味が4択の問いに2行で出た）。
  // 短い意味は1字も変わらない。
  if (shared && readerMeaning(shared, opts.lang).trim()) return shortMeaning(shared);
  const head = (opts.headword ?? "").trim();
  for (const m of [opts.explanation, opts.cached]) {
    const fit = shortMeaning(readerMeaning((m ?? "").trim(), opts.lang));
    if (fit && !(head && fit.includes(head))) return fit;
  }
  return "";
}
