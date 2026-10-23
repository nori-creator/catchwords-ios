/**
 * サーバーから来たエラーを、**画面の言語で**出す。
 *
 * ## なぜ要るか
 * 生のメッセージをそのまま出すと `fetch failed` や `PGRST116` が画面に
 * 並ぶ。読み手には何も分からないし、対処もできない。
 *
 * かといって全部まとめて「失敗しました」に潰すのも間違いだった。
 * こちらが自分で投げている「1日の利用上限(300回)に達しました」は、
 * **理由も対処も分かる**メッセージで、これを潰すとユーザーは
 * 二度と直らないものを押し続けることになる(独立監査の指摘)。
 *
 * ## 言語を混ぜない（オーナー指示 2026-09-23 の3回目）
 * サーバーのメッセージは日本語で書いてある。英語・台湾華語で使っている人に
 * そのまま出すと、画面に日本語が混ざる。
 *  ・日本語で使っている人 … こちらが書いた日本語の文はそのまま出す
 *  ・それ以外 … 知っている文（上限・権限・見つからない・もう一度）は
 *    その言語の文に置き換え、知らない文は `fallback`（その言語の汎用の文）
 */
import { useCallback } from "react";
import { useT, useUiLang, type UiLang } from "./i18n";
import { noticeAiConsentError } from "./ai-consent-client";

/** サーバーの日本語の文 → 辞書の鍵。上から順に見る。 */
const KNOWN: Array<[RegExp, string]> = [
  [/利用上限/, "err.dailyCap"],
  [/Pro 限定/, "err.proOnly"],
  [/権限がありません|編集できません|削除できません|管理者のみ/, "err.forbidden"],
  [/見つかりません/, "err.notFound"],
  [/もう一度|形が整いませんでした|返りませんでした|生成できませんでした/, "err.tryAgain"],
];

/**
 * サーバが**印**で投げる理由 → 辞書の鍵。
 *
 * `NOT_TARGET_LANGUAGE` は保存の関所（`upsertWord`）が、学習言語の字でない
 * 見出し語を止めたときの印（オーナー報告 2026-10-02「英語の図鑑にノート」）。
 * 印は英字なので、下の「人に向けた文か」の見分けに掛けると汎用の
 * 「保存に失敗しました」に潰れる — **なぜ入らないのかが分からない**。
 */
/*
 * `AI_DAILY_CAP` / `AI_GLOBAL_CAP` / `AI_USAGE_CHECK_FAILED` は AI の上限（`ai-cap.ts`）。
 * 文の頭に印を付けて投げるので、日本語の人にも辞書の文で出す（2026-10-03。前は日本語の
 * 文がそのまま出て、英語・繁體中文の人には文の当て推量に頼っていた）。
 */
const KNOWN_CODES: Array<[string, string]> = [
  ["NOT_TARGET_LANGUAGE", "err.notTargetLanguage"],
  ["AI_DAILY_CAP", "err.dailyCap"],
  ["AI_GLOBAL_CAP", "err.aiBusy"],
  ["AI_USAGE_CHECK_FAILED", "err.usageCheck"],
  // 外部の AI へ送る同意が無い（`ai-consent.ts`）。文を出し、確認の画面も開く。
  ["AI_CONSENT_REQUIRED", "err.aiConsent"],
  ["AI_CONSENT_CHECK_FAILED", "err.usageCheck"],
  // 購入口・定期購入の管理（`stripe-catalog.ts` の `BILLING_ERRORS`）。
  ["BILLING_PORTAL_NOT_CONFIGURED", "pro.err.portalNotConfigured"],
  ["BILLING_NO_CUSTOMER", "pro.err.noCustomer"],
  ["BILLING_LEGAL_NOT_READY", "pro.err.legalNotReady"],
  ["BILLING_NOT_CONFIGURED", "pro.err.notConfigured"],
  ["BILLING_DISABLED", "pro.err.disabled"],
  ["BILLING_TERMS_CHANGED", "pro.err.termsChanged"],
];

