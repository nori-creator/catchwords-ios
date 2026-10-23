/**
 * 意味を決める・絵を確かめる AI の守り（同意・回数の枠・覚え・失敗しても投げない）。
 * ネットにも AI にも出ない（どちらも差し替える）。
 */
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const h = vi.hoisted(() => ({
  consent: vi.fn(async () => undefined),
  cap: vi.fn(async () => undefined),
  generateText: vi.fn(),
  wordsRows: [] as Array<{ extras: unknown }>,
}));

vi.mock("./ai-consent.server", () => ({ assertAiConsent: h.consent }));
vi.mock("ai", () => ({ generateText: h.generateText }));
vi.mock("@/integrations/supabase/client.server", () => ({
  supabaseAdmin: {
    from: () => ({
      select: () => ({
        eq: () => ({ eq: () => ({ limit: async () => ({ data: h.wordsRows }) }) }),
      }),
    }),
  },
}));
vi.mock("./ai-provider.server", () => ({
  assertWithinDailyCap: h.cap,
  getAiAttemptChain: async () => [{ label: "test:vision", model: { id: "vision" } }],
  parseJsonFromAiText: (t: string) => JSON.parse(t),
}));

import { clearImageSenseCaches, imageSenseDepsFor } from "./image-sense.server";

const WORD = { headword: "蓮藕", meaning: "レンコン", language: "zh-TW" };
const SENSE = { query: "lotus root", avoid: ["flower"] };
const IMAGES = [
  { url: "https://images.unsplash.com/a", thumb: "https://images.unsplash.com/a-s" },
  { url: "https://images.unsplash.com/b", thumb: "https://images.unsplash.com/b-s" },
];

const fetchMock = vi.fn();
beforeEach(() => {
  clearImageSenseCaches();
  h.consent.mockReset().mockResolvedValue(undefined);
  h.cap.mockReset().mockResolvedValue(undefined);
  h.generateText.mockReset();
  h.wordsRows = [];
  fetchMock.mockReset();
  fetchMock.mockImplementation(
    async () =>
      new Response(new Uint8Array([1, 2, 3]), { headers: { "content-type": "image/jpeg" } }),
  );
  vi.stubGlobal("fetch", fetchMock);
  vi.spyOn(console, "warn").mockImplementation(() => undefined);
});
afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe("resolveSense", () => {
  it("同意 → 枠 → AI の順。答えは覚えて、2回目は AI を呼ばない", async () => {
    h.generateText.mockResolvedValue({
      text: JSON.stringify({ query: "lotus root", avoid: ["flower", "pond"], sense: "lotus root" }),
    });
    const d = imageSenseDepsFor("u1");
    expect(await d.resolveSense(WORD)).toEqual({
      query: "lotus root",
      avoid: ["flower", "pond"],
      sense: "lotus root",
    });
    expect(h.consent).toHaveBeenCalledWith("u1");
    expect(h.cap).toHaveBeenCalledWith("u1", "image_sense");
    expect(await imageSenseDepsFor("u1").resolveSense(WORD)).toMatchObject({ query: "lotus root" });
    expect(h.generateText).toHaveBeenCalledTimes(1);
  });

  it("共有の語の行に検索語が在れば AI を呼ばない（同意も枠も要らない）", async () => {
    h.wordsRows = [{ extras: { image_query: "lotus root", image_avoid: ["flower"] } }];
    expect(await imageSenseDepsFor("u1").resolveSense(WORD)).toEqual({
      query: "lotus root",
      avoid: ["flower"],
    });
    expect(h.generateText).not.toHaveBeenCalled();
    expect(h.cap).not.toHaveBeenCalled();
  });

  it("同意が無ければ AI に何も送らず null（枠も数えない）", async () => {
    h.consent.mockRejectedValue(new Error("AI_CONSENT_REQUIRED"));
    expect(await imageSenseDepsFor("u1").resolveSense(WORD)).toBeNull();
    expect(h.cap).not.toHaveBeenCalled();
    expect(h.generateText).not.toHaveBeenCalled();
  });

  it("枠に届いたら null（投げない）", async () => {
    h.cap.mockRejectedValue(new Error("AI_DAILY_CAP"));
    expect(await imageSenseDepsFor("u1").resolveSense(WORD)).toBeNull();
    expect(h.generateText).not.toHaveBeenCalled();
  });

  it("AI が失敗・形が違っても投げない", async () => {
    h.generateText.mockRejectedValue(new Error("timeout"));
    expect(await imageSenseDepsFor("u1").resolveSense(WORD)).toBeNull();
    h.generateText.mockResolvedValue({ text: "not json" });
    expect(await imageSenseDepsFor("u1").resolveSense({ ...WORD, headword: "竹筍" })).toBeNull();
  });
});

describe("verify", () => {
  it("小さい絵を取り、写真の読めるモデルに絵を添えて聞く。答えは絵ごとに覚える", async () => {
    h.generateText.mockResolvedValue({ text: JSON.stringify({ match: [1] }) });
    const d = imageSenseDepsFor("u1");
    const r = await d.verify({ word: WORD, sense: SENSE, images: IMAGES });
    expect(r?.checked).toEqual([0, 1]);
    expect([...(r?.matched ?? [])]).toEqual([1]);
    const msg = h.generateText.mock.calls[0][0].messages[0].content;
    expect(msg.filter((p: { type: string }) => p.type === "image")).toHaveLength(2);
    expect(String(fetchMock.mock.calls[0][0])).toBe("https://images.unsplash.com/a-s");
    // 2回目は覚えから（AI も絵の取り寄せも無し）。
    const again = await imageSenseDepsFor("u1").verify({
      word: WORD,
      sense: SENSE,
      images: IMAGES,
    });
    expect([...(again?.matched ?? [])]).toEqual([1]);
    expect(h.generateText).toHaveBeenCalledTimes(1);
  });

  it("許していない置き場の絵は取りに行かない（確かめない）", async () => {
    const r = await imageSenseDepsFor("u1").verify({
      word: WORD,
      sense: SENSE,
      images: [{ url: "http://169.254.169.254/x" }],
    });
    expect(r).toBeNull();
    expect(fetchMock).not.toHaveBeenCalled();
    expect(h.generateText).not.toHaveBeenCalled();
  });

  it("同じ写真と言われた物は duplicates で返す。Openverse・Flickr の絵も取りに行ける", async () => {
    h.generateText.mockResolvedValue({ text: JSON.stringify({ match: [0], duplicate: [1] }) });
    const r = await imageSenseDepsFor("u1").verify({
      word: WORD,
      sense: SENSE,
      images: [
        {
          url: "https://live.staticflickr.com/1/2_ab_b.jpg",
          thumb: "https://live.staticflickr.com/1/2_ab_w.jpg",
        },
        { url: "https://api.openverse.org/v1/images/9/thumb/" },
      ],
      timeoutMs: 2_000,
    });
    expect([...(r?.matched ?? [])]).toEqual([0]);
    expect([...(r?.duplicates ?? [])]).toEqual([1]);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("同意が無ければ絵を送らない", async () => {
    h.consent.mockRejectedValue(new Error("AI_CONSENT_REQUIRED"));
    expect(
      await imageSenseDepsFor("u1").verify({ word: WORD, sense: SENSE, images: IMAGES }),
    ).toBeNull();
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
