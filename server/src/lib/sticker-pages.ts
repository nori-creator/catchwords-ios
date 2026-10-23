import type { QueryClient } from "@tanstack/react-query";
import type { StickerWithWord } from "./stickers.functions";
import type { AlbumEncounter } from "./album-encounters";
import { POSTGREST_PAGE } from "./pagination";

/**
 * **札の一覧を、ページごとに読み足す**（2026-10-03 監査「図鑑・ホームが一度に最大 3000 件を
 * 読む」）。
 *
 * 前は `listMyStickers` が 1000 件ずつ繰って最大 3000 件と、その全部の写真の署名 URL
 * （1件に最大6本）を作ってから1回で返していた。持っている札が多い人ほど、最初の絵が
 * 出るまでが長く、返事も数 MB になっていた。
 *
 * いまは:
 * 1. 最初のページ（新しい順に `FIRST_PAGE` 件）だけを待って描く。
 * 2. 残りは裏で `NEXT_PAGE` 件ずつ読み、届くたびに同じ鍵（`["stickers"]`）の中身を
 *    差し替える。合計の天井（3000 件）は今までどおり（サーバの `STICKER_TOTAL_CAP`）。
 * 3. 読み終えたら、途中で止まったか（天井・失敗）を `truncated` に出す（前と同じ意味）。
 *
 * 一覧を使う側（ホーム・図鑑・撮影・スキャン）の形は変えない（`items` / `truncated` /
 * `total` / `albumEncounters` …）。読み足している間は `loadingMore` が true。
 */
export const STICKER_FIRST_PAGE = 120;
export const STICKER_NEXT_PAGE = 500;
/** 1回に頼める上限（PostgREST の `db-max-rows`。`pagination.ts` の値をそのまま使う）。 */
export const STICKER_PAGE_MAX = POSTGREST_PAGE;

export const STICKERS_KEY = ["stickers"] as const;

export type StickerPageInput = { offset: number; limit: number };

/**
 * サーバの入力の検め。**入力なし（前からの呼び方）は null** — その時は今までどおり
 * 全部まとめて返す（iOS 版・MCP が使う）。
 */
export function parseStickerPageInput(input: unknown): StickerPageInput | null {
  if (input == null) return null;
  if (typeof input !== "object") throw new Error("invalid sticker page");
  const { offset, limit } = input as { offset?: unknown; limit?: unknown };
  const o = Number(offset ?? 0);
  const l = Number(limit ?? STICKER_FIRST_PAGE);
  if (!Number.isInteger(o) || o < 0 || o > 100_000) throw new Error("invalid sticker page");
  if (!Number.isInteger(l) || l < 1) throw new Error("invalid sticker page");
  return { offset: o, limit: Math.min(l, STICKER_PAGE_MAX) };
}

/** サーバが1ページごとに返す形（`listMyStickers` に `{ offset, limit }` を渡した時）。 */
export type StickerPage = {
  items: StickerWithWord[];
  truncated: boolean;
  total: number | null;
  targetLanguage: string;
  otherLanguages: number | null;
  albumEncounters: AlbumEncounter[];
  nextOffset: number | null;
  rawCount: number;
};

/** 画面が持つ一覧（前と同じ形 + 読み足しの印）。 */
export type StickerList = Omit<StickerPage, "nextOffset" | "rawCount"> & {
  /** まだ裏でページを読んでいる。 */
  loadingMore?: boolean;
  /** どの読み込みの結果か（新しい読み込みが始まったら古い読み足しは手を引く）。 */
  loadId?: string;
};

/** 時刻の書式（`Z` と `+00:00`）が混ざっても比べられるように数にする。 */
const at = (iso: string) => Date.parse(iso) || 0;
const newer = (a: StickerWithWord, b: StickerWithWord) =>
  at(a.created_at) === at(b.created_at) ? a.id > b.id : at(a.created_at) > at(b.created_at);

