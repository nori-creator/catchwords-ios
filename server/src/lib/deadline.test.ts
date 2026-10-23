import { describe, expect, it, vi } from "vitest";
import { withDeadline } from "./deadline";

describe("withDeadline", () => {
  it("間に合えばその値", async () => {
    await expect(withDeadline(Promise.resolve(1), 100, null)).resolves.toBe(1);
  });

  it("失敗したら代わりの値（例外にしない）", async () => {
    await expect(withDeadline(Promise.reject(new Error("x")), 100, null)).resolves.toBeNull();
  });

  it("**返ってこない約束でも、上限で進む**（iPhone の位置の許可待ち）", async () => {
    vi.useFakeTimers();
    const never = new Promise<number>(() => {});
    const p = withDeadline(never, 3000, null);
    vi.advanceTimersByTime(3000);
    await expect(p).resolves.toBeNull();
    vi.useRealTimers();
  });
});
