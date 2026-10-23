/**
 * 「まだ先があるか」の判定。
 *
 * ## なぜ2行のために別ファイルにしたか
 * ここを**2回続けて間違えた**から。
 *
 * 1回目: 上限を明示しただけで、上限に達したことをユーザーに伝えなかった。
 *        図鑑は黙って途中で止まったまま。
 * 2回目: 「上限+1件を引いて余りが出たら先がある」と書いた。ところが
 *        PostgREST は `db-max-rows`(既定1000)で切るので、
 *        **1001件目は永遠に来ない**。判定は常に false になり、そのために
 *        足した案内は一度も出ない — 直したつもりで何も直っていなかった。
 *
 * どちらも動かしてみれば分かるのに、動かせない場所に置いたまま
 * 「直した」と言っていた。純粋な関数にして、試せるようにする。
 */

/**
 * @param total    サーバーが数えた総数(`count: "exact"`)。数えられなければ null。
 * @param returned 実際に受け取った件数。
 * @param limit    こちらが要求した上限。
 */
export function isTruncated(total: number | null, returned: number, limit: number): boolean {
  // 総数が分かっているならそれがすべて。上限やサーバー側の切り詰めに
  // 左右されない。
  if (total != null) return total > returned;
  // 数えられなかったときの当て推量: ちょうど上限まで返ってきたなら、
  // その先があると考えておく。**多めに言う側に倒す** —
  // 「まだあるかも」と言って実は無かったより、
  // 黙って消えるほうがずっと悪い。
  return returned >= limit;
}

/** PostgREST が1回に返す行の上限（`db-max-rows` の既定）。これより大きく頼んでも来ない。 */
export const POSTGREST_PAGE = 1000;

/**
 * **全部の行を、1000 行ずつ読む**（ベータの指標、2026-10-03）。
 *
 * `.limit(50000)` と書いても PostgREST は 1000 行で切る（上の注の2回目と同じ罠）。
 * `page(from, to)` は `.order(…).range(from, to)` を付けた問い合わせを返すこと
 * （並びが決まっていないと、ページの境で行が抜けたり重なったりする）。
 * `parallel` ページずつ並べて読み、短いページが来たら終わり。`maxRows` で止めた時は
 * `truncated: true`（黙って切らない）。
 */
export async function readAllPages<T>(
  page: (
    from: number,
    to: number,
  ) => PromiseLike<{ data: T[] | null; error: { message?: string } | null }>,
  opts: { pageSize?: number; maxRows?: number; parallel?: number } = {},
): Promise<{ rows: T[]; truncated: boolean }> {
  const size = Math.min(opts.pageSize ?? POSTGREST_PAGE, POSTGREST_PAGE);
  const maxRows = opts.maxRows ?? 100_000;
  const parallel = Math.max(1, opts.parallel ?? 4);
  const rows: T[] = [];
  for (let start = 0; ; start += size * parallel) {
    const batch = await Promise.all(
      Array.from({ length: parallel }, (_, i) => {
        const from = start + i * size;
        return page(from, from + size - 1);
      }),
    );
    for (const res of batch) {
      if (res.error) throw new Error(res.error.message ?? "read failed");
      const got = res.data ?? [];
      rows.push(...got);
      if (rows.length >= maxRows) return { rows: rows.slice(0, maxRows), truncated: true };
      if (got.length < size) return { rows, truncated: false };
    }
  }
}
