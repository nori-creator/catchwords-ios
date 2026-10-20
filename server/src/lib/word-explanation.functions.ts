import { createServerFn } from "@tanstack/react-start";
import { readerMeaning, readerText } from "./note-language";
import { meaningRule, shortMeaning } from "./meaning-rule";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { z } from "zod";
import { normalizeExtras, publicExtras } from "./extras";
import { UI_LANGS } from "./i18n";
import { fillReaderExplanation } from "./shared-word-guard";
import {
  explanationKey,
  pickExplanation,
  readerMeaningWriteTarget,
  type ExplanationRow,
} from "./word-explanation";

/**
 * 語の解説を**共有キャッシュ**から引く / 置く。
 *
 * オーナー指示 2026-08-24:
 * > 「カードの解説や復習の解説や日記の解説が**ユーザーにストレスを感じさせない
 * >  速度**で実行したい」
 *
 * ## なぜ別の server fn にしたか
 * `getSticker` に混ぜなかったのは、解説だけを別に取り直したいから。
 * 裏で項目を1つずつ埋めていく間(`auto-fill.ts`)、札の写真や場所まで
 * 取り直す必要は無い。問い合わせの鍵を分けておけば、解説が届いたときに
 * 解説だけが描き直る。
 *
 * ## 移行が当たっていなくても壊さない
 * `word_explanations` はまだ流していない移行で作られる。表が無い環境では
 * **静かに「解説なし」を返す** — 呼ぶ側は古い `words.extras` に落ちるので、
 * いままでどおり動く(遅いままなだけ)。
 */

/**
 * 生成済みの型定義に無い表を触るための緩い形。
 * **`any` を撒かない** — 使う所だけを書いて、それ以外は型で止める。
 */
type LooseDb = {
  from: (table: string) => {
    select: (cols: string) => {
      eq: (
        k: string,
        v: string,
      ) => Promise<{
        data: Record<string, unknown>[] | null;
        error: { message: string } | null;
      }>;
    };
  };
};

const GetInput = z.object({
  word_id: z.string().uuid(),
  /** 解説を書く言語(= 表示言語)。 */
  explain_lang: z.string().min(1).max(16),
  /** 誰の母語向けか。 */
  l1: z.string().min(1).max(16),
});

export type WordExplanationResult = {
  /** その人に出す解説。無ければ null(呼ぶ側が作る)。 */
  picked: ExplanationRow | null;
  /**
   * 表がまだ無い(移行待ち)。
   * **黙って「解説なし」と区別する** — 移行待ちなら作りに行っても
   * 保存できないので、呼ぶ側が無駄なAIを呼ばずに済む。
   */
  unavailable: boolean;
  /**
   * メインの例文の札を、返事の後で書きに行った（`example-scene-label.server.ts`）。画面はこの返事を
   * 「すぐ古くなる」扱いにして、次に開いた時に読み直す（PR #189 の点検 P2 — 30 分持たない）。
   */
  labelPending?: boolean;
};

