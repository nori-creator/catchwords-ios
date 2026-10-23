/**
 * The app's server as one Supabase Edge Function: `POST /functions/v1/native-fn`.
 *
 * Same contract the iOS app had with the web server's `/api/native-fn` (web `src/routes/api.native-fn.ts`):
 * send `{ "fn": "generateCard", "data": { … } }` with `Authorization: Bearer <Supabase access token>`;
 * get `{ "result": … }`, or `{ "error": "…" }` with 400 / 401 / 403 / 404 / 429 / 500 / 503.
 * Only the functions listed in `NATIVE_FNS` can be called, and each checks the caller itself
 * (`requireSupabaseAuth`); the AI keys stay in this function's secrets and are never returned.
 */
import { runWithRequest } from "../shims/tanstack-start-server";
import { NATIVE_FNS, publicMessage, statusForError } from "@/lib/native-fn";

declare const EdgeRuntime: { waitUntil(promise: Promise<unknown>): void } | undefined;

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return json({ error: "POST だけを受け付けます。" }, 405);
  let body: { fn?: unknown; data?: unknown };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return json({ error: "送った内容の形が違います。" }, 400);
  }
  const name = typeof body.fn === "string" ? body.fn : "";
  const load = Object.prototype.hasOwnProperty.call(NATIVE_FNS, name) ? NATIVE_FNS[name] : undefined;
  if (!load) return json({ error: "その機能はありません。" }, 404);

  // Work that continues after the answer (`after-response.ts`, `background-task.ts`) is handed to the runtime.
  if (typeof EdgeRuntime !== "undefined") {
    (request as Request & { waitUntil?: (p: Promise<unknown>) => void }).waitUntil = (p) =>
      EdgeRuntime.waitUntil(p);
  }
  return runWithRequest(request, async () => {
    try {
      const fn = await load();
      const result = await fn({ data: body.data });
      return json({ result: result ?? null });
    } catch (e) {
      const status = statusForError(e);
      if (status >= 500) console.warn(`[native-fn] ${name} failed: ${(e as Error)?.message}`);
      return json({ error: publicMessage(e) }, status);
    }
  });
});
