import { createServerFn } from "@tanstack/react-start";
import { startOfAppDay } from "./taipei-day";
import { readAllPages } from "./pagination";
import { runAfterResponse } from "./background-task";
import {
  matchesTargetLanguage,
  wordBelongsToTarget,
  wordLanguageFilter,
} from "@/lib/language-filter";
import { targetProfile } from "@/lib/target-profile";
import { getUserTargetLanguage } from "@/lib/ai-provider.server";
import { batchEndKind } from "@/lib/review-batch";
import { DEFAULT_TARGET_LANGUAGE, normalizeTargetLanguage } from "./target-lang";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { z } from "zod";
// 復習の間隔と忘却曲線は src/lib/srs.ts(外の世界に触れない純粋な計算)。
// このファイルは createServerFn と Supabase を読み込むので、ここに置くと
// 計算だけを取り出して試すことができない。
import {
  nextSrs,
  retentionNow,
  modeFor,
  stabilityOf,
  daysUntilRetention,
  effectiveDueMs,
  effectiveDueIso,
  dueNowOrFilter,
  LAPSE_SCORE,
  MAX_INTERVAL_DAYS,
} from "@/lib/srs";
import { pickInterval } from "@/lib/jev-tasks";
import { GradeSaveError, MAX_RESPONSE_MS, isAlreadyGraded } from "@/lib/review-grade-guard";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/integrations/supabase/types";
import {
  buildRetentionSeries,
  type RetentionCard,
  type RetentionEvent,
  type RetentionPoint,
} from "@/lib/retention-series";
export { nextSrs } from "@/lib/srs";
// 4択を組む所も同じ理由で外に出してある(「必ず4つ」を試せるように)。
import { FALLBACK_MEANINGS_BY_LANG, buildChoices, shuffle } from "@/lib/quiz-choices";
import { fitsReaderLanguage, quizMeaningLanguage } from "@/lib/meaning-language";
import {
  generateStructured,
  getAi,
  getAiFor,
  getUserLevelGoal,
  getExplanationLanguage,
} from "./ai-provider.server";
import { ttsObjectPath, TTS_VOICE_DEFAULT } from "./tts-cache";
import { normalizeExtras, refineUsageChunks } from "./extras";
import { explainOf, type ReviewExplain } from "./review-explain";
import { rankDueReviews } from "./review-priority";

/**
 * Review card modes escalate with SRS maturity (repetitions):
 * 0-1 recognition (see photo+word, pick meaning)
 * 2-3 listening   (audio only, pick meaning; photo/word revealed after answer)
 * 4-5 reverse     (see meaning+photo, pick the headword)
 * 6+  production  (see photo+meaning, say the word; client falls back to
 *                  reverse when speech recognition is unavailable)
 */
export type ReviewMode = "recognition" | "listening" | "reverse" | "production";

/** 答え合わせに出す解説。組む所は `review-explain.ts`（画面も同じ物を使う）。 */
export type { ReviewExplain } from "./review-explain";

export type DueReviewCard = {
  review_id: string;
  sticker_id: string;
  word_id: string;
  headword: string;
  /**
   * その語を**何語として覚えているか**。
   * 読み上げの声・言語がこれで決まる。空なら既定の学習言語。
   */
  language: string | null;
  reading_zhuyin: string | null;
  pinyin: string | null;
  meaning_ja: string;
  example_sentence: string | null;
  example_translation: string | null;
  /**
   * 4択の答え合わせで見せる「ネイティブが最もよく一緒に使う形」。
   * 例文は長くて読み飛ばされるので、チャンク(型)1つに絞る。
   * zh = 繁体字の型、ja = 短い説明。無ければ null。
   */
  top_chunk: { zh: string; ja: string } | null;
  /** 答え合わせで見せる解説一式(スピーキングで使える塊優先)。 */
  explain: ReviewExplain | null;
  category_key: string | null;
  entry_type: string;
  cutout_url: string | null;
  /** 撮った元の写真。切り抜きが無い札はこれで出す。 */
  object_url: string | null;
  /** Ghost cards (§5.3): temporary stand-in image so review isn't a blank. */
  placeholder_url: string | null;
  audio_url: string | null; // cached TTS if it exists; client falls back to speechSynthesis
  caption: string | null;
  location_name: string | null;
  taken_at: string | null;
  review_count: number; // completed reviews so far (word-tree unlock count)
  /** 思い出せなかった回数(score < 3)。「もう一度撮ろう」の判定に使う。 */
  lapses: number;
  /** この語でこれまでに撮った写真の枚数(最初の1枚 + 再会)。 */
  photo_count: number;
  blur_seen: boolean;
  ease: number;
  interval_days: number;
  repetitions: number;
  /** 現在の推定記憶率 0-100(記憶レベルバッジ用)。 */
  retention: number;
  mode: ReviewMode;
  choices: string[]; // 4 meaning_ja options (shuffled); correct = meaning_ja
  headword_choices: string[]; // 4 headword options for reverse mode
  /** 4択の各選択肢の読み(注音・拼音)。表示は端末の表記設定に従う。 */
  headword_choice_infos: Array<{ headword: string; zhuyin: string | null; pinyin: string | null }>;
};

/**
 * 単語の extras から「最もよく一緒に使う型」を1つ取り出す。
 * usage_chunks[0] は生成時に「よく使う動詞・量詞・定番チャンクを優先」して
 * 並べてあるので先頭が最頻。パーツを繋いで読める1行にする。
 * 旧データ(collocations だけ)にも耐えるようフォールバックを持つ。
 */
function topChunkOf(
  rawExtras: unknown,
  headword: string,
  language?: string | null,
): { zh: string; ja: string } | null {
  const ex = normalizeExtras(rawExtras);
  if (!ex) return null;
  // 量詞は答え合わせの「量詞」の行で読む。先頭の型がその写しだと、
  // 同じ「一張」が2行続けて出る(オーナー指摘 2026-08-18)。
  // **学習言語を渡す。** 渡さないと台湾華語の目盛り(8文字)で測るので、
  // 英語の型が1つ残らず落ちる(`extras.ts` の `MAX_CHUNK_CHARS_EN` の注)。
  const chunk = refineUsageChunks(ex.usage_chunks, ex.measure_words, headword, language)[0];
  const sep = normalizeTargetLanguage(language) === "en" ? " " : "";
  const zh = chunk?.parts?.map((p) => p.text).join(sep) ?? "";
  if (zh.trim()) return { zh, ja: chunk?.ja ?? "" };
  const legacy = ex.collocations?.[0];
  if (legacy?.trim()) return { zh: legacy, ja: "" };
  return null;
}

export type ReviewStageFocus = "all" | "weak" | "new";

/**
 * 復習の出題設定。列がまだ無い環境(マイグレーション未適用)でも
 * 既定値で動き続けるよう、読めなければ既定にフォールバックする。
 */
async function getReviewPrefs(
  supabase: { from: (t: string) => never } | unknown,
  userId: string,
): Promise<{ limit: number; focus: ReviewStageFocus }> {
  const fallback = { limit: 20, focus: "all" as ReviewStageFocus };
  const clamp = (limit: number, focusRaw: unknown) => ({
    limit: Math.max(0, Math.min(200, typeof limit === "number" ? limit : 20)),
    focus: (focusRaw === "weak" || focusRaw === "new" ? focusRaw : "all") as ReviewStageFocus,
  });
  /**
   * **自分の行は SECURITY DEFINER の関数で読む**（`profile.functions.ts` に
   * 同じ注）。`profiles` の私用の列は `authenticated` に配られていないので、
   * 直の `select` は必ず権限違反になり、復習の枚数設定が毎回既定に戻る。
   */
  try {
    const rpc = await (
      supabase as {
        rpc: (fn: string) => Promise<{ data: unknown; error: unknown }>;
      }
    ).rpc("get_my_profile");
    if (!rpc.error && rpc.data) {
      const row = (Array.isArray(rpc.data) ? rpc.data[0] : rpc.data) as {
        review_daily_limit?: number;
        review_stage_focus?: string;
      } | null;
      if (row) return clamp(row.review_daily_limit ?? 20, row.review_stage_focus);
    }
  } catch {
    /* 関数がまだ無い環境では下の直読みへ落ちる */
  }
  try {
    const { data, error } = await (
      supabase as {
        from: (t: string) => {
          select: (c: string) => {
            eq: (
              k: string,
              v: string,
            ) => {
              maybeSingle: () => Promise<{
                data: { review_daily_limit?: number; review_stage_focus?: string } | null;
                error: unknown;
              }>;
            };
          };
        };
      }
    )
      .from("profiles")
      .select("review_daily_limit, review_stage_focus")
      .eq("id", userId)
      .maybeSingle();
    /**
     * **読めなかったときは、上限を掛けない。**（オーナー報告 2026-09-15
     * 「設定で復習の枚数を無制限にしても復習ができない」）
     *
     * ここは何が起きても `20` に落ちていた。つまり**一度の読み取り失敗で、
     * 無制限にした人が 20 枚で「今日の分は終わりです」と言われる**。
     * しかも次に開けば直るので、再現しないまま残り続ける。
     *
     * 二つの「読めなかった」を分ける:
     *   ・行が無い（`!data`）… まだ設定を触っていない人。**20 が正しい既定**
     *   ・読めなかった（`error`）… 分からない。**知らないことを理由に
     *     止めない** — 多く出してしまう害より、「まだあるのに終わりだ」と
     *     言う害のほうが大きい
     */
    if (error) return { limit: 0, focus: "all" as ReviewStageFocus };
    if (!data) return fallback;
    const limit = typeof data.review_daily_limit === "number" ? data.review_daily_limit : 20;
    const focus =
      data.review_stage_focus === "weak" || data.review_stage_focus === "new"
        ? (data.review_stage_focus as ReviewStageFocus)
        : "all";
    return { limit: Math.max(0, Math.min(200, limit)), focus };
  } catch {
    return fallback;
  }
}

