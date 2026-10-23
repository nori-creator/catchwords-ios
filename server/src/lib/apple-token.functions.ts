import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";

/**
 * **Apple でサインインした直後に、Apple の token をサーバに預ける**（退会のときに取り消すため。
 * `apple-revoke.ts`）。Supabase は Apple の `provider_refresh_token` をサインインの直後に**1回だけ**
 * ブラウザへ渡すので、画面がそれを拾ってここへ送る（`apple-token-capture.ts`）。
 *
 * - 本人の分しか置けない（ログインの token の人の行）。Apple でサインインしたことの無い人の
 *   送った物は置かない。
 * - 置き場所（`apple_tokens`）はサーバの鍵だけが触る。返事に token は出さない。
 */
export const saveAppleToken = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) =>
    z
      .object({
        token: z.string().min(10).max(4096),
        kind: z.enum(["refresh_token", "access_token"]),
      })
      .parse(input),
  )
  .handler(async ({ context, data }) => {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data: u, error } = await supabaseAdmin.auth.admin.getUserById(context.userId);
    if (error || !u?.user) return { stored: false };
    const providers = new Set<string>([
      ...((u.user.app_metadata?.providers as string[] | undefined) ?? []),
      ...(u.user.identities ?? []).map((i) => i.provider),
    ]);
    if (!providers.has("apple")) return { stored: false };
    const { storeAppleToken } = await import("./apple-revoke.server");
    return storeAppleToken(context.userId, { token: data.token, kind: data.kind });
  });

/**
 * **iOS 版: Apple でサインインした直後に、Apple の `authorizationCode` を預ける**
 * （iOS の ASAuthorizationAppleIDCredential は Supabase に identityToken しか渡さず、
 * refresh token が残らない。退会で取り消せるよう、ここで code を refresh token に引き換えて置く）。
 *
 * - code は iOS の bundle id に向けて出る（`client_id` = bundle id。Services ID ではない）。
 * - 本人の分だけ。Apple でサインインしたことの無い人・別の Apple ID の code は置かない。
 * - 設定（APPLE_TEAM_ID / APPLE_KEY_ID / APPLE_PRIVATE_KEY）が無い・Apple が断った時も
 *   投げずに `{ ok: false }`（iOS はどの返事も見ない。サインインは止めない）。token は返さない。
 */
export const storeAppleAuthCode = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => z.object({ code: z.string().min(10).max(4096) }).parse(input))
  .handler(async ({ context, data }): Promise<{ ok: boolean }> => {
    try {
      const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
      const { data: u, error } = await supabaseAdmin.auth.admin.getUserById(context.userId);
      if (error || !u?.user) return { ok: false };
      const appleIdentities = (u.user.identities ?? []).filter((i) => i.provider === "apple");
      const providers = new Set<string>([
        ...((u.user.app_metadata?.providers as string[] | undefined) ?? []),
        ...(u.user.identities ?? []).map((i) => i.provider),
      ]);
      if (!providers.has("apple")) return { ok: false };
      const appleSubs = appleIdentities
        .flatMap((i) => [
          (i.identity_data as { sub?: unknown } | undefined)?.sub,
          (i as { provider_id?: unknown }).provider_id,
        ])
        .filter((v): v is string => typeof v === "string" && v.length > 0);
      const { storeAppleAuthCodeForUser } = await import("./apple-revoke.server");
      const r = await storeAppleAuthCodeForUser(context.userId, data.code, { appleSubs });
      return { ok: r.ok };
    } catch {
      return { ok: false };
    }
  });
