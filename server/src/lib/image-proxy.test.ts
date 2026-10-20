import { describe, expect, it, vi } from "vitest";
import fs from "node:fs";
import path from "node:path";
import {
  IMAGE_FETCH_USER_AGENT,
  MAX_IMAGE_REDIRECTS,
  assertAllowedImageUrl,
  fetchAllowedImage,
} from "./image-proxy";
import { MAX_PROXY_IMAGE_BYTES, TOO_LARGE_MESSAGE } from "./byte-cap";

/**
 * 文字で足した語の見出しが「画像をネットから探しています…」のまま止まり、
 * 候補を押すと「画像の変更に失敗しました。」だけが出た（オーナー報告 2026-10-07）。
 * ここで守るのは「**名乗って取りに行き、転送も許した置き場の中なら辿る**」と
 * 「**SSRF 除けと大きさの上限は崩さない**」の両方。
 */

const COMMONS = "https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/X.jpg/960px-X.jpg";

const image = (body = "abc", headers: Record<string, string> = {}) =>
  new Response(body, { status: 200, headers: { "content-type": "image/jpeg", ...headers } });
const redirect = (location: string | null, status = 302) =>
  new Response(null, { status, headers: location ? { location } : {} });

describe("fetchAllowedImage", () => {
  it("**名乗って**取りに行く(コモンズは名乗らない相手を 403 で弾く)", async () => {
    const f = vi.fn(async (_url: string, _init: RequestInit) => image());
    const out = await fetchAllowedImage(COMMONS, f);
    expect(out.dataUrl).toBe(`data:image/jpeg;base64,${Buffer.from("abc").toString("base64")}`);
    const init = f.mock.calls[0][1];
    expect((init.headers as Record<string, string>)["User-Agent"]).toBe(IMAGE_FETCH_USER_AGENT);
    expect(IMAGE_FETCH_USER_AGENT).toMatch(/^CatchWords\/\S+ \(https:\/\//);
    // 転送は自動で辿らせない(行き先を自分で確かめるため)。
    expect(init.redirect).toBe("manual");
  });

  it("断られたら**状態の番号を添えて**投げる(画面に理由を出す)", async () => {
    const f = vi.fn(async () => new Response("no", { status: 403 }));
    await expect(fetchAllowedImage(COMMONS, f)).rejects.toThrow("（403）");
  });

  it("許した置き場の中の転送は辿る(相対の行き先も)", async () => {
    const f = vi
      .fn()
      .mockResolvedValueOnce(redirect("https://images.unsplash.com/photo-1"))
      .mockResolvedValueOnce(redirect("/photo-2", 301))
      .mockResolvedValueOnce(image());
    await expect(fetchAllowedImage(COMMONS, f)).resolves.toHaveProperty("dataUrl");
    expect(f.mock.calls.map((c) => c[0])).toEqual([
      COMMONS,
      "https://images.unsplash.com/photo-1",
      "https://images.unsplash.com/photo-2",
    ]);
  });

  it("**許していない所への転送は取りに行かない**(SSRF 除け)", async () => {
    for (const to of [
      "http://upload.wikimedia.org/x.jpg",
      "https://169.254.169.254/latest/meta-data",
      "https://evil.example/x.jpg",
    ]) {
      const f = vi.fn().mockResolvedValueOnce(redirect(to)).mockResolvedValue(image());
      await expect(fetchAllowedImage(COMMONS, f)).rejects.toThrow();
      expect(f).toHaveBeenCalledTimes(1);
    }
  });

  it("転送が続きすぎたら止める・行き先の無い転送は失敗", async () => {
    const loop = vi.fn(async () => redirect(COMMONS));
    await expect(fetchAllowedImage(COMMONS, loop)).rejects.toThrow("転送が多すぎます");
    expect(loop).toHaveBeenCalledTimes(MAX_IMAGE_REDIRECTS + 1);
    const empty = vi.fn(async () => redirect(null));
    await expect(fetchAllowedImage(COMMONS, empty)).rejects.toThrow("（302）");
  });

  it("画像でない物・大きすぎる物は断る", async () => {
    const html = vi.fn(
      async () => new Response("<html>", { headers: { "content-type": "text/html" } }),
    );
    await expect(fetchAllowedImage(COMMONS, html)).rejects.toThrow("not a permitted image type");
    const big = vi.fn(async () =>
      image("x", { "content-length": String(MAX_PROXY_IMAGE_BYTES + 1) }),
    );
    await expect(fetchAllowedImage(COMMONS, big)).rejects.toThrow(TOO_LARGE_MESSAGE);
  });
});

describe("assertAllowedImageUrl", () => {
  it("https の許した置き場だけ通す", () => {
    expect(assertAllowedImageUrl(COMMONS).hostname).toBe("upload.wikimedia.org");
    expect(() => assertAllowedImageUrl("http://images.unsplash.com/x")).toThrow();
    expect(() => assertAllowedImageUrl("https://localhost/x")).toThrow();
    expect(() => assertAllowedImageUrl("not a url")).toThrow();
  });
});