export function readableError(
  e: unknown,
  fallback: string,
  lang: UiLang = "ja",
  t?: (key: string) => string,
): string {
  const msg = e instanceof Error ? e.message : "";
  if (!msg) return fallback;
  // 同意が無くて断られた時は、確認の画面を開く（設定から探させない）。
  noticeAiConsentError(e);
  // **サーバが印で投げた理由**（文ではない）。どの表示言語でもその言語の文に直す。
  if (t) {
    for (const [code, key] of KNOWN_CODES) if (msg.includes(code)) return t(key);
  }
  // ひらがな・カタカナ・漢字のいずれかを含む = 人に向けて書かれた文。
  const human = /[぀-ヿ一-龯]/.test(msg);
  if (!human) return fallback;
  if (lang === "ja") return msg;
  if (t) {
    for (const [re, key] of KNOWN) if (re.test(msg)) return t(key);
  }
  return fallback;
}

/** 画面の中で使う形（言語と辞書を自分で持つ）。 */
export function useReadableError(): (e: unknown, fallback: string) => string {
  const t = useT();
  const lang = useUiLang();
  return useCallback((e, fallback) => readableError(e, fallback, lang, t), [lang, t]);
}

/**
 * **ログイン・新規登録・パスワード再設定の失敗を、画面の言語で出す。**
 *
 * Supabase の認証エラーは**英語の文**（`Invalid login credentials` など）で返ってくる。
 * 前はそれを `toast.error(err.message)` でそのまま出していたので、日本語・台湾華語の
 * 画面でも英語が出ていた（2026-09-30 の全体点検）。エラーの**コード**（`invalid_credentials`）
 * から言語の文に直し、知らないものは `fallback`（その場面の汎用の文）にする。
 * 生の英語は絶対に出さない（内部の理由が漏れることもある）。
 */
const AUTH_CODE_KEY: Record<string, string> = {
  invalid_credentials: "autherr.invalidCredentials",
  email_not_confirmed: "autherr.emailNotConfirmed",
  user_already_exists: "autherr.alreadyRegistered",
  email_exists: "autherr.alreadyRegistered",
  weak_password: "autherr.weakPassword",
  same_password: "autherr.samePassword",
  over_request_rate_limit: "autherr.rateLimit",
  over_email_send_rate_limit: "autherr.rateLimit",
  email_address_invalid: "autherr.emailInvalid",
  email_address_not_authorized: "autherr.emailInvalid",
  validation_failed: "autherr.emailInvalid",
  signup_disabled: "autherr.signupDisabled",
  otp_expired: "autherr.linkExpired",
  flow_state_expired: "autherr.linkExpired",
  session_expired: "autherr.linkExpired",
  request_timeout: "autherr.network",
};
/** コードが付いていない古い応答のための、文言からの見分け。 */
const AUTH_MESSAGE_KEY: Array<[RegExp, string]> = [
  [/invalid login credentials/i, "autherr.invalidCredentials"],
  [/email not confirmed/i, "autherr.emailNotConfirmed"],
  [/already (been )?registered|already exists/i, "autherr.alreadyRegistered"],
  [/password should be at least|weak password|password.*characters/i, "autherr.weakPassword"],
  [/same as the old|different from the old/i, "autherr.samePassword"],
  [/rate limit|too many requests|after \d+ seconds/i, "autherr.rateLimit"],
  [/invalid.*email|unable to validate email/i, "autherr.emailInvalid"],
  [/expired|invalid.*(token|link)/i, "autherr.linkExpired"],
  [/failed to fetch|network|load failed|fetch failed/i, "autherr.network"],
];

export function authErrorText(e: unknown, fallback: string, t: (key: string) => string): string {
  const code =
    typeof e === "object" && e !== null && "code" in e
      ? String((e as { code?: unknown }).code ?? "")
      : "";
  if (code && AUTH_CODE_KEY[code]) return t(AUTH_CODE_KEY[code]);
  const msg = e instanceof Error ? e.message : typeof e === "string" ? e : "";
  for (const [re, key] of AUTH_MESSAGE_KEY) if (re.test(msg)) return t(key);
  return fallback;
}
