import { createServerFn } from "@tanstack/react-start";
import { DEFAULT_TARGET_LANGUAGE, normalizeTargetLanguage } from "./target-lang";
import { assertTargetHeadword } from "./target-language";
import {
  wordLanguageFilter,
  matchesTargetLanguage,
  headwordMatchesTarget,
} from "./language-filter";
import { getExplanationLanguage, getUserTargetLanguage } from "./ai-provider.server";
import {
  DICTIONARY_SELECT,
  resolveDictionaryFields,
  type RawDictionaryRow,
} from "./dictionary-entry";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { z } from "zod";
import { pregenerateDistractors } from "./reviews.functions";
import { isNativeRequest } from "./native-request.server";
import { buildBranchPlan } from "./wordtree";
import { normalizeCategory } from "./category";
import { isTruncated, POSTGREST_PAGE } from "./pagination";
import { parseStickerPageInput } from "./sticker-pages";
import { isBuiltinRoom, normalizeShelfProposal, type RawShelfProposal } from "./shelf-proposal";
import type { UserShelf } from "./shelf-plan";
import { normalizeExtras, hasExtrasContent, publicExtras, type WordExtrasDTO } from "./extras";

/**
 * 1枚の札を読む時、台湾華語の型の札に読み（拼音・注音）を付ける（`chunk-readings.server.ts`）。
 * 辞書が大きいので遅延で読み込み、失敗しても読みが無いだけでカードは返す。
 */
async function withReadingsOnRead<T extends WordExtrasDTO | null>(
  extras: T,
  language: string | null,
): Promise<T> {
  if (!extras) return extras;
  try {
    const { withChunkReadingsInExtras } = await import("./chunk-readings.server");
    return withChunkReadingsInExtras(extras, language);
  } catch (e) {
    console.warn("getSticker: 型の読みを付けられなかった", (e as Error)?.message);
    return extras;
  }
}
import {
  BoundedExtrasSchema,
  LanguageCodeSchema,
  LOCATION_NAME_MAX,
  STORAGE_PATH_MAX,
  SharedColumnsPatchSchema,
  WordInputSchema,
  fillEmptySharedColumns,
  fillEmptySharedExtras,
  isExplanationLangCode,
  sharedColumnsFromCard,
  type SharedWordColumn,
} from "./shared-word-guard";
import { findGeneratedCard, type GeneratedCardLookup, type TrustedCard } from "./generated-cards";
import { explanationKey } from "./word-explanation";
import {
  alignExampleExtras,
  exampleMatchesSentence,
  guardExampleColumns,
} from "./example-patterns";
import { keepShownFields } from "./explanation-cache";
import { runAfterResponse } from "./after-response";

import type { AlbumEncounter } from "./album-encounters";

// WordExtrasDTO / extras の正規化は src/lib/extras.ts に一本化(re-export)。
export type { WordExtrasDTO } from "./extras";

export type PlaceholderCredit = { name?: string; link?: string; source?: string };

export type StickerWithWord = {
  id: string;
  word_id: string;
  caption: string | null;
  location_name: string | null;
  lat: number | null;
  lng: number | null;
  taken_at: string;
  created_at: string;
  encounter_count: number;
  object_url: string | null;
  cutout_url: string | null;
  selfie_url: string | null;
  /** Small grid thumbnails (`${path}.thumb.webp`) — null for older stickers. */
  object_thumb_url: string | null;
  cutout_thumb_url: string | null;
  /** 'photo' | 'text' | 'voice' — non-photo catches are ghosts (§5.3). */
  capture_type: string;
  /**
   * この1枚を表に出すときの主役(要望 #17)。null なら設定に従う。
   * 列がまだ無い環境では undefined のまま来るので `?` を付けてある。
   * **文字列のまま持つ** — `pickStickerPhoto` の `prefer` が
   * 知らない値を既定の順に落としてくれるので、ここで縛る必要が無い。
   */
  hero_role?: string | null;
  /** 日ごとのアルバム配置。未設定は従来の自動配置。 */
  album_order?: number | null;
  album_size?: "small" | "portrait" | "landscape" | "large" | null;
  /**
   * 紙の上の座標（オーナー指示 2026-09-15）。**升目ではなく連続値。**
   * 単位は台紙の箱に対する割合で、別の端末で開いても同じ見た目になる。
   * 列がまだ無い環境では undefined のまま来る（`?` を付けてある）ので、
   * `placementFrom()` が昔の並びに寄せた場所へ自動で置く。
   */
  album_x?: number | null;
  album_y?: number | null;
  album_scale?: number | null;
  album_rot?: number | null;
  /**
   * その人だけの棚の上書き(AI が作った棚)。null なら語の分類を使う。
   * 列がまだ無い環境では undefined のまま来る。
   */
  shelf_key?: string | null;
  /** 自分の札か（詳細だけが入れる。カテゴリーを変える道を持ち主にだけ出す）。 */
  is_owner?: boolean;
  /** Signed URL of the temporary stand-in image for ghosts. */
  placeholder_url: string | null;
  placeholder_credit: PlaceholderCredit | null;
  /** §6 word tree: branch plan frozen at save time (getSticker only). */
  branch_plan?: Array<{ type: string; zh: string; ja?: string }> | null;
  /** §6 word tree: completed reviews = unlocked branch count (getSticker only). */
  review_count?: number;
  word: {
    headword: string;
    /**
     * その語を**何語として覚えているか**。
     * 台湾華語の語と英語の語を両方持っている人が居るので、
     * 作り直し・読み上げ・行き先は**その語の値**を見る
     * （いま設定している学習言語ではない）。
     */
    language: string | null;
    reading_zhuyin: string | null;
    pinyin: string | null;
    meaning_ja: string;
    part_of_speech: string | null;
    example_sentence: string | null;
    example_translation: string | null;
    level: string | null;
    category_key: string | null;
    silhouette_emoji: string | null;
    extras: WordExtrasDTO | null;
  };
};

type SignedUrlsClient = {
  storage: {
    from: (b: string) => {
      createSignedUrls: (
        p: string[],
        e: number,
      ) => Promise<{
        data: Array<{ path: string | null; signedUrl: string | null; error: string | null }> | null;
      }>;
    };
  };
};

/**
 * Sign many storage paths in a single API call (avoids the N+1 of one
 * createSignedUrl round-trip per image) and return a path→URL lookup.
 */
const SIGN_BATCH = 500;

export async function signUrlMap(
  supabase: SignedUrlsClient,
  paths: (string | null | undefined)[],
): Promise<Map<string, string>> {
  const unique = [...new Set(paths.filter((p): p is string => !!p))];
  const map = new Map<string, string>();
  if (unique.length === 0) return map;
  // **まとめて投げすぎない。** 1件につき最大6本(写真・切り抜き・自撮り・
  // 代替画像・サムネ2枚)署名するので、3000件まで読むようにした結果
  // 最大18000本を1回の呼び出しに詰め込むことになった。要求も応答も
  // 数MBになり、ここで詰まると図鑑が丸ごと出てこない。
  for (let i = 0; i < unique.length; i += SIGN_BATCH) {
    const chunk = unique.slice(i, i + SIGN_BATCH);
    const { data } = await supabase.storage.from("stickers").createSignedUrls(chunk, 60 * 60 * 6);
    for (const row of data ?? []) {
      if (row.path && row.signedUrl && !row.error) map.set(row.path, row.signedUrl);
    }
  }
  return map;
}

/**
 * Per-sticker encounter counts, tolerant of the pre-migration schema
 * (encounter_count column may not exist yet — then everything is 0).
 */
async function encounterCounts(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  supabase: any,
  ids: string[],
): Promise<Map<string, number>> {
  const map = new Map<string, number>();
  if (ids.length === 0) return map;
  // **欲しい id だけを聞く。** 以前はユーザーの全行を引いていたので、
  // PostgREST の 1000 行で切られていた。図鑑を3000件まで読むように
  // した以上、切られた先の語は再会の回数が 0 に見える — しかも
  // どれが 0 になるかは並び順しだいで**読むたびに変わる**。
  for (let i = 0; i < ids.length; i += SIGN_BATCH) {
    const chunk = ids.slice(i, i + SIGN_BATCH);
    const { data, error } = await supabase
      .from("stickers")
      .select("id, encounter_count")
      .in("id", chunk)
      .gt("encounter_count", 0);
    if (error) return map; // 再会の印は飾り。取れなければ黙って諦める。
    for (const row of data ?? []) map.set(row.id, row.encounter_count ?? 0);
  }
  return map;
}

/**
 * 1回の問い合わせで受け取る件数。
 *
 * PostgREST は `db-max-rows`(既定1000)で切るので、これより大きくしても
 * 意味がない。**1000は「1ページの大きさ」であって「合計の上限」ではない。**
 */
const STICKER_PAGE_SIZE = POSTGREST_PAGE;

/**
 * 全部で受け取る件数の天井。
 *
 * ## なぜ天井が要るか
 * 図鑑は「集めたものが全部ある」ことが値打ちの画面なので、本来は
 * 上限で終わりにできない。だからページを繰って全部取る。
 * ただし1件ごとに署名URLを6本(写真・切り抜き・自撮り・サムネ2枚…)
 * 作るので、**際限なく取ると1回の起動が際限なく重くなる**。
 * どこかで止める必要がある。
 *
 * 3000件は「毎日1語キャッチして8年ぶん」。ここに届く人が出たら、
 * そのときは本当のページ送り(古い方を後から読む)を作る。
 * それまでは、天井に当たったことを画面に出して**黙って消えない**ようにする。
 */
const STICKER_TOTAL_CAP = 3000;

/**
 * 自分の札の一覧。
 *
 * **入力なし**（iOS 版・MCP など前からの呼び方）: 今までどおり 1000 件ずつ繰って
 * 3000 件まで一度に返す。
 *
 * **`{ offset, limit }` 付き**（2026-10-03 監査「一度に最大 3000 件を読む」）: その1ページ
 * だけ返す（`limit` は 1〜1000）。画面は最初の1ページで描き、残りを裏で順に読み足す
 * （`lib/sticker-pages.ts`）。ページごとに署名する写真の数も、そのページの分だけになる。
 */
