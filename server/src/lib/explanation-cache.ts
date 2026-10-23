/**
 * **単語の解説を端末に覚えておく**（オーナー指示 2026-09-28「単語の詳細の項目、開いたときに
 * 表示されたものが、ぱっと消えて新しいものが表示されるバグがある…すべてのユーザーの
 * 共通のものはサーバーに保存して高速で同じものを表示」「過去に生成したデータは全て
 * 端末に保存して瞬間的に表示されるようにして」）。
 *
 * 解説そのものは全員で共有する表（`word_explanations`、語 × 解説の言語 × 母語）に
 * 在る。ここはその**返事をそのまま端末に写す**だけ — 次に開いた時は通信を待たずに
 * 同じ物を出し、裏で確かめ直す。数は上限を置き、古い物から捨てる。
 */
const KEY = "word-explanations-v1";
const MAX = 400;

type Entry<T> = { k: string; v: T };

function load<T>(): Array<Entry<T>> {
  try {
    const raw = globalThis.localStorage?.getItem(KEY);
    const list = raw ? (JSON.parse(raw) as unknown) : [];
    return Array.isArray(list) ? (list as Array<Entry<T>>) : [];
  } catch {
    return [];
  }
}

export function explanationCacheKey(wordId: string, lang: string, l1: string): string {
  return `${wordId}:${lang}:${l1}`;
}

export function readCachedExplanation<T>(key: string): T | undefined {
  return load<T>().find((e) => e.k === key)?.v;
}

export function writeCachedExplanation<T>(key: string, value: T): void {
  try {
    const rest = load<T>().filter((e) => e.k !== key);
    const next = [{ k: key, v: value }, ...rest].slice(0, MAX);
    globalThis.localStorage?.setItem(KEY, JSON.stringify(next));
  } catch {
    // 容量いっぱい・書けない端末でも、画面は通信の結果で出る。
  }
}

export function lacksNotes(v: unknown): boolean {
  return (
    Array.isArray(v) && v.every((r) => !String((r as { note?: unknown } | null)?.note ?? "").trim())
  );
}

/**
 * **いま見えている項目は差し替えない**。AI が欠けた項目を埋め直す時、既に中身の
 * ある項目は画面に出ている物をそのまま残し、空だった項目だけ新しい物で埋める
 * （全部を作り直した物で上書きすると、読んでいる途中の項目が別の文に化ける）。
 */
export function keepShownFields<T extends Record<string, unknown>>(
  shown: T | null | undefined,
  fresh: T,
): T {
  if (!shown) return fresh;
  const filled = (v: unknown) =>
    Array.isArray(v) ? v.length > 0 : typeof v === "string" ? v.trim().length > 0 : v != null;
  const out: Record<string, unknown> = { ...fresh };
  for (const [k, v] of Object.entries(shown)) {
    if (!filled(v)) continue;
    // 語だけで解説（note）が1つも無い関連語は「見えている中身」に数えない
    // （2026-09-30 保溫瓶: 空の解説が新しく作った解説を押しのけて残り続けた）。
    if (k === "related_words" && lacksNotes(v)) continue;
    out[k] = v;
  }
  // 解説の言語の目印は新しい方（その人向けに作った物）を使う。
  if ("explain_lang" in fresh) out.explain_lang = fresh.explain_lang;
  if ("explain_l1" in fresh) out.explain_l1 = (fresh as Record<string, unknown>).explain_l1;
  return out as T;
}