/**
 * 今日の列を読むときに、`fetchLimit` より多めに読む数。見出しの字が学習言語で
 * ない札（保存の関所ができる前の行）を落とすので、その分を見込んでおく。
 * 落とす札は期限が来たまま残るので、多めに読まないと毎回の束の枠を食い続ける。
 */
const DUE_OVERFETCH = 10;

export const getDueReviews = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) =>
    z
      .object({
        /**
         * 名指しで先に出したい1枚。場所の知らせを押して来たときに使う。
         * **期限も1日の上限も無視する** — 押した人はその言葉を思い出したくて
         * 押しているので、「今日の分は終わりです」と返すのは答えになっていない。
         */
        sticker_id: z.string().uuid().optional(),
      })
      .optional()
      .parse(input ?? undefined),
  )
  .handler(async ({ context, data: input }): Promise<DueReviewCard[]> => {
    const { supabase, userId } = context;
    const nowIso = new Date().toISOString();
    const wantedSticker = input?.sticker_id ?? null;

    // 1日の上限(NORI指摘: 開くたびに新しい単語が無限に出て終われない)。
    // 「今日すでに何枚やったか」を review_history から数え、残り枚数だけ返す。
    // 端末をまたいでも一貫させたいのでサーバー側で数える。0 = 無制限。
    const { limit: dailyLimit, focus: stageFocus } = await getReviewPrefs(supabase, userId);
    let remaining = Number.POSITIVE_INFINITY;
    if (dailyLimit > 0) {
      // 「今日」は台湾の日付で数える（ARCHITECTURE「Day boundaries」）。前はサーバの
      // 時計の 0:00（= UTC の 0:00 = 台湾の朝8時）で区切っていたので、台湾の朝に
      // 「今日の分」が始まり直していた。
      const since = startOfAppDay();
      const { count } = await supabase
        .from("review_history")
        .select("id", { count: "exact", head: true })
        .eq("user_id", userId)
        .gte("reviewed_at", since);
      remaining = Math.max(0, dailyLimit - (count ?? 0));
      // 上限に当たったときも空配列を返す。**画面側は「今日の分は終わり」と
      // 「そもそも出る語が無い」を区別できないので**、下の
      // `getReviewCapState` で別途聞けるようにしてある(§8)。
      // 名指しで来た1枚だけは通す(下で改めて読む)。
      if (remaining === 0 && !wantedSticker) return [];
    }
    // 1回のフェッチは最大10枚のまま(体感の軽さ)。残り枚数がそれ未満なら絞る。
    const fetchLimit = Math.min(10, remaining);

    /**
     * **復習も学習言語で分ける。** 英語に切り替えた人に台湾華語の札が
     * 出るなら、アルバムと図鑑だけ分けても意味が無い
     * (オーナー指示「混ぜないで」)。
     *
     * 絞りは埋め込んだ2段先に掛ける — `reviews → stickers → words`。
     * PostgREST の形は `stickers.words.or=(…)` で、**通らない prefix は
     * 400 を返す**ので、下で拾って絞りを外す(空の復習を出さない)。
     */
    const [targetLanguage, reader] = await Promise.all([
      getUserTargetLanguage(userId),
      // 4択の意味と解説を読む人の言語（表示言語）。
      getExplanationLanguage(userId),
    ]);
    const langFilter = wordLanguageFilter(targetLanguage);
    // 4択の受け皿は**その言語のもの**(`target-profile.ts` が持つ)。
    const quizFallback = {
      headwords: targetProfile(targetLanguage).capture.quizFallbackHeadwords,
      readings: targetProfile(targetLanguage).capture.quizFallbackReadings,
    };
    const dueSelect = (withGhost: boolean) =>
      `id, sticker_id, ease, interval_days, repetitions, blur_seen, last_reviewed_at, due_at, stickers!inner(cutout_image_url, object_image_url, caption, location_name, taken_at${withGhost ? ", placeholder_image_url" : ""}, words!inner(id, headword, language, reading_zhuyin, pinyin, meaning_ja, example_sentence, example_translation, category_key, entry_type, extras))`;
    // 記憶段階の優先度(設定):
    //   weak = 忘れかけ(ease が低い=何度も間違えた語)から先に
    //   new  = 覚えたて(復習回数が少ない語)から先に
    //   all  = 期限順(既定)
    const runDue = async (withLang: boolean) => {
      const base = supabase
        .from("reviews")
        .select(dueSelect(true))
        .eq("user_id", userId)
        // 期限が来た札。2026-10-03 より前の数年先の期限は、最後の復習から 180 日で
        // 来た扱い（`dueNowOrFilter`。DB は書き換えない）。
        .or(dueNowOrFilter(Date.parse(nowIso)));
      const scoped = withLang ? base.or(langFilter, { referencedTable: "stickers.words" }) : base;
      const focused =
        stageFocus === "weak"
          ? scoped.order("ease", { ascending: true })
          : stageFocus === "new"
            ? scoped.order("repetitions", { ascending: true })
            : scoped;
      // **少し多めに読む**（下で見出しの字が学習言語でない札を落とすため）。
      // 落とした分だけ束が痩せ続けないよう、落とした後で `fetchLimit` に切る。
      // 既定（all）は多めの候補から「忘れかけ × 大事さ」で選ぶ（`review-priority.ts`）。
      const pool = stageFocus === "all" ? Math.max(fetchLimit * 3, 30) : fetchLimit;
      return await focused.order("due_at", { ascending: true }).limit(pool + DUE_OVERFETCH);
    };
    let { data, error } = await runDue(true);
    // 絞りが通らない環境(列がまだ無い / 埋め込みの形が違う)では絞りを外す。
    // **復習が空になるより混ざるほうがまし。**
    if (error && /language|embedded resource/i.test(error.message)) {
      console.warn("[reviews] 学習言語で絞れないので絞りを外す:", error.message);
      ({ data, error } = await runDue(false));
    }
    if (error && /placeholder_image_url|entry_type/.test(error.message)) {
      ({ data, error } = (await supabase
        .from("reviews")
        .select(
          "id, sticker_id, ease, interval_days, repetitions, blur_seen, last_reviewed_at, stickers(cutout_image_url, object_image_url, caption, location_name, taken_at, words(id, headword, reading_zhuyin, pinyin, meaning_ja, example_sentence, example_translation, category_key))",
        )
        .eq("user_id", userId)
        .or(dueNowOrFilter(Date.parse(nowIso)))
        .order("due_at", { ascending: true })
        .limit(fetchLimit)) as unknown as { data: typeof data; error: typeof error });
    }
    if (error) throw new Error(error.message);

    type DueRow = {
      id: string;
      sticker_id: string;
      ease: number;
      interval_days: number;
      repetitions: number;
      blur_seen: boolean;
      last_reviewed_at: string | null;
      due_at?: string | null;
      stickers: {
        cutout_image_url: string | null;
        object_image_url: string | null;
        caption: string | null;
        location_name: string | null;
        taken_at: string | null;
        placeholder_image_url?: string | null;
        words: {
          id: string;
          headword: string;
          language: string | null;
          reading_zhuyin: string | null;
          pinyin: string | null;
          meaning_ja: string;
          example_sentence: string | null;
          example_translation: string | null;
          category_key: string | null;
          entry_type: string | null;
          extras?: unknown;
        } | null;
      } | null;
    };
    /**
     * **学習言語の語だけを残す**(オーナー報告 2026-08-26)。
     * > 「復習の記憶の状態が他の学習言語と混ざってるから、ほかの言語の
     * >  ものは表示しないで」
     *
     * 絞りは問い合わせの側でも掛けているが、列がまだ無い環境では
     * **絞りごと外して**投げ直している(上の `runDue(false)`)。
     * そこを通ると混ざったまま画面へ出ていた — 「空になるより混ざる
     * ほうがまし」と書いてあったが、オーナーが見たのは**まさにその混ざり**。
     *
     * 手元に来た行なら言語で選り分けられるので、ここで最後にもう一度通す。
     * 判定は `language-filter.ts` の1つだけを使う(問い合わせ側と同じ規則)。
     */
    /*
     * **見出し語の字も見る**（オーナー報告 2026-10-02「拿鐵の繁體中文の4択が
     * 3.5秒出てから英語の4択に替わる」）。「拿鐵」は `language = 'en'` で
     * 保存されていたので、言語の列だけの絞り（問い合わせ側も、端末の束の
     * 確かめも）を素通りし、4択の誤答は見出しの字に引かれて台湾華語の辞書から
     * 作られていた。保存の関所（`upsertWord`）ができる前の行が残っているので、
     * 見せる側でも同じ規則（`wordBelongsToTarget`）で落とす。
     */
    const eligible = ((data ?? []) as unknown as DueRow[])
      .filter((r) => r.stickers?.words)
      .filter((r) => wordBelongsToTarget(r.stickers?.words, targetLanguage));
    // **出す順は「忘れかけ × 大事さ」**（ROADMAP Phase 7-3。2026-10-03）。設定で weak / new を
    // 選んだ人はその並びのまま。
    const ordered: DueRow[] =
      stageFocus === "all"
        ? rankDueReviews(
            eligible.map((r) => ({ ...r, caught_at: r.stickers?.taken_at ?? null })),
            Date.parse(nowIso),
          )
        : eligible;
    const rows: DueRow[] = ordered.slice(0, fetchLimit);

    // 名指しの1枚を先頭へ。
    // 既に今日の列に居るなら**動かすだけ**(二重に出さない)。
    // 居ないなら期限を無視して1枚だけ読む — 早めに復習しても SRS は壊れない
    // (間隔が伸びるだけ)。読めなくても列そのものは返す。
    if (wantedSticker) {
      const at = rows.findIndex((r) => r.sticker_id === wantedSticker);
      if (at > 0) {
        rows.unshift(...rows.splice(at, 1));
      } else if (at < 0) {
        const { data: one } = await supabase
          .from("reviews")
          .select(dueSelect(true))
          .eq("user_id", userId)
          .eq("sticker_id", wantedSticker)
          .maybeSingle();
        const row = one as unknown as DueRow | null;
        if (row?.stickers?.words) rows.unshift(row);
      }
    }

    if (rows.length === 0) return [];

    // Word-tree unlock counts: one review_history row per completed review.
    // **つまずいた回数もここで数える** — `repetitions` は連続正解の回数で、
    // つまずくたびに 0 に戻るので「何度もやったのに覚えられない」語ほど
    // 小さくなる。撮り直しの判定に使えるのは通算の回数のほう
    // (`src/lib/retake.ts`)。
    const stickerIds = rows.map((r) => r.sticker_id);
    const reviewCounts = new Map<string, number>();
    const lapseCounts = new Map<string, number>();
    {
      const { data: histRows } = await supabase
        .from("review_history")
        .select("sticker_id, score")
        .eq("user_id", userId)
        .in("sticker_id", stickerIds);
      for (const h of (histRows ?? []) as Array<{ sticker_id: string; score: number | null }>) {
        reviewCounts.set(h.sticker_id, (reviewCounts.get(h.sticker_id) ?? 0) + 1);
        if ((h.score ?? 5) < LAPSE_SCORE) {
          lapseCounts.set(h.sticker_id, (lapseCounts.get(h.sticker_id) ?? 0) + 1);
        }
      }
    }
    // 撮った枚数 = 最初の1枚 + 再会の回数。列がまだ無い環境でも
    // **落とさない** — 数えられなければ「1枚」として扱い、提案は出る。
    const encounterCounts = new Map<string, number>();
    {
      const { data: encRows } = await supabase
        .from("encounters")
        .select("sticker_id")
        .eq("user_id", userId)
        .in("sticker_id", stickerIds);
      for (const e of (encRows ?? []) as Array<{ sticker_id: string }>) {
        encounterCounts.set(e.sticker_id, (encounterCounts.get(e.sticker_id) ?? 0) + 1);
      }
    }

    /**
     * その人が撮った語が誤答の池 — 復習のときに AI を1回も呼ばずに済む。
     *
     * **学習言語で絞る**（オーナー報告 2026-08-26、2度目
     * 「復習の4択の選択肢が言語が混ざってる。英語なら英語だけの選択肢を
     * 作って」）。
     *
     * 前の周で辞書の池と受け皿は言語で絞ったのに、**この池だけ素通し**
     * だった。しかもここは4つの池のうち**いちばん先に使われる**ので、
     * 両方の言語で撮っている人の4択は、ほぼ必ず混ざる。
     * 直す所を数えたときに、いちばん大きい1つを数え落としていた。
     */
    const { data: deckRows } = await supabase
      .from("stickers")
      .select("words(id, headword, language, meaning_ja, category_key, reading_zhuyin, pinyin)")
      .eq("user_id", userId)
      .limit(500);
    type DeckWord = {
      id: string;
      headword: string;
      language?: string | null;
      meaning_ja: string;
      category_key: string | null;
      reading_zhuyin?: string | null;
      pinyin?: string | null;
    };
    const deck: DeckWord[] = [];
    const seen = new Set<string>();
    for (const r of (deckRows ?? []) as unknown as Array<{ words: DeckWord | null }>) {
      if (!r.words || seen.has(r.words.id)) continue;
      // 判定は1箇所(`language-filter.ts`)。列が空の古い行も同じ規則で見る。
      // 見出しの字も見る — 「ノート」（`en`）を英語の4択の誤答にしない。
      if (!wordBelongsToTarget(r.words, targetLanguage)) continue;
      seen.add(r.words.id);
      deck.push(r.words);
    }

    // A3 レベル連動: 目標レベル以下の辞書語をヘッドワード・ディストラクタの
    // 追加プールにする(デッキが小さいうちも4択が「全部知らない字」にならない)。
    let dictPool: string[] = [];
    // 4択の選択肢に読み(注音/拼音)を出すための逆引き表。
    const readingByHead = new Map<string, { zhuyin: string | null; pinyin: string | null }>();
    try {
      const levelGoal = await getUserLevelGoal(userId);
      const lvl = Number(levelGoal.match(/(\d)/)?.[1] ?? 2);
      const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
      const pivot = crypto.randomUUID();
      /**
       * **誤答は学習言語の語から作る**(オーナー報告 2026-08-26)。
       * > 「4択の選択に英単語の4択なのに、学習言語、台湾華語のものが
       * >  混ざってる。学習言語の単語だけを表示して」
       *
       * ここは `DEFAULT_TARGET_LANGUAGE` と `tocfl_level` に決め打たれて
       * いた。英語を学んでいる人の4択に、**中国語の語が3つ並ぶ**。
       *
       * 級の列も言語で違う: `tocfl_level` は名前のとおり台湾華語の列で、
       * 英語の行には入らない(`admin.functions.ts` の注)。言語中立の
       * `level_step` を見て、**級が付いていない語(級外)も混ぜる** —
       * 英語の辞書は級外のほうが多いので、外すと誤答が作れない。
       */
      const readingCols =
        targetLanguage === DEFAULT_TARGET_LANGUAGE
          ? "headword, zhuyin, pinyin"
          : "headword, reading_primary, reading_alt";
      const pool = supabaseAdmin
        .from("dictionary_entries")
        .select(readingCols)
        .eq("language", targetLanguage)
        .gte("id", pivot)
        .limit(40);
      const { data: dictRows } =
        targetLanguage === DEFAULT_TARGET_LANGUAGE
          ? await pool.lte("tocfl_level", lvl)
          : await pool.or(`level_step.lte.${lvl},level_step.is.null`);
      const dicts = (dictRows ?? []) as unknown as Array<{
        headword: string;
        zhuyin?: string | null;
        pinyin?: string | null;
        reading_primary?: string | null;
        reading_alt?: string | null;
      }>;
      // 読みの列名も言語で違う。**新しい列を先に見る**(`dictionary-entry.ts`)。
      for (const d of dicts) {
        readingByHead.set(d.headword, {
          zhuyin: d.reading_primary ?? d.zhuyin ?? null,
          pinyin: d.reading_alt ?? d.pinyin ?? null,
        });
      }
      dictPool = shuffle(dicts.map((d) => d.headword));
    } catch {
      /* dictionary pool is optional */
    }

    // Pre-generated AI distractors (best-effort: table may not exist yet).
    const wordIds = rows.map((r) => r.stickers!.words!.id);
    const cached = new Map<string, string[]>();
    const { data: choiceRows } = await supabase
      .from("review_choices")
      .select("word_id, distractors")
      .in("word_id", wordIds);
    for (const c of choiceRows ?? []) cached.set(c.word_id, c.distractors ?? []);

    // Batch-sign all image and audio URLs in two calls instead of one per card.
    // **元写真も署名する。**
    //
    // ここは切り抜きとネット画像しか取っていなかった。つまり
    // **切り抜きの無い札は写真なしで復習に出ていた** — かざして撮った札は
    // 設計上いま切り抜きを作らないので、その一群がまるごと該当する。
    // 「写真を見て、その語を言う」が復習の中身なのに、写真が無い。
    // (7箇所の選び方を `sticker-photo.ts` に集めていて気づいた。)
    const cutoutPaths = rows
      .flatMap((r) => [
        r.stickers!.cutout_image_url,
        r.stickers!.object_image_url ?? null,
        r.stickers!.placeholder_image_url ?? null,
      ])
      .filter((p): p is string => !!p);
    const cutoutUrlByPath = new Map<string, string>();
    if (cutoutPaths.length > 0) {
      const { data: signed } = await supabase.storage
        .from("stickers")
        .createSignedUrls([...new Set(cutoutPaths)], 60 * 60 * 6);
      for (const s of signed ?? []) {
        if (s.path && s.signedUrl && !s.error) cutoutUrlByPath.set(s.path, s.signedUrl);
      }
    }
    // 置き場所は**いまの声の札**で引く（開発者が声を変えたら、新しい声の音を探す）。
    const { currentVoiceTag } = await import("./tts-provider.server");
    const voice = await currentVoiceTag(DEFAULT_TARGET_LANGUAGE);
    const audioPaths = await Promise.all(
      rows.map((r) => ttsObjectPath(DEFAULT_TARGET_LANGUAGE, voice, r.stickers!.words!.headword)),
    );
    const audioUrlByPath = new Map<string, string>();
    {
      const { data: signed } = await supabase.storage
        .from("tts")
        .createSignedUrls(audioPaths, 60 * 60 * 6);
      for (const s of signed ?? []) {
        if (s.path && s.signedUrl && !s.error) audioUrlByPath.set(s.path, s.signedUrl);
      }
    }

    return rows.map((row, i) => {
      const w = row.stickers!.words!;
      const sameCat = shuffle(
        deck.filter((d) => d.id !== w.id && d.category_key === w.category_key),
      );
      const otherCat = shuffle(
        deck.filter((d) => d.id !== w.id && d.category_key !== w.category_key),
      );

      // 池は「その学習者の頭の中で実際に混ざる誤答」から先に。
      // 最後は必ず受け皿 — 撮った語がまだ1つでも、選択肢は4つ出す。
      // **4つを同じ言語で揃える**（オーナー報告 2026-09-27「復習の4択に別の
      // 言語が混ざる」）。池の中身は作った日の表示言語で保存されているので、
      // 読み手の言語（正解が古い別の言語なら、その言語）に合う物だけを使う。
      const quizLang = quizMeaningLanguage(w.meaning_ja, reader);
      const sameLang = (xs: readonly string[]) => xs.filter((x) => fitsReaderLanguage(x, quizLang));
      const meaningChoices = buildChoices(w.meaning_ja, [
        sameLang(sameCat.map((d) => d.meaning_ja)),
        sameLang(cached.get(w.id) ?? []),
        sameLang(otherCat.map((d) => d.meaning_ja)),
        FALLBACK_MEANINGS_BY_LANG[quizLang],
      ]);
      const headwordChoices = buildChoices(w.headword, [
        sameCat.map((d) => d.headword),
        dictPool,
        otherCat.map((d) => d.headword),
        // **受け皿もその言語のもの**(オーナー報告 2026-08-26
        // 「4択が学習言語英語なのに台湾華語の単語が混ざってる」)。
        // 撮った語が少ない人ほどここまで落ちるので、ここが混ざると
        // 始めたばかりの人の4択が丸ごと別の言語になる。
        quizFallback.headwords,
      ]);

      // デッキ語の読みも逆引き表へ(4択の注音表示用)。
      for (const d of deck) {
        if (!readingByHead.has(d.headword)) {
          readingByHead.set(d.headword, {
            zhuyin: d.reading_zhuyin ?? null,
            pinyin: d.pinyin ?? null,
          });
        }
      }
      readingByHead.set(w.headword, { zhuyin: w.reading_zhuyin, pinyin: w.pinyin });
      for (const [h, r] of Object.entries<{ zhuyin: string; pinyin: string }>(
        quizFallback.readings,
      )) {
        if (!readingByHead.has(h)) readingByHead.set(h, r);
      }
      // 記憶の起点は**最後の復習**だけ。未復習（null）の札は 0%（撮っただけではまだ
      // 覚えていない — オーナー指示 2026-10-02）。一覧（getMemoryOverview）も同じ規則。
      const lastMs = row.last_reviewed_at ? new Date(row.last_reviewed_at).getTime() : null;

      const cutoutPath = row.stickers!.cutout_image_url;
      const reviewCount = reviewCounts.get(row.sticker_id) ?? 0;
      return {
        review_id: row.id,
        sticker_id: row.sticker_id,
        word_id: w.id,
        headword: w.headword,
        language: w.language ?? null,
        reading_zhuyin: w.reading_zhuyin,
        pinyin: w.pinyin,
        meaning_ja: w.meaning_ja,
        example_sentence: w.example_sentence,
        example_translation: w.example_translation,
        // 4択の答え合わせで見せるのは長い例文ではなく「一番よく一緒に使う形」。
        // extras.usage_chunks の先頭(=最頻の型)をその場で読める短い1行にする。
        top_chunk: topChunkOf(w.extras, w.headword, w.language),
        explain: explainOf(w.extras, w.headword, w.language, reader),
        category_key: w.category_key,
        entry_type: w.entry_type ?? "word",
        cutout_url: cutoutPath ? (cutoutUrlByPath.get(cutoutPath) ?? null) : null,
        object_url: row.stickers!.object_image_url
          ? (cutoutUrlByPath.get(row.stickers!.object_image_url) ?? null)
          : null,
        placeholder_url: row.stickers!.placeholder_image_url
          ? (cutoutUrlByPath.get(row.stickers!.placeholder_image_url) ?? null)
          : null,
        audio_url: audioUrlByPath.get(audioPaths[i]) ?? null,
        caption: row.stickers!.caption,
        location_name: row.stickers!.location_name,
        taken_at: row.stickers!.taken_at,
        review_count: reviewCount,
        lapses: lapseCounts.get(row.sticker_id) ?? 0,
        photo_count: 1 + (encounterCounts.get(row.sticker_id) ?? 0),
        blur_seen: row.blur_seen,
        ease: row.ease,
        interval_days: row.interval_days,
        repetitions: row.repetitions,
        retention: Math.round(retentionNow(row.interval_days, row.ease, lastMs, Date.now())),
        mode: modeFor(row.repetitions),
        choices: meaningChoices,
        headword_choices: headwordChoices,
        headword_choice_infos: headwordChoices.map((h) => ({
          headword: h,
          zhuyin: readingByHead.get(h)?.zhuyin ?? null,
          pinyin: readingByHead.get(h)?.pinyin ?? null,
        })),
      };
    });
  });