export const getWordExplanation = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => GetInput.parse(input))
  .handler(async ({ context, data }): Promise<WordExplanationResult> => {
    // `word_explanations` は生成済みの型定義より新しい表(移行
    // 20260824120000)。型を再生成するまでは緩いクライアントとして扱う
    // — `app_config` で既に使っている作法(`ai-provider.server.ts`)。
    const db = context.supabase as unknown as LooseDb;
    const { data: rows, error } = await db
      .from("word_explanations")
      .select("explain_lang, l1, meaning, example_translation, extras, source")
      .eq("word_id", data.word_id);
    if (error) {
      // 表がまだ無い = 移行待ち。**記録には残す**(黙って飲まない)。
      if (/word_explanations/.test(error.message)) {
        console.warn("getWordExplanation: 表がまだ無い", error.message);
        return { picked: null, unavailable: true };
      }
      throw new Error(error.message);
    }
    const parsed: ExplanationRow[] = (rows ?? []).map((r) => ({
      explain_lang: String(r.explain_lang ?? ""),
      l1: String(r.l1 ?? ""),
      meaning: String(r.meaning ?? ""),
      example_translation: (r.example_translation as string | null) ?? null,
      // 退役した欄（口語/書面の札）は返さない（2026-10-15）。
      extras: publicExtras(r.extras),
      source: (r.source as string | null) ?? "ai",
    }));
    const picked = pickExplanation(parsed, explanationKey(data.explain_lang, data.l1));
    // 語の行（言語・見出し語・メインの例文・共有の解説）。読みを付ける時と、メインの例文の札を確かめる時に
    // 使う（1回の読み）。
    let word: {
      language: string | null;
      headword: string;
      example_sentence: string | null;
      extras: unknown;
      source: string | null;
    } | null = null;
    try {
      const { data: ws } = await db
        .from("words")
        .select("language, headword, example_sentence, extras, source")
        .eq("id", data.word_id);
      const w = ws?.[0];
      if (w) {
        word = {
          language: (w.language as string | null | undefined) ?? null,
          headword: String(w.headword ?? ""),
          example_sentence: (w.example_sentence as string | null | undefined) ?? null,
          extras: w.extras ?? null,
          source: (w.source as string | null | undefined) ?? null,
        };
      }
    } catch (e) {
      console.warn("getWordExplanation: 語の行を読めない", (e as Error)?.message);
    }
    if (!picked) {
      /**
       * 読む人の行が無い語は、画面が共有の解説（同じ言語で書かれていれば）を出す。その共有の行の札の無い
       * 例文も、返事の後で札を付ける（PR #189 の点検 P2）。
       */
      const labelPending = word
        ? await scheduleLabelIfNeeded({
            userId: context.userId,
            wordId: data.word_id,
            key: explanationKey(data.explain_lang, data.l1),
            reader: null,
            shared: { extras: word.extras, source: word.source },
            word,
          })
        : false;
      return { picked, unavailable: false, ...(labelPending ? { labelPending } : {}) };
    }
    /**
     * 台湾華語の語なら、型の札に読み（拼音・注音）を付けて返す（2026-10-15、`chunk-readings.server.ts`）。
     * 古い解説は読みを持っていないので、読む所で辞書から付ける。
     */
    if (
      picked.extras &&
      (picked.extras.usage_chunks?.length || picked.extras.example_chunks?.length)
    ) {
      try {
        const { withChunkReadingsInExtras } = await import("./chunk-readings.server");
        picked.extras = withChunkReadingsInExtras(picked.extras, word?.language ?? null);
      } catch (e) {
        console.warn("getWordExplanation: 型の読みを付けられなかった", (e as Error)?.message);
      }
    }
    /**
     * **札の無い古いメインの例文**（2026-10-16 冰淇淋「夏天吃冰淇淋。」）。返事の後で札だけを書く小さな呼び出しを
     * 1回する（文は変えない。次に開いた時に出る — `example-scene-label.server.ts`）。返事は待たせない。
     */
    const labelPending = word
      ? await scheduleLabelIfNeeded({
          userId: context.userId,
          wordId: data.word_id,
          key: { explainLang: picked.explain_lang, l1: picked.l1 },
          // 選んだ読む人の行と、同じ言語の共有の行（図鑑から開いた詳細が出す）の**どちらか**が直せれば頼む。
          reader: { extras: picked.extras, source: picked.source },
          shared: { extras: word.extras, source: word.source },
          word,
        })
      : false;
    return { picked, unavailable: false, ...(labelPending ? { labelPending } : {}) };
  });

/**
 * 画面に出し得る解説（選んだ読む人の行・同じ言語の共有の行）のメインの例文に札が無ければ、返事の後で
 * 札を付けに行く。頼んだら true。頼むかは `shouldLabelMainExample`（直せる行が無い・AI が要るのに同意が
 * 無い・自分の語でない時は頼まない）。**投げない**（読むだけの道を落とさない）。
 */
