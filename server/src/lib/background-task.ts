/**
 * **返事の後に続ける裏の仕事を、落とさずに走らせる**（2026-10-03 監査）。
 *
 * 本番は Cloudflare Workers。Workers は返事を返した時点で、その要求の中で始めた
 * `void promise` を待たずに止めてよい。`gradeReview` の Jev の影の記録
 * （`model_shadow_predictions`）は `void …` で投げっぱなしだったので、返事の後に
 * 黙って消えていた（較正のための記録が貯まらない）。
 *
 * - `waitUntil` が使える（Workers。nitro/srvx が要求に付ける）→ そこに預けてすぐ戻る。
 *   採点の返事は待たせない（ARCHITECTURE.md「grading never waits for Jev」）。
 * - Workers なのに `waitUntil` が見つからない → 最大 `timeoutMs` だけ待つ（落とすよりまし。
 *   待ちすぎないよう上限つき）。
 * - それ以外（Node の開発サーバ・テスト）→ 走らせっぱなしで消えないので待たない。
 *
 * 仕事の失敗は投げない（ログに残すだけ）。
 */

export type WaitUntil = (promise: Promise<unknown>) => void;

/** いまの要求の `waitUntil`。要求の外・見つからない時は null。 */
export async function currentWaitUntil(): Promise<WaitUntil | null> {
  try {
    const { getRequest } = await import("@tanstack/react-start/server");
    const req = getRequest() as unknown as {
      waitUntil?: unknown;
      runtime?: { cloudflare?: { context?: { waitUntil?: unknown } } };
    };
    if (typeof req?.waitUntil === "function") return req.waitUntil as WaitUntil;
    const ctx = req?.runtime?.cloudflare?.context;
    if (ctx && typeof ctx.waitUntil === "function")
      return (ctx.waitUntil as WaitUntil).bind(ctx) as WaitUntil;
  } catch {
    // 要求の外（テスト・裏の処理）。
  }
  return null;
}

/** Cloudflare Workers の上で動いているか（`navigator.userAgent` が決まった値）。 */
export function onWorkers(): boolean {
  const nav = (globalThis as { navigator?: { userAgent?: string } }).navigator;
  return nav?.userAgent === "Cloudflare-Workers";
}

export async function runAfterResponse(
  label: string,
  task: () => Promise<unknown>,
  opts: { timeoutMs?: number; waitUntil?: WaitUntil | null; workers?: boolean } = {},
): Promise<void> {
  const safe = Promise.resolve()
    .then(task)
    .then(
      () => undefined,
      (e: unknown) => {
        console.warn(`[bg] ${label} failed:`, (e as Error)?.message ?? e);
      },
    );
  const waitUntil = opts.waitUntil === undefined ? await currentWaitUntil() : opts.waitUntil;
  if (waitUntil) {
    try {
      waitUntil(safe);
      return;
    } catch {
      // 預けられなかった（要求がもう終わっている等）。下で待つ。
    }
  }
  if (!(opts.workers ?? onWorkers())) return;
  let timer: ReturnType<typeof setTimeout> | undefined;
  await Promise.race([
    safe,
    new Promise<void>((resolve) => {
      timer = setTimeout(resolve, opts.timeoutMs ?? 2000);
    }),
  ]);
  if (timer) clearTimeout(timer);
}
