import { createServerFn } from "@tanstack/react-start";
import { internalFailure } from "./safe-error";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { z } from "zod";
import {
  assertWithinDailyCap,
  concreteModelId,
  generateStructured,
  getAi,
  getAiFor,
  getUserLevelGoal,
  levelInstruction,
  explanationLanguageRule,
  getExplanationLanguage,
  explanationLanguageName,
  l1Rule,
  isProUser,
  getUserTargetLanguage,
} from "./ai-provider.server";
import { targetProfile } from "./target-profile";
import { taipeiDay } from "./taipei-day";

export type NativePhrase = { zh: string; ja: string; note: string };

export type JournalEntry = {
  id: string;
  entry_date: string;
  /** Legacy full model-diary text (feature removed per roadmap B6; kept for old entries). */
  body_zh: string | null;
  body_ja: string | null;
  user_draft: string | null;
  correction: string | null;
  feedback_ja: string | null;
  native_phrases: NativePhrase[] | null;
  used_sticker_ids: string[];
  created_at: string;
};

/**
 * Rows come back from a `select("*")`; the generated DB types may predate the
 * native_phrases migration, so normalize the column here instead of casting.
 */
function toJournalEntry(row: unknown): JournalEntry {
  const r = row as JournalEntry & { native_phrases?: unknown };
  const phrases = Array.isArray(r.native_phrases)
    ? (r.native_phrases as unknown[])
        .filter((p): p is Record<string, unknown> => !!p && typeof p === "object")
        .map((p) => ({
          zh: typeof p.zh === "string" ? p.zh : "",
          ja: typeof p.ja === "string" ? p.ja : "",
          note: typeof p.note === "string" ? p.note : "",
        }))
        .filter((p) => p.zh)
    : null;
  return { ...r, native_phrases: phrases };
}

export const listJournal = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const { supabase, userId } = context;
    const { data, error } = await supabase
      .from("journal_entries")
      .select("*")
      .eq("user_id", userId)
      .order("entry_date", { ascending: false })
      .limit(30);
    if (error) throw internalFailure("journal", error, "日記を読み込めませんでした");
    return (data ?? []).map(toJournalEntry);
  });

/** 日記の材料になる「今日撮ったもの」。必要な列だけを型として書く。 */
type TodaysCapture = {
  created_at: string;
  caption: string | null;
  location_name: string | null;
  word: { headword: string; meaning_ja: string | null } | null;
  id: string;
};

/**
 * supabase は認証ミドルウェアが作ったクライアント。型を書き出すと
 * 生成物への依存が増えるので、この関数が使う `from()` だけを要求する。
 */
type SupabaseLike = {
  // クエリビルダは .select().eq().gte()... と連鎖し、戻り値の型が段ごとに
  // 変わる。ここで正確に書くと生成された型定義に強く依存してしまうので、
  // この1行に限って any を許す(戻り値は下で TodaysCapture[] に絞る)。
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  from: (table: string) => any;
};

/**
 * The last day a diary may be written for. The app's day is Taipei's (`taipeiDay`), but the iOS app keys each page
 * by the phone's own calendar day (the home album's days, `AlbumDay.days`): a phone east of Taipei (Japan, Korea)
 * is already on the next date for an hour each night, so one day past Taipei's today is allowed. Anything later is a
 * future day (owner: 「未来の日には書けない」).
 */
export function latestDiaryDay(now: Date = new Date()): string {
  return taipeiDay(new Date(now.getTime() + 24 * 3600 * 1000));
}

const DAY = /^\d{4}-\d{2}-\d{2}$/;

/**
 * The photos taken on one app day (`day`: `YYYY-MM-DD`, Taipei's calendar; today when not given), oldest first —
 * the diary's material for that day (iOS 2026-10-24: a diary page per day of the album, so a past day is corrected
 * against that day's photos, not today's).
 */