// --- Distractor pre-generation (runs once at card save time, off the review path) ---

const MakerSchema = z.object({
  distractors: z.array(z.string().min(1)).length(3),
});
const CheckerSchema = z.object({
  verdicts: z.array(
    z.object({
      ok: z.boolean(),
      reason: z.string().optional().default(""),
    }),
  ),
});

/**
 * Maker/Checker loop producing 3 plausible-but-wrong meanings. Called from
 * saveSticker (fire-and-forget); results land in review_choices. Failure is
 * fine — reviews fall back to the user's own deck.
 */
export async function pregenerateDistractors(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  supabase: any,
  userId: string,
  wordId: string,
  headword: string,
  correctMeaning: string,
  categoryKey: string | null,
  /** その語の学習言語。渡さない古い呼び出しは既定(台湾華語)のまま。 */
  language?: string | null,
): Promise<void> {
  const ai = await getAiFor("review", "distractors");
  // 「◯◯の単語」の呼び方は言語の表から(日本語の語を「台湾華語の単語」と呼ばない)。
  const quizWordLabel = targetProfile(language).coach.quizWordLabel;
  const accepted: string[] = [];
  let iter = 0;
  const MAX = 2;

  while (accepted.length < 3 && iter < MAX) {
    iter++;
    const makerPrompt = `${quizWordLabel}「${headword}」（意味: ${correctMeaning}${categoryKey ? `、カテゴリ: ${categoryKey}` : ""}）の4択クイズ用に、もっともらしいが間違っている意味を3つ作ってください。**正解「${correctMeaning}」と同じ言語で書く**(正解が英語なら英語、日本語なら日本語)。
- 正解「${correctMeaning}」と同義語/言い換えは禁止
- 文字数は正解と同程度
- 学習者が一瞬迷う難易度（同カテゴリの別物がベスト）
- すでに却下された候補: ${accepted.length ? accepted.join(", ") : "なし"}`;

    let candidates: string[] = [];
    try {
      const makerOut = await generateStructured({
        model: ai.gateway(ai.modelFast),
        prompt: makerPrompt,
        schema: MakerSchema,
      });
      candidates = makerOut.distractors;
    } catch {
      continue; // this iteration produced nothing; reviews fall back to the deck
    }

    const checkerPrompt = `以下は単語「${headword}」（正解の意味: ${correctMeaning}）の4択クイズの不正解候補です。
各候補について、(a) 正解と意味が被っていない (b) 学習者を惑わすが正解とは明確に違う、を満たすかtrue/falseで判定してください。
候補:
${candidates.map((c, i) => `${i + 1}. ${c}`).join("\n")}`;

    let verdicts: z.infer<typeof CheckerSchema>["verdicts"] = [];
    try {
      const checkOut = await generateStructured({
        model: ai.gateway(ai.modelFast),
        prompt: checkerPrompt,
        schema: CheckerSchema,
      });
      verdicts = checkOut.verdicts;
    } catch {
      /* no checker verdicts — candidates pass unless they duplicate the answer */
    }

    for (let i = 0; i < candidates.length; i++) {
      const v = verdicts[i];
      const c = candidates[i];
      if (!c || c === correctMeaning || accepted.includes(c)) continue;
      if (v?.ok !== false) accepted.push(c);
      if (accepted.length >= 3) break;
    }
  }
  if (accepted.length === 0) return;

  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
  await supabaseAdmin
    .from("review_choices")
    .upsert({ word_id: wordId, distractors: accepted.slice(0, 3) });
  await supabase.from("ai_runs").insert({
    user_id: userId,
    loop: "review_distractor_pregen",
    iterations: iter,
    accepted: accepted.length,
    meta: { headword },
  });
}