async function scheduleLabelIfNeeded(input: {
  userId: string;
  wordId: string;
  key: { explainLang: string; l1: string };
  /** 選んだ読む人の行（無ければ null。在って extras が空の行も、札の無い行として扱う）。 */
  reader: { extras: unknown; source?: string | null } | null;
  /** 共有の行（言語と、人が確かめた語かは `shouldLabelMainExample` が見る）。 */
  shared: { extras: unknown; source?: string | null };
  word: { language: string | null; headword: string; example_sentence: string | null };
}): Promise<boolean> {
  try {
    const label = await import("./example-scene-label.server");
    if (
      !(await label.shouldLabelMainExample({
        userId: input.userId,
        wordId: input.wordId,
        reader: input.reader,
        shared: input.shared,
        lang: input.key.explainLang,
        word: input.word,
      }))
    ) {
      return false;
    }
    await label.scheduleMainExampleLabel({
      userId: input.userId,
      wordId: input.wordId,
      key: input.key,
    });
    return true;
  } catch (e) {
    // 頼む段の失敗も開発者の記録に数える（読む道は落とさない — PR #189 の点検）。
    try {
      const { reportServerBackgroundFailure } = await import("./background-failure.server");
      await reportServerBackgroundFailure("scene_label", input.userId, e, {
        where: "scheduleLabelIfNeeded",
        word_id: input.wordId,
      });
    } catch {
      console.warn("getWordExplanation: 例文の札を頼めなかった", (e as Error)?.message);
    }
    return false;
  }
}

/**
 * 解説を共有キャッシュへ置く。
 *
 * **`updateWordExtras` から呼ぶ。** 置き場所は `explain_lang` / `l1` の鍵で決まる。
 *
 * **空の所だけ埋める**（監査 2026-10-03 H2）。鍵が「語 × 解説の言語 × 母語」なので、
 * 同じ鍵の行は**同じ言語・同じ母語で読む全員**が見る。前はここで行ごと上書きしていたので、
 * 札を1枚持てば、その全員の解説を好きな文に変えられた。判断は
 * `fillReaderExplanation`（`shared-word-guard.ts`）1つ — 行が無ければ置き、在れば空の項目
 * （と、読む人の言語で書かれていない意味・訳）だけを埋める。
 *
 * **人が確かめた解説は触らない**。中身を丸ごと作り直して書くのは、サーバが自分で作って
 * 確かめる道（`runSectionRegen` → `mergeIntoReaderExplanation`）だけ。
 */
export async function saveWordExplanation(
  admin: unknown,
  input: {
    word_id: string;
    explain_lang: string;
    l1: string;
    meaning: string;
    example_translation?: string | null;
    extras: Record<string, unknown>;
  },
): Promise<{ saved: boolean; reason?: string }> {
  const key = explanationKey(input.explain_lang, input.l1);
  const db = admin as SaveDb;
  try {
    const { data: existing, error: readErr } = await db
      .from("word_explanations")
      .select("meaning, example_translation, extras, source")
      .eq("word_id", input.word_id)
      .eq("explain_lang", key.explainLang)
      .eq("l1", key.l1)
      .maybeSingle();
    if (readErr) {
      if (/word_explanations/.test(readErr.message)) {
        console.warn("saveWordExplanation: 表がまだ無い", readErr.message);
        return { saved: false, reason: "migration" };
      }
      // 読めないまま書くと、在る行を上書きしかねない。**書かない。**
      console.warn("saveWordExplanation: 行を読めない", readErr.message);
      return { saved: false, reason: "error" };
    }
    const write = fillReaderExplanation(
      existing as Record<string, unknown> | null as never,
      {
        meaning: input.meaning,
        // 読む人の言語でない訳（例文の写しなど）は貯めない（2026-09-29）。
        example_translation: readerText(input.example_translation, key.explainLang) || null,
        extras: input.extras,
      },
      key.explainLang,
    );
    if (write.kind === "skip") return { saved: false, reason: write.reason };
    const now = new Date().toISOString();
    const { error } =
      write.kind === "insert"
        ? await db.from("word_explanations").upsert(
            [
              {
                word_id: input.word_id,
                explain_lang: key.explainLang,
                l1: key.l1,
                meaning: write.row.meaning,
                example_translation: write.row.example_translation ?? null,
                extras: write.row.extras,
                source: "ai",
                updated_at: now,
              },
            ],
            // 同じ鍵の行が間に作られていたら**そちらを残す**（上書きしない）。
            { onConflict: "word_id,explain_lang,l1", ignoreDuplicates: true },
          )
        : await db
            .from("word_explanations")
            .update({ ...write.patch, updated_at: now })
            .eq("word_id", input.word_id)
            .eq("explain_lang", key.explainLang)
            .eq("l1", key.l1);
    if (error) {
      if (/word_explanations/.test(error.message)) {
        // 移行待ち。**黙って飲まない** — 記録には残す。
        console.warn("saveWordExplanation: 表がまだ無い", error.message);
        return { saved: false, reason: "migration" };
      }
      console.warn("saveWordExplanation failed", error.message);
      return { saved: false, reason: "error" };
    }
    return { saved: true };
  } catch (e) {
    // 解説の控えは**付け足し**。落ちてもカードの保存まで巻き込まない。
    console.warn("saveWordExplanation threw", e);
    return { saved: false, reason: "error" };
  }
}