async function getCapturesOn(supabase: SupabaseLike, userId: string, day: string = taipeiDay()) {
  const start = new Date(`${day}T00:00:00+08:00`);
  const end = new Date(start.getTime() + 24 * 3600 * 1000);
  const { data, error } = await supabase
    .from("stickers")
    .select("id, caption, location_name, created_at, word:words(headword, meaning_ja)")
    .eq("user_id", userId)
    .gte("created_at", start.toISOString())
    .lt("created_at", end.toISOString())
    .order("created_at", { ascending: true })
    .limit(12);
  if (error) throw internalFailure("journal", error, "日記を読み込めませんでした");
  return { today: day, stickers: (data ?? []) as TodaysCapture[] };
}

function describeCaptures(stickers: TodaysCapture[]) {
  return stickers
    .map((s) => {
      const t = new Date(s.created_at).toLocaleTimeString("ja-JP", {
        hour: "2-digit",
        minute: "2-digit",
        timeZone: "Asia/Taipei",
      });
      const head = s.word?.headword ?? "?";
      const meaning = s.word?.meaning_ja ?? "";
      const where = s.location_name ? `@${s.location_name}` : "";
      const note = s.caption ? `「${s.caption}」` : "";
      return `${t} ${head}(${meaning}) ${where} ${note}`.trim();
    })
    .join("\n");
}

/**
 * `date`: the diary page's day (iOS, a page per day). Absent (the web's diary): today.
 * `notes`: what the sentence-by-sentence check (`checkDiarySentence`) pointed out while the diary was being written —
 * also the ones the learner then fixed — so the summary can say what they tend to get wrong (owner 2026-10-25:
 * 「リアルタイムで1文ずつ確認していた間違いなどを含めて、ユーザーがどんな間違いをしやすいのか…」).
 */
const CorrectInput = z.object({
  draft: z.string().min(1).max(2000),
  date: z.string().regex(DAY).optional(),
  notes: z
    .array(z.object({ wrong: z.string().max(80), fix: z.string().max(80), kind: z.string().max(20) }))
    .max(40)
    .optional(),
});

/** One mistake of the day, explained (the finished diary's correction). */
export type DiaryMistake = { wrong: string; fix: string; explain: string };

/** `correctMyJournal`'s answer: the stored row, and the day's review as parts (iOS 2026-10-25). */
export type JournalCorrection = JournalEntry & { mistakes: DiaryMistake[]; tendencies: string[] };

/**
 * The review kept in the row's one text column (`feedback_ja`) so a later read still has it: the coach's words, then
 * the day's mistakes and the learner's tendencies as short lists. (No new columns: the table's migrations are applied
 * by hand.)
 */
export function composeFeedback(
  coach: string,
  mistakes: DiaryMistake[],
  tendencies: string[],
  heads: { mistakes: string; tendencies: string },
): string {
  const parts = [coach.trim()];
  if (mistakes.length)
    parts.push(
      `${heads.mistakes}\n` +
        mistakes.map((m) => `・${m.wrong} → ${m.fix}${m.explain ? `：${m.explain}` : ""}`).join("\n"),
    );
  if (tendencies.length) parts.push(`${heads.tendencies}\n` + tendencies.map((t) => `・${t}`).join("\n"));
  return parts.filter(Boolean).join("\n\n");
}

