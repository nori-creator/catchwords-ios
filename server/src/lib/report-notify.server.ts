import { reportEmail, type ReportMailInput } from "./entry-report";
import { siteUrlFor } from "./site-url";

/**
 * **開発者に報告を知らせる**（2026-10-15）。
 *
 * この app にはメールを送る部品が無かった（Resend などの連携は未設定。`grep -ri resend src` が 0 件）。
 * 鍵が在れば Resend の HTTP API で送り、無ければ**送らずに**「送れない」を返す — その時は管理画面
 * （`/admin/metrics` のエラー報告）と iOS の開発者画面（`adminListEntryReports`）が知らせる場所になる。
 *
 * 環境変数:
 * - `RESEND_API_KEY` … 無ければ送らない（既定）
 * - `REPORT_NOTIFY_TO` … 送り先（既定: オーナーのメール）
 * - `REPORT_NOTIFY_FROM` … 送り元（既定: Resend の試験用 `onboarding@resend.dev`。自分のドメインを
 *   Resend に登録したらそのアドレスに）
 *
 * 試験は `fetch` を差し替えて呼ぶ（本物には送らない）。
 */

export const DEFAULT_REPORT_NOTIFY_TO = "nori0122hiroshima@gmail.com";
export const DEFAULT_REPORT_NOTIFY_FROM = "CatchWords <onboarding@resend.dev>";

export type NotifyResult = "sent" | "skipped" | "failed";

export function notifyConfig(env: Record<string, string | undefined> = process.env): {
  apiKey: string | null;
  to: string;
  from: string;
} {
  const apiKey = (env.RESEND_API_KEY ?? "").trim() || null;
  return {
    apiKey,
    to: (env.REPORT_NOTIFY_TO ?? "").trim() || DEFAULT_REPORT_NOTIFY_TO,
    from: (env.REPORT_NOTIFY_FROM ?? "").trim() || DEFAULT_REPORT_NOTIFY_FROM,
  };
}

export async function sendDeveloperEmail(
  mail: { subject: string; text: string },
  deps: {
    env?: Record<string, string | undefined>;
    fetchFn?: typeof fetch;
  } = {},
): Promise<NotifyResult> {
  const cfg = notifyConfig(deps.env ?? process.env);
  if (!cfg.apiKey) {
    console.info("[report] developer email skipped: RESEND_API_KEY is not set");
    return "skipped";
  }
  const fetchFn = deps.fetchFn ?? fetch;
  try {
    const res = await fetchFn("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${cfg.apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from: cfg.from,
        to: [cfg.to],
        subject: mail.subject,
        text: mail.text,
      }),
    });
    if (!res.ok) {
      console.warn(`[report] developer email failed: HTTP ${res.status}`);
      return "failed";
    }
    return "sent";
  } catch (e) {
    console.warn("[report] developer email failed:", (e as Error)?.message);
    return "failed";
  }
}

/** 報告1件を開発者に知らせる（メール。管理画面の URL を添える）。 */
export async function notifyDeveloperOfReport(
  r: Omit<ReportMailInput, "adminUrl">,
  deps: { env?: Record<string, string | undefined>; fetchFn?: typeof fetch } = {},
): Promise<NotifyResult> {
  const mail = reportEmail({ ...r, adminUrl: siteUrlFor("/admin/metrics") });
  return sendDeveloperEmail(mail, deps);
}
