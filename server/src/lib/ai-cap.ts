import {
  pruneBudgetRows,
  reserveBudgetSlot,
  shouldPruneAfter,
  type BudgetDb,
} from "./budget-slots";
import { taipeiDay } from "./taipei-day";

/**
 * **AI の費用の蓋**（Phase B-2 の乱用よけ + 監査 2026-10-03）。
 *
 * これは課金の壁ではない（constitution: スキャンに課金壁を置かない）。人の使い方では
 * まず届かない数に置き、暴走したループや機械的な乱用で AI の予算が溶けるのを止める。
 *
 * ## 3つの蓋
 * 1. **その人の 24 時間の上限**（種類ごと、`DAILY_CAPS`）。数えるのは `usage_events`。
 * 2. **全員を合わせた 1 日の上限**（`AI_GLOBAL_DAILY_CAP`、既定 5,000 回、台湾の日付で
 *    区切る）。`app_config` の一意の鍵で数える（`budget-slots.ts`）— 利用者が自分で
 *    行を足せる `usage_events` で数えると、1人が行を足すだけで全員を止められるため。
 *    発音（`tts`）は数えない（AI の文章生成ではなく、貯めた音の再利用が多いため）。
 * 3. **数えられないときは断る**（前は通していた）。有料にする以上、数えられない間に
 *    費用が青天井になる方が困る。
 *
 * ## 呼ぶ前に1回ぶんを確保する
 * 前は「数える → AI を呼ぶ（数秒〜数十秒）→ 記録する」だったので、同時に何本も
 * 送ると全部が数える段を通り抜けて上限を超えられた。最初のキャッチの会員の道
 * （`first-catch-ai.server.ts`）と同じく、**呼ぶ前に `usage_events` に1行入れる**。
 * 失敗した呼び出しも1回に数える（呼んだ分は費用がかかる）。呼ぶ側は成功の後に
 * 同じ種類をもう一度記録しない。
 *
 * ## 匿名の人と無料の人の枠（監査 2026-10-03）
 * チュートリアルの匿名アカウント（`signInAnonymously`）も `requireSupabaseAuth` を通る。
 * 匿名アカウントは誰でもいくつでも作れるので、1人あたりの上限が大きいままだと、
 * 何人分も作って全体の 5,000 回を使い切り、**お金を払っている人まで止められた**。
 * - 匿名の人は種類ごとの上限を小さくする（`ANONYMOUS_DAILY_CAPS`）。チュートリアルの
 *   AI（`first_catch_ai`）だけは登録した人と同じ（体験を壊さない）。
 * - 全体の枠は Pro の人だけが使う形ではなく、**Pro でない人には小さい「子の枠」を
 *   重ねる**: 匿名の人 `ai-anon-budget:`（既定 500）、無料の人 `ai-free-budget:`
 *   （既定 2,500）。どちらも全体（5,000）にも数えるので、費用の天井は変わらない。
 *   子の枠の合計が全体より小さいので、Pro の人には少なくとも残り（既定 2,000）が残る。
 *
 * ## その人の上限の確保は1回で（監査 2026-10-03）
 * 前は「数える → 1行入れる」の2回で、同時に何本も送ると全部が数える段を通り抜けた。
 * 今は `reserveUsage` が数えると入れるを1回で行う（Postgres の関数
 * `reserve_usage_event`、同じ人・同じ種類は鍵で1本ずつ。`usage-reserve.ts`）。
 *
 * ## 失敗の文
 * 画面の言語で出せるよう、文の頭に印（`AI_DAILY_CAP` など）を付ける
 * （`errors.ts` の `KNOWN_CODES`）。iOS の道（`native-fn.ts`）は日本語の文でも
 * 見分けるので、日本語の文も残す。
 */

