import { choice, noul, score, type JevAnswer, type JevEntry, type JevQuestion } from "./jev";

/**
 * Jev に聞く問いの**中身**と、答えの読み方。通信は `jev-tasks.server.ts`。
 *
 * どれも「落ちたら従来の処理」。Jev の答えが無い・自信が低いときは
 * 何も変えない（`null` を返す）。
 */

// --- 1) スキャンの候補: どれをいちばん調べたいか ----------------------------

export type CandidateInput = {
  headword: string;
  meaning?: string | null;
  kind?: "object" | "text" | string;
  /** 検出の確かさ 0〜1。 */
  confidence?: number;
  /** もう図鑑に在るか。 */
  owned?: boolean;
};

/**
 * 候補ごとの名前は `c0`, `c1`… にする。語そのものを選択肢の名前にすると、
 * 同じ語が2つ来たときや記号を含む語で名前が壊れる。
 */
export function candidateQuestion(items: CandidateInput[]): {
  state: JevEntry;
  questions: Record<string, JevQuestion>;
} {
  const criteria: Record<string, JevEntry> = {};
  items.forEach((it, i) => {
    criteria[`c${i}`] = `${it.headword}${it.meaning ? `（${it.meaning}）` : ""}`;
  });
  return {
    state: {
      task: "A language learner pointed their camera at a scene and these words were detected.",
      candidates: items.map((it) => ({
        word: it.headword,
        meaning: it.meaning ?? null,
        kind: it.kind ?? null,
        detection_confidence: typeof it.confidence === "number" ? it.confidence : null,
        already_in_collection: Boolean(it.owned),
      })),
    },
    questions: {
      wanted: choice(
        "Which one word is this learner most likely trying to look up right now? Prefer the main subject of the photo and words they do not own yet.",
        criteria,
      ),
      // **同じ1回の問い合わせで、台湾の言い方かも確かめる**（待ち時間は増えない）。
      // オーナー指示 2026-09-23 の3回目「Jev をこのアプリで活用して、速さと
      // 正確性を両立させて」。大陸だけの言い方（出租车 → 計程車 など）を学ばせない。
      ...Object.fromEntries(
        items.map((it, i) => [
          `tw${i}`,
          noul(
            `Is "${it.headword}"${it.meaning ? ` (${it.meaning})` : ""} the standard word people in Taiwan use for this, written in Traditional Chinese — not a mainland-China-only term or a simplified form?`,
            {
              true: "standard in Taiwan",
              false: "mainland-only, simplified, or not used in Taiwan",
            },
          ),
        ]),
      ),
    },
  };
}

/**
 * 台湾の言い方として**はっきり疑わしい**候補の番号。Jev が「台湾の標準」と
 * 言う確率が `max` 未満のものだけ（迷うものは疑わない — 正しい語を下げない）。
 */
export function doubtfulTaiwanTerms(
  count: number,
  answers: Record<string, JevAnswer | undefined> | undefined,
  max = 0.15,
): number[] {
  const out: number[] = [];
  for (let i = 0; i < count; i++) {
    const a = answers?.[`tw${i}`];
    if (a && a.type === "noul" && a.noul < max) out.push(i);
  }
  return out;
}

/**
 * 候補を「調べたい見込み」の高い順に並べ替える。**答えが無い・自信が低い
 * ときは元の順のまま**（`null`）。元の順は検出の順で、それも意味を持つ。
 */
export function rankByWanted<T>(
  items: T[],
  answer: JevAnswer | undefined,
  minConfidence = 0.35,
): { order: number[]; probs: number[] } | null {
  if (!answer || answer.type !== "choice") return null;
  if (answer.confidence < minConfidence) return null;
  const probs = items.map((_, i) => answer.probabilities[`c${i}`] ?? 0);
  if (probs.every((p) => p === 0)) return null;
  const order = items.map((_, i) => i).sort((a, b) => probs[b] - probs[a] || a - b);
  return { order, probs };
}

// --- 2) カテゴリー: 生成が「その他」に逃げたときだけ -------------------------

export function categoryQuestion(
  word: { headword: string; meaning?: string | null; pos?: string | null },
  keys: readonly string[],
): { state: JevEntry; questions: Record<string, JevQuestion> } {
  const criteria: Record<string, JevEntry> = {};
  for (const k of keys) criteria[k] = null;
  return {
    state: { word: word.headword, meaning: word.meaning ?? null, part_of_speech: word.pos ?? null },
    questions: {
      category: choice(
        "Which collection shelf does this word belong on? Choose 'other' only if none fits.",
        criteria,
      ),
    },
  };
}

/** 「その他」から上げてよい答えか。自信が十分で、「その他」以外を選んだときだけ。 */
export function acceptCategory(answer: JevAnswer | undefined, minConfidence = 0.6): string | null {
  if (!answer || answer.type !== "choice") return null;
  if (answer.choice === "other" || answer.confidence < minConfidence) return null;
  return answer.choice;
}