export const listMyStickers = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => parseStickerPageInput(input))
  .handler(async ({ context, data: pageInput }) => {
    const { supabase, userId } = context;
    // 1ページだけ読む回か（null = 前からの「全部まとめて」）。
    const paged = pageInput ?? null;
    const firstFrom = paged?.offset ?? 0;
    const firstSize = paged?.limit ?? STICKER_PAGE_SIZE;
    // 総数は最初のページでだけ数える（2ページ目以降は誰も見ない）。
    const firstCount = firstFrom === 0;
    /**
     * **学習言語で絞る。** オーナー指示「学習言語によってアルバムや図鑑に
     * 表示されるものをすべて区別して。混ぜないで」。
     *
     * 正はプロフィール（端末の localStorage ではない）。端末の値は
     * 撮る道が使うが、**見えるものを決めるのに端末を信じてはいけない** —
     * 別の端末で開いたときに違う物が見える。
     */
    const targetLanguage = await getUserTargetLanguage(userId);
    const langFilter = wordLanguageFilter(targetLanguage);
    // `!inner` にすると、条件に合わない語の札は**親ごと落ちる**。
    // ここを普通の埋め込みにすると `words: null` の札が残り、
    // 「絵はあるのに文字が無い札」が並ぶ。
    const wordCols =
      "words!inner(headword, language, reading_zhuyin, pinyin, meaning_ja, part_of_speech, example_sentence, example_translation, level, category_key, silhouette_emoji, extras)";
    const fullCols = `id, word_id, caption, location_name, lat, lng, taken_at, created_at, object_image_url, cutout_image_url, selfie_image_url, hero_role, album_order, album_size, album_x, album_y, album_scale, album_rot, capture_type, placeholder_image_url, placeholder_credit, shelf_key, ${wordCols}`;
    // `hero_role` だけが無い環境のための段。**ゴーストの列と一緒くたにしない**
    // — 一緒にすると、この移行だけ当たっていない環境でネット画像まで落ちる。
    const noHeroCols = fullCols.replace(", hero_role", "");
    // Migration not applied yet — fall back to the photo-only shape.
    // **新しい列を1つ足すたびに、無い環境でも読める形を残す。**
    // ここを忘れると、列が無い環境で図鑑が丸ごと空になる。
    const legacyCols = `id, word_id, caption, location_name, lat, lng, taken_at, created_at, object_image_url, cutout_image_url, selfie_image_url, ${wordCols}`;

    /**
     * 1ページ取る。
     *
     * **並びに `id` を足すこと。** `created_at` だけでは同点になりうるし、
     * ページを繰っている最中に1件増えると DESC の位置がずれて、
     * 999番目の行が次のページの先頭にもう一度出てくる(= 同じ id が2つ
     * 並び、代わりに古い1件が黙って落ちる)。別のタブでキャッチしたり、
     * オフラインキューが流れたりすると現実に起きる。
     *
     * `count` は最初のページでだけ数える。毎ページ数えると、3000件の人が
     * COUNT(*) を3回走らせることになる(2回目以降は誰も見ない)。
     */
    /**
     * 言語で絞るかどうか。**`words.language` がまだ無い環境では絞れない。**
     * その場合に空の図鑑を出すのが一番悪いので、絞りを外して全部出す
     * (混ざるが、消えない)。下の JS 側でもう一度同じ規則を掛ける。
     */
    let filterInDb = true;
    const page = async (
      cols: string,
      from: number,
      withCount: boolean,
      size: number = STICKER_PAGE_SIZE,
    ) => {
      const q = supabase
        .from("stickers")
        .select(cols, withCount ? { count: "exact" } : undefined)
        .eq("user_id", userId);
      const filtered = filterInDb ? q.or(langFilter, { referencedTable: "words" }) : q;
      return await filtered
        .order("created_at", { ascending: false })
        .order("id", { ascending: false })
        .range(from, from + size - 1);
    };

    const pageWithJwtClockSkewRetry = async (
      cols: string,
      from: number,
      withCount: boolean,
      size: number = STICKER_PAGE_SIZE,
    ) => {
      let res = await page(cols, from, withCount, size);
      for (const delayMs of [400, 900, 1600]) {
        if (!res.error || !/JWT issued at future/i.test(res.error.message)) break;
        // Auth tokens can be accepted by Auth before the database edge accepts
        // their `iat`. A short server-side retry prevents a transient blank app.
        await new Promise((resolve) => setTimeout(resolve, delayMs));
        res = await page(cols, from, withCount, size);
      }
      return res;
    };

    let cols = fullCols;
    let first = await pageWithJwtClockSkewRetry(cols, firstFrom, firstCount, firstSize);
    // 列がまだ無い / 埋め込みの絞りが通らない環境では、絞りだけ諦める。
    // **`pageWithJwtClockSkewRetry` を通す**(main が足した時計ずれの
    // 待ち直し)。ここだけ素の `page` に戻すと、絞りを外した1回目が
    // 時計ずれで落ちたときに図鑑が丸ごと空になる。
    if (first.error && /language/.test(first.error.message)) {
      console.warn("[stickers] words.language で絞れないので絞りを外す:", first.error.message);
      filterInDb = false;
      first = await pageWithJwtClockSkewRetry(cols, firstFrom, firstCount, firstSize);
    }
    if (first.error && /words!inner|words/.test(first.error.message) && filterInDb) {
      filterInDb = false;
      first = await pageWithJwtClockSkewRetry(cols, firstFrom, firstCount, firstSize);
    }
    /**
     * 紙の上の座標の列がまだ無い環境（オーナー指示 2026-09-15 の移行が
     * 当たる前）。**これだけを外す** — 一緒くたに `legacyCols` へ落とすと、
     * この移行が遅れているだけの人からゴーストの絵まで消える。
     * 外しても `placementFrom()` が昔の並びに寄せた場所へ自動で置くので、
     * 見た目は今までどおりになる。
     */
    if (first.error && /album_(x|y|scale|rot)/.test(first.error.message)) {
      cols = cols.replace(", album_x, album_y, album_scale, album_rot", "");
      first = await pageWithJwtClockSkewRetry(cols, firstFrom, firstCount, firstSize);
    }
    if (first.error && /hero_role/.test(first.error.message)) {
      cols = noHeroCols.replace(", album_x, album_y, album_scale, album_rot", "");
      first = await pageWithJwtClockSkewRetry(cols, firstFrom, firstCount, firstSize);
    }
    if (first.error && /capture_type|placeholder/.test(first.error.message)) {
      cols = legacyCols;
      first = await pageWithJwtClockSkewRetry(cols, firstFrom, firstCount, firstSize);
    }
    // **最初のページの失敗だけが致命的。** ここで読めなければ何も出せない。
    if (first.error) throw new Error(first.error.message);

    const count = first.count;
    const acc = (first.data ?? []) as unknown[];
    const seen = new Set<string>();
    for (const r of acc) seen.add((r as { id: string }).id);

    /**
     * 2ページ目から先。**途中で失敗しても、そこまでを返す。**
     *
     * 以前はここで throw していた。1000件読めているのに、1001件目の
     * 問い合わせがこけただけで**図鑑が丸ごとエラー画面になる**。
     * 手元にあるものを見せないほうがよほど悪い。
     *
     * 範囲外を頼むと PostgREST は空配列ではなく 416 を返す。つまり
     * 「空が来たら終わり」では終われない場合がある(数えたあとに
     * 誰かが消したときなど)。失敗はすべて「そこで打ち切り」に倒す。
     */
    let stoppedEarly = false;
    // 1ページだけの回は繰らない（続きは画面が `nextOffset` から頼む）。
    if (!paged && typeof count === "number") {
      const want = Math.min(count, STICKER_TOTAL_CAP);
      while (acc.length < want) {
        const next = await pageWithJwtClockSkewRetry(cols, acc.length, false);
        if (next.error) {
          stoppedEarly = true;
          break;
        }
        const rows = (next.data ?? []) as unknown[];
        if (rows.length === 0) {
          stoppedEarly = acc.length < want;
          break;
        }
        // 並びがずれて同じ行が再度来ても二重に積まない。
        for (const r of rows) {
          const id = (r as { id: string }).id;
          if (seen.has(id)) continue;
          seen.add(id);
          acc.push(r);
        }
      }
    }
    const data = acc as typeof first.data;
    // 絞り（言語・見出しの字）を掛ける**前**の行数。次のページの始まりはこの数で決める。
    const rawCount = acc.length;
    const nextOffset =
      paged &&
      rawCount >= firstSize &&
      firstFrom + rawCount < STICKER_TOTAL_CAP &&
      (typeof count !== "number" || firstFrom + rawCount < count)
        ? firstFrom + rawCount
        : null;

    type RowShape = {
      id: string;
      word_id: string;
      caption: string | null;
      location_name: string | null;
      lat: number | null;
      lng: number | null;
      taken_at: string;
      created_at: string;
      object_image_url: string | null;
      cutout_image_url: string | null;
      selfie_image_url: string | null;
      hero_role?: string | null;
      album_order?: number | null;
      album_size?: StickerWithWord["album_size"];
      album_x?: number | null;
      album_y?: number | null;
      album_scale?: number | null;
      album_rot?: number | null;
      capture_type?: string | null;
      placeholder_image_url?: string | null;
      placeholder_credit?: PlaceholderCredit | null;
      shelf_key?: string | null;
      words: (Omit<StickerWithWord["word"], "extras"> & { extras?: unknown }) | null;
    };
    let rows = (data ?? []) as unknown as RowShape[];
    // **絞りを DB で掛けられなかったときの受け皿。** 同じ規則を
    // `language-filter.ts` の1箇所から読むので、DB と画面で判断が
    // 食い違うことがない。DB で絞れているときは何も落ちない。
    if (!filterInDb) {
      rows = rows.filter((r) => matchesTargetLanguage(r.words?.language, targetLanguage));
    }
    // 総数は最初のページが返した `count`。
    //
    // **`count` が取れなかったときの上限は「1ページ分」。** ここを天井
    // (3000)にしていたせいで、1000件だけ受け取って `truncated: false` に
    // なる道が残っていた — この周で潰したはずの「黙って途中で止まる」が、
    // 細い経路で生き残っていた。
    const total = typeof count === "number" ? count : null;
    // 1ページだけの回は、途中まで読んだかを画面が決める（全部のページを読み終えた時）。
    const truncated =
      !paged &&
      (stoppedEarly ||
        isTruncated(total, rows.length, total == null ? STICKER_PAGE_SIZE : STICKER_TOTAL_CAP));
    /**
     * **学習言語の字でない見出し語の札は出さない**（オーナー報告 2026-10-02
     * 「英語の図鑑にノートが出る。言語が混ざってる」）。言語の列は `en` でも、
     * 見出しが「ノート」「拿鐵」の行が既にある（保存の関所が無かった頃の物）。
     * 札も行も消さない — 見せないだけ。判定は `language-filter.ts` の1つ。
     * 「途中まで」の判定（上の `truncated`）は**隠す前の数**で済ませてある
     * — 隠した数を「読み切れなかった」と取り違えない。
     */
    rows = rows.filter((r) => headwordMatchesTarget(r.words?.headword, targetLanguage));
    // Also sign the `${path}.thumb.webp` companions (uploaded since 2026-07).
    // Missing thumbs (old stickers) simply return error rows and drop out of
    // the map — the client falls back to the full image.
    const thumbOf = (p: string | null | undefined) => (p ? `${p}.thumb.webp` : null);
    const [urlMap, counts] = await Promise.all([
      signUrlMap(
        supabase,
        rows.flatMap((r) => [
          r.object_image_url,
          r.cutout_image_url,
          r.selfie_image_url,
          r.placeholder_image_url,
          thumbOf(r.object_image_url),
          thumbOf(r.cutout_image_url),
        ]),
      ),
      encounterCounts(
        supabase,
        rows.map((r) => r.id),
      ),
    ]);

    const result: StickerWithWord[] = [];
    for (const row of rows) {
      const wRaw = row.words;
      if (!wRaw) continue;
      result.push({
        id: row.id,
        word_id: row.word_id,
        shelf_key: row.shelf_key ?? null,
        /** 長押しで決めた主役。**一覧にも効かせる** —
            詳細でだけ効くと「変えたのに図鑑では変わらない」になる。 */
        hero_role: row.hero_role ?? null,
        album_order: row.album_order ?? null,
        album_size: row.album_size ?? null,
        album_x: row.album_x ?? null,
        album_y: row.album_y ?? null,
        album_scale: row.album_scale ?? null,
        album_rot: row.album_rot ?? null,
        caption: row.caption,
        location_name: row.location_name,
        lat: row.lat,
        lng: row.lng,
        taken_at: row.taken_at,
        created_at: row.created_at,
        encounter_count: counts.get(row.id) ?? 0,
        object_url: row.object_image_url ? (urlMap.get(row.object_image_url) ?? null) : null,
        cutout_url: row.cutout_image_url ? (urlMap.get(row.cutout_image_url) ?? null) : null,
        selfie_url: row.selfie_image_url ? (urlMap.get(row.selfie_image_url) ?? null) : null,
        object_thumb_url: row.object_image_url
          ? (urlMap.get(`${row.object_image_url}.thumb.webp`) ?? null)
          : null,
        cutout_thumb_url: row.cutout_image_url
          ? (urlMap.get(`${row.cutout_image_url}.thumb.webp`) ?? null)
          : null,
        capture_type: row.capture_type ?? "photo",
        placeholder_url: row.placeholder_image_url
          ? (urlMap.get(row.placeholder_image_url) ?? null)
          : null,
        placeholder_credit: row.placeholder_credit ?? null,
        // 一覧では読みは付けない（枚数が多い）。退役した欄だけ外す。
        word: { ...wRaw, extras: publicExtras(wRaw.extras) },
      });
    }
    /**
     * **他の学習言語に何枚あるか。**
     *
     * 学習言語を英語に変えた人の図鑑は空になる（指示どおり）。でも
     * そこに「まだ何もキャッチしていません」と出すのは**嘘**で、
     * その人は150枚持っている。集めた物が消えたように見える画面は
     * この作業場で一番やってはいけない壊し方なので、
     * **他の言語に何枚あるかを数えて画面に渡す。**
     *
     * 数えられなくても画面は出す（飾りなので `null` に倒す）。
     */
    let otherLanguages: number | null = null;
    if (filterInDb && firstFrom === 0) {
      const all = await supabase
        .from("stickers")
        .select("id", { count: "exact", head: true })
        .eq("user_id", userId);
      if (!all.error && typeof all.count === "number" && typeof total === "number") {
        otherLanguages = Math.max(0, all.count - total);
      }
    }
    /**
     * **再会の写真**（ホームのアルバムに貼る。`lib/album-encounters.ts`）。
     * 直近 120 日・500 枚まで。読めなくても一覧は返す（飾りなので空に倒す）。
     */
    let albumEncounters: AlbumEncounter[] = [];
    // 1ページだけの回は最初のページでだけ返す。札がどのページにあるか分からないので、
    // **札で絞るのは画面**（全部のページを合わせた一覧で、`lib/sticker-pages.ts`）。
    if (!paged || firstFrom === 0)
      try {
        const ids = new Set(result.map((r) => r.id));
        const since = new Date(Date.now() - 120 * 86_400_000).toISOString();
        const { data: encRows, error: encErr } = await supabase
          .from("encounters")
          .select("id, sticker_id, created_at, location_name, lat, lng, image_path, cutout_path")
          .eq("user_id", userId)
          .gte("created_at", since)
          .order("created_at", { ascending: false })
          .limit(500);
        if (!encErr && encRows) {
          const withPhoto = encRows.filter(
            (e) => (paged || ids.has(e.sticker_id)) && (e.image_path || e.cutout_path),
          );
          const encUrls = await signUrlMap(
            supabase,
            withPhoto.flatMap((e) => [e.image_path, e.cutout_path, thumbOf(e.image_path)]),
          );
          albumEncounters = withPhoto
            .map((e) => ({
              id: e.id,
              sticker_id: e.sticker_id,
              created_at: e.created_at,
              location_name: e.location_name ?? null,
              lat: e.lat ?? null,
              lng: e.lng ?? null,
              image_url:
                (e.image_path ? encUrls.get(e.image_path) : undefined) ??
                (e.cutout_path ? encUrls.get(e.cutout_path) : undefined) ??
                "",
              thumb_url: e.image_path ? (encUrls.get(`${e.image_path}.thumb.webp`) ?? null) : null,
            }))
            .filter((e) => e.image_url);
        }
      } catch {
        albumEncounters = [];
      }
    return {
      items: result,
      truncated,
      total,
      targetLanguage,
      otherLanguages,
      albumEncounters,
      // 1ページだけの回: 次のページの始まり（無ければ null）と、絞る前に読んだ行数。
      nextOffset,
      rawCount,
    };
  });

