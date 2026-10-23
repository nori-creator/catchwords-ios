/**
 * TEMPORARY: takes the iOS app's data over from the Lovable web app (owner, 2026-10-22). Delete after the move.
 *
 * Reads the Lovable app's one-off export route (`/api/migration-export` in nori-creator/Lovable-catch-words-app)
 * and writes into this project with the service role:
 *   POST { "step": "table", "table": "stickers", "offset": 0, "limit": 500 }  → rows upserted
 *   POST { "step": "photos", "offset": 0, "limit": 25 }                       → files copied into Storage
 * Only rows of non-anonymous users, the shared dictionary and card caches, and the photos those rows point to
 * come over; diaries, posts and logs do not (decided on the export side).
 *
 * MIGRATION_EXPORT_SECRET (an Edge Function secret the owner enters, the same value as in Lovable; never in code
 * or chat) opens the export. A step runs only with `x-run-token` whose SHA-256 is RUN_TOKEN_SHA256 (the token
 * itself is kept by whoever runs the move, not here). Otherwise the function answers 404.
 */
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const EXPORT_URL = "https://catchwords.lovable.app/api/migration-export";
/** Lovable Cloud's project address: public file URLs saved in rows (avatars) move to this project's. */
const OLD_HOST = "https://arjicopbmvseztldpxpk.supabase.co";
const CONFLICT: Record<string, string> = {
  generated_cards: "language,headword,explain_lang,l1",
  corpus_pairs: "word_a,word_b,day,source",
  corpus_stats: "word,day,source",
  categories: "key",
  // A test sign-in on the new app already cached a few headwords: the old row (same word) takes its place.
  dictionary_entries: "language,headword,entry_type",
  review_choices: "word_id",
  // Inserting a sticker creates a fresh review (`stickers_create_review`); the old one, with its schedule, replaces it.
  reviews: "user_id,sticker_id",
  apple_tokens: "user_id",
};

const RUN_TOKEN_SHA256 = "f8992980a9bd3451288571ef1625447f5c5c97160f4ffb463f05c26f3e4efbc2";

const hidden = () => new Response("Not Found", { status: 404 });
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

function same(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

Deno.serve(async (req) => {
  const secret = Deno.env.get("MIGRATION_EXPORT_SECRET") ?? "";
  if (req.method !== "POST" || secret.length < 32) return hidden();
  const given = new TextEncoder().encode(req.headers.get("x-run-token") ?? "");
  const digest = Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", given)))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  if (!same(digest, RUN_TOKEN_SHA256)) return hidden();

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });
  const pull = async (params: Record<string, string>) => {
    const res = await fetch(`${EXPORT_URL}?${new URLSearchParams(params)}`, {
      headers: { "x-migration-secret": secret },
    });
    if (!res.ok) throw new Error(`export ${res.status}`);
    const body = await res.json();
    if (body.error) throw new Error(`export: ${body.error}`);
    return body;
  };

  let input: { step?: string; table?: string; offset?: number; limit?: number };
  try {
    input = await req.json();
  } catch {
    return json({ error: "bad json" }, 400);
  }
  const offset = Math.max(0, Number(input.offset ?? 0));
  const limit = Math.max(1, Number(input.limit ?? 500));

  try {
    if (input.step === "users") return json(await pull({ what: "users" }));

    if (input.step === "table" && input.table) {
      const { rows } = await pull({ what: "table", table: input.table, offset: String(offset), limit: String(limit) });
      const here = Deno.env.get("SUPABASE_URL")!.replace(/\/+$/, "");
      let list = (rows as Record<string, unknown>[]).map((r) =>
        JSON.parse(JSON.stringify(r).split(OLD_HOST).join(here)) as Record<string, unknown>
      );
      if (input.table === "words" && list.length) {
        // `created_by` may name an anonymous account that does not come over.
        const { users } = await pull({ what: "users" });
        const known = new Set(users as string[]);
        list = list.map((r) => (r.created_by && !known.has(String(r.created_by)) ? { ...r, created_by: null } : r));
      }
      if (list.length) {
        const { error } = await admin.from(input.table).upsert(list, {
          onConflict: CONFLICT[input.table] ?? "id",
        });
        if (error) return json({ error: error.message, table: input.table, offset }, 500);
      }
      return json({ table: input.table, offset, written: list.length, done: list.length < limit });
    }

    if (input.step === "photos") {
      const { total, photos } = await pull({ what: "photos", offset: String(offset), limit: String(limit) });
      let copied = 0;
      const failed: string[] = [];
      for (const p of photos as { bucket: string; name: string; url: string }[]) {
        const file = await fetch(p.url);
        if (!file.ok) {
          failed.push(p.name);
          continue;
        }
        const body = new Uint8Array(await file.arrayBuffer());
        const { error } = await admin.storage.from(p.bucket).upload(p.name, body, {
          contentType: file.headers.get("content-type") ?? "application/octet-stream",
          upsert: true,
        });
        if (error) failed.push(p.name);
        else copied++;
      }
      return json({ total, offset, copied, failed, done: offset + limit >= total });
    }
    return json({ error: "unknown step" }, 400);
  } catch (e) {
    return json({ error: (e as Error).message }, 500);
  }
});
