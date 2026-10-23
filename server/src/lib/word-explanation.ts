import { looksWrongForReader } from "./note-language";
/**
 * 「その語の解説を、いま作り直す必要があるか」を決める唯一の場所。
 *
 * ## なぜ切り出したか — ここが最大の遅さと揺れの原因だった
 *
 * 解説は `words.extras` に載っていた。`words` は `(language, headword)` で
 * **全ユーザー共有の1行**。ところが解説は**読む人の言語と母語で中身が変わる**。
 * だから `StickerSheet.tsx` はこう書かざるを得なかった:
 *
 *     const wrongLanguage = (ex.explain_lang || "ja") !== uiLang;
 *     const wrongL1       = (ex.explain_l1   || "ja") !== nativeLang;
 *
 * 表示言語か母語が違う人が開くと、**開くたびに丸ごと作り直して上書き**する。
 * 日本語の人と韓国語の人が同じ語を持っていたら、互いに開くたび永久に作り直し
 * 合う — 遅く、高く、しかも解説が毎回揺れる。
 *
 * 解説を `word_explanations (word_id, explain_lang, l1)` に分けたので、
 * **もう作り直さなくてよい**。組み合わせが違えば別の行として並んで居られる。
 * 判断はここ1つに置く — 画面と server が別々に答えを持つと、server が
 * 「空だ」と言い続けて作り、画面が「埋まっている」と言い続ける止まらない
 * 生成になる(`card-sections.ts` で同じ形を一度踏んでいる)。
 *
 * 外の世界に触れるものをここに入れないこと。
 */

import { hasExtrasContent, type WordExtrasDTO } from "./extras";

/** 解説がどこから来たか。**画面に必ず出す。** */
export const EXPLANATION_SOURCES = ["seed", "verified", "ai"] as const;
export type ExplanationSource = (typeof EXPLANATION_SOURCES)[number];

/**
 * 解説を1つに決める鍵。
 *
 * **3つ揃いで1つ。** どれか1つでも違えば別の解説で、混ぜてはいけない。
 */
export type ExplanationKey = {
  /** 学ぶ言語ではなく、**解説を書く言語**(= 表示言語)。 */
  explainLang: string;
  /** 誰の母語向けか。発音のコツと語順の説明はここで変わる。 */
  l1: string;
};

/** 旧データの既定。`explain_lang` / `explain_l1` が空なら日本語話者向けの日本語。 */
export const LEGACY_KEY: ExplanationKey = { explainLang: "ja", l1: "ja" };

/**
 * 鍵を正規化する。空・null は旧データの既定に落とす。
 *
 * **黙って未知の値で動かさない** — 知らない言語のまま引くと、
 * 何にも当たらない鍵で毎回作り直すことになる(直したかった不具合そのもの)。
 */
export function explanationKey(
  explainLang: string | null | undefined,
  l1: string | null | undefined,
): ExplanationKey {
  return {
    explainLang: (explainLang ?? "").trim() || LEGACY_KEY.explainLang,
    l1: (l1 ?? "").trim() || LEGACY_KEY.l1,
  };
}

/** 同じ解説を指しているか。 */
export function sameKey(a: ExplanationKey, b: ExplanationKey): boolean {
  return a.explainLang === b.explainLang && a.l1 === b.l1;
}

/** DB から届いた1行(必要な所だけ)。 */
export type ExplanationRow = {
  explain_lang: string;
  l1: string;
  meaning: string;
  example_translation?: string | null;
  extras: WordExtrasDTO | null;
  source?: string | null;
};

/**
 * 並んでいる解説から、その人に出す1つを選ぶ。
 *
 * 1. **ぴったり合う物**(言語も母語も同じ)
 * 2. 無ければ**言語だけ合う物** — 母語が違っても、読める言語で書いてある
 *    ほうが読めない言語よりましだから。発音のコツだけが他の母語向けになる。
 * 3. それも無ければ `null`(呼ぶ側が作る)
 *
 * **言語の合わない解説には落ちない。** 読めない言語の解説を出すのは、
 * 何も出さないより悪い(オーナー指摘「量詞の説明が台湾華語になってる」と
 * 同じ種類の間違い)。
 */
export function pickExplanation(
  rows: readonly ExplanationRow[] | null | undefined,
  want: ExplanationKey,
): ExplanationRow | null {
  if (!rows || rows.length === 0) return null;
  const exact = rows.find((r) => r.explain_lang === want.explainLang && r.l1 === want.l1);
  if (exact) return exact;
  // 言語だけ合う物。**人が確かめた物を先に。** 次に中身の多い物。
  const sameLang = rows
    .filter((r) => r.explain_lang === want.explainLang)
    .sort((a, b) => sourceRank(b.source) - sourceRank(a.source));
  return sameLang[0] ?? null;
}