export const getSticker = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => z.object({ id: z.string().uuid() }).parse(input))
  .handler(async ({ context, data }) => {
    const { supabase, userId } = context;
    // `hero_role` は別の段にする。**ゴーストの列と一緒くたにしない** —
    // 一緒にすると、`hero_role` の移行だけ当たっていない環境で
    // ネット画像(placeholder)まで丸ごと落ちる。無い列だけを諦める。
    const cols = (withGhost: boolean, withHero: boolean) =>
      `id, user_id, word_id, caption, location_name, lat, lng, taken_at, created_at, object_image_url, cutout_image_url, selfie_image_url${withHero ? ", hero_role" : ""}${shelfCol ? ", shelf_key" : ""}${withGhost ? ", capture_type, placeholder_image_url, placeholder_credit, branch_plan" : ""}, words(headword, language, reading_zhuyin, pinyin, meaning_ja, part_of_speech, example_sentence, example_translation, level, category_key, silhouette_emoji, extras)`;

    // Try to read as owner first (RLS-scoped); retry without ghost columns
    // when the migration hasn't been applied.
    let heroCols = true;
    let ghostCols = true;
    // 写真ごとのカテゴリー（2026-09-27 から詳細で変えられる）。これも**別の段**。
    let shelfCol = true;
    const read = () =>
      supabase
        .from("stickers")
        .select(cols(ghostCols, heroCols))
        .eq("id", data.id)
        .eq("user_id", userId)
        .maybeSingle();
    let { data: row, error } = await read();
    if (error && /shelf_key/.test(error.message)) {
      shelfCol = false;
      ({ data: row, error } = await read());
    }
    // **無い列だけを諦める。** 列が無いときは `data: null` ではなく
    // **error** が返る(以前ここを `!row` で判定して外した)。
    if (error && /hero_role/.test(error.message)) {
      heroCols = false;
      ({ data: row, error } = await read());
    }
    if (error && /capture_type|placeholder|branch_plan/.test(error.message)) {
      ghostCols = false;
      ({ data: row, error } = await read());
    }
    if (error) throw new Error(error.message);

    /**
     * **自分の札だけ**（監査 2026-10-03）。前は自分の札でなければ、その札を載せた投稿
     * （`posts.sticker_id`）を探して管理者の鍵で読んでいた。投稿の持ち主と札の持ち主を
     * 突き合わせていなかったので、他人の札の番号を自分の投稿に書けば、その札の写真まで
     * 読めた。投稿（ソーシャル）は 2026-10-01 の整理で画面ごと消えていて、この道を
     * 使う画面はもう無い — 道ごと消した。
     */
    if (!row) return null;
    type StickerRow = {
      id: string;
      /** 主役の絵。移行が当たっていない環境では届かない。 */
      hero_role?: string | null;
      /** 写真ごとに移したカテゴリー。 */
      shelf_key?: string | null;
      user_id: string;
      word_id: string;
      caption: string | null;
      location_name: string | null;
      lat: number | null;
      lng: number | null;
      taken_at: string;
      created_at: string;
      object_image_url: string | null;
      cutout_image_url: string | null;
      selfie_image_url: string | null;
      capture_type?: string | null;
      placeholder_image_url?: string | null;
      placeholder_credit?: PlaceholderCredit | null;
      branch_plan?: unknown;
      words: (Omit<StickerWithWord["word"], "extras"> & { extras?: unknown }) | null;
    };
    const r = row as unknown as StickerRow;

    // §6 word tree: unlock count = completed reviews (monotonic).
    const { count: reviewCountRaw } = await supabase
      .from("review_history")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId)
      .eq("sticker_id", r.id);
    const reviewCount = reviewCountRaw ?? 0;
    const [urlMap, counts] = await Promise.all([
      signUrlMap(supabase, [
        r.object_image_url,
        r.cutout_image_url,
        r.selfie_image_url,
        r.placeholder_image_url ?? null,
      ]),
      encounterCounts(supabase, [r.id]),
    ]);

    const wRaw = r.words;
    if (!wRaw) return null;
    const res: StickerWithWord = {
      id: r.id,
      word_id: r.word_id,
      caption: r.caption,
      location_name: r.location_name,
      lat: r.lat,
      lng: r.lng,
      taken_at: r.taken_at,
      created_at: r.created_at,
      encounter_count: counts.get(r.id) ?? 0,
      object_url: r.object_image_url ? (urlMap.get(r.object_image_url) ?? null) : null,
      cutout_url: r.cutout_image_url ? (urlMap.get(r.cutout_image_url) ?? null) : null,
      selfie_url: r.selfie_image_url ? (urlMap.get(r.selfie_image_url) ?? null) : null,

      // Detail view always shows the full-resolution image.
      object_thumb_url: null,
      cutout_thumb_url: null,
      capture_type: r.capture_type ?? "photo",
      /** null なら設定に従う。**知らない値も素通しでよい** —
          `pickStickerPhoto` の `prefer` が既定の順に落としてくれる。 */
      hero_role: r.hero_role ?? null,
      shelf_key: r.shelf_key ?? null,
      /** 自分の札か（カテゴリーを変える道は持ち主にだけ出す）。 */
      is_owner: true,
      placeholder_url: r.placeholder_image_url
        ? (urlMap.get(r.placeholder_image_url) ?? null)
        : null,
      placeholder_credit: r.placeholder_credit ?? null,
      branch_plan: (r.branch_plan as StickerWithWord["branch_plan"]) ?? null,
      review_count: reviewCount,
      // 退役した欄（口語/書面の札）は返さない。台湾華語の型の札には読み（拼音・注音）を付けて返す —
      // 古いカードは読みを持っていないので、読む所で辞書から付ける（`chunk-readings.server.ts`）。
      word: {
        ...wRaw,
        extras: await withReadingsOnRead(
          publicExtras(wRaw.extras),
          (wRaw as { language?: string | null }).language ?? null,
        ),
      },
    };
    return res;
  });

/**
 * ひと言の長さの上限（撮影画面の欄・アルバムの表示と同じ数を共有する）。
 * 保存の入力（`SaveStickerInput`）でも使うので、それより上に置く。
 */
export const CAPTION_MAX = 500;

const SaveStickerInput = z.object({
  client_catch_id: z.string().uuid().optional(),
  // 語の形と上限は `shared-word-guard.ts`（文字・声のキャッチと同じ物）。
  word: WordInputSchema,
  /**
   * AI が「どの棚にも当てはまらない」と判断したときの新しい棚。
   * 形は信用しない — `normalizeShelfProposal` で直すか諦める（長すぎる値も諦める）。
   */
  new_shelf: z
    .object({
      key: z.string().max(64).optional().catch(undefined),
      label: z.string().max(64).optional().catch(undefined),
      emoji: z.string().max(32).optional().catch(undefined),
      room_key: z.string().max(64).optional().catch(undefined),
      room_label: z.string().max(64).optional().catch(undefined),
    })
    .nullish()
    .catch(null),
  language: LanguageCodeSchema,
  object_path: z.string().max(STORAGE_PATH_MAX).nullable().optional(),
  cutout_path: z.string().max(STORAGE_PATH_MAX).nullable().optional(),
  selfie_path: z.string().max(STORAGE_PATH_MAX).nullable().optional(),
  caption: z.string().max(CAPTION_MAX).nullable().optional(),
  location_name: z.string().max(LOCATION_NAME_MAX).nullable().optional(),
  lat: z.number().nullable().optional(),
  lng: z.number().nullable().optional(),
});

export type WordUpsertInput = z.infer<typeof SaveStickerInput>["word"] & {
  entry_type?: "word" | "phrase";
};

/** 共有の解説が、その言語で書かれているか（目印が空なら古いデータ = 日本語）。 */
function sharedExtrasInLang(raw: unknown, lang: string): boolean {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return false;
  const v = (raw as Record<string, unknown>).explain_lang;
  return ((typeof v === "string" && v.trim()) || "ja") === lang;
}