export const correctMyJournal = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => CorrectInput.parse(input))
  .handler(async ({ context, data }) => {
    // 外部の AI へ送る前の同意（`ai-consent.ts`）。無ければ何も送らずに断る。
    await (await import("./ai-consent.server")).assertAiConsent(context.userId);
    const { supabase, userId } = context;
    if (data.date && data.date > latestDiaryDay()) throw new Error("未来の日の日記は書けません");
    await assertWithinDailyCap(userId, "correction");
    const { today, stickers } = await getCapturesOn(supabase, userId, data.date);

    const ai = await getAiFor("journal", "journal_correct");

    // Roadmap B6: no full model-diary. Correction + "ネイティブならこう言う"
    // phrases + an explanation of the sentence patterns actually used.
    // iOS 2026-10-25 (owner): the most natural full text of what the learner meant, today's mistakes, what they tend to
    // get wrong, and phrases to use — written from the situation they wrote about.
    const Schema = z.object({
      correction: z.string().min(1),
      feedback_ja: z.string().min(1),
      mistakes: z
        .array(z.object({ wrong: z.string(), fix: z.string(), explain: z.string() }))
        .max(8),
      tendencies: z.array(z.string()).max(4),
      native_phrases: z
        .array(z.object({ zh: z.string(), ja: z.string(), note: z.string() }))
        .min(1)
        .max(3),
    });
    const notes = (data.notes ?? [])
      .filter((n) => n.wrong.trim() && n.fix.trim())
      .map((n) => `- 「${n.wrong.trim()}」→「${n.fix.trim()}」(${n.kind})`)
      .join("\n");
    const pro = await isProUser(userId);
    const richModel = pro ? ai.modelRichPremium : ai.modelRich;
    const levelGoal = await getUserLevelGoal(userId);
    const levelRule = await levelInstruction(userId);
    const langRule = await explanationLanguageRule(userId);
    // 本文中の「日本語で」を表示言語に合わせる(#65)。
    // **3言語すべてを名前で引く**（`=== "en" ? "英語" : "日本語"` だと繁體中文の人の
    // 解説が日本語で作られる。`ai-provider.server.ts` の注と同じ話）。
    const NL = explanationLanguageName(await getExplanationLanguage(userId));
    // 日記の間違い方も母語で決まる(SOVの語順、冠詞、動詞活用…)。
    const l1 = await l1Rule(userId, "grammar");
    // 添削者の言語・字・ネイティブの呼び名は学習言語の表から(`coach`)。
    // 台湾華語の値はいままでの文そのもの。
    const coach = targetProfile(await getUserTargetLanguage(userId)).coach;
    const corrected = await generateStructured({
      model: ai.gateway(richModel),
      schema: Schema,
      prompt:
        `あなたは${coach.journalLanguage}のネイティブ作文添削者。学習者が今日の日記を書いてくれました。\n` +
        `${langRule}\n${levelRule}\n${l1}\n` +
        `今日のキャプチャ参考:\n${describeCaptures(stickers)}\n\n` +
        `学習者の文章:\n"""\n${data.draft}\n"""\n\n` +
        (notes ? `書いている間に1文ずつの添削で指摘された点（あとで本人が直した物も含む）:\n${notes}\n\n` : "") +
        `次を出力:\n` +
        `- correction: 学習者が言いたいことに沿って、${coach.journalNatives}が一番自然に書く完全版。意図・内容は変えない（足さない・削らない）。\n` +
        `- feedback_ja: 学習者が書いた状況（今日の出来事）に沿った、短い全体の講評を${NL}で2〜3文。どこが良かったか、次に何を意識すると自然になるか。\n` +
        `- mistakes: 今日の間違い（最大8個。上の指摘も含めて、大事な順）。各要素は wrong(学習者が書いた部分)、fix(直した形)、explain(なぜ違うか・どう使い分けるかを${NL}で1〜2文)。\n` +
        `- tendencies: この学習者が間違えやすいこと（今日の間違い・指摘から言える物だけ、最大4個、${NL}で1文ずつ。根拠の無い一般論は書かない。無ければ空）。\n` +
        `- native_phrases: 学習者が言いたかった気持ちを、${coach.journalNatives}が実際の会話で使う自然なフレーズ・チャンクで2〜3個。各要素は zh(${coach.journalScript}フレーズ)、ja(訳・${NL})、note(いつ・どんな気持ちで使うか、よく一緒に使う語)。`,
    });

    const mistakes = corrected.mistakes
      .map((m) => ({ wrong: m.wrong.trim(), fix: m.fix.trim(), explain: m.explain.trim() }))
      .filter((m) => m.wrong && m.fix && m.wrong !== m.fix);
    const tendencies = corrected.tendencies.map((t) => t.trim()).filter(Boolean);
    const baseRow = {
      user_id: userId,
      entry_date: today,
      user_draft: data.draft,
      correction: corrected.correction,
      feedback_ja: composeFeedback(corrected.feedback_ja, mistakes, tendencies, await reviewHeadings(userId)),
      used_sticker_ids: stickers.map((s) => s.id),
      // 合言葉（`latest-flash` など）のままではなく、実際に呼んだ版付きの ID を残す。
      model: await concreteModelId(ai, richModel),
    };
    // Try with native_phrases first; retry without it if the column hasn't
    // been migrated yet, so correction never breaks on a stale schema.
    let inserted: JournalEntry | null = null;
    {
      const { data: row, error } = await supabase
        .from("journal_entries")
        .upsert(
          { ...baseRow, native_phrases: corrected.native_phrases as never },
          { onConflict: "user_id,entry_date" },
        )
        .select("*")
        .single();
      if (!error) {
        inserted = toJournalEntry(row);
      } else if (/native_phrases/.test(error.message)) {
        const { data: row2, error: e2 } = await supabase
          .from("journal_entries")
          .upsert(baseRow, { onConflict: "user_id,entry_date" })
          .select("*")
          .single();
        if (e2) throw internalFailure("journal", e2, "日記を保存できませんでした");
        inserted = { ...toJournalEntry(row2), native_phrases: corrected.native_phrases };
      } else {
        throw internalFailure("journal", error, "日記を保存できませんでした");
      }
    }
    return { ...(inserted as JournalEntry), mistakes, tendencies } satisfies JournalCorrection;
  });

