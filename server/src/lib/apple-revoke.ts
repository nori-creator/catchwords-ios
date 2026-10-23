/**
 * **退会のときに「Apple でサインイン」の許可を取り消す**（Apple の退会の決まり・TN3194）。
 *
 * Apple の決まり（2026-10-03 に公式の文書で確かめた）:
 * - 取り消しの口は `POST https://appleid.apple.com/auth/revoke`
 *   （`application/x-www-form-urlencoded`）。送る物は `client_id`（Supabase の Apple ログインに
 *   使っている Services ID）・`client_secret`（下の JWT）・`token`（利用者の refresh token か
 *   access token）・`token_type_hint`（`refresh_token` / `access_token`）。
 *   取り消せた・前に無効になっていた時は **200 で本文なし**。失敗は `{"error":"invalid_client"}` など。
 * - `client_secret` は ES256（P-256 + SHA-256）で署名した JWT。頭は `alg: ES256`・`kid: Key ID`、
 *   中身は `iss: Team ID`・`iat`・`exp`（今から **15777000 秒（6か月）以内**）・
 *   `aud: https://appleid.apple.com`・`sub: client_id と同じ Services ID`。
 * - 取り消す token が無い人（この変更より前に Apple で登録した人）でも退会は必ず終える。
 *   その人は Apple の「Apple でサインイン」の設定から自分で外せる（TN3194）。
 *
 * ここは Cloudflare でも動くように **Web Crypto だけ**を使う（Node の crypto・JWT の道具は使わない）。
 * DB を読む所は `apple-revoke.server.ts`。
 */

export const APPLE_REVOKE_URL = "https://appleid.apple.com/auth/revoke";
export const APPLE_TOKEN_URL = "https://appleid.apple.com/auth/token";
/**
 * iOS アプリの bundle id。iOS の「Apple でサインイン」（ASAuthorizationAppleIDCredential）の
 * `authorizationCode` は **この bundle id に向けて**出るので、引き換え・取り消しの `client_id` と
 * `client_secret` の `sub` もこれにする（Web の Services ID では Apple が `invalid_client` で断る）。
 * 環境変数 `APPLE_BUNDLE_ID` があればそちら。
 */
export const APPLE_IOS_BUNDLE_ID = "com.nori.catchwords";
export const APPLE_AUDIENCE = "https://appleid.apple.com";
/** Apple が受ける `exp` の上限（今から 6 か月 = 15777000 秒）。少し余して 1 時間にする。 */
export const CLIENT_SECRET_TTL_S = 60 * 60;
export const CLIENT_SECRET_MAX_TTL_S = 15_777_000;

export type AppleConfig = {
  teamId: string;
  keyId: string;
  /** p8 の中身（`-----BEGIN PRIVATE KEY-----` …）。改行が `\n` の文字になっていても読む。 */
  privateKey: string;
  /** Web の Services ID。iOS の行（`client_id` = bundle id）だけを扱う時は空でもよい。 */
  servicesId: string;
};

/**
 * 環境変数から読む。どれか欠けていれば null と足りない名前。
 * `needServicesId: false` は iOS の bundle id で署名する時（Services ID を使わない）。
 */
export function readAppleConfig(
  env: Record<string, string | undefined>,
  opts: { needServicesId?: boolean } = {},
): {
  config: AppleConfig | null;
  missing: string[];
} {
  const names = ["APPLE_TEAM_ID", "APPLE_KEY_ID", "APPLE_PRIVATE_KEY"];
  if (opts.needServicesId !== false) names.push("APPLE_SERVICES_ID");
  const missing = names.filter((n) => !env[n]?.trim());
  if (missing.length) return { config: null, missing };
  return {
    config: {
      teamId: env.APPLE_TEAM_ID!.trim(),
      keyId: env.APPLE_KEY_ID!.trim(),
      privateKey: env.APPLE_PRIVATE_KEY!,
      servicesId: env.APPLE_SERVICES_ID?.trim() ?? "",
    },
    missing: [],
  };
}

/** iOS の bundle id（`APPLE_BUNDLE_ID` があればそれ）。 */
export function appleBundleId(env: Record<string, string | undefined>): string {
  return env.APPLE_BUNDLE_ID?.trim() || APPLE_IOS_BUNDLE_ID;
}

