/**
 * 外部の AI へ送る前の同意を、サーバで確かめ・記録する（表と理由は `ai-consent.ts`）。
 *
 * - 記録は `ai_consents`（移行 `20261003140000_ai_consents.sql`）。書くのはサーバの鍵だけ。
 *   本人は自分の行を読めるだけ（同意の日時を勝手に書き換えられない）。
 * - 確かめた「同意あり」は 60 秒だけ覚える（AI を呼ぶたびに DB へ行かない）。取り消しは
 *   覚えを消すので、同じサーバではすぐ効く（他のサーバでも 60 秒以内に効く）。
 * - **表がまだ無い環境（移行待ち）では通す**（ログに残す）。移行を当てる前に出しても AI が
 *   全部止まらないように。移行を当てた後は、DB が読めない時は閉じる側に倒す
 *   （`AI_CONSENT_CHECK_FAILED`）。
 */
import {
  AI_CONSENT_CHECK_FAILED,
  AI_CONSENT_REQUIRED,
  AI_CONSENT_VERSION,
  consentModeFor,
  consentStatusFrom,
  hasCurrentConsent,
  type AiConsentRow,
  type AiConsentStatus,
} from "./ai-consent";

const TABLE = "ai_consents";
const CACHE_MS = 60_000;

type LooseError = { message?: string; code?: string } | null;
type Result<T> = PromiseLike<{ data: T | null; error: LooseError }>;

/** 使う所だけの形（試験で差し替える）。 */
export type ConsentDb = {
  from: (t: string) => {
    select: (c: string) => {
      eq: (
        k: string,
        v: string,
      ) => {
        order: (
          k: string,
          o: { ascending: boolean },
        ) => {
          limit: (n: number) => Result<AiConsentRow[]>;
        };
      };
    };
    insert: (row: Record<string, unknown>) => Result<unknown>;
    update: (patch: Record<string, unknown>) => {
      eq: (
        k: string,
        v: string,
      ) => {
        is: (k: string, v: null) => Result<unknown>;
      };
    };
  };
};

/** 表がまだ無い（移行待ち）か。 */
export function isMissingConsentTable(error: LooseError): boolean {
  if (!error) return false;
  if (error.code === "PGRST205" || error.code === "42P01") return true;
  return (
    new RegExp(TABLE).test(error.message ?? "") && /exist|schema cache/i.test(error.message ?? "")
  );
}

const agreedUntil = new Map<string, number>();

/** 覚えた同意を消す（取り消した時・試験）。 */
export function forgetConsent(userId?: string) {
  if (userId) agreedUntil.delete(userId);
  else agreedUntil.clear();
}

async function adminDb(): Promise<ConsentDb> {
  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
  return supabaseAdmin as unknown as ConsentDb;
}

async function readRows(
  db: ConsentDb,
  userId: string,
): Promise<{ rows: AiConsentRow[]; missing: boolean }> {
  const { data, error } = await db
    .from(TABLE)
    .select("version, agreed_at, revoked_at")
    .eq("user_id", userId)
    .order("agreed_at", { ascending: false })
    .limit(20);
  if (error) {
    if (isMissingConsentTable(error)) return { rows: [], missing: true };
    throw new Error(`${AI_CONSENT_CHECK_FAILED}: ${error.message ?? "read failed"}`);
  }
  return { rows: data ?? [], missing: false };
}

/** その人の今の状態（設定の画面・iOS に返す）。表が無ければ「同意なし」。 */
export async function getAiConsentStatus(
  userId: string,
  db?: ConsentDb,
): Promise<AiConsentStatus & { recorded: boolean }> {
  const { rows, missing } = await readRows(db ?? (await adminDb()), userId);
  return { ...consentStatusFrom(rows), recorded: !missing };
}

/**
 * 今の版に同意しているか。表が無い（移行待ち）時は true（通す）を返し、ログに残す。
 */
export async function hasAiConsent(userId: string, db?: ConsentDb, now = Date.now()) {
  const until = agreedUntil.get(userId);
  if (until && until > now) return true;
  const { rows, missing } = await readRows(db ?? (await adminDb()), userId);
  if (missing) {
    console.warn(
      "[ai-consent] ai_consents が無い（移行 20261003140000_ai_consents.sql が未適用）。同意を確かめずに通す",
    );
    return true;
  }
  const ok = hasCurrentConsent(rows);
  if (ok) agreedUntil.set(userId, now + CACHE_MS);
  return ok;
}

/**
 * **AI を呼ぶ前の関所。** 同意が無ければ `AI_CONSENT_REQUIRED` で断る（何も送らない）。
 * iOS（`/api/native-fn`）は `consentModeFor` の決まりで、見出しか環境変数がある時だけ。
 */
export async function assertAiConsent(
  userId: string,
  deps: {
    db?: ConsentDb;
    request?: { url: string; headers: { get(name: string): string | null } } | null;
    env?: Record<string, string | undefined>;
  } = {},
): Promise<void> {
  let request = deps.request;
  if (request === undefined) {
    try {
      const { getRequest } = await import("@tanstack/react-start/server");
      request = getRequest() ?? null;
    } catch {
      request = null;
    }
  }
  if (consentModeFor(request, deps.env ?? process.env) === "skip") return;
  if (await hasAiConsent(userId, deps.db)) return;
  throw new Error(
    `${AI_CONSENT_REQUIRED}: AI を使う機能は、AI へのデータ送信に同意すると使えます。`,
  );
}

/**
 * 同意する・取り消す（Web の確認の画面・設定・iOS の `recordAiConsent`）。
 * 同意は1回ごとに行を足す（いつ・どの版に同意したかの記録）。取り消しは、取り消して
 * いない行すべてに今の時刻を入れる。
 */
export async function recordAiConsentFor(
  userId: string,
  input: { agreed: boolean; version: number; source: "web" | "ios" | "guest" },
  db?: ConsentDb,
): Promise<AiConsentStatus> {
  const d = db ?? (await adminDb());
  const now = new Date().toISOString();
  forgetConsent(userId);
  if (input.agreed) {
    if (input.version < AI_CONSENT_VERSION) {
      // 古い版の画面で同意した物は、今の版の同意にしない（聞き直す）。
      throw new Error(
        `${AI_CONSENT_REQUIRED}: 同意の内容が新しくなりました。もう一度ご確認ください。`,
      );
    }
    const { error } = await d.from(TABLE).insert({
      user_id: userId,
      version: input.version,
      agreed_at: now,
      source: input.source,
    });
    if (error) throw new Error(`${AI_CONSENT_CHECK_FAILED}: ${error.message ?? "insert failed"}`);
  } else {
    const { error } = await d
      .from(TABLE)
      .update({ revoked_at: now })
      .eq("user_id", userId)
      .is("revoked_at", null);
    if (error && !isMissingConsentTable(error))
      throw new Error(`${AI_CONSENT_CHECK_FAILED}: ${error.message ?? "update failed"}`);
  }
  const { rows } = await readRows(d, userId);
  return consentStatusFrom(rows);
}