const GradeInput = z.object({
  review_id: z.string().uuid(),
  correct: z.boolean(),
  blur_seen: z.boolean().default(false),
  response_ms: z.number().int().nonnegative().default(0),
});

/** 採点の入力（iOS `ReviewStore.grade` と Web の復習が同じ形で送る）。 */
export type GradeInputData = z.infer<typeof GradeInput>;

/**
 * 採点の入力を読む。**形が違えば ZodError**（`native-fn.ts` の `statusForError` が 400 と
 * 「送った内容の形が違います。アプリを最新にしてください。」にする — 500 にしない）。
 */
export function parseGradeInput(input: unknown): GradeInputData {
  return GradeInput.parse(input);
}

/**
 * 今日の復習が「上限で止まっている」のか「もう出る語が無い」のかを返す。
 *
 * ## なぜ要るか
 * `listDueReviews` はどちらの場合も空配列を返す。画面はそれを見て
 * 「今日復習する単語はありません」と出していた — 期限切れが180枚
 * 溜まっていても同じ文面で、**上限に当たったとは一言も書かれず、
 * 上限を上げる導線も無い**。
 *
 * 図鑑では「全N件のうち…まだ出せていません」と正直に書いているのに、
 * 復習だけが「無い」と言っていた。同じアプリの中で基準が食い違う。
 *
 * 一覧が空だったときにだけ聞けばいいので、別の関数にしてある。
 */
