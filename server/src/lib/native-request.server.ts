/**
 * **いまの要求が iOS 版から来たか**（`/api/native-fn` を通った要求か）。
 *
 * iOS は Web のサーバ関数を `/api/native-fn` からそのまま呼ぶ（`native-fn.ts`）ので、関数の中で
 * 「iOS からだけ違うことをする」時はここで見分ける（`ai-consent.functions.ts` と同じ見方）。
 * 読めない時（試験・サーバ関数の外）は Web 扱い。
 */
export async function isNativeRequest(): Promise<boolean> {
  try {
    const { getRequest } = await import("@tanstack/react-start/server");
    return /\/(?:api\/)?native-fn\/?$/.test(new URL(getRequest().url).pathname);
  } catch {
    return false;
  }
}
