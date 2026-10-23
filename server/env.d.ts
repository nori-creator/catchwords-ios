// Types for the two runtimes this package meets: Deno (the Edge Function) and Vite-style `import.meta.env`
// in the browser client file kept for the shared types (`src/integrations/supabase/client.ts`).
declare const Deno: { serve(handler: (request: Request) => Response | Promise<Response>): unknown };
interface ImportMeta {
  readonly env: Record<string, string | undefined>;
}
