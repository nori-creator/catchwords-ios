import { askJev, jevAvailable } from "./jev.server";
import {
  acceptCategory,
  categoryQuestion,
  entryFixQuestion,
  entryOpinion,
  exampleQuestion,
  intervalDaysFrom,
  parseJevIntervalMode,
  recallQuestion,
  scheduleQuestion,
  type EntryFields,
  type EntryOpinion,
  type JevIntervalMode,
  type RecallState,
  type ScheduleState,
} from "./jev-tasks";

/**
 * Jev の問いを実際に投げる所。**どれも失敗を投げない**（従来の処理に戻る）。
 */

type Db = {
  // 生成済みの型より新しい表（20260923020000）なので、緩い形で受ける。
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  from: (t: string) => any;
};

let modeCache: { at: number; value: JevIntervalMode } = { at: 0, value: "shadow" };

/**
 * 次の復習の日を誰が決めるか（`parseJevIntervalMode` の注）。60秒だけ覚えておく
 * （採点のたびに設定を読みに行かない）。読めなければ `shadow`。
 */
export async function jevIntervalMode(): Promise<JevIntervalMode> {
  const now = Date.now();
  if (now - modeCache.at < 60_000) return modeCache.value;
  let value: JevIntervalMode = "shadow";
  try {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data } = await (supabaseAdmin as unknown as Db)
      .from("app_config")
      .select("value")
      .eq("key", "jev_interval")
      .maybeSingle();
    value = parseJevIntervalMode((data as { value?: unknown } | null)?.value ?? null);
  } catch (e) {
    console.warn("[jev] interval mode unreadable, using shadow:", (e as Error)?.message ?? e);
  }
  modeCache = { at: now, value };
  return value;
}

/** 本人の札の語を引く（Jev に語そのものの難しさも見せるため）。 */
async function headwordOf(
  db: Db,
  userId: string,
  stickerId: string,
): Promise<{ headword: string; meaning: string | null } | null> {
  const { data } = await db
    .from("stickers")
    .select("words(headword, meaning_ja)")
    .eq("id", stickerId)
    .eq("user_id", userId)
    .maybeSingle();
  const w = (data as { words?: { headword?: string; meaning_ja?: string } } | null)?.words;
  return w?.headword ? { headword: w.headword, meaning: w.meaning_ja ?? null } : null;
}

/**
 * **次の復習の日を Jev に聞く。**（オーナー指示 2026-09-23「jevにすぐに
 * 切り替えて」）
 *
 * 返すのは Jev の日数（柵に収める前）。鍵が無い・時間切れ・答えの形が
 * 違う・語が引けないときは `null` — 呼ぶ側は SM-2 の日数を使う
 * （`pickInterval`）。**失敗を投げない。**
 *
 * 復習の返事はこれを待つので、時間切れは短くしてある（2.5秒）。
 * 画面の側は採点の返事を待たずに次の札へ進む（`review.tsx`）。
 */
export async function jevScheduleDays(
  db: Db,
  args: { userId: string; stickerId: string; state: ScheduleState },
): Promise<{ days: number; model: string; confidence: number } | null> {
  if (!jevAvailable()) return null;
  try {
    let state = args.state;
    if (!state.headword) {
      const w = await headwordOf(db, args.userId, args.stickerId);
      if (!w) return null;
      state = { ...state, headword: w.headword, meaning: w.meaning };
    }
    const q = scheduleQuestion(state);
    const res = await askJev(q.state, q.questions, { timeoutMs: 2500 });
    const iv = res?.answers.interval;
    const days = intervalDaysFrom(iv);
    if (!res || days == null || !iv || iv.type !== "score") return null;
    return { days, model: res.model, confidence: Math.max(0, Math.min(1, iv.confidence)) };
  } catch (e) {
    console.warn("[jev] schedule skipped:", (e as Error)?.message ?? e);
    return null;
  }
}

/**
 * 決めた間隔を**記録に残す**（後で当たり方を確かめるため）。
 * 結果（次の復習で思い出せたか）はこの時点では分からないので空。
 */
export async function logScheduleDecision(
  db: Db,
  args: {
    userId: string;
    stickerId: string;
    model: string;
    confidence: number;
    jevDays: number;
    srsDays: number;
    usedDays: number;
    /** その時どちらが決めたか（影の実行なら使った日数は SM-2 のもの）。 */
    mode: JevIntervalMode;
  },
): Promise<void> {
  try {
    await db.from("model_shadow_predictions").insert({
      user_id: args.userId,
      sticker_id: args.stickerId,
      task: "interval",
      model: args.model,
      // 間隔は確率ではないので、Jev の自信を入れ、日数は meta に置く。
      predicted: args.confidence,
      outcome: null,
      meta: {
        jev_days: args.jevDays,
        srs_days: args.srsDays,
        used_days: args.usedDays,
        mode: args.mode,
      },
    });
  } catch (e) {
    console.warn("[jev] schedule log skipped:", (e as Error)?.message ?? e);
  }
}

