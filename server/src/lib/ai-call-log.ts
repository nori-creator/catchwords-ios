/**
 * **AI を呼んだ1回ずつの記録**（オーナー依頼 2026-10-11「アプリの開発者の設定から、それぞれの機能で
 * 使う AI を切り替えたときの結果を計測し、分析できるようにして。…すべての AI を使っている個所の
 * 速さと正確性を計測したい」）。
 *
 * どの AI の呼び出しも `getAiFor` / `getAiAttemptChain`（`ai-provider.server.ts`）で選んだモデルを
 * 通る。そこでモデルを包み（`ai-call-log.server.ts`）、**1回ごとに `ai_runs` へ1行**
 * （loop = `ai_call`）残す。中身は機能・用途・モデル・かかった時間・成否・使った量（トークン）
 * だけ — 写真・語・文は残さない。集計は `ai-model-stats.ts`、画面は開発者の「AI の設定」。
 *
 * ここは表と純粋な関数だけ（試験・画面からも読める。DB にも鍵にも触らない）。
 */
import type { Json } from "@/integrations/supabase/types";
import { AI_ATTEMPT_TIMEOUT, attemptErrorCode } from "./ai-attempts";
import type { AiFeature } from "./ai-features";

export const AI_CALL_LOOP = "ai_call";

/**
 * **用途の表**。同じ機能（例 `scan`）でも、写真の候補と単語帳の読み取りでは待ち時間の桁が違う。
 * まとめて数えると、使われ方が変わっただけで「速くなった・遅くなった」に見えるので、用途ごとに
 * 分けて数える。**新しく AI を呼ぶ所を書いたら、ここに用途を足して `getAiFor(機能, 用途)` で呼ぶ。**
 * 用途を渡さない呼び出しは機能の名前で数える（画面では「その他」）。
 */
export const AI_TASKS = [
  // スキャン（写真を読む速いモデル）
  { id: "photo_candidates", feature: "scan" }, // 撮った写真の単語の候補（suggestWords）
  { id: "tutorial_candidates", feature: "scan" }, // チュートリアルの写真の候補
  { id: "word_candidates", feature: "scan" }, // 母語で調べた語の候補（suggestWordCandidates）
  { id: "scan_detect", feature: "scan" }, // スキャンの画面の物・文字の検出（detectScan）
  { id: "scan_parts", feature: "scan" }, // 「+細かく」の部分の検出（detectParts）
  { id: "image_sense", feature: "scan" }, // 語の絵の意味を決める（image-sense）
  { id: "image_verify", feature: "scan" }, // 語の絵を見て確かめる（image-sense）
  { id: "wordbook", feature: "scan" }, // 単語帳の頁の読み取り
  // 単語カード
  { id: "card", feature: "card" }, // 単語カード（詳細の解説・例文）
  { id: "tutorial_card", feature: "card" }, // チュートリアルのカード
  { id: "tutorial_lesson", feature: "card" }, // チュートリアルの、その人に合わせた短いレッスン
  { id: "phrase_card", feature: "card" }, // フレーズカード
  { id: "section_regen", feature: "card" }, // 項目の作り直し
  { id: "reader_meaning", feature: "card" }, // 読む人の言語での意味
  { id: "chunk_verify", feature: "card" }, // 使い方の型の点検（`AI_CHUNK_VERIFY=inline` の時だけ）
  // 復習・日記
  { id: "distractors", feature: "review" }, // 4択の誤答の作り置き
  { id: "journal_correct", feature: "journal" }, // 日記の添削
  { id: "journal_prompts", feature: "journal" }, // 日記の書き出しの質問
  // 点検・辞書の裏方
  { id: "report_locate", feature: "audit" }, // 報告された項目の特定
  { id: "reading_check_1", feature: "audit" }, // 読みの突き合わせ（1人目）
  { id: "correction_judge", feature: "audit" }, // 作り直しの判定
  { id: "reading_check_2", feature: "reading_check" }, // 読みの突き合わせ（2人目）
  { id: "lexicon_audit", feature: "lexicon" }, // 辞書の点検
  { id: "lexicon_corpus", feature: "lexicon" }, // 生きた例文の生成
  { id: "report_triage", feature: "lexicon" }, // 利用者の報告の検証
  { id: "category_backfill", feature: "lexicon" }, // 棚の分類の付け直し
  // iOS の自由文の窓口（`/api/native-ai`。既定では閉じている）
  { id: "native_ai", feature: null },
] as const satisfies ReadonlyArray<{ id: string; feature: AiFeature | null }>;