/**
 * いま出せる復習の枚数を数える。学習言語で絞った数。
 *
 * 絞りが通らない環境では**絞らずに数え直す** — 0 と答えると画面が
 * 「今日は終わり」と言い切ってしまい、元の不具合に戻る。
 */
async function countDue(
  supabase: { from: (t: string) => never } | ReturnType<typeof Object>,
  userId: string,
  langFilter: string,
): Promise<{ count: number | null }> {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const db = supabase as any;
  const base = () =>
    db
      .from("reviews")
      .select("id, stickers!inner(words!inner(language))", { count: "exact", head: true })
      .eq("user_id", userId)
      .or(dueNowOrFilter(Date.now()));
  const res = await base().or(langFilter, { referencedTable: "stickers.words" });
  if (!res.error) return { count: res.count ?? 0 };
  const plain = await db
    .from("reviews")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .or(dueNowOrFilter(Date.now()));
  return { count: plain.error ? null : (plain.count ?? 0) };
}

export const getReviewCapState = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const { supabase, userId } = context;
    const { limit: dailyLimit } = await getReviewPrefs(supabase, userId);
    const dueLangFilter = wordLanguageFilter(await getUserTargetLanguage(userId));
    // **上限が無制限でも数える。** 前はここで早く返していたが、
    // 「あと何枚出せるか」は上限とは別の話で、束(10枚)を終えた画面が
    // それを知らないと「今日の復習、終わりました」と言い切ってしまう
    // (`src/lib/review-batch.ts` の注釈)。
    const [doneRes, dueRes] = await Promise.all([
      supabase
        .from("review_history")
        .select("id", { count: "exact", head: true })
        .eq("user_id", userId)
        .gte("reviewed_at", startOfAppDay()),
      // 採点した札は `due_at` が先へ動くので、ここには残らない。
      // **絞りは `getDueReviews` と同じにする。** ここだけ絞らないと
      // 「あと190枚あります」と言ったのに「続ける」で1枚も出てこない。
      countDue(supabase, userId, dueLangFilter),
    ]);
    const doneToday = doneRes.count ?? 0;
    const dueRemaining = dueRes.count ?? 0;
    const limit = Math.max(0, dailyLimit);
    // 言い方の判断は**純粋な関数1つ**に寄せる。画面も同じものを読む。
    const kind = batchEndKind({ limit, doneToday, dueRemaining });
    return { capped: kind === "capped", limit, doneToday, dueRemaining };
  });

export const gradeReview = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => parseGradeInput(input))
  .handler(async ({ context, data }) => gradeReviewWith(context, data));

/** 採点が使う Jev の記録（`jev-tasks.server.ts`。試験では差し替える）。 */
type GradeJev = Pick<
  typeof import("./jev-tasks.server"),
  "jevIntervalMode" | "jevScheduleDays" | "logScheduleDecision" | "recordRecallShadow"
>;

/** 採点の返事（iOS `ReviewStore.grade` は `score` と `interval_days` だけを読む。どちらも null でよい）。 */
export type GradeResult = {
  score: number | null;
  next_due_at: string | null;
  interval_days: number | null;
  /** もう採点済みだった（通信のやり直し・二重送信・同時に2回届いた後の方）。何も進めていない。 */
  duplicate: boolean;
  /**
   * **札がもう無い**（図鑑から消した札 — 復習の行も一緒に消える — か、この人の札ではない）。何も書いていない。
   * 古い画面はこれを「保存できた」として次へ進む（何度も「もう一度答えてください」と出さない）。
   */
  gone?: true;
  history_saved?: boolean;
};

/** 札がもう無い時の返事（呼ぶたびに新しい物 — 返した物を誰かが書き換えても次に響かない）。 */
const gone = (): GradeResult => ({
  score: null,
  next_due_at: null,
  interval_days: null,
  duplicate: false,
  gone: true,
});

const REVIEW_COLUMNS =
  "id, sticker_id, ease, interval_days, repetitions, blur_seen, last_reviewed_at, due_at, last_score";

/**
 * **採点の本体**（`gradeReview`。試験から直に呼ぶ）。
 *
 * 2026-10-15 18:53（台湾）本番: iOS の復習で 內褲 を答えると「採点を保存できませんでした…サーバーエラー（500）」。
 * その札（sticker 71282f52…）と復習の行は今は無い（図鑑から消すと復習の行も連鎖で消える。同じ回のほかの 49 枚は
 * 保存されている）。前はここで `.single()` で行を読み、**行が無いと PostgREST の英語の失敗（PGRST116 "Cannot coerce
 * the result to a single JSON object"）をそのまま投げて 500** にしていた（iOS は英語の文を日本語の画面に出さず
 * 「サーバーエラー（500）」と出す）。iOS は回の札を最初に読んだまま使い、保存に失敗した札を回の最後に戻す（iOS #32）
 * ので、回の途中で消えた札は何度答えても 500 になる。DB に一瞬届かなかった時も同じ 500 だった。
 *
 * - 行が無い → 何も書かずに `gone: true`（200）。もう一度届いても同じ（冪等）。
 * - もう採点済み（期限が先）・同時に2回届いた後の方 → 今の状態を `duplicate: true` で返す（1回分しか進めない）。
 * - DB に届かない・書けない → 503 と読める文（`GradeSaveError`。もう一度答えれば保存される）。500 にしない。
 * - 形の違う入力 → 400（`parseGradeInput` の ZodError、`native-fn.ts` の `statusForError`）。
 * - Jev の記録が読み込めなくても採点は止めない（予定は FSRS のまま）。
 */
