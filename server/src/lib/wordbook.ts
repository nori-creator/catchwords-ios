/**
 * 単語帳の取り込み — 写真から読んだ語を、入れられる形に整える。
 *
 * オーナー:
 * > 「単語帳の取り込みは**単語帳を写真撮ったら、そこにある単語のカードを
 * >  一括で作成**でき、復習も**図鑑の単語とは別に、単語帳を選択すると
 * >  単語帳で取り込んだものを SRS で復習**できるように。」
 *
 * ## 図鑑に混ぜない
 * 図鑑は「街で出会って**自分で撮った**物」の記録という約束で作ってある。
 * 単語帳の語には写真も場所も無いので、混ぜると図鑑の意味が変わり、
 * 絵の無い札が並ぶ。復習側の**本棚**として別に持つ(移行の注釈も参照)。
 *
 * ## ここが受け持つのは「整える」ことだけ
 * AI は同じ語を2回返すし、記号だけの行も返すし、1ページに200語あると
 * 200語返してくる。**そのまま入れると、1冊で1日の復習が埋まる。**
 * 整えるところを純粋な関数にして、境目をテストで押さえる。
 */

/** 写真から読み取った1語。 */
export type WordbookEntryDraft = {
  headword: string;
  reading_zhuyin?: string | null;
  pinyin?: string | null;
  meaning_ja?: string | null;
};

/** 1枚の写真から取り込む語数の上限。 */
export const MAX_ENTRIES_PER_PHOTO = 60;
/** 単語帳の名前の長さの上限。 */
export const MAX_TITLE_CHARS = 40;

import { isTargetHeadword } from "./target-language";

/** 漢字が1文字も無い行は語ではない(ページ番号・記号・欧文の見出し)。 */
const HAS_HAN = /[㐀-䶿一-鿿]/;

/**
 * その行を語として通すか。
 *
 * 台湾華語(と、学習言語を渡さない古い呼び出し)は**いままでどおり漢字の有無**で見る。
 * 英語・日本語の単語帳(2026-10-01、単語帳も学習言語に付いていくようにした)は、
 * その言語の見出し語の規則で見る — 「漢字が無い」で落とすと、英単語も
 * 「りんご」「バス」も1つも入らない。
 */
function isEntryWord(headword: string, language?: string | null): boolean {
  if (!language || language.startsWith("zh")) return HAS_HAN.test(headword);
  return isTargetHeadword(headword, language);
}

function trim(s: string | null | undefined): string {
  return (s ?? "").replace(/\s+/g, " ").trim();
}

function clean(s: string | null | undefined): string | null {
  const v = trim(s);
  return v ? v : null;
}

/**
 * 取り込む語を整える。
 *
 * - 前後の空白と連続空白を潰す
 * - **漢字を含まない行は捨てる**(ページ番号や記号だけの行が混ざる)
 * - 同じ見出しは最初の1つだけ残す。**あとから来た方の読み・意味で
 *   空欄を埋める** — 単語帳は「語」と「意味」が別の列に並ぶので、
 *   片方だけの行が2つ返ってくることがある
 * - 上限で切る
 */
export function cleanWordbookEntries(
  raw: readonly WordbookEntryDraft[] | null | undefined,
  max: number = MAX_ENTRIES_PER_PHOTO,
  /** 学習言語。渡さなければ台湾華語の規則(漢字を含む行だけ)。 */
  language?: string | null,
): WordbookEntryDraft[] {
  const byHead = new Map<string, WordbookEntryDraft>();
  for (const r of raw ?? []) {
    const headword = trim(r?.headword);
    if (!headword || !isEntryWord(headword, language)) continue;
    const existing = byHead.get(headword);
    if (existing) {
      existing.reading_zhuyin = existing.reading_zhuyin ?? clean(r.reading_zhuyin);
      existing.pinyin = existing.pinyin ?? clean(r.pinyin);
      existing.meaning_ja = existing.meaning_ja ?? clean(r.meaning_ja);
      continue;
    }
    if (byHead.size >= Math.max(0, max)) continue;
    byHead.set(headword, {
      headword,
      reading_zhuyin: clean(r.reading_zhuyin),
      pinyin: clean(r.pinyin),
      meaning_ja: clean(r.meaning_ja),
    });
  }
  return [...byHead.values()];
}

/**
 * 単語帳の名前。AI が付けた名前を優先し、無ければ日付から作る。
 * **空の名前を作らない** — 名前の無い本は、あとから選べない。
 */
export function wordbookTitle(
  suggested: string | null | undefined,
  fallback: string,
  max: number = MAX_TITLE_CHARS,
): string {
  const s = trim(suggested);
  const base = s || trim(fallback) || "単語帳";
  return base.length > max ? base.slice(0, max) : base;
}

export type WordbookEntryState = {
  due_at: string | null;
  repetitions: number;
};

/** その本の進み具合。**「今日出す数」と「覚えた数」を分けて数える。** */
export function wordbookProgress(
  entries: readonly WordbookEntryState[],
  nowMs: number = Date.now(),
): { total: number; due: number; learned: number } {
  let due = 0;
  let learned = 0;
  for (const e of entries) {
    const at = e.due_at ? new Date(e.due_at).getTime() : 0;
    if (!Number.isFinite(at) || at <= nowMs) due += 1;
    if (e.repetitions >= 3) learned += 1;
  }
  return { total: entries.length, due, learned };
}