/** `saveWordExplanation` が触る所だけを書いた緩い形（生成済みの型に無い表があるため）。 */
type SaveDb = {
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
          eq: (
            k: string,
            v: string,
          ) => {
            maybeSingle: () => Promise<{ data: unknown; error: { message: string } | null }>;
          };
        };
      };
    };
    upsert: (rows: unknown, opts: unknown) => Promise<{ error: { message: string } | null }>;
    update: (row: unknown) => {
      eq: (
        k: string,
        v: string,
      ) => {
        eq: (
          k: string,
          v: string,
        ) => { eq: (k: string, v: string) => Promise<{ error: { message: string } | null }> };
      };
    };
  };
};

const MeaningsInput = z.object({
  word_ids: z.array(z.string().uuid()).min(1).max(200),
  /** 読む人の言語（表示言語）。 */
  explain_lang: z.string().min(1).max(16),
});

/**
 * **その人の言語で書かれた意味だけを、まとめて引く**（R17「学習言語を日本語にしてるのに、
 * 図鑑のスライドの意味や例文の訳に英語が表示される…混ざらないようにシステムを作って徹底して」）。
 *
 * 図鑑・暦・地図は共有の `words.meaning_ja`（最初に作った人の言語）を出していたので、
 * 別の言語で作られた語は、その人向けの解説が出来ていても図鑑では違う言語のままだった。
 * ここは解説の表から、読む人の言語の意味だけを語ごとに返す（無ければ入れない）。
 */
export const getReaderMeanings = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => MeaningsInput.parse(input))
  .handler(async ({ context, data }): Promise<Record<string, string>> => {
    const db = context.supabase as unknown as {
      from: (t: string) => {
        select: (c: string) => {
          in: (
            k: string,
            v: string[],
          ) => {
            eq: (
              k: string,
              v: string,
            ) => Promise<{
              data: Record<string, unknown>[] | null;
              error: { message: string } | null;
            }>;
          };
        };
      };
    };
    const { data: rows, error } = await db
      .from("word_explanations")
      .select("word_id, explain_lang, l1, meaning, source")
      .in("word_id", data.word_ids)
      .eq("explain_lang", data.explain_lang);
    // 表がまだ無い環境・読めない時は空（呼ぶ側は共有の意味を言語で選り分けて出す）。
    if (error) return {};
    const out: Record<string, string> = {};
    const rank = (s: unknown) => (s === "verified" ? 2 : s === "seed" ? 1 : 0);
    const best = new Map<string, Record<string, unknown>>();
    for (const r of rows ?? []) {
      const id = String(r.word_id ?? "");
      const m = readerText(String(r.meaning ?? ""), data.explain_lang).trim();
      if (!id || !m) continue;
      const have = best.get(id);
      if (!have || rank(r.source) > rank(have.source)) best.set(id, { ...r, meaning: m });
    }
    for (const [id, r] of best) out[id] = String(r.meaning);
    return out;
  });