// --- 3) 記憶: いま思い出せるか（**記録して較正を見る**。予定は 5) が決める）

export type RecallState = {
  headword: string;
  meaning?: string | null;
  daysSinceLastReview: number | null;
  intervalDays: number;
  ease: number;
  /** 連続正解数（間違えると 0）。 */
  repetitions: number;
  /** このアプリの式（`retentionNow`）が出している見込み 0〜1。比べる相手。 */
  baselineRecall: number;
};

export function recallQuestion(s: RecallState): {
  state: JevEntry;
  questions: Record<string, JevQuestion>;
} {
  return {
    state: {
      word: s.headword,
      meaning: s.meaning ?? null,
      days_since_last_review: s.daysSinceLastReview,
      current_interval_days: s.intervalDays,
      ease_factor: Math.round(s.ease * 100) / 100,
      consecutive_correct: s.repetitions,
    },
    questions: {
      recall: noul("Will the learner correctly recall this vocabulary word if tested right now?", {
        true: "recalls it correctly",
        false: "fails to recall it",
      }),
    },
  };
}

// --- 4) 辞書の日々の点検・報告の仕分け: 直してよいかの**第二の目** ------------

export type EntryFields = { zhuyin: string | null; pinyin: string | null; meaning: string | null };

/**
 * 共有の辞書の1行について、「いまの中身」と「直した案」のどちらが正しいかを
 * 聞く。点検の AI とは**別の目**（`QA.md`「利用者の報告による正本の修正は、
 * 全体へ広げる前に確かめる」）。
 */
export function entryFixQuestion(
  headword: string,
  current: EntryFields,
  proposed: EntryFields,
): { state: JevEntry; questions: Record<string, JevQuestion> } {
  return {
    state: {
      language: "Taiwan Mandarin (Traditional Chinese, Taiwan Ministry of Education standard)",
      word: headword,
      current: { zhuyin: current.zhuyin, pinyin: current.pinyin, meaning_ja: current.meaning },
      proposed: { zhuyin: proposed.zhuyin, pinyin: proposed.pinyin, meaning_ja: proposed.meaning },
    },
    questions: {
      which: choice(
        "Which dictionary entry is correct for this word in Taiwan Mandarin? Mainland-only pronunciations or meanings are not correct here.",
        { current: "the current entry", proposed: "the proposed fix", unsure: "cannot tell" },
      ),
    },
  };
}

export type EntryOpinion = { pProposed: number; pCurrent: number } | null;

export function entryOpinion(answer: JevAnswer | undefined): EntryOpinion {
  if (!answer || answer.type !== "choice") return null;
  return {
    pProposed: answer.probabilities.proposed ?? 0,
    pCurrent: answer.probabilities.current ?? 0,
  };
}

/**
 * **直す**のは、点検の AI が 0.85 以上で確信し、かつ Jev も直した案を
 * 6割以上で選んだときだけ。Jev が使えないときは従来どおり（AI の確信だけ）。
 * 二つの目がそろわない修正は、人間の確認へ回る。
 */
export function allowEntryFix(llmConfidence: number, jev: EntryOpinion): boolean {
  if (llmConfidence < 0.85) return false;
  return jev == null || jev.pProposed >= 0.6;
}

/** 報告を**却下**するのも同じ。Jev がいまの中身を6割以上で選んだときだけ。 */
export function allowDismiss(llmConfidence: number, jev: EntryOpinion): boolean {
  if (llmConfidence < 0.85) return false;
  return jev == null || jev.pCurrent >= 0.6;
}

// --- 5) 復習のタイミング（**Jev が決める**。オーナー指示 2026-09-23）-------

/**
 * 次の復習までの間隔の段（日）。
 *
 * （オーナー指示 2026-09-23「jevにすぐに切り替えて」— 以前は影で記録する
 *  だけだった。`ARCHITECTURE.md`「Memory」に指示の日付と理由を残した）
 */
export const INTERVAL_BUCKETS = [1, 3, 7, 14, 30, 60, 120] as const;

/**
 * 「次はいつ見せるか」の問い。狙いはこのアプリの狙いの定着度（90%）に
 * そろえる — 画面の「復習どき」と、Jev が決める日が同じ意味になるように。
 */
export function intervalQuestion(): JevQuestion {
  return score(
    "After this review, how many days from now should the learner see this word again so that they still have about a 90% chance of recalling it?",
    INTERVAL_BUCKETS.map((d) => `${d} days`),
  );
}

