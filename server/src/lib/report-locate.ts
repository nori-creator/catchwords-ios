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
    if (k === "headword") return word.headword ?? "";
    // 意味は語の列では `meaning_ja`（項目名の `meaning` では空になり、AI に「意味は空」と見せていた）。
    if (k === "meaning") return word.meaning ?? word.meaning_ja ?? ex.meaning ?? "";
    // 例文は語の列（`example_sentence` / `example_translation`）。extras の写しは古い試験の形だけ。
    if (k === "example" && !("example" in word) && !ex.example) {
      return [word.example_sentence, word.example_translation].filter(Boolean).join(" / ");
    }
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

/**
 * **見出し語そのものが写っている物の名前として違う**ことを指す項目名（2026-11-24、オーナー「写真に写ってるのは
 * トルティーヤチップス」）。項目の候補にいつも足し、AI がこれを選んだら札を正しい語に付け替える。
 */
export const HEADWORD_ITEM = "headword";

/** 1回の報告で直す項目の上限（意味と台湾メモが一緒に違う、など）。 */
export const MAX_REPORTED_ITEMS = 3;

/**
 * 報告で**間違っている項目を全部**（上限まで）。答えは `{"items":[...]}` か古い形の `{"item":"…"}`。
 * 候補に無い名前・「なし」・重なりは落とす。見出し語（`headword`）が入れば、それだけを返す（語が違えば、
 * その語の中身を直しても意味が無い — 付け替えた先の語の中身はその語の物で作られる）。
 */
export function pickReportedItems<T extends string>(raw: unknown, candidates: readonly T[]): T[] {
  if (!raw || typeof raw !== "object") return [];
  const r = raw as { items?: unknown; item?: unknown };
  const list = Array.isArray(r.items) ? r.items : r.item != null ? [r.item] : [];
  const out: T[] = [];
  for (const v of list) {
    if (typeof v !== "string") continue;
    const s = v.trim();
    if (!(candidates as readonly string[]).includes(s) || out.includes(s as T)) continue;
    out.push(s as T);
  }
  if ((out as string[]).includes(HEADWORD_ITEM)) return [HEADWORD_ITEM as T];
  return out.slice(0, MAX_REPORTED_ITEMS);
}

/** 見出し語の直しの答え（`{"wrong":true,"headword":"…"}`）。違う・同じ語・空なら null。 */
export function pickCorrectHeadword(raw: unknown, current: string): string | null {
  if (!raw || typeof raw !== "object") return null;
  const r = raw as { wrong?: unknown; headword?: unknown };
  if (r.wrong !== true || typeof r.headword !== "string") return null;
  const h = r.headword.trim();
  if (!h || h.length > 30 || h === current.trim()) return null;
  return h;
}

type ReaderRow = {
  meaning?: string | null;
  example_translation?: string | null;
  extras?: Record<string, unknown> | null;
} | null;

type BandRow = {
  example_sentence?: string | null;
  example_translation?: string | null;
  extras?: Record<string, unknown> | null;
} | null;

const filled = (v: unknown) =>
  Array.isArray(v) ? v.length > 0 : typeof v === "string" ? v.trim().length > 0 : v != null;

/**
 * **学習者の画面に出ている語**（2026-11-24）。画面は共有の語の行に、その人の言語の解説の行（`word_explanations`）と
 * 帯の行（`word_level_content`、例文・チャンク — `docs/sharing-rules.md` S6）を重ねて出す（iOS `ReaderLanguage.resolve`）。
 * 報告の項目探し・直す前の比べ・AI に見せる「今の内容」は、共有の行ではなくこれを見る — 共有の行だけを見ていたので、
 * 画面に出ていない（もう直っている・別の言語の）物を「正しい」と判じていた（玉米片 2026-11-10）。
 */
export function readerViewOfWord(
  shared: Record<string, unknown>,
  reader: ReaderRow,
  band: BandRow,
): Record<string, unknown> {
  const extras: Record<string, unknown> = { ...((shared.extras ?? {}) as Record<string, unknown>) };
  const view: Record<string, unknown> = { ...shared };
  if (reader) {
    if (filled(reader.meaning)) view.meaning_ja = reader.meaning;
    if (filled(reader.example_translation)) view.example_translation = reader.example_translation;
    for (const [k, v] of Object.entries(reader.extras ?? {})) if (filled(v)) extras[k] = v;
  }
  if (band) {
    if (filled(band.example_sentence)) view.example_sentence = band.example_sentence;
    if (filled(band.example_translation)) view.example_translation = band.example_translation;
    for (const [k, v] of Object.entries(band.extras ?? {})) if (filled(v)) extras[k] = v;
  }
  view.extras = extras;
  return view;
}

/**
 * 作り直す時に AI に渡す**学習者の報告**（2026-11-24）。報告は直しの手がかりで、そのまま写す文ではない。
 * 報告が誤っていれば、今までどおり正しい内容を書かせる（別の目の判定が今の内容と比べる）。
 */
export function reportGuidance(note: string, current: string): string {
  const n = note.trim().slice(0, 300);
  if (!n) return "";
  return (
    `\n## 学習者からの報告（この項目が間違っているという指摘）\n` +
    `今の内容: ${current.slice(0, 600) || "(空)"}\n` +
    `報告: 「${n}」\n` +
    `報告が事実として正しければ、その指摘を直した内容にする。報告が誤っていれば、報告に合わせず正しい内容を書く。` +
    `報告の文をそのまま写さない。上の決まり（言語・長さ・形）はそのまま守る。`
  );
}
