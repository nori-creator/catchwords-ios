import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  GEMINI_STATIC_FALLBACK,
  geminiKeywordTier,
  lazyGeminiModel,
  pickLatestGemini,
  resetGeminiLatestCache,
  resolveGeminiModelId,
  resolveLatestGemini,
  withGeminiKeywords,
} from "./gemini-latest.server";

const gen = ["generateContent", "countTokens"];
const m = (name: string, methods: string[] = gen) => ({
  name: `models/${name}`,
  supportedGenerationMethods: methods,
});

const LIST = [
  m("gemini-2.5-flash"),
  m("gemini-2.5-pro"),
  m("gemini-3.5-flash"),
  m("gemini-3.8-flash"),
  m("gemini-3.8-flash-lite"),
  m("gemini-3.9-pro"),
  m("gemini-3.10-pro"),
  m("gemini-9-flash-preview"),
  m("gemini-9.0-flash-exp"),
  m("gemini-9.0-flash-tts"),
  m("gemini-9.0-flash-image"),
  m("gemini-9.0-flash-live"),
  m("gemini-9.0-flash-001"),
  m("gemini-9.0-flash-preview-09-2026"),
  m("gemini-9.0-flash-lite-preview"),
  m("gemini-9.0-pro-exp-0801"),
  m("gemini-flash-latest"),
  m("gemini-9.9-flash", ["embedContent"]),
];

describe("pickLatestGemini", () => {
  it("段ごとに版がいちばん大きい安定版を選ぶ(3.8 > 3.5、3.10 > 3.9)", () => {
    expect(pickLatestGemini(LIST, "flash")).toBe("gemini-3.8-flash");
    expect(pickLatestGemini(LIST, "flash-lite")).toBe("gemini-3.8-flash-lite");
    expect(pickLatestGemini(LIST, "pro")).toBe("gemini-3.10-pro");
  });

  it("preview・exp・tts・image・live・日付や番号つき・generateContent 無しを外す", () => {
    expect(pickLatestGemini(LIST, "flash")).not.toMatch(/^gemini-9/);
  });

  it("major だけの版(gemini-4-flash)も major.minor と比べられる", () => {
    expect(pickLatestGemini([m("gemini-3.9-flash"), m("gemini-4-flash")], "flash")).toBe(
      "gemini-4-flash",
    );
    expect(pickLatestGemini([m("gemini-4-flash"), m("gemini-4.1-flash")], "flash")).toBe(
      "gemini-4.1-flash",
    );
  });

  it("該当が無い・壊れた入力なら null", () => {
    expect(pickLatestGemini([], "pro")).toBeNull();
    expect(pickLatestGemini([null, 1, { name: 3 }, { name: "models/gemini-3-pro" }], "pro")).toBe(
      null,
    );
  });
});

describe("合言葉", () => {
  it("latest-* と auto を段に読み替え、ほかは null", () => {
    expect(geminiKeywordTier("latest-flash")).toBe("flash");
    expect(geminiKeywordTier("latest-flash-lite")).toBe("flash-lite");
    expect(geminiKeywordTier("latest-pro")).toBe("pro");
    expect(geminiKeywordTier("auto")).toBe("flash");
    expect(geminiKeywordTier("gemini-2.5-flash")).toBeNull();
    expect(geminiKeywordTier("gemini-flash-latest")).toBeNull();
  });
});

function okFetch(models: unknown[]) {
  return vi.fn(async () => new Response(JSON.stringify({ models }), { status: 200 }));
}

