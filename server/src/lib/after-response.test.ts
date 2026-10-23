/**
 * 返事の後も続けたい処理を、黙って捨てさせない（監査 2026-10-03 L5、`after-response.ts`）。
 */
import { afterEach, describe, expect, it, vi } from "vitest";
import { runAfterResponse, waitUntilFrom } from "./after-response";

afterEach(() => {
  vi.restoreAllMocks();
});

describe("waitUntilFrom（要求に付いた waitUntil を探す）", () => {
  it("nitro が付ける request.waitUntil を使う", () => {
    const wu = vi.fn();
    expect(waitUntilFrom({ waitUntil: wu })).toBe(wu);
  });

  it("runtime.cloudflare.context.waitUntil でもよい（this を保つ）", () => {
    const ctx = {
      seen: [] as unknown[],
      waitUntil(this: { seen: unknown[] }, p: Promise<unknown>) {
        this.seen.push(p);
      },
    };
    const wu = waitUntilFrom({ runtime: { cloudflare: { context: ctx } } });
    const p = Promise.resolve();
    wu?.(p);
    expect(ctx.seen).toEqual([p]);
  });

  it("無ければ null", () => {
    expect(waitUntilFrom(null)).toBeNull();
    expect(waitUntilFrom({})).toBeNull();
    expect(waitUntilFrom({ waitUntil: "x" })).toBeNull();
  });
});

describe("runAfterResponse", () => {
  it("waitUntil があれば預けて、待たずに戻る", async () => {
    const wu = vi.fn();
    let finish!: () => void;
    const task = vi.fn(() => new Promise<void>((r) => (finish = r)));
    await expect(runAfterResponse("t", task, { waitUntil: wu })).resolves.toBe("deferred");
    expect(task).toHaveBeenCalledTimes(1);
    expect(wu).toHaveBeenCalledTimes(1);
    finish();
  });

  it("waitUntil が無ければ、終わるまで待つ", async () => {
    let done = false;
    const r = await runAfterResponse(
      "t",
      async () => {
        await new Promise((res) => setTimeout(res, 5));
        done = true;
      },
      { waitUntil: null },
    );
    expect(r).toBe("awaited");
    expect(done).toBe(true);
  });

  it("待つのは上限まで。過ぎたら記録に残して戻る", async () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    const r = await runAfterResponse("slow", () => new Promise(() => {}), {
      waitUntil: null,
      timeoutMs: 10,
    });
    expect(r).toBe("awaited");
    expect(warn).toHaveBeenCalledWith(expect.stringContaining("slow: still running after 10ms"));
  });

  it("失敗は投げずに、名前付きで記録に残す（黙って飲まない）", async () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    await expect(
      runAfterResponse(
        "distractors",
        async () => {
          throw new Error("boom");
        },
        { waitUntil: null },
      ),
    ).resolves.toBe("awaited");
    expect(warn).toHaveBeenCalledWith("[after-response] distractors failed", "boom");
  });

  it("同期で投げる仕事も同じ扱い", async () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    await runAfterResponse(
      "sync",
      () => {
        throw new Error("sync boom");
      },
      { waitUntil: null },
    );
    expect(warn).toHaveBeenCalledWith("[after-response] sync failed", "sync boom");
  });

  it("server fn の外（要求が無い）では待つ側に落ちる", async () => {
    let done = false;
    const r = await runAfterResponse("outside", async () => {
      done = true;
    });
    expect(r).toBe("awaited");
    expect(done).toBe(true);
  });
});
