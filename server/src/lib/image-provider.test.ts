import { describe, expect, it } from "vitest";
import {
  DEFAULT_HIGGSFIELD_IMAGE_MODEL,
  DEFAULT_OPENROUTER_IMAGE_MODEL,
  HIGGSFIELD_USER_AGENT,
  explainHiggsfieldHttp,
  higgsfieldErrorDetail,
  higgsfieldHeaders,
  higgsfieldImageInput,
  pickHiggsfieldResult,
  pickOpenRouterImage,
  readHiggsfieldCredentials,
  readImageConfig,
  resolveImageConfig,
} from "./image-provider";

describe("readImageConfig", () => {
  it("何も設定しなければ今までどおり（Lovable・写真が先）", () => {
    expect(readImageConfig({})).toMatchObject({ provider: "lovable", mode: "photo-first" });
  });

  it("OpenRouter を選び、型番が無ければ既定の型番", () => {
    const c = readImageConfig({ IMAGE_PROVIDER: "OpenRouter" });
    expect(c.provider).toBe("openrouter");
    expect(c.model).toBe(DEFAULT_OPENROUTER_IMAGE_MODEL);
  });

  it("型番と順番を指定できる", () => {
    const c = readImageConfig({
      IMAGE_PROVIDER: "openrouter",
      IMAGE_MODEL: " google/some-image-model ",
      IMAGE_SEARCH_MODE: "ai-first",
    });
    expect(c).toEqual({
      provider: "openrouter",
      model: "google/some-image-model",
      mode: "ai-first",
    });
  });

  it("打ち間違いは既定に戻す（止めない）", () => {
    expect(readImageConfig({ IMAGE_PROVIDER: "openruoter" }).provider).toBe("lovable");
    expect(readImageConfig({ IMAGE_SEARCH_MODE: "ai" }).mode).toBe("photo-first");
  });

  it("off で作らない", () => {
    expect(readImageConfig({ IMAGE_PROVIDER: "off" }).provider).toBe("off");
  });

  it("Google と OpenAI は専用のモデルを使う", () => {
    expect(readImageConfig({ IMAGE_PROVIDER: "google" }).model).toBe("gemini-2.5-flash-image");
    expect(readImageConfig({ IMAGE_PROVIDER: "openai" }).model).toBe("gpt-image-1-mini");
  });

  it("開発者設定が環境の既定より優先され、別の提供元のモデルは引き継がない", () => {
    expect(
      resolveImageConfig(
        { IMAGE_PROVIDER: "openrouter", IMAGE_MODEL: "old/model" },
        { provider: "google" },
      ),
    ).toMatchObject({ provider: "google", model: "gemini-2.5-flash-image" });
    expect(resolveImageConfig({}, { provider: "openai", model: "gpt-image-1" })).toMatchObject({
      provider: "openai",
      model: "gpt-image-1",
    });
  });
});

describe("pickOpenRouterImage", () => {
  it("絵の専用の口の形", () => {
    expect(pickOpenRouterImage({ data: [{ b64_json: "AAA", media_type: "image/webp" }] })).toBe(
      "data:image/webp;base64,AAA",
    );
  });
  it("会話の口の形", () => {
    expect(
      pickOpenRouterImage({
        choices: [{ message: { images: [{ image_url: { url: "data:image/png;base64,BBB" } }] } }],
      }),
    ).toBe("data:image/png;base64,BBB");
  });
  it("何も無ければ null", () => {
    expect(pickOpenRouterImage({})).toBeNull();
    expect(pickOpenRouterImage(null)).toBeNull();
  });
});

