import { describe, expect, it, vi } from "vitest";
import {
  CHUNK_EXAMPLES_TIMEOUT_MS,
  chunkExamplesTimeout,
  fillChunkExamples,
} from "./chunk-example-fill";

// オーナー報告 2026-11-20 雨傘: 型が3つで例文が2つ。足す呼び出しは 8 秒の締め切りで 28 回中 27 回時間切れだった。
const umbrella = [
  { parts: [{ text: "帶" }, { text: "雨傘" }] },
  { parts: [{ text: "撐" }, { text: "雨傘" }] },
  { parts: [{ text: "收" }, { text: "雨傘" }] },
];
const card = () => ({
  example_sentence: "外面快要下雨了，出門記得帶雨傘喔！",
  example_translation: "訳",
  extras: {
    examples_extra: [
      { zh: "雨越下越大了，我們一起撐這把雨傘走吧。", ja: "訳", scene: "場面", scene_for: "雨越下越大了，我們一起撐這把雨傘走吧。" },
      { zh: "你的雨傘還在滴水，先放在門口雨傘架上吧。", ja: "訳", scene: "場面", scene_for: "你的雨傘還在滴水，先放在門口雨傘架上吧。" },
    ],
  } as Record<string, unknown>,
});
const base = {
  chunks: umbrella,
  headword: "雨傘",
  language: "zh-TW",
  readerLang: "ja",
  withExtra: true,
  rule: (missing: unknown[]) => `missing:${missing.length}`,
  parse: (text: string) => JSON.parse(text),
};
const reply = (sentence: string) =>
  JSON.stringify({
    example_patterns: [
      { share: 0, sentence, translation: "訳", scene: "店に入る前に", chunks: [], scene_fits: true },
    ],
  });
const zh = (c: { extras?: Record<string, unknown> | null }) =>
  ((c.extras?.examples_extra as Array<{ zh: string }>) ?? []).map((e) => e.zh);

describe("chunkExamplesTimeout — 残り時間から締め切りを決める", () => {
  it("ふつうは 15 秒（小さな呼び出しの 90% が 13 秒以内）", () => {
    expect(CHUNK_EXAMPLES_TIMEOUT_MS).toBe(15_000);
    expect(chunkExamplesTimeout(20_000)).toBe(15_000);
    expect(chunkExamplesTimeout(37_000)).toBe(15_000);
  });
  it("iOS の 60 秒に間に合うよう、遅いカードの後は短く、足りなければ呼ばない", () => {
    expect(chunkExamplesTimeout(42_000)).toBe(10_000);
    expect(chunkExamplesTimeout(46_000)).toBe(6_000);
    expect(chunkExamplesTimeout(47_000)).toBe(0);
    expect(chunkExamplesTimeout(58_000)).toBe(0);
  });
});

describe("fillChunkExamples", () => {
  it("例文の無い型だけを1回で頼み、返った文を足す（雨傘の「收＋雨傘」）", async () => {
    const generate = vi.fn(async (_prompt: string, _signal: AbortSignal) => ({
      text: reply("到店門口了，我們先收雨傘吧。"),
    }));
    const r = await fillChunkExamples(card(), { ...base, generate, timeoutMs: 15_000 });
    expect(generate).toHaveBeenCalledTimes(1);
    // 画面にもう出ている「撐…雨傘」は頼まない — 無いのは1つだけ。
    expect(generate.mock.calls[0][0]).toBe("missing:1");
    expect(r.asked).toBe(1);
    expect(r.missing).toEqual([]);
    expect(zh(r.card).at(-1)).toBe("到店門口了，我們先收雨傘吧。");
    expect(r.card.extras).toMatchObject({ example_pattern_count: 4 });
  });

  it("全部の型に例文が在れば AI を呼ばない", async () => {
    const generate = vi.fn(async () => ({ text: "{}" }));
    const r = await fillChunkExamples(card(), {
      ...base,
      chunks: umbrella.slice(0, 2),
      generate,
      timeoutMs: 15_000,
    });
    expect(generate).not.toHaveBeenCalled();
    expect(r).toMatchObject({ asked: 0, missing: [] });
  });

  it("同じ返事の生のパターンに在れば、そこから拾って AI を呼ばない", async () => {
    const generate = vi.fn(async () => ({ text: "{}" }));
    const r = await fillChunkExamples(card(), {
      ...base,
      patterns: [
        { situation: "", share: 10, sentence: "到店門口了，我們先收雨傘吧。", translation: "訳", scene: "店に入る前に", chunks: [], scene_fits: true },
      ],
      generate,
      timeoutMs: 15_000,
    });
    expect(generate).not.toHaveBeenCalled();
    expect(r.missing).toEqual([]);
  });

  it("時間切れ・崩れた返事・型を含まない文なら、カードはそのまま（型も例文も捨てない）", async () => {
    const before = card();
    const timedOut = await fillChunkExamples(card(), {
      ...base,
      generate: async () => {
        throw new Error("The operation was aborted due to timeout");
      },
      timeoutMs: 15_000,
    });
    expect(timedOut.card).toEqual(before);
    expect(timedOut).toMatchObject({ asked: 1, missing: [2] });
    expect(timedOut.error).toContain("timeout");

    const broken = await fillChunkExamples(card(), {
      ...base,
      generate: async () => ({ text: "not json" }),
      timeoutMs: 15_000,
    });
    expect(broken.card).toEqual(before);
    expect(broken.missing).toEqual([2]);

    const off = await fillChunkExamples(card(), {
      ...base,
      generate: async () => ({ text: reply("我先把雨傘收起來放門口喔。") }),
      timeoutMs: 15_000,
    });
    expect(zh(off.card)).toEqual(zh(before));
    expect(off.missing).toEqual([2]);
  });

  it("残り時間が無い時（timeoutMs 0）は呼ばない", async () => {
    const generate = vi.fn(async () => ({ text: "{}" }));
    const r = await fillChunkExamples(card(), { ...base, generate, timeoutMs: 0 });
    expect(generate).not.toHaveBeenCalled();
    expect(r).toMatchObject({ asked: 0, missing: [2] });
  });

  it("締め切りの合図を渡す", async () => {
    let got: AbortSignal | undefined;
    await fillChunkExamples(card(), {
      ...base,
      generate: async (_p, signal) => {
        got = signal;
        return { text: "{}" };
      },
      timeoutMs: 15_000,
    });
    expect(got).toBeInstanceOf(AbortSignal);
  });
});
