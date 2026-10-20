import { createServerFn } from "@tanstack/react-start";
import { internalFailure } from "./safe-error";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { generateText } from "ai";
import { z } from "zod";
import { assertWithinDailyCap, getAiFor, getUserTargetLanguage } from "./ai-provider.server";
import { targetProfile, type WordbookPhrases } from "./target-profile";
import { effectiveDueIso, effectiveDueMs, nextSrs } from "./srs";
import { isAlreadyGraded } from "./review-grade-guard";
import {
  cleanWordbookEntries,
  wordbookTitle,
  wordbookProgress,
  MAX_ENTRIES_PER_PHOTO,
  type WordbookEntryDraft,
} from "./wordbook";
import { taipeiDay } from "./taipei-day";

/**
 * 単語帳の取り込みと、単語帳だけを回す復習(オーナー指摘 2026-08-20)。
 *
 * > 「単語帳の取り込みは単語帳を写真撮ったら、そこにある単語のカードを
 * >  一括で作成でき、復習も**図鑑の単語とは別に、単語帳を選択すると
 * >  単語帳で取り込んだものを SRS で復習**できるように。」
 *
 * 図鑑(`stickers`)には入れない。理由は移行(`20260820200000_wordbooks.sql`)の
 * 冒頭に書いてある。間隔の計算は `srs.ts` の `nextSrs` を共有する —
 * ここに別の計算を書くと、同じ「復習」が2種類の理屈で動くことになる。
 */

function parseJsonFromAiText(text: string): unknown {
  const trimmed = text.trim();
  const fenced = trimmed.match(/```(?:json)?\s*([\s\S]*?)\s*```/i);
  if (fenced?.[1]) return JSON.parse(fenced[1]);
  const start = trimmed.indexOf("{");
  const end = trimmed.lastIndexOf("}");
  if (start >= 0 && end > start) return JSON.parse(trimmed.slice(start, end + 1));
  return JSON.parse(trimmed);
}

const ExtractInput = z.object({
  // scan と同じ上限。ここを外すと AI の視覚呼び出しで青天井になる。
  imageBase64: z.string().min(100).max(8_000_000),
});

const ExtractSchema = z.object({
  /** その頁の見出し(単元名・級)。読めなければ空。 */
  title: z.string().catch(""),
  entries: z
    .array(
      z.object({
        headword: z.string(),
        // **1語でも形が崩れたら全部落ちる**のを避ける(候補・カードで踏んだ穴)。
        reading_zhuyin: z.string().catch(""),
        pinyin: z.string().catch(""),
        meaning_ja: z.string().catch(""),
      }),
    )
    .catch([]),
});

/**
 * 読み取りの指示文。**学習言語に付いていく**(オーナー方針 2026-10-01)。
 * 前は台湾華語に決め打ちで、英語・日本語の単語帳を撮っても繁体字に直そうとしていた。
 * 言語で変わる所だけを `target-profile.ts` の `wordbook` から入れる。
 */
const extractPrompt = (
  wb: WordbookPhrases,
) => `あなたは${wb.engineLabel}の学習アプリの、単語帳読み取りエンジンです。
入力画像は**単語帳・教科書の語彙ページ・自作の単語リスト**です。そこに並んでいる語を読み取ってください。

厳守ルール:
- 出力は下記の JSON オブジェクト1つだけ。前置き・後書き・コードフェンス禁止。
- **写っている語だけを返す。足さない。** 関連語や思いついた語を混ぜない。
- ${wb.scriptLine}
- ${wb.readingLine}
- ページ番号・単元番号・記号だけの行、欧文だけの見出しは語ではないので返さない。
- 語は**ページに並んでいる順**で返す。
- 多くても${MAX_ENTRIES_PER_PHOTO}語まで。

{"title":"単元名や級(読めなければ空文字)","entries":[{${wb.sample},"meaning_ja":"意味"}]}`;

export type WordbookDraft = {
  title: string;
  entries: WordbookEntryDraft[];
};

/**
 * 写真から語を読み取る。**まだ保存しない** — 読み違いをそのまま溜めないため、
 * 画面で確かめてから `createWordbook` に渡す。
 */