/** 一意の制約に当たった（同じ行が既に在る）か。 */
function isUniqueViolation(error: { code?: string; message?: string } | null | undefined): boolean {
  if (!error) return false;
  return error.code === "23505" || /duplicate key|unique constraint/i.test(error.message ?? "");
}

/**
 * 新しい共有の語の行に入れる中身を決める（監査 2026-10-03 M3）。
 *
 * 1. サーバの控え（`generated_cards`）— `generateCard` のカード全体を候補より優先
 * 2. 辞書（`dictionary_entries`）— 読みと、その人の解説の言語の意味・品詞
 * 3. どちらも無ければ空（見出しだけ）
 *
 * **画面の送った文（意味・例文・級・解説）は使わない。** 例外は控えの表がまだ無い環境
 * （移行待ち）だけで、そのときは前の動きのまま送られた物を入れる。
 */
export async function newSharedWordContent(
  admin: unknown,
  userId: string,
  word: WordUpsertInput,
  language: string,
): Promise<{
  columns: Partial<Record<SharedWordColumn, string>>;
  extras: Record<string, unknown>;
  categoryKey: string | null;
  from: "card" | "candidate" | "dictionary" | "client" | "none";
}> {
  // 共有の意味は「最初に作った人の言語」で入る（`ARCHITECTURE.md`）。その人の解説の言語の
  // カードがあればそれを先に使う。
  let explainLang: string | undefined;
  try {
    explainLang = await getExplanationLanguage(userId);
  } catch {
    explainLang = undefined;
  }
  const lookup = await findGeneratedCard(admin, {
    language,
    headword: word.headword,
    preferExplainLang: explainLang,
  });
  if (!lookup.available) {
    console.warn("upsertWord: 控えの表がまだ無い — 送られた中身で新しい語を作る");
    return {
      columns: sharedColumnsFromCard(word as unknown as Record<string, unknown>),
      extras: (word.extras ?? {}) as Record<string, unknown>,
      categoryKey: null,
      from: "client",
    };
  }
  if (lookup.card) {
    const card: TrustedCard = lookup.card;
    return {
      columns: sharedColumnsFromCard(card as Record<string, unknown>),
      extras: card.extras ?? {},
      categoryKey: card.category_key ?? null,
      from: lookup.kind ?? "card",
    };
  }
  try {
    const db = admin as {
      from: (t: string) => {
        select: (c: string) => {
          eq: (
            k: string,
            v: string,
          ) => {
            eq: (
              k: string,
              v: string,
            ) => {
              limit: (n: number) => PromiseLike<{
                data: Array<RawDictionaryRow & { pos?: string | null }> | null;
                error: { message: string } | null;
              }>;
            };
          };
        };
      };
    };
    const { data: rows, error } = await db
      .from("dictionary_entries")
      .select(DICTIONARY_SELECT)
      .eq("language", language)
      .eq("headword", word.headword)
      .limit(1);
    const entry = !error ? rows?.[0] : undefined;
    if (entry) {
      const f = resolveDictionaryFields(entry, explainLang ?? "ja");
      return {
        columns: sharedColumnsFromCard({
          meaning_ja: f.meaning,
          reading_zhuyin: f.reading ?? "",
          pinyin: f.readingAlt ?? "",
          part_of_speech: entry.pos ?? "",
        }),
        extras: {},
        categoryKey: null,
        from: "dictionary",
      };
    }
    if (error) console.warn("upsertWord: 辞書を引けない", error.message);
  } catch (e) {
    console.warn("upsertWord: 辞書を引けない", e instanceof Error ? e.message : e);
  }
  return { columns: {}, extras: {}, categoryKey: null, from: "none" };
}

/**
 * Shared word upsert: find by (language, headword) or insert as source='ai'.
 * Used by both photo catches (saveSticker) and ghost catches (§5.2/5.3).
 */
export async function upsertWord(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  supabase: any,
  userId: string,
  word: WordUpsertInput,
  language: string,
): Promise<string> {
  /**
   * **学習言語の字でない見出し語は、行を作る前に止める**（オーナー報告
   * 2026-10-02「英語の図鑑にノート」「英語の復習に拿鐵の4択」）。
   *
   * ここは写真のキャッチ（`saveSticker`）・文字と声のキャッチ
   * （`saveGhostSticker`）・見出しの直し（`setStickerHeadword`）・iOS 版の
   * `/api/native-fn` が**全部通る1本道**。画面の側の関所は道ごとに書くので
   * 1本でも書き忘れると母語や別の言語の語が共有の `words` に入り、
   * その行は `(language, headword)` で全員に見える。
   *
   * 既存の行を探す前に止める — 既に入ってしまった「ノート/en」の行に
   * 新しい札を足すのも、同じ混ざりを増やすだけ。
   * 言語は付け替えない・見出しも直さない（`assertTargetHeadword` の注）。
   */
  assertTargetHeadword(word.headword, language);
  const findExisting = async (): Promise<string | undefined> => {
    const { data: existing } = await supabase
      .from("words")
      .select("id")
      .eq("language", language)
      .eq("headword", word.headword)
      .maybeSingle();
    return (existing?.id as string | undefined) ?? undefined;
  };

  let wordId: string | undefined = await findExisting();
  if (!wordId) {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    /**
     * **新しい語の行の中身は、サーバが作った物だけ**（監査 2026-10-03 M3）。
     *
     * 前は画面の送った意味・例文・級・解説をそのまま、サーバの権限で共有の行に入れていた。
     * 最初に保存した人の文が、後から同じ語を撮る全員のカードになる。いまは
     * `newSharedWordContent` が、サーバの控え（`generateCard` / 候補）→ 辞書 の順に
     * 中身を決める。どちらも無ければ見出しだけの行を作り、`generateCard` が作り終えた
     * 時（`fillSharedWordFromCard`）と単語の詳細の自動生成が空の所を埋める
     * （見出しの直し `setStickerHeadword` と同じ形）。
     */
    const content = await newSharedWordContent(supabaseAdmin, userId, word, language);
    // カテゴリー正規化(2026-07-23の不具合修正):
    // 以前はここで「categories 表に無いキー→ other」に落とすだけだった。
    // 表には20キーしか無くコードは54キーを使っていたため、body/kitchenware/
    // medicine 等に分類された語がすべて「その他」に潰れていた。
    // いまは (1) 見出し語から確実に補正 → (2) それでも表に無ければ other、の順。
    // 表の不足キーは 20260723090000_seed_missing_categories.sql で投入済み。
    // 棚の鍵は決まった一覧の中の値なので、画面の送った物も使ってよい（文ではない）。
    let categoryKey: string = normalizeCategory(
      word.headword,
      content.categoryKey || word.category_key,
    );
    const { data: catRow } = await supabase
      .from("categories")
      .select("key")
      .eq("key", categoryKey)
      .maybeSingle();
    if (!catRow) categoryKey = "other";

    const cols = content.columns;
    const row = {
      language,
      headword: word.headword,
      reading_zhuyin: cols.reading_zhuyin || null,
      pinyin: cols.pinyin || null,
      // 列は空を許さない。中身が無ければ空の文字列（空の行は後から埋まる）。
      meaning_ja: cols.meaning_ja ?? "",
      part_of_speech: cols.part_of_speech || null,
      level: cols.level || null,
      category_key: categoryKey,
      example_sentence: cols.example_sentence || null,
      example_translation: cols.example_translation || null,
      extras: content.extras as never,
      source: "ai",
      entry_type: word.entry_type ?? "word",
    };
    /**
     * **共有の語はサーバの権限で足す**（2026-10-01）。words は全員が同じ行を見るので、
     * ブラウザの権限で足せると、アプリを通さずに中身を決めた行を先に置けてしまう
     * （後から同じ語を撮った人は全員その行を見る）。足した人は `created_by` に残す
     * （DB の `enforce_words_source` は auth.uid() が空のとき渡した値を使う）。
     * ブラウザの追加口は閉じてある
     * （`supabase/migrations/20261001100200_words_server_only_insert.sql`、本番に 2026-10-02 適用）。
     */
    const rowWithOwner = { ...row, created_by: userId };
    let ins = await supabaseAdmin
      .from("words")
      .insert(rowWithOwner as never)
      .select("id")
      .single();
    if (ins.error && /entry_type/.test(ins.error.message)) {
      const { entry_type: _entryType, ...withoutEntryType } = rowWithOwner;
      ins = await supabaseAdmin
        .from("words")
        .insert(withoutEntryType as never)
        .select("id")
        .single();
    }
    /**
     * **同じ新しい語を2人が同時に初めて撮った**（監査 2026-10-03 M4）。探してから足すまでの
     * 間に相手の行が入ると、`(language, headword)` の一意の制約で落ちる。落ちたのは
     * 「もう在る」という意味なので、探し直してその行を使う（キャッチは失敗させない）。
     */
    if (ins.error && isUniqueViolation(ins.error)) {
      const raced = await findExisting();
      if (raced) return raced;
    }
    if (ins.error) throw new Error(ins.error.message);
    wordId = ins.data.id as string;

    // Pre-generate quiz distractors off the review path. Reviews fall back to the
    // user's own deck when this hasn't landed.
    // **Workers で黙って捨てられないよう、返事の後まで預ける**（`after-response.ts`、L5）。
    // 正解の意味は**共有の行に入れた物**（画面の送った文はプロンプトにも入れない）。
    // **iOS で保存した語では作らない**（2026-10-14）。iOS の4択は「意味を見て語を選ぶ」形で、
    // ここで作る誤答（＝間違った意味）を使わない。誤答はその人の語と、アプリに入っている
    // 日常の語（`QuizPool.swift`、同じ分類から）で作るので、撮った語が少ない人でも4択になる。
    if (row.meaning_ja.trim() && !(await isNativeRequest())) {
      const newId = wordId;
      await runAfterResponse("pregenerateDistractors", () =>
        pregenerateDistractors(
          supabase,
          userId,
          newId,
          word.headword,
          row.meaning_ja,
          categoryKey,
          // 学習言語を渡す(誤答の指示文で「◯◯の単語」と呼ぶため。2026-10-01)。
          language,
        ),
      );
    }
  } else if (word.extras && hasExtrasContent(word.extras)) {
    // Fill extras for an existing word when the AI generated rich ones.
    //
    // The words UPDATE RLS policy only covers source='ai', so writing through
    // the user client silently updated 0 rows for verified dictionary words —
    // that is why a caught TOCFL word showed only 意味 + 例文 and none of the
    // rich sections (コロケーション/類義語/語源/覚え方…): its extras never
    // persisted. Write via the service role instead, and — like reportWordIssue,
    // keeping constitution §2-1 intact — only ever touch the `extras` supplement
    // (the UI already labels it AI-generated), never verified base fields.
    //
    // **空の項目だけ埋める**（監査 2026-10-03）。中身は**サーバの控え**から取る
    // （画面の送った物は、控えの表がまだ無い環境でだけ使う。`newSharedWordContent` と同じ）。
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const lookup = await findGeneratedCard(supabaseAdmin, {
      language,
      headword: word.headword,
    });
    const incoming = lookup.available
      ? (lookup.card?.extras ?? null)
      : (word.extras as unknown as Record<string, unknown>);
    if (incoming) {
      const { data: cur } = await supabaseAdmin
        .from("words")
        .select("extras")
        .eq("id", wordId)
        .maybeSingle();
      const filled = fillEmptySharedExtras(cur?.extras, incoming);
      if (filled) {
        await supabaseAdmin
          .from("words")
          .update({ extras: filled as never })
          .eq("id", wordId);
      }
    }
  }
  return wordId;
}

