import { createServerFn } from "@tanstack/react-start";
import { FirstCatchAIInput } from "./first-catch-ai-schema";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
/** Only this metered, read/generate-only trial endpoint is available before login. */
export const firstCatchAI = createServerFn({ method: "POST" })
  .inputValidator((raw: unknown) => FirstCatchAIInput.parse(raw))
  .handler(async ({ data }) => {
    // 外部の AI へ送る前の同意（登録前なので、この端末で同意した版を確かめる）。
    (await import("./ai-consent")).assertAttestedConsent(data.aiConsentVersion);
    const { getRequest } = await import("@tanstack/react-start/server");
    const { executeGuestFirstCatch } = await import("./first-catch-guest.server");
    return executeGuestFirstCatch(data, getRequest());
  });

/** Direct signups can run the same tutorial under their own metered account. */
export const firstCatchMemberAI = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((raw: unknown) => FirstCatchAIInput.parse(raw))
  .handler(async ({ data, context }) => {
    // 外部の AI へ送る前の同意。端末だけの匿名アカウント（登録前）はこの端末での同意の版、
    // 登録した人はサーバの記録（`ai_consents`）で確かめる。
    const anonymous = (context.claims as { is_anonymous?: boolean } | undefined)?.is_anonymous;
    if (anonymous) (await import("./ai-consent")).assertAttestedConsent(data.aiConsentVersion);
    else await (await import("./ai-consent.server")).assertAiConsent(context.userId);
    const { executeFirstCatchAI } = await import("./first-catch-ai.server");
    return executeFirstCatchAI(data, context);
  });