/** The two list headings of the stored review, in the learner's explanation language. */
async function reviewHeadings(userId: string): Promise<{ mistakes: string; tendencies: string }> {
  const lang = await getExplanationLanguage(userId);
  return (
    {
      en: { mistakes: "Today's mistakes", tendencies: "What you tend to get wrong" },
      "zh-TW": { mistakes: "今天的錯誤", tendencies: "容易出錯的地方" },
      es: { mistakes: "Errores de hoy", tendencies: "Lo que sueles confundir" },
      ko: { mistakes: "오늘의 실수", tendencies: "자주 틀리는 점" },
      vi: { mistakes: "Lỗi hôm nay", tendencies: "Những lỗi bạn hay mắc" },
    } as Record<string, { mistakes: string; tendencies: string }>
  )[lang] ?? { mistakes: "今日の間違い", tendencies: "間違えやすいところ" };
}

// ============================================================================
// 書いている間の1文ずつの添削（iOS 2026-10-25）
// ============================================================================

/**
 * **1文ずつの添削**（オーナー 2026-10-25「日記を書いてるときに間違えたら、解説ともに１文ごとやリアルタイムで添削修整、
 * ここが間違ってる単語や文法を指してここが間違ってると修整され、ユーザが言いたいことの最も自然なフレーズな文も表示される」）。
 *
 * iOS は文を書き終えた時（。！？ や改行）にその1文だけを送る。同じ文は端末が覚えていて送り直さない。速いモデルの
 * 小さな呼び出し（`journal_sentence`）、1日の上限は `diary_sentence`。保存はしない — 指摘は書き終えた時の添削
 * （`correctMyJournal` の `notes`）に渡され、そこで「間違えやすいこと」の材料になる。
 */
const SentenceInput = z.object({
  sentence: z.string().min(1).max(300),
  /** The sentences before it (what the learner has been saying), for the meaning. */
  before: z.string().max(1500).optional(),
  date: z.string().regex(DAY).optional(),
});

/** A wrong part of the sentence: `wrong` is exactly as written in it. */
export type SentenceIssue = { wrong: string; fix: string; kind: SentenceIssueKind; explain: string };
export type SentenceIssueKind = "word" | "grammar" | "order" | "particle" | "measure" | "other";
export type SentenceCheck = { ok: boolean; issues: SentenceIssue[]; natural: string; natural_note: string };

const ISSUE_KINDS: readonly SentenceIssueKind[] = ["word", "grammar", "order", "particle", "measure", "other"];

/**
 * The model's answer made safe for the page: an issue is kept only when its `wrong` is written in the sentence (the
 * page underlines it there) and its fix is different; at most 4. `ok` is true only when nothing is left to fix.
 * The natural version is dropped when it is the sentence itself.
 */