/**
 * AI が出した棚の提案を、その人の棚として確保する。**戻り値は棚の鍵か null。**
 *
 * ここは**絶対に投げない**。棚は「あれば嬉しい」もので、
 * 作れなかったからといって語のキャッチを失敗させる理由が無い。
 * 失敗の道は全部 null に畳んで、語は既定の54棚のどれかに載る。
 *
 * 同じ鍵が既に在れば作り直さない(`unique (user_id, key)`)。
 * 名前や絵文字の上書きもしない — 一度できた棚の名前が、次に似た語を
 * 取った瞬間に変わると、棚を目印にしている人の手がかりが消える。
 */
async function ensureUserShelf(
  supabase: unknown,
  userId: string,
  raw: RawShelfProposal | null | undefined,
): Promise<string | null> {
  const proposal = normalizeShelfProposal(raw);
  if (!proposal) return null;
  try {
    const client = supabase as unknown as {
      from: (t: string) => {
        upsert: (
          v: Record<string, unknown>,
          o: { onConflict: string; ignoreDuplicates: boolean },
        ) => Promise<{ error: { message: string } | null }>;
      };
    };
    const { error } = await client.from("user_shelves").upsert(
      {
        user_id: userId,
        key: proposal.key,
        label: proposal.label,
        emoji: proposal.emoji,
        room_key: proposal.room_key,
        // 既定の8部屋なら、部屋の名前は i18n から出す。AI の文言を入れると
        // 「食べる」が人によって「食事」になり、同じ部屋が2つの名前で出る。
        room_label: isBuiltinRoom(proposal.room_key) ? proposal.room_key : proposal.room_label,
      },
      { onConflict: "user_id,key", ignoreDuplicates: true },
    );
    if (error) {
      console.warn(
        "[shelf] could not create the shelf, falling back to the word's own category",
        error.message,
      );
      return null;
    }
    return proposal.key;
  } catch (e) {
    console.warn("[shelf] could not create the shelf", e);
    return null;
  }
}

/** その人の棚。図鑑の並びに使う。 */
export const listMyShelves = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const { supabase, userId } = context;
    try {
      const client = supabase as unknown as {
        from: (t: string) => {
          select: (c: string) => {
            eq: (
              k: string,
              v: string,
            ) => {
              order: (
                c: string,
                o: { ascending: boolean },
              ) => Promise<{ data: UserShelf[] | null; error: { message: string } | null }>;
            };
          };
        };
      };
      const { data, error } = await client
        .from("user_shelves")
        .select("key, label, emoji, room_key, room_label")
        .eq("user_id", userId)
        .order("created_at", { ascending: true });
      // 棚が読めなくても図鑑は出す。**既定の54棚だけで成立する。**
      if (error) return { shelves: [] as UserShelf[] };
      return { shelves: data ?? [] };
    } catch {
      return { shelves: [] as UserShelf[] };
    }
  });

/** `reuseOwnedSticker` が使う所だけの形（試験では手元の偽物を渡す）。 */
type ReuseClient = {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  from: (table: string) => any;
};

/**
 * その人が**同じ語の札をもう持っていれば**、その札に再会を1回書き足して札の id を返す
 * （`recordEncounter` と同じ形: `encounters` に1行、札の `encounter_count` を1つ増やす。
 * 復習の間隔は動かさない）。持っていない・書けなかった時は null（呼ぶ側が新しい札を作る）。
 */
export async function reuseOwnedSticker(
  supabase: ReuseClient,
  userId: string,
  wordId: string,
  enc: {
    image_path: string | null;
    cutout_path: string | null;
    lat: number | null;
    lng: number | null;
    location_name: string | null;
  },
): Promise<string | null> {
  try {
    const { data: owned, error } = await supabase
      .from("stickers")
      .select("id, encounter_count")
      .eq("user_id", userId)
      .eq("word_id", wordId)
      .order("created_at", { ascending: true })
      .limit(1)
      .maybeSingle();
    if (error || !owned?.id) return null;
    const ins = await supabase.from("encounters").insert({
      user_id: userId,
      sticker_id: owned.id,
      recalled: null,
      lat: enc.lat,
      lng: enc.lng,
      location_name: enc.location_name,
      image_path: enc.image_path,
      cutout_path: enc.cutout_path,
    });
    // 写真をどこにも結び付けられないまま「保存した」とは言わない — 新しい札に回す。
    if (ins?.error) return null;
    await bumpEncounterCount(supabase, userId, owned.id as string, owned.encounter_count ?? 0);
    return owned.id as string;
  } catch {
    return null;
  }
}

/**
 * 保存を**もう持っている札の再会**にしてよいか。
 *
 * **ひと言・自撮りがある回は、再会にしない**（新しい札を作る — 今までの形）。
 * 再会の行（`encounters`）にはひと言・自撮りの列が無い。再会にすると、書いたひと言は
 * 捨てられ、アップロード済みの自撮りはどこからも指されないまま残っていた。
 * 同じ語の札が2枚になる方が、書いた物が消えるよりずっと軽い（図鑑は言葉ごとにまとめる）。
 * 初めてのキャッチの引き継ぎ（`client_catch_id`）も、決めた id の札を作るので再会にしない。
 */
export function mayReuseOwnedSticker(
  data: { client_catch_id?: string | null; caption?: string | null; selfie_path?: string | null },
  userId: string,
): boolean {
  if (data.client_catch_id) return false;
  if (data.caption?.trim()) return false;
  // 自分のフォルダの自撮りだけが保存される（`ownPath`）。それ以外は元々捨てる物。
  if (data.selfie_path && data.selfie_path.startsWith(`${userId}/`)) return false;
  return true;
}

/** 数え直しを繰り返す上限（同じ札へ同時に再会が書かれた時だけ回る）。 */
const ENCOUNTER_BUMP_TRIES = 3;

/**
 * 札の `encounter_count` を1つ増やす。**結果を見る**（前は更新の失敗を黙って捨てていた —
 * 再会の行は在るのに「×N」が増えない札になる）。
 *
 * 数を足す RPC は無いので、**読んだ値のままの時だけ書く**（`eq("encounter_count", 前の値)`）。
 * 同時に別の再会が書いて1行も当たらなければ、読み直して数回やり直す。それでも書けない・
 * 失敗した時は記録に残して諦める（再会の行と写真はもう結び付いているので、札は使う）。
 */
export async function bumpEncounterCount(
  supabase: ReuseClient,
  userId: string,
  stickerId: string,
  seen: number,
): Promise<boolean> {
  let current = seen;
  for (let i = 0; i < ENCOUNTER_BUMP_TRIES; i++) {
    const { data, error } = await supabase
      .from("stickers")
      .update({ encounter_count: current + 1 })
      .eq("id", stickerId)
      .eq("user_id", userId)
      .eq("encounter_count", current)
      .select("id");
    if (error) {
      console.warn("encounter_count の更新に失敗", error.message);
      return false;
    }
    if (Array.isArray(data) && data.length > 0) return true;
    // 1行も当たらない = 読んだ後に誰かが数を変えた。読み直して、もう一度。
    const again = await supabase
      .from("stickers")
      .select("encounter_count")
      .eq("id", stickerId)
      .eq("user_id", userId)
      .maybeSingle();
    if (again.error || !again.data) {
      console.warn("encounter_count を読み直せない", again.error?.message);
      return false;
    }
    current = again.data.encounter_count ?? 0;
  }
  console.warn("encounter_count を書けないまま諦めた", stickerId);
  return false;
}

export const saveSticker = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => SaveStickerInput.parse(input))
  .handler(async ({ context, data }) => {
    const { supabase, userId } = context;

    // Stable ID makes first-Catch transfer safe after OAuth reload / retries.
    if (data.client_catch_id) {
      const { data: existing, error } = await supabase
        .from("stickers")
        .select("id, word_id")
        .eq("id", data.client_catch_id)
        .eq("user_id", userId)
        .maybeSingle();
      if (error) throw new Error(error.message);
      if (existing) return { id: existing.id, word_id: existing.word_id, first_catch: false };
    }
    /**
     * 語の登録と棚の用意は**互いを待たない**ので並べて走らせる
     * （オーナー報告 2026-09-22「祝福の演出が…4秒位停止してる」— 演出は
     * この保存が返るまで次へ進めない。直列だと往復がそのまま足し算になる）。
     *
     * 棚は、その人だけの棚。**失敗しても語のキャッチは通す。**
     * 棚が1つ増えないことと、キャッチが丸ごと失敗することは重さが違う。
     */
    const [wordId, shelfKey] = await Promise.all([
      upsertWord(supabase, userId, data.word, data.language),
      ensureUserShelf(supabase, userId, data.new_shelf),
    ]);

    // Guard against cross-account storage path spoofing: only accept paths
    // rooted under the caller's own uid folder (the client upload convention).
    const ownPath = (p: string | null | undefined): string | null => {
      if (!p) return null;
      return p.startsWith(`${userId}/`) ? p : null;
    };

    /**
     * **もう持っている言葉なら、新しい札を作らずその札の再会にする**（オーナー報告 2026-10-08
     * 「文字検索したら同じ単語でも同じものとしてカウントされてない」）。
     *
     * 画面は保存の前に「もう持っている語か」を確かめる（`checkOwnedWord`）が、確かめるのは
     * **打った・選んだ見出し語**で、カードを作った後に見出し語が学習言語の語へ直される
     * （`adoptResolvedHead`、例: 猫 → 貓）と、直した後の語はもう確かめられずに保存へ来る。
     * 同じ言葉の札が2枚でき、図鑑に「貓」が2つ並んでいた。共有の語の行は
     * `(language, headword)` で1つなので、**その人の同じ語の札**をここで見つけて使う。
     * 再会の記録が書けない環境（表・列がまだ無い）では、今までどおり新しい札を作る。
     */
    // ひと言・自撮りがある回は再会にしない（`mayReuseOwnedSticker`）。
    if (mayReuseOwnedSticker(data, userId)) {
      const reused = await reuseOwnedSticker(supabase, userId, wordId, {
        image_path: ownPath(data.object_path),
        cutout_path: ownPath(data.cutout_path),
        lat: data.lat ?? null,
        lng: data.lng ?? null,
        location_name: data.location_name ?? null,
      });
      if (reused) return { id: reused, word_id: wordId, first_catch: false, reencounter: true };
    }

    // §6 word tree: freeze the branch plan at save time so later extras
    // regenerations don't reshuffle already-unlocked branches.
    const branchPlan = buildBranchPlan(data.word.extras);
    const baseRow = {
      ...(data.client_catch_id ? { id: data.client_catch_id } : {}),
      user_id: userId,
      word_id: wordId,
      language: data.language,
      object_image_url: ownPath(data.object_path),
      cutout_image_url: ownPath(data.cutout_path),
      selfie_image_url: ownPath(data.selfie_path),
      caption: data.caption ?? null,
      location_name: data.location_name ?? null,
      lat: data.lat ?? null,
      lng: data.lng ?? null,
      // 型定義は生成物で、`shelf_key` はそれより新しい列。
      // `current_level` のときと同じで、緩いクライアントとして扱う。
      ...(shelfKey ? { shelf_key: shelfKey } : {}),
    } as Record<string, unknown>;
    let res = await supabase
      .from("stickers")
      .insert({ ...baseRow, branch_plan: branchPlan } as never)
      .select("id")
      .single();
    if (res.error && /branch_plan/.test(res.error.message)) {
      res = await supabase
        .from("stickers")
        .insert(baseRow as never)
        .select("id")
        .single();
    }
    // `shelf_key` の列がまだ無い環境(マイグレーション未適用)でも
    // キャッチは通す。**新しい仕組みのために古い経路を壊さない。**
    if (res.error && /shelf_key/.test(res.error.message)) {
      const { shelf_key: _drop, ...withoutShelf } = baseRow;
      res = await supabase
        .from("stickers")
        .insert(withoutShelf as never)
        .select("id")
        .single();
    }
    if (res.error?.code === "23505" && data.client_catch_id) {
      const { data: existing } = await supabase
        .from("stickers")
        .select("id, word_id")
        .eq("id", data.client_catch_id)
        .eq("user_id", userId)
        .maybeSingle();
      if (existing) return { id: existing.id, word_id: existing.word_id, first_catch: false };
    }
    if (res.error) throw new Error(res.error.message);

    // KPI: was this the user's very first catch? (onboarding §2 — the client
    // shows the SRS teaser「明日この単語を覚えてるか聞くね」.)
    const { count } = await supabase
      .from("stickers")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId);
    const firstCatch = (count ?? 0) === 1;
    if (firstCatch) {
      await supabase.from("usage_events").insert({ user_id: userId, kind: "first_catch" });
    }
    return { id: res.data.id, word_id: wordId, first_catch: firstCatch };
  });