/** その人の 24 時間の上限（種類ごと）。 */
export const DAILY_CAPS: Readonly<Record<string, number>> = {
  scan_detect: 300,
  scan_parts: 300,
  tts: 500,
  correction: 100,
  journal_prompt: 60,
  card: 200,
  wordbook: 60, // 1枚の写真で最大60語。取り込みは1日に何度もやる物ではない
  phrase_card: 100,
  suggest: 300,
  removebg: 100, // paid per image — tighter than the free-tier guards
  native_text: 200, // iOS 版の添削・例文など（/api/native-ai の text）
  // 読む人の言語の意味だけを埋める（`fillReaderMeanings`。1回で最大24語、辞書に無い語だけ）。
  reader_meaning: 100,
  // 絵の生成（`images.functions.ts`。1枚ごとに料金がかかる。写真の無い札の見出し用）。
  image_gen: 20,
  // スキャンの候補の並べ替え（`rankScanCandidates` → Jev）。スキャン1回に1回。
  jev_rank: 300,
  // チュートリアルの AI（`first-catch-ai.server.ts`。候補・カード・解説）。
  first_catch_ai: 24,
  // Pro の「AIで絵を作る」（`generateProWordImage`。押した時だけ1枚。1枚ごとに料金がかかる）。
  // 自動の控えの1枚（`image_gen`）とは別に数える — 自動の分で押せなくならないように。
  pro_image: 30,
  // 画像検索の意味を決める・候補の絵を確かめる（`image-sense.server.ts`。速いモデルの小さな
  // 呼び出し。説明で言い切れない検索だけ。1回の検索で最大2回）。枠に届いたら AI を使わずに探す。
  image_sense: 300,
  // 「その他」のまま保存された語の分け直し（`category-backfill.functions.ts`。速いモデルの
  // 小さな呼び出し1回で最大50語。図鑑を開いた時に1度だけ。ふつうは1〜2回で終わる）。
  category_fix: 10,
  // 札の無い古いメインの例文に札だけを書く（`example-scene-label.server.ts`。速いモデルの小さな呼び出し。
  // 単語の詳細を開いた時に、札の無い語だけ1回。同じ語は 30 分呼び直さない）。
  scene_label: 200,
};

/**
 * **匿名の人（チュートリアルの匿名アカウント）の 24 時間の上限。** 登録した人よりずっと
 * 小さい。チュートリアルの AI（`first_catch_ai`）だけは同じ（体験の道は壊さない）。
 * ここに無い種類は、匿名の人には使わせない（0 回）。
 */
export const ANONYMOUS_DAILY_CAPS: Readonly<Record<string, number>> = {
  scan_detect: 10,
  scan_parts: 10,
  tts: 60, // チュートリアルの中でも発音を聞く
  correction: 3,
  journal_prompt: 3,
  card: 10,
  wordbook: 1,
  phrase_card: 3,
  suggest: 10,
  removebg: 3,
  native_text: 3,
  reader_meaning: 5,
  image_gen: 2,
  jev_rank: 10,
  first_catch_ai: DAILY_CAPS.first_catch_ai,
  pro_image: 0, // Pro だけの機能
  image_sense: 20, // チュートリアルの文字検索でも絵の意味を確かめられるように少しだけ
  category_fix: 1,
  scene_label: 10,
};

/** 呼ぶ人の種類。枠の大きさが変わる。 */
export type AiCallerTier = "pro" | "free" | "anonymous";

/** その人・その種類の上限。上限の無い種類は `undefined`（数えない）。 */
export function dailyCapFor(kind: string, tier: AiCallerTier): number | undefined {
  const base = DAILY_CAPS[kind];
  if (base === undefined) return undefined;
  if (tier !== "anonymous") return base;
  return ANONYMOUS_DAILY_CAPS[kind] ?? 0;
}

/** 全員を合わせた 1 日の上限の既定。 */
export const DEFAULT_GLOBAL_AI_DAILY_CAP = 5_000;
/** Pro でない（無料の）人だけを合わせた 1 日の上限の既定（全体にも数える）。 */
export const DEFAULT_FREE_AI_DAILY_CAP = 2_500;
/** 匿名の人だけを合わせた 1 日の上限の既定（全体にも数える）。 */
export const DEFAULT_ANONYMOUS_AI_DAILY_CAP = 500;

/**
 * 全体の上限に数えない種類。発音は AI の文章生成ではなく、貯めた音の再利用が多い。
 * Jev の並べ替えは安い自前のモデルで、スキャン1回に1回呼ぶ（数えると全体の枠が
 * スキャンの半分で尽きる）。どちらもその人の上限は掛かる。
 */
export const GLOBAL_CAP_EXEMPT_KINDS: ReadonlySet<string> = new Set(["tts", "jev_rank"]);

/** 全体の上限の枠の鍵の頭（`<頭><台湾の日付>:<番号>`）。 */
export const GLOBAL_AI_BUDGET_ROOT = "ai-global-budget:";
/** 無料の人の子の枠の鍵の頭。 */
export const FREE_AI_BUDGET_ROOT = "ai-free-budget:";
/** 匿名の人の子の枠の鍵の頭。 */
export const ANONYMOUS_AI_BUDGET_ROOT = "ai-anon-budget:";

/** 失敗の印（`errors.ts` の `KNOWN_CODES` が画面の言語の文に直す）。 */
export const AI_CAP_CODES = {
  daily: "AI_DAILY_CAP",
  global: "AI_GLOBAL_CAP",
  unavailable: "AI_USAGE_CHECK_FAILED",
} as const;

