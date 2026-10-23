/**
 * **外から取ってくる中身の大きさに上限を掛ける**（監査 2026-10-03 L6）。
 *
 * サーバが他所の画像を取りに行って data URL にして返す所（`fetchImageAsDataUrl`・
 * Higgsfield の絵）は、前は中身を全部読んでいた。とても大きい物を返されると、
 * サーバの記憶を食い潰し、返事も膨らむ。`content-length` で先に断り、流れてくる量も
 * 数えて超えたら止める（`content-length` は付かない・偽れることがある）。
 */

/** 画面に渡す画像の上限（写真1枚には十分）。 */
export const MAX_PROXY_IMAGE_BYTES = 10 * 1024 * 1024;

export const TOO_LARGE_MESSAGE = "Response is too large";

/** 返事の本文を最大 `max` バイトまで読む。超えたら止めて `TOO_LARGE_MESSAGE` を投げる。 */
export async function readCappedBytes(res: Response, max: number): Promise<Uint8Array> {
  const declared = Number(res.headers.get("content-length") ?? "");
  if (Number.isFinite(declared) && declared > max) {
    await res.body?.cancel().catch(() => undefined);
    throw new Error(TOO_LARGE_MESSAGE);
  }
  if (!res.body) return new Uint8Array(0);
  const reader = res.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > max) {
      await reader.cancel().catch(() => undefined);
      throw new Error(TOO_LARGE_MESSAGE);
    }
    chunks.push(value);
  }
  const out = new Uint8Array(total);
  let at = 0;
  for (const c of chunks) {
    out.set(c, at);
    at += c.byteLength;
  }
  return out;
}
