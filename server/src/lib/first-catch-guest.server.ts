import { createHmac, randomUUID } from "node:crypto";
import { FirstCatchAIInput } from "./first-catch-ai-schema";
import {
  pruneBudgetRows,
  reserveBudgetSlot,
  shouldPruneAfter,
  type BudgetDb,
} from "./budget-slots";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/integrations/supabase/types";
import type { FirstCatchRun } from "./first-catch-ai.server";
import type { AiTarget } from "./ai-provider.server";

/** A narrowly scoped public trial, not an authenticated-user impersonation.
 * Atomic unique-key reservations reuse the existing server-writable app_config
 * table, so enabling Supabase anonymous accounts or a schema migration is not
 * required. Values contain no photos, words, IPs, tokens or user identifiers.
 * Global ceiling remains effective even if a proxy forwards an untrusted IP.
 * Returns the reserved slot number (0 = the first of that prefix).
 */
export async function reserveGuestSlot(
  db: SupabaseClient<Database>,
  prefix: string,
  limit: number,
  limitCode: "FIRST_CATCH_LIMIT" | "FIRST_CATCH_TRIAL_FULL" = "FIRST_CATCH_LIMIT",
): Promise<number> {
  return reserveBudgetSlot(db as unknown as BudgetDb, prefix, limit, {
    unavailable: "FIRST_CATCH_AI_UNAVAILABLE",
    limit: limitCode,
  });
}

/** ゲストの枠の鍵の頭（日ごと・IP ごと・全体）。古い日の行はこの頭で消す。 */
export const GUEST_BUDGET_ROOT = "first-catch-budget:";
/**
 * 1回のチュートリアルで AI は最低3回(候補・カード・解説)、撮り直しや再試行で
 * もっと呼ぶ。12回/日では数回の体験(開発者の確認も同じ枠を使う)で尽きて、
 * 新規ユーザーが**原因の出ない失敗**になっていた。
 *
 * **1つの回線は 15 回/日**（監査 2026-10-03。前は 30）。1000 回/日の全体の枠を
 * 少ない回線で使い切れないように。15 回でもチュートリアルは撮り直しを含めて
 * 3〜4 回通せる。ここで断られた人は、画面がその端末の匿名アカウントの道
 * （本人の枠・匿名の人の子の枠、`ai-cap.ts`）に切り替えるので、体験は止まらない。
 */
export const GUEST_IP_LIMIT_PER_DAY = 15;
export const GUEST_GLOBAL_LIMIT_PER_DAY = 1000;

/**
 * 枠を数える単位のアドレス（監査 2026-10-03）。
 *
 * **IPv6 は /64 でまとめる。** 1つの回線（家・携帯）には普通 /64 が丸ごと配られるので、
 * 1つずつ数えると、アドレスを変えるだけで 30 回/日の枠を何度でも取り直せる。
 * IPv4（`::ffff:1.2.3.4` の形も）はそのまま。読めない値はそのまま（小文字）で数える。
 */
export function guestIpBucket(ip: string): string {
  let v = ip.trim();
  const bracket = /^\[([^\]]+)\](?::\d+)?$/.exec(v);
  if (bracket) v = bracket[1];
  v = v.split("%")[0];
  if (/^\d{1,3}(\.\d{1,3}){3}(:\d+)?$/.test(v)) return v.split(":")[0];
  if (!v.includes(":")) return v.toLowerCase();
  const mapped = /^::ffff:(\d{1,3}(?:\.\d{1,3}){3})$/i.exec(v);
  if (mapped) return mapped[1];
  const groups = expandIpv6(v);
  if (!groups) return v.toLowerCase();
  return `${groups.slice(0, 4).join(":")}::/64`;
}

