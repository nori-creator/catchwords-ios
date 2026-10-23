/**
 * **報告から「どの項目が間違っているか」を決める**（オーナー指示 2026-09-27
 * 「エラーをユーザーが報告したときに AI が自動で該当の箇所を間違いを認識し、
 * 正しいものを自動で表示するシステム」）。
 *
 * 利用者が項目を選ばずに「AIに見つけてもらう」を押したとき、AI に語の中身と
 * 一言を渡し、**画面に出ている項目のどれか1つ**か「なし」を答えさせる。
 * 答えは必ずこの関数を通す — 画面に無い項目名・作り話の名前は採らない。
 */
export function pickReportedItem<T extends string>(
  raw: unknown,
  candidates: readonly T[],
): T | null {
  if (!raw || typeof raw !== "object") return null;
  const v = (raw as { item?: unknown }).item;
  if (typeof v !== "string") return null;
  const s = v.trim();
  return (candidates as readonly string[]).includes(s) ? (s as T) : null;
}

/** AI に見せる語の中身（項目ごとに長さを切る。長い語でも1回の問い合わせに収める）。 */
export function reportContext(
  candidates: readonly string[],
  word: Record<string, unknown>,
  maxPerItem = 500,
): string {
  const ex = (word.extras ?? {}) as Record<string, unknown>;
  const value = (k: string) => {
    if (k === "pronunciation")
      return [word.reading_zhuyin, word.pinyin, word.ipa].filter(Boolean).join(" / ");
    if (k === "pos") return word.part_of_speech ?? "";
    return (k in word ? word[k] : ex[k]) ?? "";
  };
  return candidates
    .map((k) => {
      const v = value(k);
      const text = typeof v === "string" ? v : JSON.stringify(v);
      return `[${k}] ${text.slice(0, maxPerItem)}`;
    })
    .join("\n");
}