export function cleanSentenceCheck(
  sentence: string,
  raw: { ok: boolean; issues: Array<{ wrong: string; fix: string; kind: string; explain: string }>; natural: string; natural_note: string },
): SentenceCheck {
  const seen = new Set<string>();
  const issues: SentenceIssue[] = [];
  for (const i of raw.issues) {
    const wrong = i.wrong.trim();
    const fix = i.fix.trim();
    if (!wrong || !sentence.includes(wrong) || wrong === fix || seen.has(wrong)) continue;
    seen.add(wrong);
    const kind = (ISSUE_KINDS as readonly string[]).includes(i.kind) ? (i.kind as SentenceIssueKind) : "other";
    issues.push({ wrong, fix, kind, explain: i.explain.trim() });
    if (issues.length === 4) break;
  }
  const natural = raw.natural.trim();
  const same = natural.replace(/[\s。！？!?，,]/g, "") === sentence.replace(/[\s。！？!?，,]/g, "");
  return {
    ok: issues.length === 0,
    issues,
    natural: same ? "" : natural,
    natural_note: same ? "" : raw.natural_note.trim(),
  };
}

export const checkDiarySentence = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => SentenceInput.parse(input))
  .handler(async ({ context, data }): Promise<SentenceCheck> => {
    // 外部の AI へ送る前の同意（`ai-consent.ts`）。無ければ何も送らずに断る。
    await (await import("./ai-consent.server")).assertAiConsent(context.userId);
    const { supabase, userId } = context;
    if (data.date && data.date > latestDiaryDay()) throw new Error("未来の日の日記は書けません");
    const sentence = data.sentence.trim();
    if (!sentence) return { ok: true, issues: [], natural: "", natural_note: "" };
    await assertWithinDailyCap(userId, "diary_sentence");
    const { stickers } = await getCapturesOn(supabase, userId, data.date);
    const ai = await getAiFor("journal", "journal_sentence");
    const levelRule = await levelInstruction(userId);
    const langRule = await explanationLanguageRule(userId);
    const NL = explanationLanguageName(await getExplanationLanguage(userId));
    const l1 = await l1Rule(userId, "grammar");
    const coach = targetProfile(await getUserTargetLanguage(userId)).coach;
    const Schema = z.object({
      ok: z.boolean(),
      issues: z
        .array(z.object({ wrong: z.string(), fix: z.string(), kind: z.string(), explain: z.string() }))
        .max(6),
      natural: z.string(),
      natural_note: z.string(),
    });
    const raw = await generateStructured({
      model: ai.gateway(ai.modelFast),
      schema: Schema,
      prompt:
        `あなたは${coach.journalLanguage}のネイティブ作文添削者。学習者が日記を書いている途中で、いま1文を書き終えました。その1文だけを見ます。\n` +
        `${langRule}\n${levelRule}\n${l1}\n` +
        `その日の撮影（場面の参考）:\n${describeCaptures(stickers) || "（なし）"}\n\n` +
        (data.before?.trim() ? `ここまでに書いた文（意味の参考。添削しない）:\n"""\n${data.before.trim()}\n"""\n\n` : "") +
        `添削する1文:\n"""\n${sentence}\n"""\n\n` +
        `次を出力:\n` +
        `- issues: 本当の間違いだけ（文法・語の選び方・語順・助詞・量詞など。好みの言い換えは入れない）。最大4個。各要素は\n` +
        `  wrong(添削する1文の中にそのまま書かれている部分。1文字も変えずに写す)、fix(直した形)、\n` +
        `  kind("word" | "grammar" | "order" | "particle" | "measure" | "other")、explain(なぜ違うかを${NL}で1〜2文)。\n` +
        `- ok: 間違いが無ければ true（issues は空）。\n` +
        `- natural: 学習者が言いたいことを、${coach.journalNatives}が一番自然に言う1文（${coach.journalScript}）。意味は変えない。\n` +
        `- natural_note: natural がなぜ自然かを${NL}で1文。natural が元の文と同じなら空。`,
    });
    return cleanSentenceCheck(sentence, raw);
  });

/**
 * **打った日記をそのまま保存する**（オーナー指示 2026-09-28「日記はユーザーが
 * タイプしたものが…表示される」）。添削（`correctMyJournal`）とは別の口 — AI を
 * 通さず、本人の文を本人の字体で見せるための保存。添削済みの列には触らない
 * （`upsert` は渡した列だけを書き換える）。
 *
 * 日付は本棚の本の「その日」。未来の日には書けない（台湾時間の今日まで）。
 */
const DiaryInput = z.object({
  date: z.string().regex(DAY),
  text: z.string().max(4000),
});