/**
 * 生成済みの型定義に無い表を、読み書きの両方で触るための緩い形。
 * 使う所（1行を引く・1行を書き換える）だけを書く。
 */
type LooseRowDb = {
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
          eq: (
            k: string,
            v: string,
          ) => { maybeSingle: () => Promise<{ data: unknown; error: unknown }> };
        };
      };
    };
    update: (row: unknown) => {
      eq: (
        k: string,
        v: string,
      ) => {
        eq: (k: string, v: string) => { eq: (k: string, v: string) => Promise<{ error: unknown }> };
      };
    };
  };
};

/**
 * その人向けの解説の行を1つ引く（無ければ・表が無ければ null）。
 *
 * **裏で項目を埋める処理（`runSectionRegen`）が、画面と同じ行を見るため。**
 * 画面は `word_explanations` の行があればそちらの解説を出す。埋める側が
 * 共有の `words.extras` だけを見て書いていたので、行のある語では
 * **作っても作っても画面に出ない**項目が残っていた（βテスト 2026-09-30
 * 「例文以下のチャンクなどが表示されない」）。
 */
export async function readReaderExplanation(
  admin: unknown,
  wordId: string,
  key: { explainLang: string; l1: string },
): Promise<{
  meaning: string;
  example_translation: string | null;
  extras: ReturnType<typeof normalizeExtras>;
  source: string;
} | null> {
  try {
    const { data, error } = await (admin as LooseRowDb)
      .from("word_explanations")
      .select("meaning, example_translation, extras, source")
      .eq("word_id", wordId)
      .eq("explain_lang", key.explainLang)
      .eq("l1", key.l1)
      .maybeSingle();
    if (error || !data) return null;
    const r = data as Record<string, unknown>;
    return {
      meaning: String(r.meaning ?? ""),
      example_translation: (r.example_translation as string | null) ?? null,
      extras: normalizeExtras(r.extras),
      source: String(r.source ?? "ai"),
    };
  } catch {
    return null;
  }
}

/**
 * その人向けの解説の行に、**1項目ぶんだけ**重ねて書く。
 *
 * 書く直前に読み直してから重ねる（同時に何項目も作るので、最初に読んだ
 * 物に重ねると先に書かれた項目を消す — `runSectionRegen` と同じ理由）。
 * 人が確かめた行（`verified`）は触らない。
 */
export async function mergeIntoReaderExplanation(
  admin: unknown,
  wordId: string,
  key: { explainLang: string; l1: string },
  patch: {
    extras: Record<string, unknown>;
    meaning?: string | null;
    example_translation?: string | null;
    /** 空でも入れ替える鍵（例文を作り直した時の `examples_extra`）。`mergeExtras` は空で上書きしない。 */
    replaceKeys?: readonly string[];
  },
): Promise<boolean> {
  const current = await readReaderExplanation(admin, wordId, key);
  if (!current || current.source === "verified") return false;
  const { mergeExtras } = await import("./extras");
  const extras: Record<string, unknown> = mergeExtras(current.extras, patch.extras as never);
  for (const k of patch.replaceKeys ?? []) if (k in patch.extras) extras[k] = patch.extras[k];
  const row: Record<string, unknown> = {
    extras,
    updated_at: new Date().toISOString(),
  };
  if ((patch.meaning ?? "").trim()) row.meaning = patch.meaning;
  const tr = readerText(patch.example_translation ?? null, key.explainLang);
  if (tr) row.example_translation = tr;
  try {
    const { error } = await (admin as LooseRowDb)
      .from("word_explanations")
      .update(row)
      .eq("word_id", wordId)
      .eq("explain_lang", key.explainLang)
      .eq("l1", key.l1);
    if (error) {
      console.warn("mergeIntoReaderExplanation failed", error);
      return false;
    }
    return true;
  } catch (e) {
    console.warn("mergeIntoReaderExplanation threw", e);
    return false;
  }
}