function sourceRank(source: string | null | undefined): number {
  return source === "verified" ? 2 : source === "seed" ? 1 : 0;
}

/**
 * その解説を**作る必要があるか**。
 *
 * ## ここが「開くたびに作り直す」を止める所
 *
 * 前は「言語が違う / 母語が違う」を作り直す理由にしていた。分けた今は、
 * **その組み合わせの解説が無いときだけ**作ればよい。あれば何度開いても
 * そのまま出す。
 *
 * 中身が薄いときも作る — 途中で失敗して半分だけ入った解説を、
 * 「在る」と数えて永久に半端なまま出し続けない。
 */
export function needsGeneration(picked: ExplanationRow | null, want: ExplanationKey): boolean {
  if (!picked) return true;
  // 言語だけ合う物で間に合わせている = その人向けの解説はまだ無い。
  if (!sameKey(explanationKey(picked.explain_lang, picked.l1), want)) return true;
  if (!(picked.meaning ?? "").trim()) return true;
  return !hasExtrasContent(picked.extras);
}

/**
 * 共有の列(`words.meaning_ja` など)を**書きに行ってよいか**。
 *
 * ## 二度間違えている所
 * `words` は全員で1行を見ている。表示言語を切り替えただけで
 * `meaning_ja` / `example_sentence` / `reading_zhuyin` まで送っていたので、
 * **設定を触っただけで他人のカードごと保存済みの意味が書き換わって**いた。
 *
 * 書いてよいのは、共有の列が**実際に欠けているとき**だけ。
 * 「言語が変わったか」ではなく「共有の列が空か」で決める — 知りたいのは
 * 後者で、それは共有の列を見れば分かる。
 */
export function shouldWriteSharedColumns(shared: {
  meaning?: string | null;
  reading?: string | null;
  example?: string | null;
}): boolean {
  const filled = (v: string | null | undefined) => !!(v ?? "").trim();
  return !filled(shared.meaning) || !filled(shared.reading) || !filled(shared.example);
}

/**
 * 画面に出す「意味・例文訳・解説」を決める。
 *
 * ## なぜ関数にしたか
 * 画面では `explanation?.meaning || word.meaning_ja` のような並びになる。
 * 3項目ぶん並ぶと、**どれか1つだけ落とし方を間違えても誰も気づかない**
 * (`??` と `||` を取り違えると、空文字のときに落ちない／落ちすぎる)。
 * しかも `StickerSheet` の写真の場面は**画面の下半分しか撮れていない**ので、
 * 意味は絵でも確かめられない。だから試験で押さえる。
 *
 * ## 落とし方
 * - 意味      … 共有キャッシュが**空でなければ**そちら。空なら古い列
 * - 例文の訳  … 同じ
 * - 解説      … キャッシュに**行が在れば**そちら(中身が空でも、それが
 *                その人向けの答え)。行が無いときだけ古い列
 *
 * 意味と解説で落とし方が違うのは、意味は「空なら意味を成さない」が、
 * 解説は「空のまま正しい」ことがあるから(裏で1項目ずつ埋めている途中)。
 *
 * ## 読む人の言語で書かれていない解説は出さない
 * オーナー報告 2026-08-26(絵つき):
 * > 「学習言語英語、表示言語台灣華語なのに、言語が混ざってる」
 *
 * 届いた絵では、例文の訳は繁体字なのに**追加例文の訳だけ日本語**だった。
 * その人向けの解説がまだ出来ていない間、古い行(日本語で書かれたもの)を
 * そのまま出していたため。
 *
 * 古い行には `explain_lang` の目印が押してある。**読む人の言語と違うなら
 * 出さない** — 裏の生成が届けば正しい言語で埋まる。
 * 「間違った言語で読ませる」より「まだ無い」と描くほうが正しい
 * (`readerLanguage` を渡さなければ、この選り分けはしない)。
 */