const UpdateExtrasInput = z.object({
  word_id: z.string().uuid(),
  // 大きさの上限つき（`shared-word-guard.ts`）。読む人の解説の行に入る。
  extras: BoundedExtrasSchema,
  /**
   * 共有の列。**いま空の列を埋めるときだけ使う**（サーバが `fillEmptySharedColumns` で
   * 決める。埋まっている列・人が確かめた語は何を送っても変わらない）。
   */
  patch: SharedColumnsPatchSchema.optional(),
  /**
   * **その人の言語で作った意味**（`generateCard` の `meaning_ja` は表示言語で書かれる）。
   * 共有の列（`patch`）は欠けているときしか送らないので、ここが無いとその人向けの解説の
   * 行に**共有の意味（別の言語）が写っていた** — 英語・繁體中文の人の図鑑と復習に意味が
   * 出なかった原因（オーナー報告 2026-10-02）。共有の列には書かない。
   */
  reader_meaning: z.string().max(200).optional(),
});

export type UpdateWordExtrasData = z.infer<typeof UpdateExtrasInput>;

/** `applyWordExtrasUpdate` が外の世界に触る所（試験で偽物を渡す）。 */
export type WordExtrasDeps = {
  /** 呼んだ人の権限の client（札の持ち主の確かめ）。 */
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  supabase: any;
  /** サーバの鍵の client（共有の語を書く）。 */
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  admin: any;
  /**
   * サーバが作った中身の控えを引く（`generated-cards.ts`）。共有の行にはこれだけを書く。
   * 渡さなければ `admin` から引く。
   */
  findCard?: (opts: {
    language: string;
    headword: string;
    explainLang: string;
    l1: string;
  }) => Promise<GeneratedCardLookup>;
  /** 読む人の言語の解説の行を置く（`saveWordExplanation`）。 */
  saveExplanation: (input: {
    word_id: string;
    explain_lang: string;
    l1: string;
    meaning: string;
    example_translation?: string | null;
    extras: Record<string, unknown>;
  }) => Promise<unknown>;
};

export const updateWordExtras = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => UpdateExtrasInput.parse(input))
  .handler(async ({ context, data }) => {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { saveWordExplanation } = await import("./word-explanation.functions");
    return applyWordExtrasUpdate(
      {
        supabase: context.supabase,
        admin: supabaseAdmin,
        saveExplanation: (input) => saveWordExplanation(supabaseAdmin as never, input),
      },
      context.userId,
      data,
    );
  });

/**
 * `updateWordExtras` の中身（試験から呼べるように切り出した）。
 *
 * 1. その語の札を持っている人だけ
 * 2. 共有の語（`words`）は**空の列・空の項目を埋めるだけ**（`shared-word-guard.ts`）
 * 3. 送られた解説の全体は、読む人の言語の行（`word_explanations`）に置く
 */
export async function applyWordExtrasUpdate(
  deps: WordExtrasDeps,
  userId: string,
  data: UpdateWordExtrasData,
): Promise<{ ok: true; saved: boolean }> {
  const { supabase, admin: supabaseAdmin } = deps;
  // Ownership check (docs/design/03 §1): words is a shared table — only a
  // user who owns a sticker referencing this word may edit it.
  const { data: owned } = await supabase
    .from("stickers")
    .select("id")
    .eq("user_id", userId)
    .eq("word_id", data.word_id)
    .limit(1)
    .maybeSingle();
  if (!owned) throw new Error("この単語を編集する権限がありません");

  const ex = (data.extras ?? {}) as Record<string, unknown>;
  // 解説の行の鍵は言語の符号だけ。それ以外の値で共有の行を作らせない（書く前に断る）。
  if (
    !isExplanationLangCode(ex.explain_lang ?? "") ||
    !isExplanationLangCode(ex.explain_l1 ?? "")
  ) {
    throw new Error("解説の言語の形が違います");
  }

  // The words UPDATE policy only covers source='ai', so writing through the
  // user client silently updates 0 rows for dictionary (verified) words —
  // their extras never persisted and the enrichment AI call was re-paid on
  // every open. Write via the service role instead, with a hard rule that
  // keeps constitution §2-1 intact: verified base fields (reading, meaning,
  // examples…) are never touched — verified words only ever gain `extras`,
  // which the UI already labels as AI-generated supplements.
  const { data: word, error: readErr } = await supabaseAdmin
    .from("words")
    // 意味と例文訳も読む。下で共有キャッシュに置くとき、`patch` が
    // 意味を運んでこない回(項目だけ作り直したとき)の落とし所になる。
    // ここを空のまま置くと「意味が空 = 未完成」と数えられて、次に開いた
    // ときにまた作りに行く — 止めたかった作り直しがそのまま復活する。
    // 共有の列はすべて読む — 空の列だけを埋めるため（`fillEmptySharedColumns`）。
    .select(
      "id, headword, language, source, extras, meaning_ja, reading_zhuyin, pinyin, part_of_speech, level, example_sentence, example_translation",
    )
    .eq("id", data.word_id)
    .maybeSingle();
  if (readErr) throw new Error(readErr.message);
  if (!word) throw new Error("単語が見つかりません");
  const shared = word as unknown as Record<SharedWordColumn, string | null> & {
    headword?: string | null;
    language?: string | null;
    source: string | null;
    extras?: unknown;
  };

  /**
   * **書く中身は、サーバが作った控えから取る**（監査 2026-10-03 H2）。
   *
   * 画面は `generateCard` の返したカードをそのまま送ってくるが、その文を信じると
   * アプリを通さずに好きな文を共有の行に置ける。同じカードは `generateCard` が
   * 控え（`generated_cards`）に残しているので、**鍵（解説の言語・母語）が同じ控え**を
   * 引いて、その中身で空の所を埋める。控えが無ければ何も書かない（次に開いたとき、
   * また作って控えが残る）。
   *
   * 控えの表がまだ無い環境（移行待ち）だけ、前の動き（送られた物で空の所だけ埋める）。
   */
  const key = explanationKey(String(ex.explain_lang ?? ""), String(ex.explain_l1 ?? ""));
  const lookup: GeneratedCardLookup =
    shared.headword && shared.language
      ? await (deps.findCard ?? ((o) => findGeneratedCard(supabaseAdmin, o)))({
          language: shared.language,
          headword: shared.headword,
          explainLang: key.explainLang,
          l1: key.l1,
        })
      : { available: true, card: null, kind: null };
  let content: {
    extras: Record<string, unknown>;
    patch: Partial<Record<string, string>> | undefined;
    readerMeaning: string | undefined;
  };
  if (!lookup.available) {
    console.warn("applyWordExtrasUpdate: 控えの表がまだ無い — 送られた物で空の所だけ埋める");
    content = { extras: ex, patch: data.patch, readerMeaning: data.reader_meaning };
  } else if (!lookup.card) {
    // サーバの作った物が無い。**送られた文は共有の行に書かない。**
    return { ok: true, saved: false };
  } else {
    const card = lookup.card;
    const fresh = {
      ...(card.extras ?? {}),
      explain_lang: key.explainLang,
      explain_l1: key.l1,
    };
    content = {
      /**
       * **いま見えている項目は残す**（R14「チャンクが表示され、すぐに違うものに変化する」）。
       * 画面は前から、その人向けの行がまだ無い語では共有の解説（読む人の言語で書かれた物）を
       * 先に出し、作り終えても見えている項目は差し替えない（`keepShownFields`）。送られた
       * 文を使わなくなったので、同じ判断をここでする。その人向けの行が在る時は、下の
       * `saveExplanation` が空の項目だけ埋める（同じ結果）。
       */
      extras: sharedExtrasInLang(shared.extras, key.explainLang)
        ? keepShownFields(shared.extras as Record<string, unknown>, fresh)
        : fresh,
      // 共有の列は、画面が「欠けている」と送ってきた回だけ（今までと同じ回数）。
      patch: data.patch ? sharedColumnsFromCard(card) : undefined,
      readerMeaning: card.meaning_ja,
    };
  }

  /**
   * **共有の行は、空の所を埋めるだけ**（監査 2026-10-03「札を1枚持てば他人のカードの
   * 意味を書き換えられる」）。
   *
   * - 共有の列: いま空の列だけ（人が確かめた語は触らない）
   * - 共有の extras: 空の項目だけ・同じ言語のときだけ。ExtrasSchema に無いキー
   *   （復習の足場キャッシュ speaking_scaffold_* など）は残す
   *
   * 送られた解説の全体は、下の**読む人の言語の行**（`word_explanations`）に入る。
   * 画面が出すのはそちらなので、作り直した本人の見え方は変わらない。
   */
  const prevRaw = shared.extras;
  // 読む人の行に重ねる共有の解説は、**同じ言語で書かれている時だけ**（控えを使う道）。
  // 別の言語の項目を読む人の行の空きに入れると、その人の画面に読めない言語が出る。
  const mergePrev =
    prevRaw &&
    typeof prevRaw === "object" &&
    !Array.isArray(prevRaw) &&
    (!lookup.available || sharedExtrasInLang(prevRaw, key.explainLang));
  /**
   * **例文の訳・場面の札・パーツは文と組で書く**（オーナー報告 2026-10-15「眼鏡: 我戴眼鏡。の上に
   * 『友達が眼鏡をしていないことに気づいたとき』」、`example-patterns.ts`）。共有の行は空の所だけ埋めるので、
   * 前から在る例文の横に、別の文のために作った札（2026-10-14 に足した空の欄）だけが入っていた。
   * 表示に使う文（埋める文 → 無ければいまの文）と違う文のために書かれた札・パーツ・訳は使わない。
   */
  const update: Record<string, unknown> = guardExampleColumns(
    fillEmptySharedColumns(shared, content.patch, {
      verified: shared.source === "verified",
    }),
    shared,
    lookup.available ? lookup.card : null,
  );
  const shownSentence =
    (update.example_sentence as string | undefined) ?? shared.example_sentence ?? null;
  const contentExtras = alignExampleExtras(content.extras, shownSentence);
  const merged: Record<string, unknown> = mergePrev
    ? { ...(prevRaw as Record<string, unknown>), ...contentExtras }
    : contentExtras;
  const filledExtras = fillEmptySharedExtras(prevRaw, contentExtras);
  if (filledExtras) update.extras = filledExtras;
  if (Object.keys(update).length > 0) {
    const { error } = await supabaseAdmin
      .from("words")
      .update(update as never)
      .eq("id", data.word_id);
    if (error) throw new Error(error.message);
  }

  /**
   * **解説を共有キャッシュにも置く**(2026-08-24)。
   *
   * `words` は `(language, headword)` で全ユーザー共有の1行。ところが解説は
   * 読む人の言語と母語で中身が変わるので、そこに置くと**開くたびに作り直して
   * 上書きし合う**(遅い・高い・解説が揺れる)。置き場所を
   * `word_explanations (word_id, explain_lang, l1)` に分けた。
   *
   * ここに足したのは、**書く所が既に1つに集まっていたから**。生成の経路が
   * 増えても、保存は必ずここを通る。2箇所に分けると片方だけ書き忘れて
   * 「作ったのに次に開くとまた作る」になる(この app が何度も踏んだ形)。
   *
   * 置けなくても**カードの保存は成功として返す** — 共有キャッシュは
   * 速さのための付け足しで、無くても動く(移行待ちの環境がまさにそれ)。
   *
   * **待ってから返す**（βテスト 2026-09-30「単語の項目を表示するのが遅い」）。
   * 待たずに返すと、画面が解説を読み直した時点でまだ書けておらず、
   * 次に開くまで（最大30分の読み置き）古い解説が出続けていた。
   * 失敗しても投げない関数なので、カードの保存は巻き込まない。
   */
  const saved = (await deps.saveExplanation({
    word_id: data.word_id,
    explain_lang: String(ex.explain_lang ?? ""),
    l1: String(ex.explain_l1 ?? ""),
    // 意味は共有の列にも在るが、**読む人の言語の物**なのでこちらが正。
    meaning: String(
      content.readerMeaning?.trim() || content.patch?.meaning_ja || shared.meaning_ja || "",
    ),
    example_translation:
      (lookup.available
        ? exampleMatchesSentence(lookup.card?.example_sentence, shownSentence)
          ? lookup.card?.example_translation
          : undefined
        : data.patch?.example_translation) ??
      shared.example_translation ??
      null,
    extras: merged,
  })) as { saved?: boolean } | undefined;
  return { ok: true, saved: saved?.saved ?? true };
}

