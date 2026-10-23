/**
 * **Higgsfield の API を呼ぶ所（サーバだけ）**。
 *
 * 公式の SDK（`@higgsfield/client`）は中で axios を使う。アプリのサーバ（Lovable の
 * 実行環境）に部品を増やさないため、ここでは**SDK と同じ手順を `fetch` で**行う:
 *
 *  1. `POST https://api.higgsfield.ai/<型番>` に入力をそのまま送る
 *     （見出し `Authorization: Key 鍵ID:鍵の秘密` と SDK と同じ `User-Agent`。
 *     向こうの不調（500番台）は SDK と同じく間を置いて送り直す）
 *  2. 返ってきた `request_id` で `GET /requests/<id>/status` を2秒ごとに見る
 *  3. `completed` なら `images[0].url` か `video.url`。`failed` / `nsfw` /
 *     `canceled` は**失敗として返す**（成功と言わない）
 *
 * 鍵の値は**記録にも返事にも出さない**。返すのは鍵を見つけた名前だけ。
 */
import {
  HIGGSFIELD_BASE_URL,
  explainHiggsfieldHttp,
  higgsfieldErrorDetail,
  higgsfieldHeaders,
  pickHiggsfieldResult,
  readHiggsfieldCredentials,
} from "./image-provider";

export type HiggsfieldOutcome =
  | { ok: true; url: string; requestId: string | null; ms: number }
  | { ok: false; reason: string; status?: string; httpStatus?: number; ms: number };

const DONE = new Set(["completed", "failed", "nsfw", "canceled", "cancelled"]);

/** 送り直す回数（SDK の既定は3回。画面で待たせすぎないよう少なめ）。 */
const POST_RETRIES = 2;

export async function runHiggsfield(
  model: string,
  input: Record<string, unknown>,
  opts: { timeoutMs?: number; pollMs?: number } = {},
): Promise<HiggsfieldOutcome> {
  const started = Date.now();
  const ms = () => Date.now() - started;
  const creds = readHiggsfieldCredentials(process.env);
  if (!creds) return { ok: false, reason: "Higgsfield の鍵が見つかりません", ms: ms() };
  const headers = higgsfieldHeaders(creds.credentials);
  const timeoutMs = opts.timeoutMs ?? 60_000;
  const pollMs = opts.pollMs ?? 2_000;
  try {
    const path = model.replace(/^\/+/, "");
    const url = `${HIGGSFIELD_BASE_URL}/${path}`;
    let res = await postOnce(url, headers, input);
    for (let i = 0; i < POST_RETRIES && res.status >= 500; i++) {
      await new Promise((ok) => setTimeout(ok, 1_000 * 2 ** i));
      res = await postOnce(url, headers, input);
    }
    if (!res.ok) {
      // 本文は JSON とは限らない（404 は道の無い所の HTML のこともある）ので、字で読む。
      const detail = higgsfieldErrorDetail(await res.text().catch(() => ""));
      console.warn("[higgsfield] request failed", { status: res.status, path, detail });
      return {
        ok: false,
        reason: explainHiggsfieldHttp(res.status, detail),
        httpStatus: res.status,
        ms: ms(),
      };
    }
    let r = pickHiggsfieldResult(await res.json());
    while (!DONE.has(r.status)) {
      if (!r.requestId)
        return { ok: false, reason: "受付番号が返りませんでした", status: r.status, ms: ms() };
      if (ms() > timeoutMs)
        return {
          ok: false,
          reason: `時間切れ（${Math.round(timeoutMs / 1000)}秒）`,
          status: r.status,
          ms: ms(),
        };
      await new Promise((ok) => setTimeout(ok, pollMs));
      const s = await fetch(`${HIGGSFIELD_BASE_URL}/requests/${r.requestId}/status`, {
        headers,
        signal: AbortSignal.timeout(15_000),
      });
      // 向こうの一時的な不調（500番台）は待って見直す（SDK と同じ）。
      if (s.status >= 500) continue;
      if (!s.ok)
        return {
          ok: false,
          reason: explainHiggsfieldHttp(
            s.status,
            higgsfieldErrorDetail(await s.text().catch(() => "")),
          ),
          httpStatus: s.status,
          ms: ms(),
        };
      const next = pickHiggsfieldResult(await s.json());
      r = { ...next, requestId: next.requestId ?? r.requestId };
    }
    if (r.status === "completed" && r.url)
      return { ok: true, url: r.url, requestId: r.requestId, ms: ms() };
    const why =
      r.status === "nsfw"
        ? "内容の審査で断られました（残高は戻ります）"
        : r.status === "failed"
          ? "生成に失敗しました（残高は戻ります）"
          : r.status === "completed"
            ? "完了しましたが URL がありませんでした"
            : "取り消されました";
    return { ok: false, reason: why, status: r.status, ms: ms() };
  } catch (e) {
    const name = e instanceof Error ? e.name : "";
    return {
      ok: false,
      reason:
        name === "TimeoutError"
          ? "Higgsfield が応答しませんでした"
          : "Higgsfield に繋がりませんでした",
      ms: ms(),
    };
  }
}

function postOnce(
  url: string,
  headers: Record<string, string>,
  input: Record<string, unknown>,
): Promise<Response> {
  return fetch(url, {
    method: "POST",
    headers,
    body: JSON.stringify(input),
    signal: AbortSignal.timeout(30_000),
  });
}

/** 鍵がどの名前で入っているか（値は返さない）。 */
export function higgsfieldCredentialSource(): string | null {
  return readHiggsfieldCredentials(process.env)?.source ?? null;
}