export function resolveDisplayWord<E extends { explain_lang?: string } | null | undefined>(
  shared: {
    meaning?: string | null;
    exampleTranslation?: string | null;
    /** 例文（訳がその写しになっていないかを見る）。 */
    exampleSentence?: string | null;
    extras: E;
  },
  explanation: {
    meaning?: string | null;
    example_translation?: string | null;
    extras: E;
  } | null,
  /**
   * 読む人の言語。渡すと、**その言語で書かれていない古い解説を出さない**。
   * 渡さなければ今までどおり(呼ぶ側が言語を持っていない場面のため)。
   */
  readerLanguage?: string | null,
): { meaning: string; exampleTranslation: string | null; extras: E } {
  const cachedMeaning = (explanation?.meaning ?? "").trim();
  const cachedTranslation = (explanation?.example_translation ?? "").trim();
  // **行が在れば中身が空でもそちら。** 裏で埋めている途中の解説を、
  // 古い言語の解説で置き換えてしまわない。
  const extras = explanation ? explanation.extras : shared.extras;
  const want = (readerLanguage ?? "").trim();
  const has = (extras?.explain_lang ?? "").trim();
  // 目印が無い解説は古すぎて言語が分からない。**分からないものは出す** —
  // 落とすには根拠が要る(この app の他の判定と同じ)。
  const wrongLanguage = !!want && !!has && has !== want;
  return {
    // 意味も読む人の言語の物だけ（2026-09-29 の言語の検査: その人向けの解説がまだ無い間、
    // 共有の語の日本語の意味が英語・台湾華語の人に出ていた）。漢字だけの和文は落とさない。
    meaning:
      [cachedMeaning, (shared.meaning ?? "").trim()].find(
        (x) => !!x && !(want && looksWrongForReader(x, want, null, { hanOnlyOk: true })),
      ) ?? "",
    // **訳は読む人の言語の物だけ**（2026-09-29「例文の訳に中文が混ざってる」）。その人向けの
    // 解説の訳 → 共有の語の訳の順に、読む人の言語で書かれた方を採る。どちらも違えば出さない。
    exampleTranslation:
      [cachedTranslation, (shared.exampleTranslation ?? "").trim()].find(
        (x) => !!x && !(want && looksWrongForReader(x, want, shared.exampleSentence)),
      ) ?? null,
    extras: wrongLanguage ? (null as E) : extras,
  };
}

/**
 * 読む人の言語の意味を**どの行に書くか**（オーナー報告 2026-10-02、英語と繁體中文の両方
 * 「図鑑のスライドに意味が出ない・復習の問いが『Which one means “グラタンマカロニ”?』」）。
 *
 * その人の言語の解説の行が無い語、在っても意味が別の言語（共有の `meaning_ja` を写した物）
 * の語は、図鑑にも復習にも意味が出せない。足りない意味だけを埋めるとき、
 *
 * 1. **ぴったり合う行**（言語も母語も同じ）があれば、その行の意味だけを書き換える
 * 2. 無ければ**言語だけ合う行**（画面が出している方 — 人が確かめた物を先に）
 * 3. その言語の行が1つも無ければ、新しく行を作る
 *
 * **人が確かめた行（`verified`）には書かない**（読むときだけ使う）。解説（extras）は
 * 触らない — 意味を埋めるだけで、別の行の解説を空で上書きしない。
 */
export function readerMeaningWriteTarget(
  rows: readonly ExplanationRow[] | null | undefined,
  want: ExplanationKey,
): { kind: "update"; row: ExplanationRow } | { kind: "insert" } | { kind: "skip" } {
  const sameLang = (rows ?? []).filter((r) => r.explain_lang === want.explainLang);
  if (sameLang.length === 0) return { kind: "insert" };
  const picked = pickExplanation(sameLang, want);
  if (!picked || picked.source === "verified") return { kind: "skip" };
  return { kind: "update", row: picked };
}

/**
 * 復習の札で、**その人向けの解説を作りに行くか**（単語の詳細と同じ生成の道を使う）。
 *
 * - その人向けの解説（言語も母語も合う行）に中身があれば作らない（`needsGeneration`）
 * - 共有の意味が読む人の言語で書かれていれば作らない — 共有の解説も同じ日に同じ言語で
 *   作られているので、今まで通りそれを出す（**日本語の表示で日本語の語は何も変わらない**）
 * - 解説の問い合わせがまだ返っていない・表がまだ無い環境では作らない（作っても置けない）
 */
export function reviewNeedsReaderExplanation(opts: {
  /** 解説の問い合わせが返ったか。 */
  loaded: boolean;
  /** 表がまだ無い（移行待ち）。 */
  unavailable: boolean;
  picked: ExplanationRow | null;
  want: ExplanationKey;
  /** 共有の意味（`words.meaning_ja`）。 */
  sharedMeaning: string | null | undefined;
}): boolean {
  if (!opts.loaded || opts.unavailable) return false;
  if (!needsGeneration(opts.picked, opts.want)) return false;
  const shared = (opts.sharedMeaning ?? "").trim();
  const sharedFits =
    !!shared && !looksWrongForReader(shared, opts.want.explainLang, null, { hanOnlyOk: true });
  return !sharedFits;
}