export const extractWordbook = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => ExtractInput.parse(input))
  .handler(async ({ context, data }): Promise<WordbookDraft> => {
    // 外部の AI へ送る前の同意（`ai-consent.ts`）。無ければ何も送らずに断る。
    await (await import("./ai-consent.server")).assertAiConsent(context.userId);
    const { supabase, userId } = context;
    await assertWithinDailyCap(userId, "wordbook");
    const ai = await getAiFor("scan", "wordbook");
    // 意味は**読む人の言語**で（iOS の言語検査 2026-10-01: 表示言語が英語・台湾華語でも
    // 単語帳の意味だけ日本語で返り、画面に言語が混ざっていた）。頁の意味が別の言語なら訳す。
    const { explanationLanguageRule } = await import("./ai-provider.server");
    const target = await getUserTargetLanguage(userId);
    const langRule = await explanationLanguageRule(userId, target);
    const image = data.imageBase64.startsWith("data:")
      ? data.imageBase64
      : `data:image/jpeg;base64,${data.imageBase64}`;

    let text = "";
    try {
      const r = await generateText({
        model: ai.gateway(ai.modelFast),
        messages: [
          {
            role: "user",
            content: [
              {
                type: "text",
                text:
                  `${extractPrompt(targetProfile(target).wordbook)}\n\n${langRule}\n` +
                  "meaning_ja の欄には、上の言語で書いた意味を入れる(頁の意味が別の言語なら訳す)。",
              },
              { type: "image", image },
            ],
          },
        ],
      });
      text = r.text;
    } catch (e) {
      throw new Error(`単語帳の読み取りに失敗しました: ${(e as Error).message}`);
    }

    let parsed: z.infer<typeof ExtractSchema>;
    try {
      parsed = ExtractSchema.parse(parseJsonFromAiText(text));
    } catch (e) {
      // **理由を飲まない。** 形が崩れた回の中身が残らないと、直しようがない。
      console.warn("extractWordbook: 形が合わない", {
        why: e instanceof Error ? e.message : String(e),
        head: text.slice(0, 300),
      });
      throw new Error("単語帳の形が読み取れませんでした。もう一度撮ってみてください。");
    }

    const entries = cleanWordbookEntries(parsed.entries, undefined, target);
    if (entries.length === 0) {
      throw new Error(
        "この写真からは単語を読み取れませんでした。明るい所で、まっすぐ撮ってみてください。",
      );
    }
    return { title: parsed.title, entries };
  });

const CreateInput = z.object({
  title: z.string().max(200).optional(),
  entries: z
    .array(
      z.object({
        headword: z.string().min(1).max(40),
        reading_zhuyin: z.string().max(100).nullable().optional(),
        pinyin: z.string().max(100).nullable().optional(),
        meaning_ja: z.string().max(200).nullable().optional(),
      }),
    )
    .min(1)
    .max(MAX_ENTRIES_PER_PHOTO),
});

/** 読み取った語をまとめて1冊にする。 */
export const createWordbook = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => CreateInput.parse(input))
  .handler(async ({ context, data }): Promise<{ wordbook_id: string; added: number }> => {
    const { supabase, userId } = context;
    // 読み取りと同じ規則で整える(学習言語の見出し語の規則)。
    const entries = cleanWordbookEntries(
      data.entries,
      undefined,
      await getUserTargetLanguage(userId),
    );
    if (entries.length === 0) throw new Error("入れる語がありません");

    const today = taipeiDay();
    const { data: book, error: bookErr } = await supabase
      .from("wordbooks")
      .insert({ user_id: userId, title: wordbookTitle(data.title, today) })
      .select("id")
      .single();
    if (bookErr || !book) {
      throw internalFailure("wordbook", bookErr ?? "no row", "単語帳を作れませんでした");
    }

    const { error: rowErr } = await supabase.from("wordbook_entries").insert(
      entries.map((e) => ({
        wordbook_id: (book as { id: string }).id,
        user_id: userId,
        headword: e.headword,
        reading_zhuyin: e.reading_zhuyin ?? null,
        pinyin: e.pinyin ?? null,
        meaning_ja: e.meaning_ja ?? null,
      })),
    );
    if (rowErr) throw internalFailure("wordbook", rowErr, "単語帳の語を保存できませんでした");

    return { wordbook_id: (book as { id: string }).id, added: entries.length };
  });