export const saveMyDiary = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => DiaryInput.parse(input))
  .handler(async ({ context, data }) => {
    const { supabase, userId } = context;
    if (data.date > latestDiaryDay()) throw new Error("未来の日の日記は書けません");
    const text = data.text.trim();
    const { data: row, error } = await supabase
      .from("journal_entries")
      .upsert(
        { user_id: userId, entry_date: data.date, user_draft: text || null },
        { onConflict: "user_id,entry_date" },
      )
      .select("*")
      .single();
    if (error) throw internalFailure("journal", error, "日記を保存できませんでした");
    return toJournalEntry(row);
  });

/**
 * **その月の日記**（ホームの本棚の本を開いた時。オーナー指示 2026-09-29「ホームのアルバムの
 * 一番上に本棚を一列作って。またアルバムを開くとその月の最初のページが開くようにして」）。
 * 見開きの右ページに、本人が打った日記（無ければ添削・昔の日記）を載せる。
 */
const MonthInput = z.object({ month: z.string().regex(/^\d{4}-\d{2}$/) });

export const listMyDiaryMonth = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => MonthInput.parse(input))
  .handler(async ({ context, data }) => {
    const { supabase, userId } = context;
    const [y, m] = data.month.split("-").map(Number);
    const next = m === 12 ? `${y + 1}-01` : `${y}-${String(m + 1).padStart(2, "0")}`;
    const { data: rows, error } = await supabase
      .from("journal_entries")
      .select("*")
      .eq("user_id", userId)
      .gte("entry_date", `${data.month}-01`)
      .lt("entry_date", `${next}-01`)
      .order("entry_date", { ascending: true })
      .limit(31);
    if (error) throw internalFailure("journal", error, "日記を読み込めませんでした");
    // `date` / `text` as the web's shelf reads them; the correction with its notes for the iOS diary page
    // (2026-10-24), which shows the red-pen version under the learner's own text.
    return (rows ?? []).map(toJournalEntry).map((r) => ({
      date: r.entry_date,
      text: r.user_draft ?? r.correction ?? r.body_zh ?? "",
      correction: r.correction,
      feedback: r.feedback_ja,
      native_phrases: r.native_phrases ?? [],
      used_sticker_ids: r.used_sticker_ids ?? [],
    }));
  });

// ============================================================================
// 書く「前」の足場(要望 #88)
// ============================================================================

/**
 * 日記は**白紙がいちばん厳しい**。
 *
 * 要望(2026-07-14):
 * 「日記に誘導・質問が必要。レベルに合う型・チャンク・文法 +
 *  今日撮った物・コメント・場所からの自然な質問」
 *
 * これまでこの画面には `placeholder` の一文しか無かった。
 * 「今日のことを台湾華語で書いてみよう」とだけ言われて空欄を渡されるのは、
 * 白紙と同じ。書き出しの足場を作って解く。
 *
 * ## 材料はその人の今日だけ
 * 質問は**その人が今日撮った物・書いた一言・居た場所**から作る。
 * 汎用の「今日は何をしましたか」を出さない — それは白紙と同じで、
 * しかも「あなたのことを聞いている」という嘘が付く。
 *
 * ## 撮っていない日は出さない
 * 材料が無ければ `null` を返す。**一般的な質問で埋めない。**
 * 出せない日に何かを出すより、出せない理由が分かるほうがいい。
 */
export type JournalPrompt = {
  /** どの1枚から作った質問か。画面で「何のことか」を示すのに使う。 */
  sticker_id: string | null;
  question_zh: string;
  question_ja: string;
};

export type JournalPattern = { zh: string; ja: string };

export type JournalScaffold = {
  prompts: JournalPrompt[];
  /** その人のレベルで使える型。押すと下書きに足せる。 */
  patterns: JournalPattern[];
  /** 質問のもとになった撮影。何のことか分からない質問にしない。 */
  captures: Array<{
    id: string;
    headword: string;
    caption: string | null;
    location_name: string | null;
  }>;
};