describe("resolveLatestGemini", () => {
  beforeEach(() => resetGeminiLatestCache());
  afterEach(() => vi.restoreAllMocks());

  it("鍵を x-goog-api-key で送り、ページをたどる", async () => {
    const f = vi.fn(async (url: string) => {
      const page2 = new URL(url).searchParams.get("pageToken") === "p2";
      const body = page2
        ? { models: [m("gemini-4-flash")] }
        : { models: [m("gemini-3.8-flash")], nextPageToken: "p2" };
      return new Response(JSON.stringify(body), { status: 200 });
    });
    const id = await resolveLatestGemini("flash", { apiKey: "k", fetch: f as never });
    expect(id).toBe("gemini-4-flash");
    expect(f).toHaveBeenCalledTimes(2);
    const [url, init] = f.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toContain("pageSize=1000");
    expect((init.headers as Record<string, string>)["x-goog-api-key"]).toBe("k");
  });

  it("6 時間は覚え、過ぎたら読み直す。同時の問い合わせは 1 本にまとめる", async () => {
    let now = 0;
    const f = okFetch(LIST);
    const opts = { apiKey: "k", fetch: f as never, now: () => now };
    const [a, b, c] = await Promise.all([
      resolveLatestGemini("flash", opts),
      resolveLatestGemini("pro", opts),
      resolveLatestGemini("flash-lite", opts),
    ]);
    expect([a, b, c]).toEqual(["gemini-3.8-flash", "gemini-3.10-pro", "gemini-3.8-flash-lite"]);
    expect(f).toHaveBeenCalledTimes(1);
    now = 5 * 60 * 60 * 1000;
    await resolveLatestGemini("flash", opts);
    expect(f).toHaveBeenCalledTimes(1);
    now = 6 * 60 * 60 * 1000 + 1;
    await resolveLatestGemini("flash", opts);
    expect(f).toHaveBeenCalledTimes(2);
  });

  it("失敗は 5 分だけ覚えて null を返す(鍵は記録に出さない)", async () => {
    let now = 0;
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    const f = vi.fn(async () => new Response("no", { status: 500 }));
    const opts = { apiKey: "secret-key", fetch: f as never, now: () => now };
    expect(await resolveLatestGemini("flash", opts)).toBeNull();
    expect(await resolveLatestGemini("flash", opts)).toBeNull();
    expect(f).toHaveBeenCalledTimes(1);
    now = 5 * 60 * 1000 + 1;
    await resolveLatestGemini("flash", opts);
    expect(f).toHaveBeenCalledTimes(2);
    expect(JSON.stringify(warn.mock.calls)).not.toContain("secret-key");
  });

  it("通信が投げても null、合言葉は固定の安定版に落ちる", async () => {
    vi.spyOn(console, "warn").mockImplementation(() => {});
    const f = vi.fn(async () => {
      throw new Error("boom");
    });
    expect(await resolveGeminiModelId("latest-pro", { apiKey: "k", fetch: f as never })).toBe(
      GEMINI_STATIC_FALLBACK.pro,
    );
    expect(await resolveGeminiModelId("gemini-2.0-flash", { apiKey: "k" })).toBe(
      "gemini-2.0-flash",
    );
  });
});

type Fake = {
  specificationVersion: "v3";
  provider: string;
  modelId: string;
  supportedUrls: Record<string, RegExp[]>;
  doGenerate: ReturnType<typeof vi.fn>;
  doStream: ReturnType<typeof vi.fn>;
};

function fakeProvider(fail?: (id: string) => boolean) {
  const made: string[] = [];
  const make = (id: string): Fake => {
    made.push(id);
    return {
      specificationVersion: "v3",
      provider: "google.chat",
      modelId: id,
      supportedUrls: {},
      doGenerate: vi.fn(async () => {
        if (fail?.(id)) throw new Error("Not Found");
        return { id };
      }),
      doStream: vi.fn(async () => ({ stream: id })),
    };
  };
  const provider = Object.assign((id: string) => make(id), {
    specificationVersion: "v3",
    languageModel: (id: string) => make(id),
    chatModel: (id: string) => make(id),
    completionModel: (id: string) => make(id),
  });
  return { provider: provider as never, made };
}

describe("withGeminiKeywords", () => {
  beforeEach(() => resetGeminiLatestCache());

  it("合言葉は最初の呼び出しで版付きの ID に置き換えて渡す", async () => {
    const { provider, made } = fakeProvider();
    const gw = withGeminiKeywords(provider, { apiKey: "k", fetch: okFetch(LIST) as never });
    const model = gw("latest-flash");
    expect(model.modelId).toBe("latest-flash");
    expect(model.specificationVersion).toBe("v3");
    expect(model.provider).toBe("google.chat");
    const out = await model.doGenerate({} as never);
    expect(out).toEqual({ id: "gemini-3.8-flash" });
    expect(model.modelId).toBe("gemini-3.8-flash");
    expect(await model.doStream({} as never)).toEqual({ stream: "gemini-3.8-flash" });
    expect(made).toContain("gemini-3.8-flash");
    const lm = gw.languageModel("latest-pro");
    expect(await lm.doGenerate({} as never)).toEqual({ id: "gemini-3.10-pro" });
  });

  it("合言葉でない ID はそのまま本物を返す", () => {
    const { provider } = fakeProvider();
    const gw = withGeminiKeywords(provider, { apiKey: "k", fetch: okFetch(LIST) as never });
    const model = gw("gemini-2.5-flash") as unknown as Fake;
    expect(model.modelId).toBe("gemini-2.5-flash");
    expect(vi.isMockFunction(model.doGenerate)).toBe(true);
    expect(typeof gw.completionModel).toBe("function");
  });

  it("選んだ版が 404 なら固定の安定版で 1 回だけやり直す", async () => {
    vi.spyOn(console, "warn").mockImplementation(() => {});
    const { provider } = fakeProvider((id) => id === "gemini-3.8-flash-lite");
    const model = lazyGeminiModel(
      (id) => (provider as unknown as (id: string) => never)(id),
      "latest-flash-lite",
      "flash-lite",
      { apiKey: "k", fetch: okFetch(LIST) as never },
    );
    expect(await model.doGenerate({} as never)).toEqual({
      id: GEMINI_STATIC_FALLBACK["flash-lite"],
    });
  });
});