export function dailyCapMessage(limit: number): string {
  return `${AI_CAP_CODES.daily} 1日の利用上限(${limit}回)に達しました。24時間以内に自動で回復します。通常の学習でここに届くことはないため、心当たりがない場合はお問い合わせください。`;
}

/** 匿名の人に使わせない種類を呼んだとき（上限 0）。登録すれば使える。 */
export const ANONYMOUS_NOT_ALLOWED_MESSAGE = `${AI_CAP_CODES.daily} この機能はアカウントを登録すると使えます。`;

export const GLOBAL_CAP_MESSAGE = `${AI_CAP_CODES.global} 本日のAIの利用が上限に達しました。時間をおいてもう一度お試しください。`;

export const USAGE_CHECK_FAILED_MESSAGE = `${AI_CAP_CODES.unavailable} 利用回数を確認できませんでした。少し待ってからもう一度お試しください。`;

/** 上限の蓋が投げた失敗か（上限・全体の枠・数えられない）。 */
export function isAiCapError(e: unknown): boolean {
  const msg = e instanceof Error ? e.message : "";
  return Object.values(AI_CAP_CODES).some((code) => msg.startsWith(code));
}

/** 正の整数の環境変数を読む。読めなければ既定。 */
function positiveInt(raw: string | undefined | null, fallback: number): number {
  const n = Number((raw ?? "").trim());
  return Number.isInteger(n) && n > 0 ? n : fallback;
}

/** `AI_GLOBAL_DAILY_CAP` を読む。正の整数でなければ既定。 */
export function globalAiDailyCap(raw: string | undefined | null): number {
  return positiveInt(raw, DEFAULT_GLOBAL_AI_DAILY_CAP);
}

/**
 * 全体・無料・匿名の 1 日の上限を環境変数から読む（`AI_GLOBAL_DAILY_CAP` /
 * `AI_FREE_DAILY_CAP` / `AI_ANON_DAILY_CAP`）。子の枠は全体より大きくしない。
 */
export function aiBudgetLimits(env: Record<string, string | undefined>): {
  global: number;
  free: number;
  anonymous: number;
} {
  const global = globalAiDailyCap(env.AI_GLOBAL_DAILY_CAP);
  return {
    global,
    free: Math.min(global, positiveInt(env.AI_FREE_DAILY_CAP, DEFAULT_FREE_AI_DAILY_CAP)),
    anonymous: Math.min(global, positiveInt(env.AI_ANON_DAILY_CAP, DEFAULT_ANONYMOUS_AI_DAILY_CAP)),
  };
}

/** 蓋が外の世界に触る所（試験で偽物を渡す）。 */
export type AiCapDeps = {
  /**
   * その人のその種類を、`sinceIso` より後の回数が `limit` 未満なら**1行入れて**その番号を
   * 返す。上限なら `null`。数えると入れるは1回で行う（同時に来ても上限を超えない）。
   * 数えられない・入れられなければ投げる。
   */
  reserveUsage: (
    userId: string,
    kind: string,
    limit: number,
    sinceIso: string,
  ) => Promise<number | null>;
  /** 確保した1行を返す（全体の枠で断られた時）。失敗しても投げない。 */
  releaseUsage?: (id: number) => Promise<void>;
  /** 全体の枠を書く表（管理者の鍵）。 */
  budgetDb: BudgetDb;
  /** 全体の上限。 */
  globalLimit: number;
  /** 無料の人の子の枠（既定 `DEFAULT_FREE_AI_DAILY_CAP`）。 */
  freeLimit?: number;
  /** 匿名の人の子の枠（既定 `DEFAULT_ANONYMOUS_AI_DAILY_CAP`）。 */
  anonymousLimit?: number;
  /** 呼ぶ人の種類（既定 `pro` = 子の枠なし）。 */
  tier?: AiCallerTier;
  now?: () => Date;
  warn?: (message: string, data?: Record<string, unknown>) => void;
};

/** 確保の結果。呼んだ AI が返事を返さなかった時に返す（`usageId`）のに使う。 */
export type AiReservation = { usageId: number | null };

let lastGlobalCapLog = 0;

/**
 * 上限の内側か確かめ、**1回ぶんを確保する**。上限・数えられないときは投げる。
 * 上限の無い種類は何もしない。
 *
 * 順番: その人の1行（1回で数えて入れる）→ 子の枠（無料・匿名）→ 全体の枠。
 * 枠で断られたら、その人の1行は返す（その人の回数を無駄に減らさない）。
 */