/** 段の期待値から日数へ（段の間は線形に）。 */
export function intervalDaysFrom(answer: JevAnswer | undefined): number | null {
  if (!answer || answer.type !== "score") return null;
  if (!Number.isFinite(answer.score)) return null;
  const x = Math.max(0, Math.min(INTERVAL_BUCKETS.length - 1, answer.score));
  const lo = Math.floor(x);
  const hi = Math.min(INTERVAL_BUCKETS.length - 1, lo + 1);
  return Math.round(
    INTERVAL_BUCKETS[lo] + (INTERVAL_BUCKETS[hi] - INTERVAL_BUCKETS[lo]) * (x - lo),
  );
}

export type ScheduleState = {
  headword: string;
  meaning?: string | null;
  /** 答える**前**の状態。 */
  daysSinceLastReview: number | null;
  intervalDaysBefore: number;
  ease: number;
  repetitionsBefore: number;
  /** **この復習の結果**。間隔はこれを見て決める。 */
  recalled: boolean;
  /** 採点 0〜5（5 = すぐ正解、2 = ヒントを見た、1 = 間違い）。 */
  score: number;
  responseSeconds: number | null;
};

/**
 * 間隔を決める問い。記憶の問い（`recallQuestion`）と違い、**この復習の
 * 結果を見せる** — 結果を知らずに次の日を決めることはできない。だから
 * 記憶の問いとは**別の呼び出し**にする（同じ state に入れると、記憶の
 * 予測に答えが漏れる）。
 */
export function scheduleQuestion(s: ScheduleState): {
  state: JevEntry;
  questions: Record<string, JevQuestion>;
} {
  return {
    state: {
      word: s.headword,
      meaning: s.meaning ?? null,
      days_since_previous_review: s.daysSinceLastReview,
      previous_interval_days: s.intervalDaysBefore,
      ease_factor: Math.round(s.ease * 100) / 100,
      consecutive_correct_before: s.repetitionsBefore,
      this_review: {
        recalled: s.recalled,
        grade_0_to_5: s.score,
        response_seconds: s.responseSeconds,
      },
    },
    questions: { interval: intervalQuestion() },
  };
}

/**
 * **実際に使う間隔**を決める。Jev の日数を、SM-2 の日数を基準にした柵の中に
 * 収める。
 *
 *  ・**思い出せなかった語は明日**（SM-2 のまま）。忘れた語を Jev の判断で
 *    先へ延ばさない — いちばん取り返しがつかない間違いなので。
 *  ・Jev の答えが無い（鍵が無い・時間切れ・形が違う）ときは SM-2 のまま。
 *  ・Jev の日数は **SM-2 の半分〜2倍**に収める（下限 1日・上限 365日）。
 *    まだ実データで当たり方を確かめていないモデルなので、1回の答えで
 *    予定が極端に動かないようにする柵。当たり方が確かめられたら広げる。
 */
export const JEV_INTERVAL_MIN_RATIO = 0.5;
export const JEV_INTERVAL_MAX_RATIO = 2;

/**
 * **次の復習の日を、誰が決めるか**（オーナー判断 2026-10-01「影の実行に戻す」）。
 *
 * - `shadow`（既定）… SM-2 が決める。Jev の答えは記録だけ（`model_shadow_predictions`）。
 *   ロードマップの「まず影響の無い影の実行で当たり方を確かめる」に戻した。
 * - `live` … Jev の日数を SM-2 の半分〜2倍の柵に収めて使う（2026-09-23〜10-01 の動き）。
 *
 * 切り替えは `app_config` の `jev_interval` = `{"mode":"live"}`（デプロイ不要）。
 * 読めない・知らない値は `shadow`（安全な側）。
 */
export type JevIntervalMode = "shadow" | "live";

export function parseJevIntervalMode(value: unknown): JevIntervalMode {
  const mode = (value as { mode?: unknown } | null)?.mode;
  return mode === "live" ? "live" : "shadow";
}

export function pickInterval(
  srsDays: number,
  jevDays: number | null,
  score: number,
  lapseScore = 3,
): { days: number; source: "jev" | "srs" } {
  const base = Math.max(1, Math.round(srsDays));
  if (score < lapseScore || jevDays == null || !Number.isFinite(jevDays)) {
    return { days: base, source: "srs" };
  }
  const lo = Math.max(1, Math.floor(base * JEV_INTERVAL_MIN_RATIO));
  const hi = Math.min(365, Math.max(lo, Math.ceil(base * JEV_INTERVAL_MAX_RATIO)));
  return { days: Math.max(lo, Math.min(hi, Math.round(jevDays))), source: "jev" };
}

// --- 6) 例文の自然さ（**影の実行**）------

export function exampleQuestion(
  headword: string,
  sentence: string,
): { state: JevEntry; questions: Record<string, JevQuestion> } {
  return {
    state: { target_word: headword, example_sentence: sentence },
    questions: {
      natural: noul(
        "Would a native Taiwan Mandarin speaker naturally say this sentence in everyday life?",
        { true: "natural", false: "unnatural or textbook-like" },
      ),
    },
  };
}