/** 1回に埋める語の数の上限（AI の1回の問い合わせに載せる量）。画面側も同じ数で束ねる。 */
export const FILL_BATCH_MAX = 24;

const FillInput = z.object({
  word_ids: z.array(z.string().uuid()).min(1).max(FILL_BATCH_MAX),
  /** 読む人の言語（表示言語）。 */
  explain_lang: z.enum(UI_LANGS),
});

/**
 * **読む人の言語の意味が無い語に、意味だけを埋める**（オーナー報告 2026-10-02、絵つき。
 * 表示言語が英語・繁體中文のとき、図鑑のスライドの見出しの下に意味が出ない・復習の問いが
 * 「Which one means “グラタンマカロニ”?」と日本語の意味で出る）。
 *
 * 共有の `words.meaning_ja` は**最初に作った人の言語**で、その人向けの解説の行
 * （`word_explanations`）は、単語の詳細を開いて解説を作った語にしか無い。しかも作った行の
 * 意味には共有の意味（別の言語）が写されていた（`updateWordExtras` — 同じ回で直した）。
 * だから日本語で集めてから英語に切り替えた人の図鑑は、意味が1つも出なかった。
 *
 * 埋める順（`nearby.functions.ts` の通知と同じ考え — 決まった事実は辞書から）:
 * 1. 共有の意味がもう読む人の言語で書かれていれば、それ
 * 2. 辞書（`dictionary_entries.meanings`）のその言語の意味
 * 3. それも無ければ、AI に**意味だけ**を一度にまとめて書かせる（語ごとに呼ばない）
 *
 * 書き先は `readerMeaningWriteTarget`（解説は触らない・人が確かめた行には書かない）。
 * 自分の図鑑に在る語だけ（`updateWordExtras` と同じ持ち主の確かめ）。
 */
