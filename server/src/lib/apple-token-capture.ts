/**
 * **Apple でサインインした直後の `provider_refresh_token` を拾ってサーバに預ける**
 * （退会のときに Apple の許可を取り消すため。`apple-revoke.ts`）。
 *
 * supabase-js は、OAuth から戻った URL を読んだ時に `provider_token` /
 * `provider_refresh_token` を session に載せて**1回だけ**知らせる。後から聞いても無い。
 * だからアプリの読み込みの最初（`__root.tsx` の読み込み時）に聞き始める。
 *
 * Lovable の OAuth の窓口を通る時、窓口がこの2つを戻り先に渡さなければ拾えない
 * （README.ja.md の「Apple の取り消し」— 拾えたかは `apple_tokens` に行があるかで確かめる）。
 */
type SessionLike = {
  provider_token?: string | null;
  provider_refresh_token?: string | null;
  user?: { app_metadata?: { provider?: string; providers?: string[] } } | null;
} | null;

/** 預ける物（Apple のサインインの直後の session だけ）。無ければ null。 */
export function appleTokenFromSession(
  session: SessionLike,
): { token: string; kind: "refresh_token" | "access_token" } | null {
  if (!session) return null;
  const meta = session.user?.app_metadata;
  const isApple = meta?.provider === "apple" || (meta?.providers ?? []).includes("apple");
  if (!isApple) return null;
  if (session.provider_refresh_token)
    return { token: session.provider_refresh_token, kind: "refresh_token" };
  if (session.provider_token) return { token: session.provider_token, kind: "access_token" };
  return null;
}

const sent = new Set<string>();
let installed = false;
let inflight: Promise<void> = Promise.resolve();

/** 預けている途中の送信を待つ（iOS へ戻る前に、`native-auth.tsx`）。最大 `ms` ミリ秒。 */
export function waitForAppleTokenCapture(ms = 3000): Promise<void> {
  return Promise.race([inflight, new Promise<void>((r) => setTimeout(r, ms))]);
}

async function send(session: SessionLike) {
  const found = appleTokenFromSession(session);
  if (!found || sent.has(found.token)) return;
  sent.add(found.token);
  try {
    const { saveAppleToken } = await import("./apple-token.functions");
    await saveAppleToken({ data: found });
  } catch (e) {
    // 預けられなくてもサインインは続ける（退会の時に取り消せないだけ。記録には残す）。
    sent.delete(found.token);
    console.warn("[apple-token] 預けられなかった", e instanceof Error ? e.message : e);
  }
}

/** 1回だけ聞き始める（ブラウザだけ）。 */
export function installAppleTokenCapture() {
  if (installed || typeof window === "undefined") return;
  installed = true;
  void import("@/integrations/supabase/client")
    .then(({ supabase }) => {
      supabase.auth.onAuthStateChange((_event, session) => {
        if (!appleTokenFromSession(session)) return;
        inflight = send(session);
      });
    })
    .catch(() => undefined);
}