export async function gradeReviewWith(
  context: { supabase: SupabaseClient<Database>; userId: string },
  data: GradeInputData,
  deps: { loadJev?: () => Promise<GradeJev>; now?: () => number } = {},
): Promise<GradeResult> {
  const { supabase, userId } = context;
  const readRow = () =>
    supabase
      .from("reviews")
      .select(REVIEW_COLUMNS)
      .eq("id", data.review_id)
      .eq("user_id", userId)
      .maybeSingle();
  const { data: row, error } = await readRow();
  if (error) {
    console.error("[reviews] gradeReview: review read failed", {
      reviewId: data.review_id,
      message: error.message,
    });
    throw new GradeSaveError();
  }
  if (!row) {
    console.info("[reviews] gradeReview: review gone (card deleted or not this account's)", {
      reviewId: data.review_id,
    });
    return gone();
  }

  /**
   * **同じ答えが2回届いても、1回分しか進めない**（2026-10-01）。
   * 復習に出す札は期限が来た物だけ（`getDueReviews` の `due_at <= 今`）。採点すると
   * 期限が先へ動くので、期限がまだ先の札への採点は「もう採点済み」— 通信のやり直し・
   * 二重送信・別の端末で先に済ませた札。進めずに今の状態を返す。
   */
  const nowMs = deps.now?.() ?? Date.now();
  // 期限は「最後の復習 + 180 日」で頭を打つ（`effectiveDueMs`）。2026-10-03 より前の
  // 数年先の期限の札も、出題された（`dueNowOrFilter`）なら採点できる。
  if (isAlreadyGraded(effectiveDueIso(row.due_at, row.last_reviewed_at), nowMs)) {
    return {
      score: row.last_score ?? 0,
      next_due_at: row.due_at as string,
      interval_days: row.interval_days,
      duplicate: true,
    };
  }

  // Score: correct=5 base; blur penalty -1; slow (>8s) -1; wrong=1.
  let score = 1;
  if (data.correct) {
    score = 5;
    if (data.blur_seen) score -= 1;
    if (data.response_ms > 8000) score -= 1;
  }
  score = Math.max(0, Math.min(5, score));

  const elapsedDays = row.last_reviewed_at
    ? (nowMs - new Date(row.last_reviewed_at).getTime()) / 86400_000
    : null;
  const srs = nextSrs(
    { ease: row.ease, interval_days: row.interval_days, repetitions: row.repetitions },
    score,
    // 復習はすべて 4択（`LightModeCard`）。見分けた証拠なので伸びは控えめ（srs.ts の冒頭）。
    { elapsedDays, evidence: "choice" },
  );

  /**
   * **次の復習の日を誰が決めるか**（`jevIntervalMode`）。
   *
   * 既定はアプリの式（FSRS、`srs.ts`。オーナー判断 2026-10-01「影の実行に戻す」）。
   * Jev の答えは記録だけ（採点の後に聞くので、採点は Jev を待たない）。`live` のとき
   * だけ、FSRS の日数を基準にして Jev の日数を柵の中に収める（`pickInterval`:
   * 思い出せなかった語は FSRS の学び直しの日のまま、Jev の答えが無ければ FSRS のまま、
   * FSRS の半分〜2倍まで）。`interval_days` 列は安定度 S そのもの（出す日 = S）なので、
   * live で Jev の日数を入れると、その語の S は Jev の日数になる。
   */
  const lastMs = row.last_reviewed_at ? new Date(row.last_reviewed_at).getTime() : null;
  const now = nowMs;
  const daysSince = lastMs == null ? null : Math.round(((now - lastMs) / 86400_000) * 10) / 10;
  const recalled = score >= LAPSE_SCORE;
  // Jev の記録が読み込めなくても採点は止めない（予定は FSRS、記録は無し）。
  let jevTasks: GradeJev | null = null;
  try {
    jevTasks = await (deps.loadJev ?? (() => import("./jev-tasks.server")))();
  } catch (e) {
    console.warn("[reviews] gradeReview: Jev tasks unavailable, FSRS only", (e as Error)?.message);
  }
  const noJev: GradeJev = {
    jevIntervalMode: async () => "shadow",
    jevScheduleDays: async () => null,
    logScheduleDecision: async () => undefined,
    recordRecallShadow: async () => undefined,
  };
  const { jevIntervalMode, jevScheduleDays, logScheduleDecision, recordRecallShadow } =
    jevTasks ?? noJev;
  const mode = await jevIntervalMode();
  const scheduleArgs = {
    userId,
    stickerId: row.sticker_id,
    state: {
      headword: "",
      daysSinceLastReview: daysSince,
      intervalDaysBefore: row.interval_days,
      ease: row.ease,
      repetitionsBefore: row.repetitions,
      recalled,
      score,
      responseSeconds: data.response_ms > 0 ? Math.round(data.response_ms / 100) / 10 : null,
    },
  };
  const jev =
    mode === "live" && score >= LAPSE_SCORE
      ? await jevScheduleDays(supabase as never, scheduleArgs)
      : null;
  const picked = pickInterval(srs.interval_days, jev?.days ?? null, score, LAPSE_SCORE);
  // Jev（live）の日数も上限 180 日の中に収める（`MAX_INTERVAL_DAYS`。4択だけの証拠）。
  const next = { ...srs, interval_days: Math.min(picked.days, MAX_INTERVAL_DAYS) };
  const dueAt = new Date(now + next.interval_days * 86400 * 1000).toISOString();

  // 読んだ時の期限のままの時だけ書く（同時に2回届いた時、後の方は0行になる）。
  const updateQuery = supabase
    .from("reviews")
    .update({
      ease: next.ease,
      interval_days: next.interval_days,
      repetitions: next.repetitions,
      last_score: score,
      last_reviewed_at: new Date(now).toISOString(),
      due_at: dueAt,
      blur_seen: row.blur_seen || data.blur_seen,
    })
    .eq("id", data.review_id)
    .eq("user_id", userId);
  const { data: updated, error: upErr } = await (
    row.due_at ? updateQuery.eq("due_at", row.due_at) : updateQuery.is("due_at", null)
  ).select("id");
  if (upErr) {
    console.error("[reviews] gradeReview: review update failed", {
      reviewId: data.review_id,
      message: upErr.message,
    });
    throw new GradeSaveError();
  }
  if (!updated || updated.length === 0) {
    // 同じ答えが同時に2回届き、先の方がもう書いた（か、その間に札が消えた）。こちらは何も進めず、
    // 先の方が書いた今の状態を返す。読めなければ、こちらで計算した値（どちらにしても進めていない）。
    const { data: now2, error: reErr } = await readRow();
    if (!reErr && !now2) return gone();
    return {
      score: now2?.last_score ?? score,
      next_due_at: (now2?.due_at as string | undefined) ?? dueAt,
      interval_days: now2?.interval_days ?? next.interval_days,
      duplicate: true,
    };
  }

  /**
   * 忘却曲線の記録。**落ちたら黙らない**（2026-10-01）— 前は失敗を見ていなかったので、
   * 曲線と「今日やった枚数」が静かに欠けていた。1回だけやり直し、それでも駄目なら
   * サーバの記録に残す（採点そのものは済んでいるので、利用者は止めない）。
   */
  const historyRow = {
    user_id: userId,
    review_id: data.review_id,
    sticker_id: row.sticker_id,
    score,
    correct: data.correct,
    blur_seen: data.blur_seen,
    // 列は integer（2^31 − 1 ms ≒ 24 日）。開いたまま放っておいた札で記録が落ちないよう頭を打つ。
    response_ms: Math.min(data.response_ms, MAX_RESPONSE_MS),
    interval_days_after: next.interval_days,
    ease_after: next.ease,
    repetitions_after: next.repetitions,
  };
  let { error: histErr } = await supabase.from("review_history").insert(historyRow);
  if (histErr) ({ error: histErr } = await supabase.from("review_history").insert(historyRow));
  if (histErr) {
    console.error("[reviews] review_history insert failed", {
      userId,
      reviewId: data.review_id,
      message: histErr.message,
    });
  }

  /**
   * **記録**（待たない — 復習の返事を遅らせない）。
   *  ・決めた間隔（Jev の日数・SM-2 の日数・使った日数）
   *  ・答える**前**の状態だけで Jev が出した「いま思い出せるか」と、
   *    このアプリの式の見込み・実際の正誤（較正を見るため）
   * 鍵が無ければ何もしない。
   */
  // **返事の後も記録を落とさない**（2026-10-03 監査）。Workers は返事の後の `void …` を
  // 待たずに止めてよいので、影の記録が黙って消えていた。`runAfterResponse` が
  // `waitUntil` に預ける（採点の返事は待たせない。見つからない Workers では最大2秒待つ）。
  const baseline = retentionNow(row.interval_days, row.ease, lastMs, now) / 100;
  const shadowTasks: Array<() => Promise<unknown>> = [];
  if (jev) {
    shadowTasks.push(() =>
      logScheduleDecision(supabase as never, {
        userId,
        stickerId: row.sticker_id,
        model: jev.model,
        confidence: jev.confidence,
        jevDays: jev.days,
        srsDays: srs.interval_days,
        usedDays: next.interval_days,
        mode,
      }),
    );
  } else if (mode === "shadow" && score >= LAPSE_SCORE) {
    // 影の実行: 採点の後で Jev に聞き、答えを記録するだけ（予定は FSRS のまま）。
    shadowTasks.push(() =>
      jevScheduleDays(supabase as never, scheduleArgs).then((shadow) => {
        if (!shadow) return;
        return logScheduleDecision(supabase as never, {
          userId,
          stickerId: row.sticker_id,
          model: shadow.model,
          confidence: shadow.confidence,
          jevDays: shadow.days,
          srsDays: srs.interval_days,
          usedDays: next.interval_days,
          mode,
        });
      }),
    );
  }
  shadowTasks.push(() =>
    recordRecallShadow(supabase as never, {
      userId,
      stickerId: row.sticker_id,
      outcome: recalled,
      state: {
        headword: "",
        daysSinceLastReview: daysSince,
        intervalDays: row.interval_days,
        ease: row.ease,
        repetitions: row.repetitions,
        baselineRecall: Math.max(0, Math.min(1, baseline)),
      },
    }),
  );
  await runAfterResponse("review shadow log", () => Promise.all(shadowTasks.map((t) => t())));

  return {
    score,
    next_due_at: dueAt,
    interval_days: next.interval_days,
    duplicate: false,
    history_saved: !histErr,
  };
}