function base64UrlFromBytes(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64UrlFromJson(v: unknown): string {
  return base64UrlFromBytes(new TextEncoder().encode(JSON.stringify(v)));
}

/** p8（PKCS#8 の PEM）から鍵の中身（DER）を取り出す。 */
export function pemToDer(pem: string): Uint8Array {
  const body = pem
    .replace(/\\n/g, "\n")
    .replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "")
    .replace(/\s+/g, "");
  if (!body) throw new Error("APPLE_PRIVATE_KEY is empty");
  const bin = atob(body);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

/**
 * Apple に渡す `client_secret`（ES256 の JWT）を作る。Web Crypto の ECDSA の署名は
 * r‖s の 64 バイト（IEEE P1363）で、JWS の ES256 が求める形そのもの。
 * `sub` は `clientId`（省略時は Services ID。iOS の token は bundle id）。
 */
export async function makeAppleClientSecret(
  config: AppleConfig,
  nowSeconds = Math.floor(Date.now() / 1000),
  ttlSeconds = CLIENT_SECRET_TTL_S,
  clientId: string = config.servicesId,
): Promise<string> {
  if (!clientId) throw new Error("Apple client_id is empty");
  const ttl = Math.min(Math.max(60, ttlSeconds), CLIENT_SECRET_MAX_TTL_S);
  const header = { alg: "ES256", kid: config.keyId, typ: "JWT" };
  const payload = {
    iss: config.teamId,
    iat: nowSeconds,
    exp: nowSeconds + ttl,
    aud: APPLE_AUDIENCE,
    sub: clientId,
  };
  const signingInput = `${base64UrlFromJson(header)}.${base64UrlFromJson(payload)}`;
  const der = pemToDer(config.privateKey);
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der.buffer.slice(der.byteOffset, der.byteOffset + der.byteLength) as ArrayBuffer,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64UrlFromBytes(new Uint8Array(sig))}`;
}

export type AppleTokenKind = "refresh_token" | "access_token";

export type RevokeResult =
  { ok: true; status: number } | { ok: false; status: number | null; error: string };

/**
 * Apple の取り消しの口を呼ぶ。**投げない**（退会を止めないため、結果で返す）。
 * `clientId` は token を出した相手（iOS の行は bundle id。省略時は Services ID）。
 */
export async function revokeAppleToken(
  input: { token: string; kind: AppleTokenKind; config: AppleConfig; clientId?: string | null },
  deps: { fetch?: typeof fetch; now?: number } = {},
): Promise<RevokeResult> {
  const doFetch = deps.fetch ?? fetch;
  try {
    const clientId = input.clientId || input.config.servicesId;
    const secret = await makeAppleClientSecret(input.config, deps.now, undefined, clientId);
    const body = new URLSearchParams({
      client_id: clientId,
      client_secret: secret,
      token: input.token,
      token_type_hint: input.kind,
    });
    const res = await doFetch(APPLE_REVOKE_URL, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: body.toString(),
      signal: AbortSignal.timeout(8000),
    });
    if (res.ok) return { ok: true, status: res.status };
    let error = `http_${res.status}`;
    try {
      const j = (await res.json()) as { error?: string };
      if (j?.error) error = j.error;
    } catch {
      // 本文が JSON でない
    }
    return { ok: false, status: res.status, error };
  } catch (e) {
    return { ok: false, status: null, error: e instanceof Error ? e.message : String(e) };
  }
}

export type ExchangeResult =
  | { ok: true; refreshToken: string; appleSub: string | null }
  | { ok: false; status: number | null; error: string };

/** id_token（Apple から TLS で直に受け取った物）の `sub` だけを読む。署名は確かめない。 */
export function appleSubFromIdToken(idToken: unknown): string | null {
  if (typeof idToken !== "string") return null;
  const part = idToken.split(".")[1];
  if (!part) return null;
  try {
    const b64 = part.replace(/-/g, "+").replace(/_/g, "/");
    const bin = atob(b64 + "=".repeat((4 - (b64.length % 4)) % 4));
    const bytes = Uint8Array.from(bin, (c) => c.charCodeAt(0));
    const payload = JSON.parse(new TextDecoder().decode(bytes)) as { sub?: unknown };
    return typeof payload.sub === "string" ? payload.sub : null;
  } catch {
    return null;
  }
}

/**
 * iOS の `authorizationCode` を Apple の `/auth/token` で refresh token に引き換える
 * （`grant_type=authorization_code`。code は 5 分・1 回だけ有効）。**投げない**。
 * 返事の token は呼んだ側が置くだけで、記録には出さない。
 */
export async function exchangeAppleAuthCode(
  input: { code: string; config: AppleConfig; clientId: string },
  deps: { fetch?: typeof fetch; now?: number } = {},
): Promise<ExchangeResult> {
  const doFetch = deps.fetch ?? fetch;
  try {
    const secret = await makeAppleClientSecret(input.config, deps.now, undefined, input.clientId);
    const body = new URLSearchParams({
      client_id: input.clientId,
      client_secret: secret,
      code: input.code,
      grant_type: "authorization_code",
    });
    const res = await doFetch(APPLE_TOKEN_URL, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: body.toString(),
      signal: AbortSignal.timeout(8000),
    });
    type TokenReply = { refresh_token?: unknown; id_token?: unknown; error?: unknown };
    const j: TokenReply | null = await res.json().then(
      (v: unknown) => (v && typeof v === "object" ? (v as TokenReply) : null),
      () => null, // 本文が JSON でない
    );
    if (!res.ok) {
      const error = typeof j?.error === "string" ? j.error : `http_${res.status}`;
      return { ok: false, status: res.status, error };
    }
    if (typeof j?.refresh_token !== "string" || !j.refresh_token) {
      return { ok: false, status: res.status, error: "no_refresh_token" };
    }
    return { ok: true, refreshToken: j.refresh_token, appleSub: appleSubFromIdToken(j.id_token) };
  } catch (e) {
    return { ok: false, status: null, error: e instanceof Error ? e.message : String(e) };
  }
}
