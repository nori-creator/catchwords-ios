/**
 * Apple の token の置き場所（`apple_tokens`）を読み書きし、退会のときに取り消す。
 * 取り消しの決まりは `apple-revoke.ts`。表は移行 `20261003150000_apple_tokens.sql`
 * （サーバの鍵だけが触る。ブラウザからは何もできない）と、token を出した相手を覚える
 * `client_id`（移行 `20261005120000_apple_tokens_client_id.sql`。null = Web の Services ID、
 * iOS の行は bundle id）。`client_id` の移行の前でも、Web の分はこれまでどおり動く。
 *
 * **退会は、取り消しがどう転んでも止めない**（`revokeAppleForUser` は投げない）。
 */
import {
  appleBundleId,
  exchangeAppleAuthCode,
  readAppleConfig,
  revokeAppleToken,
  type AppleTokenKind,
  type RevokeResult,
} from "./apple-revoke";

const TABLE = "apple_tokens";

type LooseError = { message?: string; code?: string } | null;
type Result<T> = PromiseLike<{ data: T | null; error: LooseError }>;

export type AppleTokenRow = {
  token: string;
  token_type: AppleTokenKind;
  /** token を出した相手。null / 無し = Web の Services ID。 */
  client_id?: string | null;
};

/** 使う所だけの形（試験で差し替える）。 */
export type AppleTokenDb = {
  from: (t: string) => {
    select: (c: string) => {
      eq: (k: string, v: string) => { maybeSingle: () => Result<AppleTokenRow> };
    };
    upsert: (row: Record<string, unknown>, o: { onConflict: string }) => Result<unknown>;
    delete: () => { eq: (k: string, v: string) => Result<unknown> };
  };
};

async function adminDb(): Promise<AppleTokenDb> {
  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
  return supabaseAdmin as unknown as AppleTokenDb;
}

/** `client_id` の列がまだ無い（移行の前）という失敗か。 */
function isMissingClientIdColumn(error: LooseError): boolean {
  if (!error) return false;
  return (
    /client_id/.test(error.message ?? "") &&
    (error.code === "PGRST204" ||
      error.code === "42703" ||
      /column|schema cache/i.test(error.message ?? ""))
  );
}

/** 置いてある行を読む（`client_id` の列が無ければ、それ抜きで読み直す）。 */
async function readRow(
  d: AppleTokenDb,
  userId: string,
): Promise<{ data: AppleTokenRow | null; error: LooseError }> {
  const first = await d
    .from(TABLE)
    .select("token, token_type, client_id")
    .eq("user_id", userId)
    .maybeSingle();
  if (!isMissingClientIdColumn(first.error)) return first;
  return d.from(TABLE).select("token, token_type").eq("user_id", userId).maybeSingle();
}

/**
 * Apple の token を置く（同じ人は上書き。refresh token を access token で上書きしない）。
 * `clientId`: token を出した相手（iOS は bundle id。省略・null = Web の Services ID）。
 */
export async function storeAppleToken(
  userId: string,
  input: { token: string; kind: AppleTokenKind; clientId?: string | null },
  db?: AppleTokenDb,
): Promise<{ stored: boolean }> {
  const d = db ?? (await adminDb());
  if (input.kind === "access_token") {
    const { data } = await readRow(d, userId);
    if (data?.token_type === "refresh_token") return { stored: false };
  }
  const row: Record<string, unknown> = {
    user_id: userId,
    token: input.token,
    token_type: input.kind,
    client_id: input.clientId ?? null,
    updated_at: new Date().toISOString(),
  };
  let { error } = await d.from(TABLE).upsert(row, { onConflict: "user_id" });
  // `client_id` の移行の前: Web の分（null）はその列抜きで置く。iOS の分は置かない
  // （bundle id を覚えられないと、Services ID で取り消そうとして断られるだけなので）。
  if (isMissingClientIdColumn(error) && !input.clientId) {
    const rest = { ...row };
    delete rest.client_id;
    ({ error } = await d.from(TABLE).upsert(rest, { onConflict: "user_id" }));
  }
  if (error) throw new Error(`apple_tokens の保存に失敗しました: ${error.message ?? ""}`);
  return { stored: true };
}

export type StoreCodeOutcome = {
  ok: boolean;
  reason?: "not_configured" | "exchange_failed" | "account_mismatch" | "store_failed";
};

/**
 * **iOS の「Apple でサインイン」の `authorizationCode` を refresh token に引き換えて置く**。
 * iOS の code は bundle id に向けて出るので、`client_id` / `client_secret` の `sub` は bundle id。
 * 置いた行には `client_id` = bundle id を覚え、退会の取り消しも bundle id で行う。
 * **投げない**（サインインを止めないため）。token は返事にも記録にも出さない。
 *
 * `appleSubs`: この人の Apple の利用者 ID（Supabase の identities）。分かっていれば、
 * 引き換えた id_token の `sub` と合わない code（別の人の物）は置かない。
 */
