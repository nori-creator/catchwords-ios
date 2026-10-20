import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";

/**
 * 外部の AI へ送る前の同意を読む・記録する（Web の確認の画面・設定・iOS）。
 * 仕組みは `ai-consent.server.ts`。iOS からは `/api/native-fn` で
 * `{"fn":"recordAiConsent","data":{"version":1,"agreed":true}}` のように呼ぶ
 * （`docs/ios-spec/23-ai-consent.md`）。
 */
export const getAiConsent = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const { getAiConsentStatus } = await import("./ai-consent.server");
    return getAiConsentStatus(context.userId);
  });

export const recordAiConsent = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) =>
    z
      .object({
        version: z.number().int().min(1).max(1000),
        agreed: z.boolean(),
        // 誰が記録したか（記録のため。省けば Web）。
        source: z.enum(["web", "ios", "guest"]).optional(),
      })
      .parse(input),
  )
  .handler(async ({ context, data }) => {
    const { recordAiConsentFor } = await import("./ai-consent.server");
    const { getRequest } = await import("@tanstack/react-start/server");
    // `/api/native-fn` から来たら iOS（画面が何と言っても）。
    let source = data.source ?? "web";
    try {
      if (/\/(?:api\/)?native-fn\/?$/.test(new URL(getRequest().url).pathname)) source = "ios";
    } catch {
      // 読めなければ送られた物のまま。
    }
    return recordAiConsentFor(context.userId, {
      agreed: data.agreed,
      version: data.version,
      source,
    });
  });