// --- User feedback: report a wrong word (§ self-improvement) -----------------
//
// Captures user-reported issues into ai_runs (loop="word_report") so the
// human/AI improvement loop has real signal. The AI auto-fix (regenerating the
// card) is driven client-side via generateCard + updateWordExtras; this just
// records that a report happened, for review and metrics.
const ReportInput = z.object({
  word_id: z.string().uuid(),
  headword: z.string().min(1).max(64),
  note: z.string().max(300).optional().default(""),
});

export const reportWordIssue = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => ReportInput.parse(input))
  .handler(async ({ context, data }) => {
    const { supabase, userId } = context;
    await supabase
      .from("ai_runs")
      .insert({
        user_id: userId,
        loop: "word_report",
        iterations: 1,
        accepted: 0,
        meta: { word_id: data.word_id, headword: data.headword, note: data.note },
      })
      .then(
        () => {},
        () => {},
      );
    return { ok: true };
  });

// --- B3 カード削除 -----------------------------------------------------------
const DeleteStickerInput = z.object({ sticker_id: z.string().uuid() });

/**
 * 図鑑カードの削除。所有者のみ。stickers を消すと reviews/encounters/
 * review_history は FK で連鎖削除される(deleteMyAccount で検証済みの順序)。
 * 画像は自分のフォルダ配下だけ storage から掃除する。共有 words は残す
 * (他ユーザーのカードが参照している可能性があるため)。
 */
export const deleteSticker = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => DeleteStickerInput.parse(input))
  .handler(async ({ context, data }) => {
    const { supabase, userId } = context;
    const { data: st, error: readErr } = await supabase
      .from("stickers")
      .select("id, object_image_url, cutout_image_url, selfie_image_url")
      .eq("id", data.sticker_id)
      .eq("user_id", userId)
      .maybeSingle();
    if (readErr) throw new Error(readErr.message);
    if (!st) throw new Error("このカードは削除できません");

    /**
     * **先に行を消し、それから写真を消す**（監査 2026-10-03）。前は写真を先に消して
     * いたので、行の削除が失敗すると「写真の無い札」が残った。逆なら、写真の掃除が
     * 失敗しても残るのは誰からも指されない写真だけで、札はきちんと消えている。
     */
    const { error } = await supabase
      .from("stickers")
      .delete()
      .eq("id", data.sticker_id)
      .eq("user_id", userId);
    if (error) throw new Error(error.message);

    // Storage cleanup: only paths under the caller's own folder.
    const paths = stickerStoragePaths(
      st as {
        object_image_url: string | null;
        cutout_image_url: string | null;
        selfie_image_url: string | null;
      },
      userId,
    );
    if (paths.length === 0) return { ok: true, storage_cleaned: true };
    /**
     * 写真が消せなくても札の削除は成功として返す（札はもう無い）。ただし**黙って捨てない** —
     * 画面が `reportBackgroundFailure("sticker_storage")` で開発者の記録に残す。
     */
    let storageError: string | null = null;
    try {
      const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
      const { error: rmErr } = await supabaseAdmin.storage.from("stickers").remove(paths);
      if (rmErr) storageError = rmErr.message;
    } catch (e) {
      storageError = e instanceof Error ? e.message : String(e);
    }
    if (storageError) {
      console.error("[deleteSticker] storage cleanup failed", {
        sticker_id: data.sticker_id,
        message: storageError,
      });
      return { ok: true, storage_cleaned: false, storage_error: storageError.slice(0, 200) };
    }
    return { ok: true, storage_cleaned: true };
  });

/**
 * 札を消すときに一緒に消す写真の置き場所。**自分のフォルダの物だけ**、縮小版
 * （`<path>.thumb.webp`、`image-resize.ts`）も含める。
 */
export function stickerStoragePaths(
  row: {
    object_image_url: string | null;
    cutout_image_url: string | null;
    selfie_image_url: string | null;
  },
  userId: string,
): string[] {
  const paths = [row.object_image_url, row.cutout_image_url, row.selfie_image_url].filter(
    (p): p is string => !!p && p.startsWith(`${userId}/`),
  );
  return paths.flatMap((p) => [p, `${p}.thumb.webp`]);
}

// --- B3 写真の差し替え -------------------------------------------------------
const ReplacePhotoInput = z.object({
  sticker_id: z.string().uuid(),
  object_path: z.string().min(1),
});

/**
 * 図鑑カードの実写を差し替える。object_image_url を更新し、古い切り抜きは
 * 消す(新しい写真から作り直せる)。自撮り・キャプション・場所は保持。
 * attachPhotoToSticker と違い selfie を消さないので通常カードの写真変更向け。
 */
export const replaceStickerPhoto = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => ReplacePhotoInput.parse(input))
  .handler(async ({ context, data }) => {
    const { supabase, userId } = context;
    if (!data.object_path.startsWith(`${userId}/`)) {
      throw new Error("不正な画像パスです");
    }
    // **`taken_at` は書き換えない。**
    //
    // ここは「カードの写真を差し替える」操作であって、「その言葉に
    // 出会った日」を変える操作ではない。以前は今の時刻で上書きして
    // いたので、写真を1枚替えただけで**士林で撮った日が今日になった**。
    // 図鑑のカレンダーも地図も日付順の並びも、全部そこを見ている。
    const patch = {
      object_image_url: data.object_path,
      cutout_image_url: null,
    };
    let res = await supabase
      .from("stickers")
      .update({
        ...patch,
        capture_type: "photo",
        placeholder_image_url: null,
        placeholder_credit: null,
      })
      .eq("id", data.sticker_id)
      .eq("user_id", userId);
    if (res.error && /capture_type|placeholder/.test(res.error.message)) {
      res = await supabase
        .from("stickers")
        .update(patch)
        .eq("id", data.sticker_id)
        .eq("user_id", userId);
    }
    if (res.error) throw new Error(res.error.message);
    return { ok: true };
  });

// --- 画像なしカードへの仮画像の自動添付 (2026-07-27) -------------------------
// 段ボール絵(絵文字)のカードを無くす: 詳細を開いた時に画像が1枚も無ければ、
// クライアントがWeb検索画像をアップロードしてここに登録する。
const SetPlaceholderInput = z.object({
  sticker_id: z.string().uuid(),
  placeholder_path: z.string(),
  placeholder_credit: z
    .object({ name: z.string().optional(), link: z.string().optional(), source: z.string() })
    .nullable()
    .optional(),
  /**
   * **仮画像がまだ無い時だけ入れる**（自動で付ける経路: 文字で調べた語の札・詳細を開いた時の
   * 自動の1枚）。再会になった保存（もう持っている札）に、その人が選んだ絵を自動の1枚で
   * 上書きしない。入らなかった時はアップロード済みの1枚を消す（どこからも指されない）。
   * 手で差し替える・Pro の AI の絵は渡さない（上書きしてよい）。
   */
  only_if_empty: z.boolean().optional(),
});

/** `setStickerPlaceholder` の本体（試験では手元の偽物を渡す）。 */
export async function applyStickerPlaceholder(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  supabase: { from: (table: string) => any; storage: { from: (bucket: string) => any } },
  userId: string,
  data: z.infer<typeof SetPlaceholderInput>,
): Promise<{ ok: true; applied: boolean }> {
  // Path-spoofing guard: only paths under the caller's own uid folder.
  if (!data.placeholder_path.startsWith(`${userId}/`)) {
    throw new Error("不正な画像パスです");
  }
  let q = supabase
    .from("stickers")
    .update({
      placeholder_image_url: data.placeholder_path,
      placeholder_credit: (data.placeholder_credit ?? null) as never,
    })
    .eq("id", data.sticker_id)
    .eq("user_id", userId);
  if (!data.only_if_empty) {
    const { error } = await q;
    if (error) throw new Error(error.message);
    return { ok: true, applied: true };
  }
  q = q.is("placeholder_image_url", null).select("id");
  const { data: rows, error } = await q;
  if (error) throw new Error(error.message);
  if (Array.isArray(rows) && rows.length > 0) return { ok: true, applied: true };
  // もう絵が在った。今アップロードした1枚は誰も指さないので片付ける（失敗しても札は無事）。
  try {
    await supabase.storage.from("stickers").remove([data.placeholder_path]);
  } catch {
    /* 片付けられなくても、札の絵はそのまま */
  }
  return { ok: true, applied: false };
}

export const setStickerPlaceholder = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => SetPlaceholderInput.parse(input))
  .handler(async ({ context, data }) => {
    const { supabase, userId } = context;
    return applyStickerPlaceholder(supabase as never, userId, data);
  });

/**
 * この1枚の「主役の絵」を決める(要望 #17)。
 *
 * > 「写真ごとに長押しで表示画像を変更できるようにしたい」
 *
 * 設定の既定(`lib/photo-pref.ts`)は全部の札に効く。
 * 「この1枚だけは切り抜きで見たい」はそこでは言えないので、札に持たせる。
 * `null` を渡すと設定に従う状態へ戻る。
 *
 * **列がまだ無い環境では、静かに諦める。**
 * 移行が当たっていないだけでキャッチや閲覧まで壊すのは行き過ぎなので、
 * 保存できなかったことだけを返し、投げない。
 */
export const setStickerHeroRole = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) =>
    z
      .object({
        sticker_id: z.string().uuid(),
        /** null = 設定に従う。 */
        hero_role: z.enum(["object", "cutout", "selfie", "placeholder"]).nullable(),
      })
      .parse(input),
  )
  .handler(async ({ context, data }): Promise<{ saved: boolean; reason?: string }> => {
    const { supabase, userId } = context;
    const { error } = await supabase
      .from("stickers")
      .update({ hero_role: data.hero_role } as never)
      .eq("id", data.sticker_id)
      // **自分の札だけ。** RLS も同じことを言うが、ここでも言っておく。
      .eq("user_id", userId);
    if (!error) return { saved: true };
    if (/hero_role/.test(error.message)) {
      // 移行待ち。**黙って飲まない** — 記録には残す。
      console.warn("setStickerHeroRole: 列がまだ無い", error.message);
      return { saved: false, reason: "migration" };
    }
    throw new Error(error.message);
  });

