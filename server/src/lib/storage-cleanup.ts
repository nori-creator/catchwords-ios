/**
 * **ある人のフォルダの中を、下の階層まで全部消す**（退会。監査 2026-10-03）。
 *
 * Supabase の `list(prefix)` はその階層だけを返し、フォルダは `id: null` の項目として
 * 混ざる。前の退会処理は一番上の階層だけを消していたので、`<uid>/<id>/photo.jpg` の
 * ような下の階層の写真（最初のキャッチの引き継ぎなど）が残っていた。
 */
export type StorageEntry = { name: string; id: string | null };

export type StorageBucket = {
  list: (
    prefix: string,
    opts: { limit: number; offset: number },
  ) => PromiseLike<{ data: StorageEntry[] | null; error: { message: string } | null }>;
  remove: (paths: string[]) => PromiseLike<{ error: { message: string } | null }>;
};

const PAGE = 1000;
/** フォルダの深さの上限（自分で作るのは2〜3段。万一の循環で止まらなくならないように）。 */
const MAX_DEPTH = 8;

/** `prefix` の下のファイルの置き場所を、下の階層まで全部集める。 */
export async function listFilesRecursive(
  bucket: StorageBucket,
  prefix: string,
  depth = 0,
): Promise<string[]> {
  if (depth > MAX_DEPTH) return [];
  const out: string[] = [];
  for (let offset = 0; ; offset += PAGE) {
    const { data, error } = await bucket.list(prefix, { limit: PAGE, offset });
    if (error) throw new Error(error.message);
    const entries = data ?? [];
    for (const e of entries) {
      const path = `${prefix}/${e.name}`;
      if (e.id === null) out.push(...(await listFilesRecursive(bucket, path, depth + 1)));
      else out.push(path);
    }
    if (entries.length < PAGE) break;
  }
  return out;
}

/**
 * `prefix` の下を全部消す。消した数を返す。数え方・消し方が失敗したら投げる
 * （退会は「消えたと言ったのに残っている」がいちばん困る）。
 * `missingOk` … バケットが無い環境（新しい環境）では何もしない。
 */
export async function removeAllUnder(
  bucket: StorageBucket,
  prefix: string,
  opts: { missingOk?: boolean } = {},
): Promise<number> {
  let files: string[];
  try {
    files = await listFilesRecursive(bucket, prefix);
  } catch (e) {
    if (opts.missingOk && /not found|does not exist/i.test((e as Error).message)) return 0;
    throw e;
  }
  for (let i = 0; i < files.length; i += PAGE) {
    const { error } = await bucket.remove(files.slice(i, i + PAGE));
    if (error) throw new Error(error.message);
  }
  return files.length;
}