/**
 * 読み足し途中の一覧を組む。
 *
 * - `loaded`: サーバから届いた分（新しい順。この範囲はサーバの通り）。
 * - `current`: いま画面が持っている一覧（前の読み込みの結果・端末に覚えた一覧・
 *   撮った直後に先に入れた札）。
 * - `startedAt`: この読み込みを始めた時刻。
 *
 * 1. **まだ届いていない古い側**は、手元の一覧の分をそのまま見せておく（読み直すたびに図鑑が
 *    120 枚に縮んでまた伸びる、を起こさない）。読み終えたら（`done`）落とす — そこで
 *    サーバに無い札（消した札）は消える。
 * 2. **読み込みを始めた後に手元へ先に入れた札**（撮った直後の札、`optimistic-sticker.ts`）は
 *    残す。始める前からあってサーバに無い新しい札は、消えた札として落とす。
 */
export function combineStickerItems(
  loaded: readonly StickerWithWord[],
  current: readonly StickerWithWord[] | undefined,
  startedAt: string,
  done: boolean,
): StickerWithWord[] {
  const ids = new Set(loaded.map((s) => s.id));
  const rest = (current ?? []).filter((s) => !ids.has(s.id));
  const newest = loaded[0];
  const oldest = loaded[loaded.length - 1];
  const head = rest.filter(
    (s) => at(s.created_at) > at(startedAt) && (!newest || newer(s, newest)),
  );
  const tail = done || !oldest ? [] : rest.filter((s) => newer(oldest, s));
  return [...head, ...loaded, ...tail];
}

/** 一覧に合わせて、再会の写真を札のある物だけにする（前はサーバが同じ絞りを掛けていた）。 */
export function encountersFor(
  encounters: readonly AlbumEncounter[],
  items: readonly StickerWithWord[],
): AlbumEncounter[] {
  const ids = new Set(items.map((s) => s.id));
  return encounters.filter((e) => ids.has(e.sticker_id));
}

type FetchPage = (opts: { data: StickerPageInput }) => Promise<StickerPage>;

/**
 * `useQuery({ queryKey: ["stickers"], queryFn })` の `queryFn`。最初のページで返し、
 * 残りを裏で読み足す。
 */
export function stickerListQueryFn(qc: QueryClient, fetchPage: FetchPage) {
  return async (): Promise<StickerList> => {
    const loadId = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
    const startedAt = new Date().toISOString();
    const first = await fetchPage({ data: { offset: 0, limit: STICKER_FIRST_PAGE } });
    const seen = new Set<string>();
    const loaded: StickerWithWord[] = [];
    const add = (items: readonly StickerWithWord[]) => {
      // 繰っている間に1件増えると同じ行がもう一度来る。二重に積まない。
      for (const s of items) {
        if (seen.has(s.id)) continue;
        seen.add(s.id);
        loaded.push(s);
      }
    };
    add(first.items);
    let raw = first.rawCount;
    let next = first.nextOffset;
    const build = (done: boolean, failed = false): StickerList => {
      const current = qc.getQueryData<StickerList>(STICKERS_KEY)?.items;
      const items = combineStickerItems(loaded, current, startedAt, done);
      return {
        items,
        total: first.total,
        targetLanguage: first.targetLanguage,
        otherLanguages: first.otherLanguages,
        albumEncounters: encountersFor(first.albumEncounters, items),
        // 途中で止まったことは**読み終えてから**言う（天井に当たった・続きが読めなかった）。
        truncated: done && (failed || (first.total != null && raw < first.total)),
        loadingMore: !done,
        loadId,
      };
    };
    if (next == null) return build(true);
    void (async () => {
      let failed = false;
      // 最初のページが一覧（キャッシュ）に入ってから読み足す（`loadId` で自分の番かを見るため）。
      await new Promise((resolve) => setTimeout(resolve, 0));
      try {
        while (next != null) {
          const page = await fetchPage({ data: { offset: next, limit: STICKER_NEXT_PAGE } });
          add(page.items);
          raw += page.rawCount;
          next = page.rawCount > 0 ? page.nextOffset : null;
          // 新しい読み込みが始まった（保存・削除の後の読み直し）か、一覧が捨てられたら手を引く。
          if (qc.getQueryData<StickerList>(STICKERS_KEY)?.loadId !== loadId) return;
          if (next != null) qc.setQueryData(STICKERS_KEY, build(false));
        }
      } catch {
        failed = true;
      }
      if (qc.getQueryData<StickerList>(STICKERS_KEY)?.loadId !== loadId) return;
      qc.setQueryData(STICKERS_KEY, build(true, failed));
    })();
    return build(false);
  };
}