export type WordbookSummary = {
  id: string;
  title: string;
  created_at: string;
  total: number;
  due: number;
  learned: number;
};

/** 本棚。1冊ごとに「今日出す数」と「覚えた数」を添える。 */
export const listWordbooks = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }): Promise<WordbookSummary[]> => {
    const { supabase, userId } = context;
    const [{ data: books }, { data: rows }] = await Promise.all([
      supabase
        .from("wordbooks")
        .select("id, title, created_at")
        .eq("user_id", userId)
        .order("created_at", { ascending: false }),
      supabase
        .from("wordbook_entries")
        .select("wordbook_id, due_at, repetitions")
        .eq("user_id", userId),
    ]);
    type Row = { wordbook_id: string; due_at: string | null; repetitions: number };
    const byBook = new Map<string, Row[]>();
    for (const r of (rows ?? []) as Row[]) {
      const list = byBook.get(r.wordbook_id);
      if (list) list.push(r);
      else byBook.set(r.wordbook_id, [r]);
    }
    return ((books ?? []) as Array<{ id: string; title: string; created_at: string }>).map((b) => ({
      id: b.id,
      title: b.title,
      created_at: b.created_at,
      ...wordbookProgress(byBook.get(b.id) ?? []),
    }));
  });

export type WordbookCard = {
  id: string;
  headword: string;
  reading_zhuyin: string | null;
  pinyin: string | null;
  meaning_ja: string | null;
  repetitions: number;
  interval_days: number;
  /** 4択の選択肢(同じ本の中の語から作る。AI は呼ばない)。 */
  choices: string[];
};

const DueInput = z.object({
  wordbook_id: z.string().uuid(),
  limit: z.number().int().min(1).max(50).optional().default(20),
});

/**
 * その本の、今日出す語。
 *
 * 選択肢は**同じ本の中の語**から作る。単語帳は同じ単元の語が並ぶので、
 * 図鑑から借りるより紛らわしく、練習になる。AI は1回も呼ばない。
 */
export const getWordbookDue = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => DueInput.parse(input))
  .handler(async ({ context, data }): Promise<WordbookCard[]> => {
    const { supabase, userId } = context;
    const { data: rows, error } = await supabase
      .from("wordbook_entries")
      .select(
        "id, headword, reading_zhuyin, pinyin, meaning_ja, repetitions, interval_days, due_at, last_reviewed_at",
      )
      .eq("user_id", userId)
      .eq("wordbook_id", data.wordbook_id)
      .order("due_at", { ascending: true })
      .limit(200);
    if (error) throw internalFailure("wordbook", error, "単語帳を読み込めませんでした");

    type Row = {
      id: string;
      headword: string;
      reading_zhuyin: string | null;
      pinyin: string | null;
      meaning_ja: string | null;
      repetitions: number;
      interval_days: number;
      due_at: string | null;
      last_reviewed_at: string | null;
    };
    const all = (rows ?? []) as Row[];
    const now = Date.now();
    const due = all
      // 期限は「最後の復習 + 180 日」で頭打ち（`effectiveDueMs`。srs.ts の 2026-10-03）。
      .filter((r) => !r.due_at || (effectiveDueMs(r.due_at, r.last_reviewed_at) ?? 0) <= now)
      .slice(0, data.limit);

    const pool = all.map((r) => r.headword);
    return due.map((r) => {
      const others = pool.filter((h) => h !== r.headword);
      // 並びを崩してから3つ取る。**同じ並びのまま取ると、選択肢が
      // いつも同じ顔ぶれになる**(答えを位置で覚えてしまう)。
      for (let i = others.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [others[i], others[j]] = [others[j], others[i]];
      }
      const choices = [r.headword, ...others.slice(0, 3)];
      for (let i = choices.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [choices[i], choices[j]] = [choices[j], choices[i]];
      }
      return {
        id: r.id,
        headword: r.headword,
        reading_zhuyin: r.reading_zhuyin,
        pinyin: r.pinyin,
        meaning_ja: r.meaning_ja,
        repetitions: r.repetitions,
        interval_days: r.interval_days,
        choices,
      };
    });
  });