/** IPv6 を8つの16進の組に広げる（`::` と末尾の IPv4 表記も読む）。読めなければ null。 */
function expandIpv6(raw: string): string[] | null {
  let s = raw.toLowerCase();
  const v4 = /(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(s);
  if (v4) {
    const b = v4.slice(1).map(Number);
    if (b.some((n) => n > 255)) return null;
    s =
      s.slice(0, s.length - v4[0].length) +
      `${((b[0] << 8) | b[1]).toString(16)}:${((b[2] << 8) | b[3]).toString(16)}`;
  }
  const halves = s.split("::");
  if (halves.length > 2) return null;
  const head = halves[0] ? halves[0].split(":") : [];
  const tail = halves.length === 2 && halves[1] ? halves[1].split(":") : [];
  const missing = 8 - head.length - tail.length;
  if (halves.length === 1 ? missing !== 0 : missing < 0) return null;
  const all = [...head, ...Array<string>(halves.length === 2 ? missing : 0).fill("0"), ...tail];
  if (all.length !== 8 || all.some((h) => !/^[0-9a-f]{1,4}$/.test(h))) return null;
  return all.map((h) => parseInt(h, 16).toString(16));
}

/** 呼び出し元のアドレス。取れない環境では null(全員が1つの枠を共有しないため)。 */
export function guestClientIp(headers: Headers): string | null {
  const candidates = [
    headers.get("cf-connecting-ip"),
    headers.get("x-nf-client-connection-ip"),
    headers.get("x-real-ip"),
    headers.get("x-forwarded-for")?.split(",")[0],
  ];
  for (const value of candidates) {
    const ip = value?.trim();
    if (ip) return ip;
  }
  return null;
}

/**
 * 同じ場所から出した呼び出しだけを通す。中継で URL の場所が変わる環境も許す。
 *
 * **`Origin` が無い呼び出しは断る**（監査 2026-10-03）。ブラウザは POST に必ず
 * `Origin` を付ける（同じ場所からでも）。付いていないのは、ブラウザの外から直に
 * 叩いている呼び出し — ゲストの AI の枠をそこから使わせない。
 */
export function isSameOriginRequest(request: Request): boolean {
  const origin = request.headers.get("origin");
  if (!origin) return false;
  if (origin === new URL(request.url).origin) return true;
  const host = request.headers.get("x-forwarded-host") ?? request.headers.get("host");
  return !!host && (origin === `https://${host}` || origin === `http://${host}`);
}

export async function executeGuestFirstCatch(raw: unknown, request: Request) {
  const data = FirstCatchAIInput.parse(raw);
  // 外部の AI へ送る前の同意（登録前なので、この端末での同意の版を確かめる）。
  const { assertAttestedConsent } = await import("./ai-consent");
  assertAttestedConsent(data.aiConsentVersion);
  const reserved: string[] = [];
  let db: SupabaseClient<Database> | null = null;
  let chain: Promise<AiTarget[]> | undefined;
  try {
    if (!isSameOriginRequest(request)) throw new Error("FIRST_CATCH_ORIGIN");
    const secret = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (!secret) throw new Error("FIRST_CATCH_AI_UNAVAILABLE");
    // どの AI に頼むか（設定の読み出し）は、枠の確保と**並べて**引く（実物確認 2026-10-03:
    // シャッターから候補まで 4.5〜42 秒。AI の前の往復を1つずつ待たない）。
    chain = import("./first-catch-ai.server").then((m) => m.prefetchFirstCatchChain(data.action));
    chain.catch(() => {});
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    db = supabaseAdmin;
    const day = new Date().toISOString().slice(0, 10);
    const ip = guestClientIp(request.headers);
    const ipPrefix = ip
      ? `${GUEST_BUDGET_ROOT}${day}:ip:${createHmac("sha256", secret)
          .update(`${day}:${guestIpBucket(ip)}`)
          .digest("hex")
          .slice(0, 32)}:`
      : null;
    const globalPrefix = `${GUEST_BUDGET_ROOT}${day}:global:`;
    // 回線の枠と全体の枠は**同時に**取る（前は1つずつで、往復が4回続いていた）。片方が
    // 断られたら、取れた方は下の catch で返す。全体の枠が尽きた時は別のコード（画面は匿名の
    // 道に切り替え、そこも尽きていれば「今日の体験の受け付けはいっぱい」と出す）。
    const [ipSlot, globalSlot] = await Promise.allSettled([
      ipPrefix
        ? reserveGuestSlot(supabaseAdmin, ipPrefix, GUEST_IP_LIMIT_PER_DAY)
        : Promise.resolve(null),
      reserveGuestSlot(
        supabaseAdmin,
        globalPrefix,
        GUEST_GLOBAL_LIMIT_PER_DAY,
        "FIRST_CATCH_TRIAL_FULL",
      ),
    ]);
    if (ipSlot.status === "fulfilled" && ipPrefix && ipSlot.value != null)
      reserved.push(`${ipPrefix}${ipSlot.value}`);
    if (globalSlot.status === "fulfilled") reserved.push(`${globalPrefix}${globalSlot.value}`);
    // 回線の枠の断りを先に伝える（前と同じ: 回線の上限 → FIRST_CATCH_LIMIT）。
    if (ipSlot.status === "rejected") throw ipSlot.reason;
    if (globalSlot.status === "rejected") throw globalSlot.reason;
    const slot = globalSlot.value;
    // 古い日の枠の行を、ときどき消す（`app_config` が日ごとに増え続けないように）。
    // 返事は待たせない（`runAfterResponse`）。
    if (shouldPruneAfter(slot)) {
      const admin = supabaseAdmin as unknown as BudgetDb;
      const { runAfterResponse } = await import("./after-response");
      await runAfterResponse("first-catch: prune guest budget", async () => {
        await pruneBudgetRows(admin, GUEST_BUDGET_ROOT);
        // 結果の記録（下の recordGuestRun）は失敗率を見るので長めに残す。
        await pruneBudgetRows(admin, GUEST_RUN_ROOT, new Date(), GUEST_RUN_KEEP_DAYS);
      });
    }
  } catch (e) {
    // 原因は画面にコードで出す。ここにも残す(写真・単語・IPは含めない)。
    console.error("[first-catch] guest gate refused:", e instanceof Error ? e.message : "unknown");
    // 回線の枠は取れたが全体の枠で断られた時は、回線の枠を返す（AI は呼んでいない）。
    if (db && reserved.length) await releaseGuestSlots(db, reserved);
    throw e;
  }
  const { runFirstCatchAI, failedRun } = await import("./first-catch-ai.server");
  try {
    const { value, run } = await runFirstCatchAI(data, { chain });
    if (db) await recordGuestRun(db, run);
    return value;
  } catch (e) {
    const run = failedRun(data.action, e);
    if (run && db) {
      // 返事を1つも受け取れなかった回は枠を返す（「もう一度試す」で2回分に数えない）。
      if (!run.chargeable) run.refunded = await releaseGuestSlots(db, reserved);
      await recordGuestRun(db, run);
    }
    throw e;
  }
}

/** 予約した枠を返す。返せなくても利用者は止めない（枠が1つ少なく数えられるだけ）。 */
export async function releaseGuestSlots(
  db: SupabaseClient<Database>,
  keys: string[],
): Promise<boolean> {
  if (!keys.length) return false;
  try {
    const result = await db.from("app_config").delete().in("key", keys);
    return !result.error;
  } catch {
    return false;
  }
}

/** 未登録の人の結果の記録（失敗率と待ち時間）。予約の掃除のついでに古い物を消す。 */
export const GUEST_RUN_ROOT = "first-catch-run:";
export const GUEST_RUN_KEEP_DAYS = 14;

/**
 * 未登録の人の結果を残す（`ai_runs` は本人の id が要るので使えない。予約と同じ app_config に、
 * 日付ごとの鍵で1行）。中身は機能・成否・待ち時間・試した AI の名前だけ — 写真・語・IP は無し。
 * 失敗率は `first-catch-run:<日付>:fail:%` と `…:ok:%` の行数で出る。
 */
async function recordGuestRun(db: SupabaseClient<Database>, run: FirstCatchRun) {
  try {
    const day = new Date().toISOString().slice(0, 10);
    const { runMeta } = await import("./first-catch-ai.server");
    const result = await db.from("app_config").insert({
      key: `${GUEST_RUN_ROOT}${day}:${run.ok ? "ok" : "fail"}:${randomUUID()}`,
      value: runMeta(run),
    });
    if (result.error) console.warn("[first-catch] guest run log failed:", result.error.message);
  } catch (e) {
    console.warn("[first-catch] guest run log failed:", e instanceof Error ? e.message : "");
  }
}
