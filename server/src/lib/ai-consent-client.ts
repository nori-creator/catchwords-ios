/**
 * 画面側の「外部の AI へ送る同意」（決まりは `ai-consent.ts`、確認の画面は
 * `components/AiConsentDialog.tsx`）。
 *
 * - **端末に覚える**（`cw:aiConsent:<だれ>`）。だれ = 登録した人はその id、登録前は `guest`。
 *   登録した人の正はサーバの記録（`ai_consents`）。端末の物は「同意しない」を選んだことを
 *   覚えて、開くたびに聞き直さないためと、画面を速く出すため。
 * - 登録前の同意（`guest`）は登録した人の同意にしない — 登録した後にもう一度聞いて、
 *   そこでサーバに記録する（`AiConsentAccountGate`）。
 * - 確認の画面は1つだけ（`AiConsentHost`、`__root.tsx`）。どこからでも `askAiConsent` で開き、
 *   選んだ答えを待てる。
 */
import { AI_CONSENT_VERSION, isAiConsentError } from "./ai-consent";

export type ConsentWho = "guest" | `user:${string}`;
export type LocalConsent = { status: "granted" | "declined"; version: number; at: number };

const key = (who: ConsentWho) => `cw:aiConsent:${who}`;

export function readLocalConsent(who: ConsentWho): LocalConsent | null {
  try {
    const raw = localStorage.getItem(key(who));
    if (!raw) return null;
    const v = JSON.parse(raw) as Partial<LocalConsent>;
    if ((v.status !== "granted" && v.status !== "declined") || typeof v.version !== "number")
      return null;
    return { status: v.status, version: v.version, at: Number(v.at) || 0 };
  } catch {
    return null;
  }
}

export function writeLocalConsent(who: ConsentWho, status: LocalConsent["status"]) {
  try {
    localStorage.setItem(
      key(who),
      JSON.stringify({ status, version: AI_CONSENT_VERSION, at: Date.now() }),
    );
  } catch {
    // 覚えられない端末では、次に AI を使う時にまた聞くだけ。
  }
}

export function clearLocalConsent(who: ConsentWho) {
  try {
    localStorage.removeItem(key(who));
  } catch {
    // 同上
  }
}

/** 端末で今の版に同意しているか。 */
export function localConsentGranted(who: ConsentWho): boolean {
  const v = readLocalConsent(who);
  return v?.status === "granted" && v.version >= AI_CONSENT_VERSION;
}

/** 端末で今の版について「同意しない」を選んだか（開くたびに聞き直さない）。 */
export function localConsentDeclined(who: ConsentWho): boolean {
  const v = readLocalConsent(who);
  return v?.status === "declined" && v.version >= AI_CONSENT_VERSION;
}

// ---- 確認の画面を開く口 ----------------------------------------------------------

export type ConsentAsk = {
  /** account = 登録した人（サーバに記録する） / guest = 登録前（端末だけ）。 */
  mode: "account" | "guest";
  resolve: (agreed: boolean) => void;
};

let host: ((ask: ConsentAsk) => void) | null = null;
let pending: Promise<boolean> | null = null;

/** `AiConsentHost` が自分を登録する。 */
export function setAiConsentHost(fn: ((ask: ConsentAsk) => void) | null) {
  host = fn;
}

/**
 * 確認の画面を開いて、答えを待つ（true = 同意した）。開いている間に別の所から呼ばれても、
 * 同じ答えを返す（画面を2枚重ねない）。画面が無い所（確認用ページ）では false。
 */
export function askAiConsent(mode: ConsentAsk["mode"]): Promise<boolean> {
  if (pending) return pending;
  const h = host;
  if (!h) return Promise.resolve(false);
  pending = new Promise<boolean>((resolve) => {
    h({
      mode,
      resolve: (agreed) => {
        pending = null;
        resolve(agreed);
      },
    });
  });
  return pending;
}

/** AI の関数が「同意が無い」で断った時に出る合図（`errors.ts` が出す）。 */
export const AI_CONSENT_EVENT = "cw:ai-consent-required";

/** 失敗が同意の無さなら、確認の画面を開く合図を出す。 */
export function noticeAiConsentError(e: unknown) {
  if (!isAiConsentError(e) || typeof window === "undefined") return;
  try {
    window.dispatchEvent(new Event(AI_CONSENT_EVENT));
  } catch {
    // 古いブラウザ: 文だけ出る（設定から同意できる）。
  }
}
