import { generateText, streamText } from "ai";
import { MockLanguageModelV3 } from "ai/test";
import { describe, expect, it, vi } from "vitest";
import { backedGateway, shouldTryBackup, withBackupModel } from "./ai-backup.server";

const usage = {
  inputTokens: { total: 10, noCache: 10, cacheRead: 0, cacheWrite: 0 },
  outputTokens: { total: 5, text: 5, reasoning: 0 },
};
const answering = (text: string, modelId = "ok-model") =>
  new MockLanguageModelV3({
    modelId,
    doGenerate: async () => ({
      content: [{ type: "text", text }],
      finishReason: { unified: "stop", raw: "stop" },
      usage,
      warnings: [],
    }),
  });
const failing = (message: string) =>
  new MockLanguageModelV3({
    modelId: "broken",
    doGenerate: async () => {
      throw Object.assign(new Error(message), { statusCode: 402 });
    },
    doStream: async () => {
      throw Object.assign(new Error(message), { statusCode: 402 });
    },
  });

describe("withBackupModel（AI が失敗した時の控え）", () => {
  it("1番手が答えれば控えは呼ばない", async () => {
    const backup = vi.fn(() => answering("backup"));
    const res = await generateText({
      model: withBackupModel(answering("primary"), backup),
      prompt: "hi",
    });
    expect(res.text).toBe("primary");
    expect(backup).not.toHaveBeenCalled();
  });

  it("1番手が断ったら（残高切れ 402 など）、同じ依頼を控えへ1回だけ送る", async () => {
    vi.spyOn(console, "warn").mockImplementation(() => {});
    const backupModel = answering("backup");
    const res = await generateText({
      model: withBackupModel(failing("Payment Required"), () => backupModel, "card"),
      prompt: "hello",
      maxRetries: 0,
    });
    expect(res.text).toBe("backup");
    expect(backupModel.doGenerateCalls).toHaveLength(1);
    expect(JSON.stringify(backupModel.doGenerateCalls[0].prompt)).toContain("hello");
  });

  it("流す呼び出しも控えへ回る", async () => {
    vi.spyOn(console, "warn").mockImplementation(() => {});
    const backupModel = new MockLanguageModelV3({
      doStream: async () => ({
        stream: new ReadableStream({
          start(c) {
            c.enqueue({ type: "text-start", id: "1" });
            c.enqueue({ type: "text-delta", id: "1", delta: "streamed" });
            c.enqueue({ type: "text-end", id: "1" });
            c.enqueue({ type: "finish", finishReason: { unified: "stop", raw: "stop" }, usage });
            c.close();
          },
        }),
      }),
    });
    const res = streamText({
      model: withBackupModel(failing("Payment Required"), () => backupModel),
      prompt: "hi",
      maxRetries: 0,
    });
    expect(await res.text).toBe("streamed");
  });

  it("控えも失敗したら、その失敗を返す", async () => {
    vi.spyOn(console, "warn").mockImplementation(() => {});
    await expect(
      generateText({
        model: withBackupModel(failing("first"), () => failing("second")),
        prompt: "hi",
        maxRetries: 0,
      }),
    ).rejects.toThrow(/second/);
  });

  it("控えが無ければ（null）、1番手の失敗をそのまま返す", async () => {
    await expect(
      generateText({
        model: withBackupModel(failing("only"), () => null),
        prompt: "hi",
        maxRetries: 0,
      }),
    ).rejects.toThrow(/only/);
  });

  it("呼ぶ側が止めた・締め切りが来た依頼は控えへ回さない", async () => {
    const backup = vi.fn(() => answering("backup"));
    const ctl = new AbortController();
    const slow = new MockLanguageModelV3({
      doGenerate: async ({ abortSignal }) => {
        ctl.abort();
        throw abortSignal?.reason ?? new Error("aborted");
      },
    });
    await expect(
      generateText({
        model: withBackupModel(slow, backup),
        prompt: "hi",
        maxRetries: 0,
        abortSignal: ctl.signal,
      }),
    ).rejects.toBeDefined();
    expect(backup).not.toHaveBeenCalled();
    expect(shouldTryBackup(new Error("x"), AbortSignal.abort())).toBe(false);
    expect(shouldTryBackup(Object.assign(new Error("t"), { name: "TimeoutError" }))).toBe(false);
    expect(shouldTryBackup(new Error("Payment Required"))).toBe(true);
  });
});

describe("backedGateway", () => {
  it("ゲートウェイの出すモデルを全部包み、ほかの道具は残す", async () => {
    vi.spyOn(console, "warn").mockImplementation(() => {});
    const gateway = Object.assign((_id: string) => failing("down"), { extra: 1 });
    const backed = backedGateway(gateway, () => answering("saved"), "test");
    expect(backed.extra).toBe(1);
    const res = await generateText({
      model: backed("gemini-3.8-flash"),
      prompt: "hi",
      maxRetries: 0,
    });
    expect(res.text).toBe("saved");
  });
});
