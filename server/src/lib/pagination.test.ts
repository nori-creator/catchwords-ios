import { describe, it, expect } from "vitest";
import { isTruncated, readAllPages } from "./pagination";

/**
 * 「まだ先があるか」の判定。**2回続けて間違えた**ところ。
 */

const LIMIT = 1000;

describe("isTruncated", () => {
  it("総数が分かっていて、受け取ったぶんで足りていれば false", () => {
    expect(isTruncated(12, 12, LIMIT)).toBe(false);
    expect(isTruncated(0, 0, LIMIT)).toBe(false);
  });

  it("総数が受け取ったぶんより多ければ true", () => {
    expect(isTruncated(1200, 1000, LIMIT)).toBe(true);
    expect(isTruncated(1001, 1000, LIMIT)).toBe(true);
  });

  it("サーバー側の上限で切られていても、総数さえあれば見抜ける", () => {
    // ここが2回目の間違いの本体。PostgREST は 1000 で切るので、
    // 1001件目の有無で判定しようとすると**永遠に気づけない**。
    // 総数を見ていれば、受け取りが上限ちょうどでも先があると分かる。
    const returnedCappedByServer = 1000;
    expect(isTruncated(4321, returnedCappedByServer, LIMIT)).toBe(true);
  });

  it("総数が取れないときは、上限ちょうどなら「まだある」と言う", () => {
    // 黙って消えるより、多めに言うほうがまし。
    expect(isTruncated(null, 1000, LIMIT)).toBe(true);
    expect(isTruncated(null, 999, LIMIT)).toBe(false);
    expect(isTruncated(null, 0, LIMIT)).toBe(false);
  });

  it("結合の失敗などで受け取りが上限より少なくても、総数が多ければ true", () => {
    // 単語の結合が取れなかった行は捨てられるので、返す件数は上限より
    // 少なくなりうる。件数の比較だけで判断すると、ここで取りこぼす。
    expect(isTruncated(1500, 995, LIMIT)).toBe(true);
  });
});

describe("readAllPages（1000 行ずつ全部読む）", () => {
  /** PostgREST と同じく、頼んだ範囲でも 1000 行で切る偽物。 */
  const source = (total: number) => {
    const calls: Array<[number, number]> = [];
    const page = async (from: number, to: number) => {
      calls.push([from, to]);
      const end = Math.min(total, to + 1, from + 1000);
      return {
        data: Array.from({ length: Math.max(0, end - from) }, (_, i) => from + i),
        error: null,
      };
    };
    return { page, calls };
  };

  it("reads past the 1000-row cap without gaps or duplicates", async () => {
    const { page } = source(2500);
    const { rows, truncated } = await readAllPages(page);
    expect(rows).toHaveLength(2500);
    expect(new Set(rows).size).toBe(2500);
    expect(rows[2499]).toBe(2499);
    expect(truncated).toBe(false);
  });

  it("stops on an exact multiple (empty last page) and on an empty table", async () => {
    expect((await readAllPages(source(2000).page, { parallel: 1 })).rows).toHaveLength(2000);
    expect((await readAllPages(source(0).page)).rows).toEqual([]);
  });

  it("says truncated when the safety limit stops it", async () => {
    const { rows, truncated } = await readAllPages(source(5000).page, { maxRows: 3000 });
    expect(rows).toHaveLength(3000);
    expect(truncated).toBe(true);
  });

  it("throws on a read error instead of returning partial numbers", async () => {
    await expect(
      readAllPages(async () => ({ data: null, error: { message: "boom" } })),
    ).rejects.toThrow("boom");
  });
});