/**
 * 記憶の見込みの**記録**（較正を見るため）。予定はここでは動かさない。
 *
 * 復習の答えを受けた後で、**答える前の状態だけ**を Jev に見せて「いま
 * 思い出せるか」を聞き、このアプリの式の見込み・実際の正誤と並べて残す。
 * 後で両者の当たり方（較正）を比べる。
 *
 * 鍵が無ければ何もしない（問い合わせも DB も触らない）。
 */
export async function recordRecallShadow(
  db: Db,
  args: { userId: string; stickerId: string; state: RecallState; outcome: boolean },
): Promise<void> {
  if (!jevAvailable()) return;
  try {
    let state = args.state;
    if (!state.headword) {
      const w = await headwordOf(db, args.userId, args.stickerId);
      if (!w) return;
      state = { ...state, headword: w.headword, meaning: w.meaning };
    }
    const q = recallQuestion(state);
    const res = await askJev(q.state, q.questions, { timeoutMs: 4000 });
    const a = res?.answers.recall;
    if (!res || !a || a.type !== "noul") return;
    await db.from("model_shadow_predictions").insert({
      user_id: args.userId,
      sticker_id: args.stickerId,
      task: "recall",
      model: res.model,
      predicted: a.noul,
      baseline: state.baselineRecall,
      outcome: args.outcome,
      meta: {
        interval_days: state.intervalDays,
        repetitions: state.repetitions,
        days_since: state.daysSinceLastReview,
      },
    });
  } catch (e) {
    console.warn("[jev] recall shadow skipped:", (e as Error)?.message ?? e);
  }
}

/**
 * 生成が「その他」に逃げたときだけ、Jev に棚を聞く。自信が6割以上で
 * 「その他」以外なら、その棚を返す。そうでなければ `null`（「その他」のまま）。
 *
 * 語は利用者の間で共有されるので、**よく分かっている答えを上書きしない**。
 * 触るのは「その他」＝もともと分類に失敗している語だけ。
 */
export async function categoryFallback(
  word: { headword: string; meaning?: string | null; pos?: string | null },
  keys: readonly string[],
): Promise<string | null> {
  if (!jevAvailable()) return null;
  const q = categoryQuestion(word, keys);
  const res = await askJev(q.state, q.questions, { timeoutMs: 2500 });
  const picked = acceptCategory(res?.answers.category);
  return picked && keys.includes(picked) ? picked : null;
}

/**
 * 共有の辞書を直す前の**第二の目**（日々の点検・報告の仕分け）。
 * 鍵が無い・答えが無いときは `null`（呼ぶ側は従来の規則に戻る）。
 */
export async function entryJevOpinion(
  headword: string,
  current: EntryFields,
  proposed: EntryFields,
): Promise<EntryOpinion> {
  if (!jevAvailable()) return null;
  const q = entryFixQuestion(headword, current, proposed);
  const res = await askJev(q.state, q.questions, { timeoutMs: 4000 });
  return entryOpinion(res?.answers.which);
}

/** 影の記録を1行（失敗しても何もしない）。 */
async function logShadow(
  db: Db,
  row: {
    userId: string;
    stickerId?: string | null;
    task: string;
    model: string;
    predicted: number;
    outcome?: boolean | null;
    meta?: Record<string, unknown>;
  },
): Promise<void> {
  try {
    await db.from("model_shadow_predictions").insert({
      user_id: row.userId,
      sticker_id: row.stickerId ?? null,
      task: row.task,
      model: row.model,
      predicted: Math.max(0, Math.min(1, row.predicted)),
      outcome: row.outcome ?? null,
      meta: row.meta ?? null,
    });
  } catch (e) {
    console.warn("[jev] shadow log skipped:", (e as Error)?.message ?? e);
  }
}

/**
 * 生成した例文の**自然さ**（影）。いまは記録だけ。当たり方が確かめられたら、
 * 不自然と出た例文を作り直す判断に使う。
 */
export async function recordExampleShadow(
  db: Db,
  args: { userId: string; headword: string; sentence: string },
): Promise<void> {
  if (!jevAvailable() || !args.sentence.trim()) return;
  const q = exampleQuestion(args.headword, args.sentence);
  const res = await askJev(q.state, q.questions, { timeoutMs: 4000 });
  const a = res?.answers.natural;
  if (!res || !a || a.type !== "noul") return;
  await logShadow(db, {
    userId: args.userId,
    task: "example_natural",
    model: res.model,
    predicted: a.noul,
    meta: { headword: args.headword, sentence: args.sentence.slice(0, 120) },
  });
}
