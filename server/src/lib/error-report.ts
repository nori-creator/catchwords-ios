/**
 * **Server failures to Sentry** (owner 2026-10-27, project `catchwords-server`).
 *
 * Only the answers the app gets as 500–599 (`edge/native-fn.ts`): which function failed, the error and where in the
 * code. Nothing from the request — no account, no word, no photo, no IP — is sent.
 *
 * Not Sentry's Deno SDK: it would add to a bundle that must stay under Supabase's 5 MB, and Sentry documents that in
 * Deno it cannot keep one request's context apart from another's (the runtime serves many requests at once). One event
 * is one POST to Sentry's envelope endpoint, sent after the answer (`waitUntil`), so a slow Sentry never slows the app.
 */

/** The DSN of `catchwords-server` — only an address to send to, not a secret. `SENTRY_DSN` overrides it. */
export const SERVER_SENTRY_DSN =
  "https://379c08be3ddf277d076d2f8e79d9cc23@o4512328596520960.ingest.us.sentry.io/4512328628240384";

/** Where to POST and the key to send, read from a DSN (`https://<key>@<host>/<project>`). Null if it is not one. */
export function parseDsn(dsn: string): { url: string; key: string } | null {
  try {
    const u = new URL(dsn);
    const project = u.pathname.replace(/^\/+|\/+$/g, "");
    if (!u.username || !/^\d+$/.test(project)) return null;
    return { url: `${u.protocol}//${u.host}/api/${project}/envelope/`, key: u.username };
  } catch {
    return null;
  }
}

type Frame = { function?: string; filename?: string; lineno?: number; colno?: number; in_app: boolean };

/** The frames of a V8 stack (`at name (file:line:col)` / `at file:line:col`), oldest first as Sentry wants them. */
export function stackFrames(stack: string | undefined): Frame[] {
  const frames: Frame[] = [];
  for (const line of (stack ?? "").split("\n")) {
    const m = /^\s*at (?:(.+?) \()?(.+?):(\d+):(\d+)\)?\s*$/.exec(line);
    if (!m) continue;
    const filename = m[2];
    frames.push({
      function: m[1] || undefined,
      filename,
      lineno: Number(m[3]),
      colno: Number(m[4]),
      in_app: !/node_modules|ext:|node:/.test(filename),
    });
  }
  return frames.reverse();
}

/** The envelope for one error (header line, item header line, event line). */
export function errorEnvelope(
  error: unknown,
  opts: { fn: string; status: number; dsn: string; eventId: string; now?: Date; environment?: string },
): string {
  const e = error instanceof Error ? error : new Error(String(error));
  const now = opts.now ?? new Date();
  const frames = stackFrames(e.stack);
  const event = {
    event_id: opts.eventId,
    timestamp: now.getTime() / 1000,
    platform: "javascript",
    level: "error",
    environment: opts.environment ?? "production",
    transaction: opts.fn,
    tags: { fn: opts.fn, status: String(opts.status) },
    exception: {
      values: [
        {
          type: e.name || "Error",
          value: (e.message || "").slice(0, 2000),
          ...(frames.length ? { stacktrace: { frames } } : {}),
        },
      ],
    },
  };
  return [
    JSON.stringify({ event_id: opts.eventId, sent_at: now.toISOString(), dsn: opts.dsn }),
    JSON.stringify({ type: "event" }),
    JSON.stringify(event),
  ].join("\n");
}

/** Sends one failure; never throws (a report that cannot be sent is dropped). */
export async function reportServerError(
  error: unknown,
  ctx: { fn: string; status: number },
  env: { dsn?: string; fetchImpl?: typeof fetch } = {},
): Promise<void> {
  const dsn = env.dsn ?? SERVER_SENTRY_DSN;
  const target = parseDsn(dsn);
  if (!target) return;
  try {
    const body = errorEnvelope(error, {
      ...ctx,
      dsn,
      eventId: crypto.randomUUID().replace(/-/g, ""),
    });
    await (env.fetchImpl ?? fetch)(target.url, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-sentry-envelope",
        "X-Sentry-Auth": `Sentry sentry_version=7, sentry_key=${target.key}, sentry_client=catchwords-server/1.0`,
      },
      body,
      signal: AbortSignal.timeout(3_000),
    });
  } catch {
    // Sentry unreachable: the failure is still in the function's log (`console.warn` in native-fn.ts).
  }
}
