import { createIsomorphicFn } from "@tanstack/react-start";
import { withDeadline } from "./deadline";

/**
 * **返事を返した後も続けたい処理を、黙って捨てさせない**（監査 2026-10-03 L5）。
 *
 * 本番は Cloudflare Workers（nitro の `cloudflare-module`）。Workers は返事を返した時点で
 * 待っていない約束を打ち切ることがある。`void work().catch(() => {})` と書くと、
 * 4択の誤答の作り置き（`pregenerateDistractors`）のような裏の仕事が**誰にも知られずに**
 * 消えていた。
 *
 * - 走っている環境が `waitUntil` を持っていれば（nitro は Workers の `ctx.waitUntil` を
 *   `request.waitUntil` に付ける）、それに預けてすぐ戻る — 保存は待たない
 * - 持っていなければ、上限つきで待つ（上限を過ぎたら待つのはやめる。仕事そのものは
 *   Node のように打ち切らない環境ではそのまま続く）
 * - 失敗は**必ず記録に残す**（`label` 付き）。投げはしない — 裏の仕事の失敗で
 *   本体（キャッチの保存など）を落とさない
 */

export type WaitUntil = (promise: Promise<unknown>) => void;

/** 待つ上限の既定。保存の道で使うので短く置く。 */
export const AFTER_RESPONSE_FALLBACK_MS = 3_000;

type RequestLike = {
  waitUntil?: unknown;
  runtime?: { cloudflare?: { context?: { waitUntil?: unknown } } };
};

/** 要求に付いた `waitUntil` を探す（無ければ null）。 */
export function waitUntilFrom(req: unknown): WaitUntil | null {
  if (!req || typeof req !== "object") return null;
  const r = req as RequestLike;
  if (typeof r.waitUntil === "function") return r.waitUntil as WaitUntil;
  const ctx = r.runtime?.cloudflare?.context;
  if (ctx && typeof ctx.waitUntil === "function") {
    return (p) => (ctx.waitUntil as (p: Promise<unknown>) => void).call(ctx, p);
  }
  return null;
}

/**
 * いまの要求の `waitUntil`（server fn の外・試験では null）。
 * ブラウザ側の部品からも読まれるファイルなので、サーバ専用の読み込みは
 * `.server()` の中だけに置く（ブラウザでは常に null）。
 */
const currentWaitUntil = createIsomorphicFn()
  .server(async (): Promise<WaitUntil | null> => {
    try {
      const { getRequest } = await import("@tanstack/react-start/server");
      return waitUntilFrom(getRequest());
    } catch {
      return null;
    }
  })
  .client(async (): Promise<WaitUntil | null> => null);

/**
 * `task` を返事の後まで生かす。戻り値は「預けた / 待ち終えた」だけで、`task` の結果は返さない。
 * `waitUntil` を渡すと、それを使う（試験用。普段は要求から探す）。
 */
export async function runAfterResponse(
  label: string,
  task: () => Promise<unknown>,
  opts: { timeoutMs?: number; waitUntil?: WaitUntil | null } = {},
): Promise<"deferred" | "awaited"> {
  let running: Promise<unknown>;
  try {
    running = Promise.resolve(task());
  } catch (e) {
    running = Promise.reject(e);
  }
  const guarded = running.catch((e: unknown) => {
    console.warn(`[after-response] ${label} failed`, e instanceof Error ? e.message : e);
  });
  const waitUntil = opts.waitUntil !== undefined ? opts.waitUntil : await currentWaitUntil();
  if (waitUntil) {
    try {
      waitUntil(guarded);
      return "deferred";
    } catch (e) {
      console.warn(`[after-response] ${label}: waitUntil threw`, e);
    }
  }
  const ms = opts.timeoutMs ?? AFTER_RESPONSE_FALLBACK_MS;
  const late = Symbol("late");
  const r = await withDeadline(
    guarded.then(() => null),
    ms,
    late,
  );
  // 上限を過ぎた。待つのはやめるが、黙らない（打ち切る環境なら、ここで失われ得る）。
  if (r === late) console.warn(`[after-response] ${label}: still running after ${ms}ms`);
  return "awaited";
}