// --- Forgetting curve data ---------------------------------------------------

export type StickerMemoryHistory = {
  history: Array<{
    reviewed_at: string;
    score: number;
    interval_days_after: number;
    ease_after: number;
  }>;
  current: {
    ease: number;
    interval_days: number;
    last_reviewed_at: string | null;
    due_at: string | null;
  } | null;
  /** 未復習でも曲線を引くための起点(この単語をキャッチした日)。 */
  taken_at: string | null;
};

export const getStickerMemoryHistory = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => z.object({ sticker_id: z.string().uuid() }).parse(input))
  .handler(async ({ context, data }): Promise<StickerMemoryHistory> => {
    const { supabase, userId } = context;
    const [{ data: hist }, { data: rev }, { data: st }] = await Promise.all([
      supabase
        .from("review_history")
        .select("reviewed_at, score, interval_days_after, ease_after")
        .eq("user_id", userId)
        .eq("sticker_id", data.sticker_id)
        .order("reviewed_at", { ascending: true }),
      supabase
        .from("reviews")
        .select("ease, interval_days, last_reviewed_at, due_at")
        .eq("user_id", userId)
        .eq("sticker_id", data.sticker_id)
        .maybeSingle(),
      supabase
        .from("stickers")
        .select("taken_at")
        .eq("user_id", userId)
        .eq("id", data.sticker_id)
        .maybeSingle(),
    ]);
    return {
      history: hist ?? [],
      current: rev
        ? {
            ease: rev.ease,
            interval_days: rev.interval_days,
            last_reviewed_at: rev.last_reviewed_at,
            // 次の復習日も 180 日で頭打ち（`effectiveDueIso`）。
            due_at: effectiveDueIso(rev.due_at, rev.last_reviewed_at),
          }
        : null,
      taken_at: (st as { taken_at?: string | null } | null)?.taken_at ?? null,
    };
  });

export type OverallMemoryStats = {
  /** いまの平均記憶率(0-100)。数えられる語が無ければ null。 */
  avg_retention: number | null;
  total_cards: number;
  due_now: number;
  /** -14..+14。過去は `review_history` から復元した**その日の状態**。 */
  series: RetentionPoint[];
};

export const getOverallMemoryStats = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }): Promise<OverallMemoryStats> => {
    const { supabase, userId } = context;
    /**
     * **全体の記憶率も学習言語で分ける**（オーナー指示 2026-08-26
     * 「記憶の状態の全体の記憶率も学習言語によって区別して」）。
     *
     * 隣の一覧（`getMemoryOverview`）は前の周で絞ったのに、**この数だけ
     * 素通し**だった。だから同じ画面の中で、上のバーは両方の言語を混ぜた
     * 平均、下の一覧は英語だけ、という食い違いが起きていた。
     */
    const targetLanguage = await getUserTargetLanguage(userId);
    // 過去側は**記録**から作る。ここを現在の状態から作っていたせいで、
    // 復習した瞬間に過去14日が全部 100% に塗り替わっていた
    // (`src/lib/retention-series.ts` の冒頭に経緯)。
    //
    // **PostgREST は1回に1000行で切る**（2026-10-03 監査）。札は上限なしで読んでいたので
    // 1000 枚で黙って止まり、記録は古い順に `.limit(5000)` だったので 1000 回答えた後は
    // **いちばん古い 1000 件**だけで線を引いていた（最近の復習が全部抜ける）。両方とも
    // `readAllPages` で全部読む。記録は新しい順に読んでから古い順に戻す — 安全の上限で
    // 止まっても抜けるのは古い側だけになる。
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const db = supabase as any;
    const [{ rows }, { rows: histNewestFirst }] = await Promise.all([
      readAllPages<unknown>((a, b) =>
        db
          .from("reviews")
          .select(
            "sticker_id, ease, interval_days, last_reviewed_at, due_at, stickers(taken_at, words(language))",
          )
          .eq("user_id", userId)
          .order("id")
          .range(a, b),
      ),
      readAllPages<unknown>((a, b) =>
        db
          .from("review_history")
          .select("sticker_id, reviewed_at, interval_days_after, ease_after")
          .eq("user_id", userId)
          .order("reviewed_at", { ascending: false })
          .order("id")
          .range(a, b),
      ),
    ]);
    const hist = [...histNewestFirst].reverse();
    type StatRow = {
      sticker_id: string;
      ease: number;
      interval_days: number;
      last_reviewed_at: string | null;
      due_at: string | null;
      stickers?: { taken_at?: string | null; words?: { language?: string | null } | null } | null;
    };
    // 判定は `language-filter.ts` の1つだけ(一覧・今日の列と同じ規則)。
    const raw = ((rows ?? []) as unknown as StatRow[]).filter((r) =>
      matchesTargetLanguage(r.stickers?.words?.language, targetLanguage),
    );
    /**
     * **記録も同じ札のものだけ。** 絞った札の記録に、別の言語の札の
     * 記録が混ざったままだと、過去側の線がその言語を始める前から
     * 描かれてしまう（始めた日から描く直しが効かない）。
     */
    const keep = new Set(raw.map((r) => r.sticker_id));
    const cards: RetentionCard[] = raw.map((r) => ({
      sticker_id: r.sticker_id,
      taken_at: r.stickers?.taken_at ?? null,
      ease: r.ease,
      interval_days: r.interval_days,
      last_reviewed_at: r.last_reviewed_at,
    }));
    const events = ((hist ?? []) as unknown as RetentionEvent[]).filter((e) =>
      keep.has(e.sticker_id),
    );
    const now = Date.now();
    const dueNow = raw.filter((r) => {
      const due = effectiveDueMs(r.due_at, r.last_reviewed_at);
      return due != null && due <= now;
    }).length;

    const { series, avg_retention } = buildRetentionSeries({ cards, events, nowMs: now });

    return { avg_retention, total_cards: cards.length, due_now: dueNow, series };
  });

// --- B5 記憶の状態ビジュアライズ ---------------------------------------------
export type MemoryWord = {
  sticker_id: string;
  headword: string;
  retention: number; // 0-100(現在の推定記憶率)
  interval_days: number;
  repetitions: number;
  due_at: string | null;
  days_until_forgot: number | null; // 記憶率が50%を切るまでの日数(既に下回れば0)
  fresh: boolean; // 覚えたて(repetitions<=2)
  long_term: boolean; // 長期定着(interval>=30日)
  /** 記憶の起点(最終復習 or 未復習ならキャッチ日)。曲線の描画に使う。 */
  anchor_at: string | null;
  /** 現在の安定度(日) — 記憶率が 90% に落ちるまでの日数（FSRS の S）。未復習は 0。 */
  stability_days: number;
  ease: number;
};
export type MemoryOverview = {
  danger: number; // retention < 50
  fuzzy: number; // 50-80
  solid: number; // > 80
  words: MemoryWord[];
};