export const fillReaderMeanings = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => FillInput.parse(input))
  .handler(async ({ context, data }): Promise<Record<string, string>> => {
    const { userId } = context;
    const lang = data.explain_lang;
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const admin = supabaseAdmin as unknown as FillDb;

    // 持ち主の確かめ。**自分の札が指す語だけ**を埋める。
    const { data: owned } = await admin
      .from("stickers")
      .select("word_id")
      .eq("user_id", userId)
      .in("word_id", data.word_ids);
    const ids = [...new Set((owned ?? []).map((r) => String(r.word_id ?? "")).filter(Boolean))];
    if (ids.length === 0) return {};

    const { data: wordRows } = await admin
      .from("words")
      .select("id, headword, language, meaning_ja, extras")
      .in("id", ids);
    const words = (wordRows ?? []).map((r) => ({
      id: String(r.id),
      headword: String(r.headword ?? ""),
      language: (r.language as string | null) ?? null,
      meaning: String(r.meaning_ja ?? ""),
      extras: r.extras as Record<string, unknown> | null,
    }));
    const { data: rowData, error: rowErr } = await admin
      .from("word_explanations")
      .select("word_id, explain_lang, l1, meaning, source")
      .in("word_id", ids)
      .eq("explain_lang", lang);
    // 表がまだ無い環境では置けない。**作りに行かない**（AI を呼ぶだけ無駄になる）。
    if (rowErr) {
      console.warn("fillReaderMeanings: 解説の表が読めない", rowErr.message);
      return {};
    }
    const rowsById = new Map<string, ExplanationRow[]>();
    for (const r of rowData ?? []) {
      const id = String(r.word_id ?? "");
      const list = rowsById.get(id) ?? [];
      list.push({
        explain_lang: String(r.explain_lang ?? ""),
        l1: String(r.l1 ?? ""),
        meaning: String(r.meaning ?? ""),
        extras: null,
        source: (r.source as string | null) ?? "ai",
      });
      rowsById.set(id, list);
    }

    const out: Record<string, string> = {};
    const fresh = new Map<string, string>(); // 新しく決めた意味（書きに行く物）
    const missing: typeof words = [];
    for (const w of words) {
      // もう読む人の言語の意味が在る語は、それを返すだけ（書かない）。
      const have = (rowsById.get(w.id) ?? [])
        .map((r) => shortMeaning(readerMeaning(r.meaning, lang)))
        .find(Boolean);
      if (have) {
        out[w.id] = have;
        continue;
      }
      const shared = shortMeaning(readerMeaning(w.meaning, lang));
      if (shared) fresh.set(w.id, shared);
      else missing.push(w);
    }

    // 2. 辞書。学習言語ごとに引く（同じ字でも言語が違えば別の語）。
    if (missing.length > 0) {
      const byLang = new Map<string, typeof words>();
      for (const w of missing) {
        const k = w.language ?? "";
        byLang.set(k, [...(byLang.get(k) ?? []), w]);
      }
      for (const [language, ws] of byLang) {
        if (!language) continue;
        try {
          const { data: dict } = await admin
            .from("dictionary_entries")
            .select("headword, meanings")
            .eq("language", language)
            .in(
              "headword",
              ws.map((w) => w.headword),
            );
          const found = new Map<string, string>();
          for (const d of dict ?? []) {
            const m = (d.meanings as Record<string, string> | null)?.[lang] ?? "";
            const fit = shortMeaning(readerMeaning(m, lang));
            if (fit) found.set(String(d.headword), fit);
          }
          for (const w of ws) {
            const m = found.get(w.headword);
            if (m) fresh.set(w.id, m);
          }
        } catch (e) {
          // 辞書は付け足し。読めなければ AI に回す（記録には残す）。
          console.warn("fillReaderMeanings: 辞書が読めない", e);
        }
      }
    }

    // 3. AI。**意味だけ**を、学習言語ごとに1回でまとめて書かせる。
    const left = missing.filter((w) => !fresh.has(w.id));
    if (left.length > 0) {
      const ai = await import("./ai-provider.server");
      const { targetProfile } = await import("./target-profile");
      const { generateText } = await import("ai");
      try {
        await ai.assertWithinDailyCap(userId, "reader_meaning");
        const cfg = await ai.getAiFor("card", "reader_meaning");
        const NL = ai.explanationLanguageName(lang);
        const byLang = new Map<string, typeof words>();
        for (const w of left) {
          const k = targetProfile(w.language).code;
          byLang.set(k, [...(byLang.get(k) ?? []), w]);
        }
        for (const [code, ws] of byLang) {
          const name = targetProfile(code).promptName;
          const list = ws
            .map((w, i) => `${i}. ${w.headword}${w.meaning ? `（参考: ${w.meaning}）` : ""}`)
            .join("\n");
          const prompt = [
            `次の${name}の語それぞれの意味を、**${NL}で**書きます。参考は別の言語で書かれた意味で、そのまま写さない。`,
            "**意味に見出し語そのものを書かない**（同じ字を使う言語なら、短い言い換えで言う）。",
            meaningRule(name, NL),
            `出力はJSONオブジェクト1つだけ(前置き不要): {"meanings":[{"i":0,"meaning":""}]}`,
            list,
          ].join("\n");
          const result = await ai.withModelFallback(cfg, cfg.modelFast, (m) =>
            generateText({
              model: cfg.gateway(m),
              prompt,
              abortSignal: AbortSignal.timeout(20_000),
            }),
          );
          const parsed = z
            .object({
              meanings: z.array(z.object({ i: z.number().int(), meaning: z.string().catch("") })),
            })
            .safeParse(ai.parseJsonFromAiText(result.text));
          if (!parsed.success) {
            console.warn("fillReaderMeanings: AI の形が違う", parsed.error.message);
            continue;
          }
          for (const { i, meaning } of parsed.data.meanings) {
            const w = ws[i];
            // **読む人の言語で書かれた物だけ**（AI が参考を写して返す回を落とす）。
            // 見出し語そのものを含む意味も落とす（繁體中文で台湾華語を学ぶ人に「筆記本」を
            // 意味として返すと、復習の問いが答えを言ってしまう）。
            const fit = w ? shortMeaning(readerMeaning(meaning, lang)) : "";
            if (w && fit && fit !== w.meaning.trim() && !fit.includes(w.headword)) {
              fresh.set(w.id, fit);
            }
          }
        }
      } catch (e) {
        // 上限・AI の失敗。**意味が出ないだけ**で画面は壊さない（記録には残す）。
        console.warn("fillReaderMeanings: AI で埋められない", (e as Error)?.message ?? e);
      }
    }

    if (fresh.size === 0) return out;
    // 書く。鍵は単語の詳細が刻む物（表示言語 × `getLearnerL1`）と同じ。
    const { getLearnerL1 } = await import("./ai-provider.server");
    const key = explanationKey(lang, (await getLearnerL1(userId)).code);
    const now = new Date().toISOString();
    for (const w of words) {
      const meaning = fresh.get(w.id);
      if (!meaning) continue;
      out[w.id] = meaning;
      const target = readerMeaningWriteTarget(rowsById.get(w.id), key);
      try {
        if (target.kind === "update") {
          const { error } = await admin
            .from("word_explanations")
            .update({ meaning, updated_at: now })
            .eq("word_id", w.id)
            .eq("explain_lang", target.row.explain_lang)
            .eq("l1", target.row.l1);
          if (error) console.warn("fillReaderMeanings: 書けない", error.message);
        } else if (target.kind === "insert") {
          // 解説の中身は共有の解説が**同じ言語で書かれているときだけ**写す。違う言語の解説を
          // その人向けとして置くと、単語の詳細がそれを出してしまう。
          const sharedLang = String(w.extras?.explain_lang ?? "");
          const extras = sharedLang === lang && w.extras ? w.extras : { explain_lang: lang };
          const { error } = await admin.from("word_explanations").upsert(
            [
              {
                word_id: w.id,
                explain_lang: key.explainLang,
                l1: key.l1,
                meaning,
                example_translation: null,
                extras,
                source: "ai",
                updated_at: now,
              },
            ],
            // 同じ鍵の行が間に作られていたら**そちらを残す**（中身のある解説を潰さない）。
            { onConflict: "word_id,explain_lang,l1", ignoreDuplicates: true },
          );
          if (error) console.warn("fillReaderMeanings: 置けない", error.message);
        }
      } catch (e) {
        console.warn("fillReaderMeanings: 書けない", e);
      }
    }
    return out;
  });

/** `fillReaderMeanings` が触る所だけを書いた緩い形（生成済みの型に無い表があるため）。 */
type FillDb = {
  from: (t: string) => {
    select: (c: string) => {
      eq: (
        k: string,
        v: string,
      ) => {
        in: (
          k: string,
          v: string[],
        ) => Promise<{ data: Record<string, unknown>[] | null; error: { message: string } | null }>;
      };
      in: (
        k: string,
        v: string[],
      ) => Promise<{
        data: Record<string, unknown>[] | null;
        error: { message: string } | null;
      }> & {
        eq: (
          k: string,
          v: string,
        ) => Promise<{
          data: Record<string, unknown>[] | null;
          error: { message: string } | null;
        }>;
      };
    };
    update: (row: unknown) => {
      eq: (
        k: string,
        v: string,
      ) => {
        eq: (
          k: string,
          v: string,
        ) => { eq: (k: string, v: string) => Promise<{ error: { message: string } | null }> };
      };
    };
    upsert: (rows: unknown, opts: unknown) => Promise<{ error: { message: string } | null }>;
  };
};