const GradeInput = z.object({
  entry_id: z.string().uuid(),
  correct: z.boolean(),
});

/**
 * 1語ぶんの採点。間隔の計算は図鑑の復習と**同じ** `nextSrs`。
 *
 * **同じ答えが2回届いても1回分しか進めない**（2026-10-03 監査。図鑑の復習の `gradeReview`
 * と同じ守り）。期限がまだ先の語はもう採点済み（通信のやり直し・二重送信・別の端末）なので
 * 何も書かない。書く時も読んだ時の期限のままの行だけ（同時に2回届いたら後の方は0行）。
 */
export const gradeWordbookEntry = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => GradeInput.parse(input))
  .handler(
    async ({
      context,
      data,
    }): Promise<{ next_due_at: string; interval_days: number; duplicate?: boolean }> => {
      const { supabase, userId } = context;
      const { data: row, error } = await supabase
        .from("wordbook_entries")
        .select("id, ease, interval_days, repetitions, due_at, last_reviewed_at")
        .eq("id", data.entry_id)
        .eq("user_id", userId)
        .maybeSingle();
      if (error) throw internalFailure("wordbook", error, "単語帳を読み込めませんでした");
      if (!row) throw new Error("この語を編集する権限がありません");

      const prev = row as {
        ease: number;
        interval_days: number;
        repetitions: number;
        due_at: string | null;
        last_reviewed_at: string | null;
      };
      const nowMs = Date.now();
      // 期限は「最後の復習 + 180 日」で頭を打つ（`effectiveDueIso`、出題の絞りと同じ）。
      if (isAlreadyGraded(effectiveDueIso(prev.due_at, prev.last_reviewed_at), nowMs)) {
        return {
          next_due_at: prev.due_at as string,
          interval_days: prev.interval_days,
          duplicate: true,
        };
      }
      const next = nextSrs(
        {
          ease: Number(prev.ease),
          interval_days: prev.interval_days,
          repetitions: prev.repetitions,
        },
        data.correct ? 5 : 2,
      );
      const dueAt = new Date(nowMs + next.interval_days * 86400_000).toISOString();
      // 読んだ時の期限のままの時だけ書く（同時に2回届いた時、後の方は0行になる）。
      const updateQuery = supabase
        .from("wordbook_entries")
        .update({
          ease: next.ease,
          interval_days: next.interval_days,
          repetitions: next.repetitions,
          due_at: dueAt,
          last_reviewed_at: new Date(nowMs).toISOString(),
        })
        .eq("id", data.entry_id)
        .eq("user_id", userId);
      const { data: updated, error: upErr } = await (
        prev.due_at ? updateQuery.eq("due_at", prev.due_at) : updateQuery.is("due_at", null)
      ).select("id");
      if (upErr) throw internalFailure("wordbook", upErr, "採点を保存できませんでした");
      if (!updated || updated.length === 0) {
        // 同じ答えが同時に2回届き、先の方がもう書いた。こちらは何も進めない。
        return { next_due_at: dueAt, interval_days: next.interval_days, duplicate: true };
      }
      return { next_due_at: dueAt, interval_days: next.interval_days };
    },
  );

/** 1冊まるごと消す。語も一緒に消える(外部キーの ON DELETE CASCADE)。 */
export const deleteWordbook = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => z.object({ wordbook_id: z.string().uuid() }).parse(input))
  .handler(async ({ context, data }): Promise<{ ok: true }> => {
    const { supabase, userId } = context;
    const { error } = await supabase
      .from("wordbooks")
      .delete()
      .eq("id", data.wordbook_id)
      .eq("user_id", userId);
    if (error) throw internalFailure("wordbook", error, "単語帳を削除できませんでした");
    return { ok: true };
  });