export const getMemoryOverview = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }): Promise<MemoryOverview> => {
    const { supabase, userId } = context;
    /**
     * **記憶の状態も学習言語で分ける**(オーナー報告 2026-08-26、2度目)。
     * > 「復習の記憶の状態が学習言語を英語に切り替えたのに、台湾華語の
     * >  単語が表示されてる。学習言語によって区別して混ざらないように。」
     *
     * ここには絞りが**1つも無かった**。出す列の一覧を作るときに
     * `language` を持ってきていないので、絞りようも無かった。
     * 今日の列(`getDueReviews`)だけ直しても、この画面は混ざったまま。
     */
    const targetLanguage = await getUserTargetLanguage(userId);
    // 札は 1000 枚を超えうる。PostgREST の既定の上限で黙って切られないよう、
    // `readAllPages` で全部読む（2026-10-03 監査）。
    const { rows } = await readAllPages<unknown>((a, b) =>
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      (supabase as any)
        .from("reviews")
        .select(
          "sticker_id, ease, interval_days, repetitions, last_reviewed_at, due_at, stickers(taken_at, words(headword, language))",
        )
        .eq("user_id", userId)
        .order("id")
        .range(a, b),
    );
    const now = Date.now();
    type Row = {
      sticker_id: string;
      ease: number;
      interval_days: number;
      repetitions: number;
      last_reviewed_at: string | null;
      due_at: string | null;
      stickers: {
        taken_at?: string | null;
        words: { headword: string; language?: string | null } | null;
      } | null;
    };
    const words: MemoryWord[] = ((rows ?? []) as unknown as Row[])
      .filter((r) => r.stickers?.words)
      // 判定は `language-filter.ts` の1つだけ(今日の列と同じ規則。見出しの字も見る)。
      .filter((r) => wordBelongsToTarget(r.stickers?.words, targetLanguage))
      .map((r) => {
        // 曲線の起点は最後の復習、無ければ「その単語に出会った瞬間」= sticker.taken_at。
        // ただし % は**最後の復習からだけ**数える: 未復習の札は 0%（撮っただけでは
        // まだ覚えていない — オーナー指示 2026-10-02）。出題の札（getDueReviews）も同じ規則。
        const anchorIso = r.last_reviewed_at ?? r.stickers?.taken_at ?? null;
        const anchorMs = anchorIso ? new Date(anchorIso).getTime() : null;
        const lastMs = r.last_reviewed_at ? new Date(r.last_reviewed_at).getTime() : null;
        const stability = stabilityOf(r.interval_days, r.ease);
        const retention = Math.round(retentionNow(r.interval_days, r.ease, lastMs, now));
        // 50% まで落ちる日（忘却曲線の逆。未復習なら 0）。
        let daysUntilForgot: number | null = null;
        if (anchorMs != null) {
          const dtNow = (now - anchorMs) / 86400_000;
          daysUntilForgot = Math.max(0, Math.round(daysUntilRetention(stability, 0.5) - dtNow));
        }
        return {
          sticker_id: r.sticker_id,
          headword: r.stickers!.words!.headword,
          retention,
          interval_days: r.interval_days,
          repetitions: r.repetitions,
          due_at: effectiveDueIso(r.due_at, r.last_reviewed_at),
          days_until_forgot: daysUntilForgot,
          fresh: r.repetitions <= 2,
          long_term: r.interval_days >= 30,
          anchor_at: anchorIso,
          stability_days: stability,
          ease: r.ease,
        };
      })
      .sort((a, b) => a.retention - b.retention); // 危険な語を上に

    return {
      danger: words.filter((w) => w.retention < 50).length,
      fuzzy: words.filter((w) => w.retention >= 50 && w.retention <= 80).length,
      solid: words.filter((w) => w.retention > 80).length,
      words,
    };
  });

/**
 * **これから24時間で復習の時が来る語の時刻**（通知の「おまかせ」用。
 * `review-reminder.ts` の `srsBestTime`）。時が過ぎている語も含む。
 * 絞りは `getDueReviews` と同じ学習言語（ほかの言語の語で鳴らさない）。
 */
export const getUpcomingDueTimes = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const { supabase, userId } = context;
    const horizon = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
    const targetLanguage = await getUserTargetLanguage(userId);
    const langFilter = wordLanguageFilter(targetLanguage);
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const db = supabase as any;
    let res = await db
      .from("reviews")
      .select("due_at, stickers!inner(words!inner(language))")
      .eq("user_id", userId)
      .lte("due_at", horizon)
      .or(langFilter, { referencedTable: "stickers.words" })
      .order("due_at", { ascending: true })
      .limit(200);
    if (res.error) {
      res = await db
        .from("reviews")
        .select("due_at")
        .eq("user_id", userId)
        .lte("due_at", horizon)
        .order("due_at", { ascending: true })
        .limit(200);
    }
    const rows = (res.error ? [] : (res.data ?? [])) as Array<{ due_at: string | null }>;
    return {
      dueTimes: rows.map((r) => r.due_at).filter((v): v is string => !!v),
      quiz: await reminderQuiz(db, userId, horizon, langFilter, targetLanguage),
    };
  });

/**
 * **通知の1問**（オーナー指示 2026-09-28「通知は写真付きで1問だけのタイプにする」）。
 *
 * これから24時間で時が来る語のうち、**いちばん早い・写真のある**1語。写真の
 * ある語が無ければ、いちばん早い語（文字から作った語 — 意味で問う）。
 * 通知を押すと `/review?sticker=…` でこの語から始まる（`deep-link.ts`）。
 *
 * 写真は非公開の保存場所なので**署名した URL**（6時間で切れる。切れても通知の
 * 文は出る）。読めない・列が無いときは `null`（通知は語数だけの文に戻る）。
 */
export type ReminderQuiz = {
  sticker_id: string;
  headword: string;
  meaning_ja: string | null;
  image_url: string | null;
  /**
   * **写真を撮った時刻**（撮った語だけ。文字から作った語は `null`）。通知の題
   * 「〇か月前に撮ったこの単語、覚えてる？」の「〇か月前」に使う（オーナー指示 2026-10-07）。
   * 古い版のサーバの返事には無いので省略可。
   */
  caught_at?: string | null;
};
async function reminderQuiz(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  db: any,
  userId: string,
  horizon: string,
  langFilter: string,
  targetLanguage: string,
): Promise<ReminderQuiz | null> {
  try {
    const { data, error } = await db
      .from("reviews")
      .select(
        "sticker_id, due_at, stickers!inner(object_image_url, cutout_image_url, placeholder_image_url, capture_type, taken_at, created_at, words!inner(headword, language, meaning_ja))",
      )
      .eq("user_id", userId)
      .lte("due_at", horizon)
      .or(langFilter, { referencedTable: "stickers.words" })
      .order("due_at", { ascending: true })
      .limit(20);
    if (error || !data?.length) return null;
    type Row = {
      sticker_id: string;
      stickers: {
        object_image_url: string | null;
        cutout_image_url: string | null;
        placeholder_image_url: string | null;
        capture_type?: string | null;
        taken_at?: string | null;
        created_at?: string | null;
        words: { headword: string; language?: string | null; meaning_ja: string | null } | null;
      } | null;
    };
    // 通知の1問にも、見出しの字が学習言語でない語を出さない（`getDueReviews` と同じ規則）。
    const rows = (data as Row[]).filter(
      (r) => r.stickers?.words?.headword && wordBelongsToTarget(r.stickers.words, targetLanguage),
    );
    const photoOf = (r: Row) =>
      r.stickers?.object_image_url ??
      r.stickers?.cutout_image_url ??
      r.stickers?.placeholder_image_url ??
      null;
    const pick = rows.find((r) => photoOf(r)) ?? rows[0];
    if (!pick) return null;
    const path = photoOf(pick);
    let image_url: string | null = null;
    if (path) {
      const { signUrlMap } = await import("./stickers.functions");
      image_url = (await signUrlMap(db, [path])).get(path) ?? null;
    }
    return {
      sticker_id: pick.sticker_id,
      headword: pick.stickers!.words!.headword,
      meaning_ja: pick.stickers!.words!.meaning_ja,
      image_url,
      caught_at:
        pick.stickers!.capture_type === "photo"
          ? (pick.stickers!.taken_at ?? pick.stickers!.created_at ?? null)
          : null,
    };
  } catch {
    return null;
  }
}