/**
 * **その札の「ひと言」を直す**（オーナー指示 2026-09-30「ひと言は単語の詳細や
 * ホームのアルバム、日記でそれぞれ編集できるようにして」）。
 *
 * 空にすると消える（`null`）。**自分の札だけ**（RLS に加えて `user_id` でも絞る）。
 * 長さは `CAPTION_MAX` まで（撮影画面の欄に上限が無かったので、昔の長い一言も通る広さ）。
 */
export const updateStickerCaption = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) =>
    z
      .object({
        sticker_id: z.string().uuid(),
        caption: z.string().max(CAPTION_MAX),
      })
      .parse(input),
  )
  .handler(async ({ context, data }): Promise<{ caption: string | null }> => {
    const { supabase, userId } = context;
    const caption = data.caption.trim() || null;
    const { error } = await supabase
      .from("stickers")
      .update({ caption })
      .eq("id", data.sticker_id)
      .eq("user_id", userId);
    if (error) throw new Error(error.message);
    return { caption };
  });

/** `save_album_layout` に渡す形（列の名前のまま。無い座標は null）。 */
export function albumLayoutRpcItems(
  items: ReadonlyArray<{
    sticker_id: string;
    order: number;
    size: string;
    x?: number;
    y?: number;
    scale?: number;
    rot?: number;
  }>,
): Array<Record<string, unknown>> {
  return items.map((it) => ({
    sticker_id: it.sticker_id,
    album_order: it.order,
    album_size: it.size,
    album_x: it.x ?? null,
    album_y: it.y ?? null,
    album_scale: it.scale ?? null,
    album_rot: it.rot ?? null,
  }));
}

/** その関数がまだ DB に無い（移行待ち）か。 */
export function isMissingRpc(
  error: { message?: string; code?: string } | null | undefined,
  fn: string,
): boolean {
  if (!error) return false;
  if (error.code === "PGRST202" || error.code === "42883") return true;
  return (
    new RegExp(fn).test(error.message ?? "") && /not find|does not exist/i.test(error.message ?? "")
  );
}

/** 同じ日のアルバム配置を一括保存する。RLSに加えuser_idでも本人の札に限定。 */
export const saveAlbumLayout = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) =>
    z
      .object({
        items: z
          .array(
            z.object({
              sticker_id: z.string().uuid(),
              order: z.number().int().min(0),
              size: z.enum(["small", "portrait", "landscape", "large"]),
              /**
               * 紙の上の座標（オーナー指示 2026-09-15）。
               * **範囲は表の制約と同じ値にする** — ここを緩めると、
               * 画面は通るのに保存で弾かれる（`0001_add_album_placement`）。
               */
              x: z.number().min(0).max(1).optional(),
              // **縦は台紙の幅で測る**ので 1 を越える（`album-place.ts` の注、
              // 移行 0002）。範囲は表の制約と同じ値にすること — ここを緩めると、
              // 画面は通るのに保存で弾かれる。
              y: z.number().min(0).max(8).optional(),
              scale: z.number().min(0.45).max(2.6).optional(),
              rot: z.number().min(-180).max(180).optional(),
            }),
          )
          .max(500),
      })
      .parse(input),
  )
  .handler(async ({ context, data }) => {
    const { supabase, userId } = context;
    if (data.items.length === 0) return { saved: true, placement: true };
    /**
     * **1回の問い合わせで、全部か何も無しかで書く**（監査 2026-10-03 M6）。
     *
     * 前は札の数だけ（最大500回）順に UPDATE していた。遅いうえに、途中で落ちると
     * 半分だけ並べ替わった日が残る。`save_album_layout`（移行
     * `20261003130200_save_album_layout_rpc.sql`）は呼んだ人の権限（SECURITY INVOKER・RLS）
     * で動き、`user_id = auth.uid()` の札だけを1つの文で書く。
     *
     * 関数がまだ無い環境（移行待ち）だけ、下の1枚ずつの書き方に戻る。
     */
    const rpc = await (
      supabase as unknown as {
        rpc: (
          fn: string,
          args: Record<string, unknown>,
        ) => PromiseLike<{
          data: unknown;
          error: { message: string; code?: string } | null;
        }>;
      }
    ).rpc("save_album_layout", { p_items: albumLayoutRpcItems(data.items) });
    if (!rpc.error) return { saved: true, placement: true };
    if (!isMissingRpc(rpc.error, "save_album_layout")) throw new Error(rpc.error.message);
    console.warn("saveAlbumLayout: 関数がまだ無い — 1枚ずつ書く", rpc.error.message);
    /**
     * **列がまだ無い環境では、座標を諦めて並び順だけ保存する。**
     *
     * 移行が当たっていないだけで「配置を保存できませんでした」と言って
     * 止めるのは行き過ぎ（`setStickerHeroRole` と同じ形）。一度でも
     * 列が無いと分かったら、残りの札は最初から並び順だけで書く —
     * 札の数だけ失敗を繰り返しても意味が無い。
     */
    let hasPlacement = true;
    for (const item of data.items) {
      const base = { album_order: item.order, album_size: item.size };
      const full = {
        ...base,
        album_x: item.x ?? null,
        album_y: item.y ?? null,
        album_scale: item.scale ?? null,
        album_rot: item.rot ?? null,
      };
      let { error } = await supabase
        .from("stickers")
        .update(hasPlacement ? full : base)
        .eq("id", item.sticker_id)
        .eq("user_id", userId);
      if (error && hasPlacement && /album_(x|y|scale|rot)/.test(error.message)) {
        hasPlacement = false;
        ({ error } = await supabase
          .from("stickers")
          .update(base)
          .eq("id", item.sticker_id)
          .eq("user_id", userId));
      }
      if (error) throw new Error(error.message);
    }
    return { saved: true, placement: hasPlacement };
  });

/**
 * **その札の見出し語を直す**（オーナー指示 2026-08-26
 * 「単語のカードの見出しの単語自体を変更できるようにして」）。
 *
 * ## `words` の行を書き換えない
 * `words` は `(language, headword)` で**全ユーザー共有**の1行なので、
 * そこを書き換えると、同じ語を持っている他の人のカードまで変わる。
 * 直すのは**この札がどの語を指すか**（`stickers.word_id`）だけ。
 * 新しい見出し語の行は、無ければ作る（`upsertWord` と同じ道）。
 *
 * ## 学習言語の語しか受けない
 * ここで母語を通すと、直したはずの見出しがまた母語になる
 * （報告の絵と同じ姿）。判定は `target-language.ts` ただ1つ。
 *
 * ## 中身は作り直さない
 * 意味も例文も、新しい語のものが要る。**ここでは作らない** —
 * 空の行として作って、裏の生成（`auto-fill.ts`）に任せる。
 * 待たせずに直せることのほうが値打ちが大きい。
 */
export const setStickerHeadword = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) =>
    z
      .object({
        sticker_id: z.string().uuid(),
        headword: z.string().min(1).max(60),
      })
      .parse(input),
  )
  .handler(async ({ context, data }): Promise<{ word_id: string; headword: string }> => {
    const { supabase, userId } = context;
    const headword = data.headword.trim();

    // その札と、いまの語（言語を知るために要る）。**自分の札だけ。**
    const { data: row, error: readErr } = await supabase
      .from("stickers")
      .select("id, word_id, words(language, headword)")
      .eq("id", data.sticker_id)
      .eq("user_id", userId)
      .maybeSingle();
    if (readErr) throw new Error(readErr.message);
    if (!row) throw new Error("札が見つかりません");

    const current = (row as { words?: { language?: string | null; headword?: string } | null })
      .words;
    const language = normalizeTargetLanguage(current?.language);
    // **母語のまま通さない。** 通すと、直したはずの見出しがまた母語になる。
    // （`upsertWord` も同じ関所を持つが、同じ語なら何もしない下の早道より前で止める。）
    assertTargetHeadword(headword, language);
    // 同じ語なら何もしない（押し間違いで行を増やさない）。
    if (current?.headword === headword) {
      return { word_id: row.word_id as string, headword };
    }

    const wordId = await upsertWord(
      supabase,
      userId,
      {
        headword,
        reading_zhuyin: "",
        pinyin: "",
        // **空で作る。** 中身は裏の生成が埋める（上の注）。
        meaning_ja: "",
        part_of_speech: "",
        level: "",
        category_key: "other",
        example_sentence: "",
        example_translation: "",
        extras: {},
      } as WordUpsertInput,
      language,
    );

    const { error } = await supabase
      .from("stickers")
      .update({ word_id: wordId } as never)
      .eq("id", data.sticker_id)
      .eq("user_id", userId);
    if (error) throw new Error(error.message);
    return { word_id: wordId, headword };
  });

const AttachSelfieInput = z.object({
  sticker_id: z.string().uuid(),
  selfie_path: z.string().min(1),
});

/**
 * **後から自撮りを足す**(オーナー指示 2026-08-25
 * 「自撮り未実施なら自撮りボタンを表示」)。
 *
 * 自撮りはキャッチの流れの中でしか撮れなかった。撮り損ねた札は
 * **二度と自撮りを持てない**ので、裏返しても永遠に「自撮りはまだありません」
 * と出る。詳細の画面から足せるようにする。
 *
 * `attachStickerCutout` と同じ形にしてある — 元の写真には触らず、
 * **1つの欄だけを足す**。`replaceStickerPhoto` を使い回すと、
 * 自撮りを足すたびに元写真の差し替え扱いになって切り抜きが消える。
 */
export const attachStickerSelfie = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => AttachSelfieInput.parse(input))
  .handler(async ({ context, data }) => {
    const { supabase, userId } = context;
    // **他人の場所に書かせない。** 切り抜きの側と同じ門を通す。
    if (!data.selfie_path.startsWith(`${userId}/`)) {
      throw new Error("不正な画像パスです");
    }
    const { error } = await supabase
      .from("stickers")
      .update({ selfie_image_url: data.selfie_path })
      .eq("id", data.sticker_id)
      .eq("user_id", userId);
    if (error) throw new Error(error.message);
    return { ok: true };
  });

const AttachCutoutInput = z.object({
  sticker_id: z.string().uuid(),
  cutout_path: z.string().min(1),
});

/**
 * あとから切り抜きだけを足す(要望 #18 の後半)。
 *
 * > 「キャッチ時に切り抜きするしない(**後から詳細画面でも切り抜ける**)」
 *
 * 速さを選んだ人はキャッチの瞬間に切り抜かない(`lib/catch-speed.ts`)。
 * その道しか無ければ「速さを選ぶ = 二度と切り抜けない」になってしまうので、
 * 詳細の画面から掛け直せるようにする。
 *
 * `replaceStickerPhoto` とは別にしてある。あちらは**元の写真を差し替える**
 * 操作で、古い切り抜きを消す。こちらは元の写真をそのままに、
 * **切り抜きだけを足す**。同じ関数にすると、掛け直すたびに元写真の
 * 差し替え扱いになる。
 */
export const attachStickerCutout = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => AttachCutoutInput.parse(input))
  .handler(async ({ context, data }) => {
    const { supabase, userId } = context;
    // **他人の場所に書かせない。** 差し替えの側と同じ門を通す。
    if (!data.cutout_path.startsWith(`${userId}/`)) {
      throw new Error("不正な画像パスです");
    }
    const { error } = await supabase
      .from("stickers")
      .update({ cutout_image_url: data.cutout_path })
      .eq("id", data.sticker_id)
      .eq("user_id", userId);
    if (error) throw new Error(error.message);
    return { ok: true };
  });