describe("Higgsfield", () => {
  it("公式の名前 HF_CREDENTIALS（鍵ID:鍵の秘密）を拾い、名前だけを出所として返す", () => {
    const c = readHiggsfieldCredentials({ HF_CREDENTIALS: "id1:sec1" });
    expect(c).toEqual({ credentials: "id1:sec1", source: "HF_CREDENTIALS" });
  });

  it("ID と秘密を別々に入れても拾う（SDK の古い形・よくある名前）", () => {
    expect(readHiggsfieldCredentials({ HF_API_KEY: "a", HF_API_SECRET: "b" })?.credentials).toBe(
      "a:b",
    );
    expect(
      readHiggsfieldCredentials({ HIGGSFIELD_API_KEY: "a", HIGGSFIELD_API_SECRET: "b" })?.source,
    ).toBe("HIGGSFIELD_API_KEY + HIGGSFIELD_API_SECRET");
    // 1つの名前に丸ごと入れた場合も。
    expect(readHiggsfieldCredentials({ HIGGSFIELD_API_KEY: "a:b" })?.credentials).toBe("a:b");
  });

  it("コロンの無い半端な値は鍵と見なさない", () => {
    expect(readHiggsfieldCredentials({ HF_CREDENTIALS: "onlyid" })).toBeNull();
    expect(readHiggsfieldCredentials({})).toBeNull();
  });

  it("鍵があり IMAGE_PROVIDER が空なら Higgsfield を使う。明示の指定が勝つ", () => {
    expect(readImageConfig({ HF_CREDENTIALS: "a:b" })).toMatchObject({
      provider: "higgsfield",
      model: DEFAULT_HIGGSFIELD_IMAGE_MODEL,
    });
    expect(readImageConfig({ HF_CREDENTIALS: "a:b", IMAGE_PROVIDER: "lovable" }).provider).toBe(
      "lovable",
    );
    expect(
      readImageConfig({ HF_CREDENTIALS: "a:b", IMAGE_MODEL: "higgsfield-ai/soul/standard" }).model,
    ).toBe("higgsfield-ai/soul/standard");
  });

  it("状態の返事から絵・動画の URL を取り出す（完了以外は URL を信じない側が判断）", () => {
    expect(
      pickHiggsfieldResult({
        status: "completed",
        request_id: "r",
        images: [{ url: "https://x/i.png" }],
      }),
    ).toEqual({ status: "completed", requestId: "r", url: "https://x/i.png" });
    expect(
      pickHiggsfieldResult({ status: "completed", video: { url: "https://x/v.mp4" } }).url,
    ).toBe("https://x/v.mp4");
    expect(pickHiggsfieldResult({ status: "nsfw" })).toEqual({
      status: "nsfw",
      requestId: null,
      url: null,
    });
    expect(pickHiggsfieldResult(null).status).toBe("unknown");
  });

  /**
   * 「画像生成のテスト」が「型番が見つかりません（404）」だけを出し、本当の理由が
   * 読めなかった（オーナー報告 2026-10-07）。送る形を公式 SDK に合わせ、返事は添える。
   */
  it("見出しは SDK と同じ（Key 鍵ID:秘密 と User-Agent）", () => {
    expect(higgsfieldHeaders("id:sec")).toEqual({
      Authorization: "Key id:sec",
      "Content-Type": "application/json",
      Accept: "application/json",
      "User-Agent": HIGGSFIELD_USER_AGENT,
    });
    expect(HIGGSFIELD_USER_AGENT).toBe("higgsfield-server-js/2.0");
  });

  it("入力は包まずに送る。Seedream には大きさを添える", () => {
    expect(higgsfieldImageInput(DEFAULT_HIGGSFIELD_IMAGE_MODEL, "p")).toEqual({
      prompt: "p",
      aspect_ratio: "1:1",
      resolution: "2K",
    });
    expect(higgsfieldImageInput("higgsfield-ai/soul/standard", "p")).toEqual({
      prompt: "p",
      aspect_ratio: "1:1",
    });
  });

  it("**404 でも向こうの返事を理由に添える**", () => {
    const detail = higgsfieldErrorDetail(JSON.stringify({ detail: "Model not found: x" }));
    expect(detail).toBe("Model not found: x");
    const why = explainHiggsfieldHttp(404, detail);
    expect(why).toContain("（404）");
    expect(why).toContain("Model not found: x");
    // 返事が無ければ今までどおりの文だけ。
    expect(explainHiggsfieldHttp(404, "")).not.toContain(": ");
  });

  it("返事が JSON でなくても読める（HTML の札は落とし、長さを切る）", () => {
    expect(higgsfieldErrorDetail("<html><body><h1>Not Found</h1></body></html>")).toBe("Not Found");
    expect(higgsfieldErrorDetail(JSON.stringify({ detail: [{ msg: "bad" }] }))).toBe(
      '[{"msg":"bad"}]',
    );
    expect(higgsfieldErrorDetail("x".repeat(500))).toHaveLength(200);
    expect(higgsfieldErrorDetail("")).toBe("");
  });
});