export const getJournalPrompts = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }): Promise<JournalScaffold | null> => {
    // 外部の AI へ送る前の同意（`ai-consent.ts`）。書き出しの質問はおまけなので、同意が
    // 無ければ何も送らずに「質問なし」で返す（日記の画面は止めない）。
    try {
      await (await import("./ai-consent.server")).assertAiConsent(context.userId);
    } catch (e) {
      const { isAiConsentError } = await import("./ai-consent");
      if (isAiConsentError(e)) return null;
      throw e;
    }
    const { supabase, userId } = context;
    const { stickers } = await getCapturesOn(supabase, userId);
    // **今日の材料が無ければ何も出さない。** 上限も使わない(AIを呼ばない)。
    if (stickers.length === 0) return null;

    await assertWithinDailyCap(userId, "journal_prompt");
    const ai = await getAiFor("journal", "journal_prompts");
    const levelRule = await levelInstruction(userId);
    const langRule = await explanationLanguageRule(userId);
    // **3言語すべてを名前で引く**（`=== "en" ? "英語" : "日本語"` だと繁體中文の人の
    // 解説が日本語で作られる。`ai-provider.server.ts` の注と同じ話）。
    const NL = explanationLanguageName(await getExplanationLanguage(userId));
    const l1 = await l1Rule(userId, "grammar");
    const coach = targetProfile(await getUserTargetLanguage(userId)).coach;

    // 参照を **番号で** 返させる。見出し語で返させると、同じ語を2回撮った日に
    // どちらの1枚か決まらない。番号なら1対1で戻せる。
    const list = stickers
      .map((s, i) => {
        const head = s.word?.headword ?? "?";
        const meaning = s.word?.meaning_ja ?? "";
        const where = s.location_name ? ` @${s.location_name}` : "";
        const note = s.caption ? ` 一言「${s.caption}」` : "";
        return `${i + 1}. ${head}(${meaning})${where}${note}`;
      })
      .join("\n");

    const Schema = z.object({
      prompts: z
        .array(
          z.object({
            /** 1始まりの番号。範囲外・欠落は下で null に落とす。 */
            capture: z.number().int().nullable(),
            question_zh: z.string().min(1),
            question_ja: z.string().min(1),
          }),
        )
        .min(1)
        .max(3),
      patterns: z
        .array(z.object({ zh: z.string().min(1), ja: z.string() }))
        .min(1)
        .max(3),
    });

    const out = await generateStructured({
      model: ai.gateway(ai.modelRich),
      schema: Schema,
      prompt:
        `あなたは${coach.journalLanguage}の先生。学習者がこれから今日の日記を書きます。\n` +
        `白紙から書くのは難しいので、**書き出しのきっかけになる質問**を作ってください。\n` +
        `${langRule}\n${levelRule}\n${l1}\n\n` +
        `今日この人が撮ったもの:\n${list}\n\n` +
        `次を出力:\n` +
        `- prompts: 質問を3つ。**必ず上の撮影のどれかに結びつける**(capture にその番号)。\n` +
        `  一般論の質問(「今日は何をしましたか」)は禁止。その人の**気持ち・思い出・` +
        `そのとき考えたこと**を引き出す質問にする。一言が書いてあるものは、その気持ちを深める。\n` +
        `  question_zh は学習者のレベルで読める短い${coach.journalScript}の質問。question_ja はその訳(${NL})。\n` +
        `- patterns: その質問に答えるときに使える文型を2〜3個。zh は${coach.journalOpener}のような` +
        `**書き出しの形**(穴埋めできる形)、ja はどんなときに使うかの一言(${NL})。`,
    });

    // **番号は信じきらない。** 範囲外なら結び付けを諦めて null にする —
    // 間違った1枚を指すより、指さないほうが害が小さい。
    const prompts: JournalPrompt[] = out.prompts.map((p) => {
      const i = typeof p.capture === "number" ? p.capture - 1 : -1;
      const hit = i >= 0 && i < stickers.length ? stickers[i] : null;
      return {
        sticker_id: hit?.id ?? null,
        question_zh: p.question_zh,
        question_ja: p.question_ja,
      };
    });

    return {
      prompts,
      patterns: out.patterns,
      captures: stickers.map((s) => ({
        id: s.id,
        headword: s.word?.headword ?? "",
        caption: s.caption,
        location_name: s.location_name,
      })),
    };
  });
