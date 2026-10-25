/**
 * **外部の AI へ送る前の同意**（App Store Review Guideline 5.1.2(i) と同じ扱い・
 * 個人情報保護法 28 条の外国にある第三者への提供。2026-10-03）。
 *
 * 写真・調べた語・入力した文（日記・報告のメモ）を外部の AI（Google など）へ送る関数は、
 * その人が**はっきり同意した後**でしか動かない。iOS 版の `AIConsent.swift` と同じ版・同じ
 * 関数の一覧を持つ（どちらかを変えたら両方を直す）。
 *
 * ここは**表と純粋な関数だけ**（画面とサーバの両方から読む）。DB を読むのは
 * `ai-consent.server.ts`、画面の確認は `components/AiConsentDialog.tsx`。
 */

/**
 * 同意の版。**送る物・送り先を変えたら上げる**（古い版の同意は聞き直す）。
 * iOS の `AIConsent.currentVersion` と同じ数にする。
 */
export const AI_CONSENT_VERSION = 1;

/** プライバシーポリシーの「外部の事業者」の節（第4条。第5条が続く）。 */
export const PRIVACY_AI_SECTION_URL = "/privacy#external-services";

/** 同意が無くて断った時の印（`errors.ts` が画面の言語の文に直し、確認の画面を開く）。 */
export const AI_CONSENT_REQUIRED = "AI_CONSENT_REQUIRED";
/** 同意を確かめられなかった時の印（DB が読めない。少し待てば通る）。 */
export const AI_CONSENT_CHECK_FAILED = "AI_CONSENT_CHECK_FAILED";

/**
 * 同意が要るサーバ関数（写真・語・文を外部の AI に渡す物）。
 * 先頭の9つは iOS の `AIConsent.aiFunctions` と同じ。残りは Web だけで使う同じ種類の物。
 * 書いた物を読むだけの関数（意味・解説の読み出し）・保存・復習の採点・発音は入れない。
 */
export const AI_CONSENT_FUNCTIONS = [
  "suggestWords",
  "detectScan",
  "rankScanCandidates",
  "suggestWordCandidates",
  "generateCard",
  "regenerateCardSection",
  "reportAndFixSection",
  "getJournalPrompts",
  "correctMyJournal",
  "checkDiarySentence",
  // Web（と iOS の native-fn）で同じ種類の物
  "generatePhraseCard",
  "detectParts",
  "extractWordbook",
  "firstCatchAI",
  "firstCatchMemberAI",
  "generateProWordImage",
  "reclassifyOtherWords",
] as const;

/**
 * iOS が「同意の仕組みを持つ版」であることを示す見出し（`/api/native-fn`）。
 * 値は iOS が持つ同意の版（数字）。`AI-Consent-Version` を正とし、頼まれた綴りの
 * `ai_consent_version` も受ける（下線の見出しは途中の機械に落とされることがあるので非推奨）。
 */
export const AI_CONSENT_HEADERS = ["ai-consent-version", "ai_consent_version"] as const;

/** iOS（`/api/native-fn`）でも必ず確かめるようにする環境変数（締め切り後に立てる）。 */
export const AI_CONSENT_ENFORCE_NATIVE_ENV = "AI_CONSENT_ENFORCE_NATIVE";

export function isTruthyEnv(v: string | undefined | null): boolean {
  return !!v && /^(1|true|yes|on)$/i.test(v.trim());
}

/**
 * この呼び出しで同意を確かめるか。
 *
 * - Web の画面から（`/_serverFn/...`）… いつも確かめる。
 * - iOS（`/api/native-fn`、Supabase の Edge Function では `/native-fn`）… **同意の見出しが付いている**か、**`AI_CONSENT_ENFORCE_NATIVE`
 *   が立っている**時だけ。同意をサーバに送らない古い iOS を壊さないため（古い iOS も
 *   端末の中で同意を確かめてから送っている — `NativeAPI.call`）。
 */
export function consentModeFor(
  request: { url: string; headers: { get(name: string): string | null } } | null | undefined,
  env: Record<string, string | undefined>,
): "enforce" | "skip" {
  if (!request) return "enforce";
  let path = "";
  try {
    path = new URL(request.url).pathname;
  } catch {
    return "enforce";
  }
  if (!/\/(?:api\/)?native-fn\/?$/.test(path)) return "enforce";
  if (AI_CONSENT_HEADERS.some((h) => request.headers.get(h) !== null)) return "enforce";
  return isTruthyEnv(env[AI_CONSENT_ENFORCE_NATIVE_ENV]) ? "enforce" : "skip";
}

/** `ai_consents` の1行（読む所だけ）。 */
export type AiConsentRow = {
  version: number;
  agreed_at: string;
  revoked_at: string | null;
};

/** 今の版に同意していて、取り消していない行があるか。 */
export function hasCurrentConsent(rows: AiConsentRow[] | null | undefined): boolean {
  return (rows ?? []).some((r) => r.revoked_at === null && r.version >= AI_CONSENT_VERSION);
}

/** 画面・iOS に返す今の状態。 */
export type AiConsentStatus = {
  /** 今の版に同意していて、取り消していない。 */
  agreed: boolean;
  /** 最後に同意した版（無ければ null）。 */
  version: number | null;
  agreedAt: string | null;
  /** 最後に取り消した時刻（同意中なら null）。 */
  revokedAt: string | null;
  /** サーバが求める版（`AI_CONSENT_VERSION`）。 */
  currentVersion: number;
};

export function consentStatusFrom(rows: AiConsentRow[] | null | undefined): AiConsentStatus {
  const sorted = [...(rows ?? [])].sort((a, b) => b.agreed_at.localeCompare(a.agreed_at));
  const latest = sorted[0];
  return {
    agreed: hasCurrentConsent(sorted),
    version: latest?.version ?? null,
    agreedAt: latest?.agreed_at ?? null,
    revokedAt: latest?.revoked_at ?? null,
    currentVersion: AI_CONSENT_VERSION,
  };
}

/** 失敗が「同意が無い」か（画面で確認を開くため）。 */
export function isAiConsentError(e: unknown): boolean {
  return e instanceof Error && e.message.includes(AI_CONSENT_REQUIRED);
}

/**
 * **登録前（ゲスト・端末だけの匿名アカウント）の同意。** サーバに記録する相手が居ないので、
 * 画面が「この端末で今の版に同意した」と送ってきた版（`aiConsentVersion`）を確かめる。
 * 登録した後は、アカウントの確認（`AiConsentAccountGate`）でもう一度聞いて記録する。
 */
export function assertAttestedConsent(version: number | null | undefined): void {
  if (typeof version === "number" && version >= AI_CONSENT_VERSION) return;
  throw new Error(
    `${AI_CONSENT_REQUIRED}: AI を使う機能は、AI へのデータ送信に同意すると使えます。`,
  );
}