export type AiTask = (typeof AI_TASKS)[number]["id"];

export function isAiTask(v: unknown): v is AiTask {
  return typeof v === "string" && AI_TASKS.some((t) => t.id === v);
}

/** 呼び出しに付ける札（機能・用途・会社）。会社は `AiConfig.name`（`google` / `anthropic` …）。 */
export type AiCallTag = { feature: AiFeature; task: AiTask | AiFeature; provider: string };

/** 記録に残す `会社:モデル`。`getAiAttemptChain` の札（`label`）と同じ形。 */
export function aiCallModelLabel(provider: string, modelId: string): string {
  return `${provider}:${modelId}`.slice(0, 160);
}

/** 1回の結果。`code` は失敗の短い印（`timeout` / `cancelled` / `http_429` …）。 */
export type AiCallRecord = {
  feature: AiFeature;
  task: string;
  model: string;
  ms: number;
  ok: boolean;
  code?: string;
  /** 使った量。会社が返さなければ無い。 */
  tokensIn?: number;
  tokensOut?: number;
  reasoning?: number;
  stream?: boolean;
};

/**
 * `ai_runs` の1行。**使った量は `meta` に入れ、`tokens_in` / `tokens_out` の列には入れない** —
 * 列はチュートリアルの記録（`first_catch_ai`）が同じ呼び出しの量を既に書いていて、利用者ごとの
 * 画面（`admin-users.functions.ts`）が列を足し合わせているため（二重に数えない）。
 */
export function aiCallRow(userId: string, r: AiCallRecord) {
  const num = (v: number | undefined) =>
    typeof v === "number" && Number.isFinite(v) && v >= 0 ? Math.round(v) : undefined;
  const meta: { [key: string]: Json } = {
    feature: r.feature,
    task: r.task,
    model: r.model,
    ms: Math.max(0, Math.round(r.ms)),
    ok: r.ok,
  };
  if (!r.ok && r.code) meta.code = r.code.slice(0, 60);
  const tin = num(r.tokensIn);
  const tout = num(r.tokensOut);
  const reasoning = num(r.reasoning);
  if (tin !== undefined) meta.in = tin;
  if (tout !== undefined) meta.out = tout;
  if (reasoning !== undefined) meta.reasoning = reasoning;
  if (r.stream) meta.stream = true;
  return {
    user_id: userId,
    loop: AI_CALL_LOOP,
    iterations: 1,
    accepted: r.ok ? 1 : 0,
    meta,
  };
}

/**
 * 失敗の印。止めたのが誰かで分ける:
 * - `timeout`: 締め切り（`runAiAttempts` の1回ごとの締め切り、`AbortSignal.timeout`）— 遅さの失敗
 * - `cancelled`: 追いかけで負けた回・枠の確保が断られて止めた回 — **AI の失敗ではない**
 * - それ以外は `attemptErrorCode`（`http_429` など）
 */
export function aiCallErrorCode(error: unknown, signal?: AbortSignal | null): string {
  if (signal?.aborted) {
    const reason = signal.reason as { name?: unknown; message?: unknown } | undefined;
    if (reason?.message === AI_ATTEMPT_TIMEOUT || reason?.name === "TimeoutError") return "timeout";
    return "cancelled";
  }
  return attemptErrorCode(error);
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * 要求の `Authorization: Bearer <JWT>` から、**記録を誰の行にするか**だけを読む。
 *
 * 署名はここでは確かめない — 確かめるのは各 server fn の `requireSupabaseAuth`（と iOS の入口）で、
 * AI を呼ぶ口はどれもそれを通った後に呼ばれる。ここで読んだ値は記録の持ち主にだけ使い、
 * 権限の判断には使わない。ログインした人の鍵（`role` = `authenticated`・期限内・`sub` が UUID）
 * でなければ null（記録しない）。
 */
export function callerFromAuthHeader(
  header: string | null | undefined,
  nowMs: number,
): string | null {
  if (!header?.startsWith("Bearer ")) return null;
  const parts = header.slice(7).trim().split(".");
  if (parts.length !== 3) return null;
  try {
    const json = atob(parts[1].replace(/-/g, "+").replace(/_/g, "/"));
    const claims = JSON.parse(json) as { sub?: unknown; role?: unknown; exp?: unknown };
    if (claims.role !== "authenticated") return null;
    if (typeof claims.exp === "number" && claims.exp * 1000 < nowMs) return null;
    return typeof claims.sub === "string" && UUID.test(claims.sub) ? claims.sub : null;
  } catch {
    return null;
  }
}