export async function storeAppleAuthCodeForUser(
  userId: string,
  code: string,
  deps: {
    appleSubs?: string[];
    db?: AppleTokenDb;
    env?: Record<string, string | undefined>;
    fetch?: typeof fetch;
    log?: (msg: string) => void;
  } = {},
): Promise<StoreCodeOutcome> {
  const log = deps.log ?? ((m: string) => console.warn(m));
  try {
    const env = deps.env ?? process.env;
    const { config, missing } = readAppleConfig(env, { needServicesId: false });
    if (!config) {
      log(`[apple-code] 設定が足りない（${missing.join(", ")}）。預けずに続ける`);
      return { ok: false, reason: "not_configured" };
    }
    const clientId = appleBundleId(env);
    const res = await exchangeAppleAuthCode({ code, config, clientId }, { fetch: deps.fetch });
    if (!res.ok) {
      log(`[apple-code] Apple が引き換えを断った（${res.status ?? "network"} ${res.error}）`);
      return { ok: false, reason: "exchange_failed" };
    }
    const subs = (deps.appleSubs ?? []).filter(Boolean);
    if (subs.length && res.appleSub && !subs.includes(res.appleSub)) {
      log("[apple-code] code の持ち主がこのアカウントの Apple ID と違う。置かない");
      return { ok: false, reason: "account_mismatch" };
    }
    try {
      await storeAppleToken(
        userId,
        { token: res.refreshToken, kind: "refresh_token", clientId },
        deps.db,
      );
    } catch (e) {
      log(`[apple-code] 置けなかった（${e instanceof Error ? e.message : String(e)}）`);
      return { ok: false, reason: "store_failed" };
    }
    return { ok: true };
  } catch (e) {
    log(`[apple-code] 失敗（${e instanceof Error ? e.message : String(e)}）`);
    return { ok: false, reason: "exchange_failed" };
  }
}

export type RevokeOutcome =
  | { status: "revoked" }
  | { status: "skipped"; reason: "no_token" | "not_configured" | "table_missing" }
  | { status: "failed"; error: string; httpStatus: number | null };

/**
 * 退会の前に呼ぶ。置いてある token を Apple で取り消し、置き場所から消す。
 * どんな失敗でも投げずに結果を返し、記録（console）に残す。
 */
export async function revokeAppleForUser(
  userId: string,
  deps: {
    db?: AppleTokenDb;
    env?: Record<string, string | undefined>;
    fetch?: typeof fetch;
    log?: (msg: string) => void;
  } = {},
): Promise<RevokeOutcome> {
  const log = deps.log ?? ((m: string) => console.warn(m));
  try {
    const d = deps.db ?? (await adminDb());
    const { data, error } = await readRow(d, userId);
    if (error) {
      const missing =
        error.code === "PGRST205" ||
        error.code === "42P01" ||
        /apple_tokens/.test(error.message ?? "");
      log(
        `[apple-revoke] token を読めない（${missing ? "表が無い" : error.message}）。取り消さずに退会を続ける`,
      );
      return missing
        ? { status: "skipped", reason: "table_missing" }
        : { status: "failed", error: error.message ?? "read failed", httpStatus: null };
    }
    if (!data?.token) {
      log(
        "[apple-revoke] Apple の token が置かれていない（この変更より前の登録・Apple 以外）。取り消しは飛ばす",
      );
      return { status: "skipped", reason: "no_token" };
    }
    // iOS の行は bundle id で取り消す（Services ID は要らない）。Web の行は Services ID。
    const rowClientId = data.client_id?.trim() || null;
    const { config, missing } = readAppleConfig(deps.env ?? process.env, {
      needServicesId: !rowClientId,
    });
    if (!config) {
      log(`[apple-revoke] 設定が足りない（${missing.join(", ")}）。取り消さずに退会を続ける`);
      return { status: "skipped", reason: "not_configured" };
    }
    const res: RevokeResult = await revokeAppleToken(
      {
        token: data.token,
        kind: data.token_type ?? "refresh_token",
        config,
        clientId: rowClientId,
      },
      { fetch: deps.fetch },
    );
    // 取り消せても失敗しても、token は残さない（表は退会で消えるが、先に消しておく）。
    await d
      .from(TABLE)
      .delete()
      .eq("user_id", userId)
      .then(
        () => undefined,
        () => undefined,
      );
    if (res.ok) {
      log("[apple-revoke] Apple の許可を取り消した");
      return { status: "revoked" };
    }
    log(
      `[apple-revoke] Apple が取り消しを断った（${res.status ?? "network"} ${res.error}）。退会は続ける`,
    );
    return { status: "failed", error: res.error, httpStatus: res.status };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    log(`[apple-revoke] 取り消しで失敗（${msg}）。退会は続ける`);
    return { status: "failed", error: msg, httpStatus: null };
  }
}