export async function reserveAiCall(
  deps: AiCapDeps,
  userId: string,
  kind: string,
): Promise<AiReservation> {
  const tier = deps.tier ?? "pro";
  const limit = dailyCapFor(kind, tier);
  if (limit === undefined) return { usageId: null };
  if (limit <= 0) throw new Error(ANONYMOUS_NOT_ALLOWED_MESSAGE);
  const now = deps.now?.() ?? new Date();
  const warn = deps.warn ?? ((m, d) => console.warn(m, d));

  let usageId: number | null;
  try {
    const since = new Date(now.getTime() - 24 * 60 * 60 * 1000).toISOString();
    usageId = await deps.reserveUsage(userId, kind, limit, since);
  } catch (e) {
    // **閉じる側に倒す。** 数えられなかったことはサーバの記録に残す。
    warn("[usage] cap check failed", { kind, message: (e as Error)?.message ?? String(e) });
    throw new Error(USAGE_CHECK_FAILED_MESSAGE);
  }
  if (usageId === null) throw new Error(dailyCapMessage(limit));

  if (!GLOBAL_CAP_EXEMPT_KINDS.has(kind)) {
    const day = taipeiDay(now);
    const buckets: Array<{ root: string; limit: number }> = [];
    if (tier === "anonymous")
      buckets.push({
        root: ANONYMOUS_AI_BUDGET_ROOT,
        limit: deps.anonymousLimit ?? DEFAULT_ANONYMOUS_AI_DAILY_CAP,
      });
    if (tier === "free")
      buckets.push({
        root: FREE_AI_BUDGET_ROOT,
        limit: deps.freeLimit ?? DEFAULT_FREE_AI_DAILY_CAP,
      });
    buckets.push({ root: GLOBAL_AI_BUDGET_ROOT, limit: deps.globalLimit });
    for (const bucket of buckets) {
      let slot: number;
      try {
        slot = await reserveBudgetSlot(deps.budgetDb, `${bucket.root}${day}:`, bucket.limit, {
          unavailable: USAGE_CHECK_FAILED_MESSAGE,
          limit: GLOBAL_CAP_MESSAGE,
        });
      } catch (e) {
        if (e instanceof Error && e.message === GLOBAL_CAP_MESSAGE) {
          // 上限に届いたことを残す（同じ実体からは1分に1回）。
          if (now.getTime() - lastGlobalCapLog > 60_000) {
            lastGlobalCapLog = now.getTime();
            console.error("[usage] global AI daily ceiling reached", {
              limit: bucket.limit,
              bucket: bucket.root,
              day,
              kind,
            });
          }
        } else {
          warn("[usage] global budget check failed", { kind, bucket: bucket.root });
        }
        // 呼ばなかった回は、その人の回数に数えない。
        if (deps.releaseUsage) await deps.releaseUsage(usageId).catch(() => undefined);
        throw e;
      }
      if (shouldPruneAfter(slot)) await pruneBudgetRows(deps.budgetDb, bucket.root, now);
    }
  }
  return { usageId };
}

/** 呼ぶ人の種類を調べる所（試験で偽物を渡す）。 */
export type CallerTierDeps = {
  /** 匿名アカウントか。調べられなければ投げる。 */
  isAnonymous: (userId: string) => Promise<boolean>;
  /** Pro か（管理者も Pro）。調べられなければ false（課金の判定は開かない側に倒す）。 */
  isPro: (userId: string) => Promise<boolean>;
  now?: () => number;
};

/** 種類を覚えておく時間。匿名の人が登録した直後は、長くてもこの間だけ小さい枠のまま。 */
export const CALLER_TIER_TTL_MS = 60_000;
const tierCache = new Map<string, { tier: AiCallerTier; at: number }>();

/**
 * 呼ぶ人の種類（匿名・無料・Pro）。匿名かどうかが分からない時は
 * `USAGE_CHECK_FAILED_MESSAGE` を投げる（**閉じる側に倒す**）。少しの間覚えておく。
 */
export async function resolveCallerTier(
  deps: CallerTierDeps,
  userId: string,
): Promise<AiCallerTier> {
  const now = deps.now?.() ?? Date.now();
  const hit = tierCache.get(userId);
  if (hit && now - hit.at < CALLER_TIER_TTL_MS) return hit.tier;
  let anonymous: boolean;
  try {
    anonymous = await deps.isAnonymous(userId);
  } catch (e) {
    console.warn("[usage] caller tier check failed", (e as Error)?.message ?? String(e));
    throw new Error(USAGE_CHECK_FAILED_MESSAGE);
  }
  const tier: AiCallerTier = anonymous
    ? "anonymous"
    : (await deps.isPro(userId).catch(() => false))
      ? "pro"
      : "free";
  if (tierCache.size > 5_000) tierCache.clear();
  tierCache.set(userId, { tier, at: now });
  return tier;
}

/** 試験用。 */
export function resetAiCapLogForTest(): void {
  lastGlobalCapLog = 0;
  tierCache.clear();
}
