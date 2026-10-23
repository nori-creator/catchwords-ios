/**
 * **全員で使う音の置き場（`tts` の bucket）に貯めてよい文か**（監査 2026-10-03）。
 *
 * 音の置き場所は `(言語, 声, 文)` から決まり（`tts-cache.ts`）、ログインした人なら誰でも
 * 読める。前は**読み上げた文を何でも**（日記の一文・ひと言・打ち込んだ文、最大 400 字）
 * そこへ貯めていたので、他人の書いた文が全員の置き場に残り、同じ文を知っていれば
 * 「誰かがこの文を読み上げた」ことまで確かめられた（ARCHITECTURE「Do not share
 * user-specific/private speech output as a global cache」）。
 *
 * 貯めてよいのは、**辞書の側にもともと在る文**だけ:
 * - 見出し語（`dictionary_entries.headword` / `words.headword`）
 * - 共有の語の例文（`words.example_sentence`）
 * - サーバが作って共有の語・解説に置いた追加例文（`extras.examples_extra[].zh`）
 *
 * それ以外の文は、その場で作って返すだけで貯めない（端末の中の控え `tts-store.ts` には
 * 残るので、同じ端末で2回目からは待たない）。調べられないときも**貯めない側**に倒す。
 */

type Res = PromiseLike<{ data: unknown[] | null; error: unknown }>;

/** 使う問い合わせの形だけ（試験で偽物を渡せるように）。 */
export type TtsShareDb = {
  from: (table: string) => {
    select: (cols: string) => {
      eq: (
        col: string,
        value: string,
      ) => {
        eq: (col: string, value: string) => { limit: (n: number) => Res };
        contains: (col: string, value: unknown) => { limit: (n: number) => Res };
        limit: (n: number) => Res;
      };
      contains: (col: string, value: unknown) => { limit: (n: number) => Res };
    };
  };
};

async function found(q: Res): Promise<boolean> {
  try {
    const { data, error } = await q;
    return !error && Array.isArray(data) && data.length > 0;
  } catch {
    return false;
  }
}

/**
 * 貯めてよい文なら true。見出し語（索引が効く）を先に見て、当たらなければ例文を見る
 * （例文の検索は重いので、音の置き場に無かったときだけ呼ぶ）。
 */
export async function isShareableTtsText(
  db: TtsShareDb,
  language: string,
  text: string,
): Promise<boolean> {
  const t = text.trim();
  if (!t) return false;
  // 1. 見出し語（索引が効く）
  const [dict, word] = await Promise.all([
    found(
      db
        .from("dictionary_entries")
        .select("id")
        .eq("language", language)
        .eq("headword", t)
        .limit(1),
    ),
    found(db.from("words").select("id").eq("language", language).eq("headword", t).limit(1)),
  ]);
  if (dict || word) return true;
  // 2. 例文（共有の語の例文・追加例文、読む人ごとの解説の追加例文）
  const extra = { examples_extra: [{ zh: t }] };
  const hits = await Promise.all([
    found(
      db.from("words").select("id").eq("language", language).eq("example_sentence", t).limit(1),
    ),
    found(
      db.from("words").select("id").eq("language", language).contains("extras", extra).limit(1),
    ),
    found(db.from("word_explanations").select("word_id").contains("extras", extra).limit(1)),
  ]);
  return hits.some(Boolean);
}
