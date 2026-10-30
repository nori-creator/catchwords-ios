import { describe, expect, it } from "vitest";
import {
  awaitChunksV2,
  readChunkLibrary,
  runChunksV2Pipeline,
  speedOptions,
  startChunksV2Job,
  writeChunkLibrary,
  type AskFn,
  type ChunkWriter,
} from "./chunks-v2.server";

/** 書き手の偽物（会社の名前だけが要る。`ask` を差し替えるので gateway は呼ばれない）。 */
function writer(company: string): ChunkWriter {
  return { company, model: `${company}-model`, cfg: { provider: "openai-compatible", name: company, gateway: (() => ({})) as never, modelFast: "m", modelRich: "m", modelRichPremium: "m" } };
}

type Raw = { text: string; sentence: string; key: string; pattern?: string; slot?: string | null; alts?: string[] };
function reply(chunks: Raw[]) {
  return { chunks: chunks.map((c) => ({ pattern: "object", slot: null, alts: [], ...c })) };
}

/** 書く段の返事（中国語だけ・軽い形）。 */
const BA: Raw = { text: "把原子筆放進筆袋裡", sentence: "我把原子筆放進筆袋裡了。", key: "放進", pattern: "coverb", slot: "原子筆", alts: ["鉛筆", "橡皮擦"] };
const BA_B: Raw = { ...BA, text: "把鉛筆放進筆袋裡", sentence: "把鉛筆放進筆袋裡吧。", slot: "鉛筆", alts: ["原子筆", "尺"] };
const OPEN: Raw = { text: "打開筆袋", sentence: "幫我打開筆袋。", key: "打開" };
const ZIP: Raw = { text: "筆袋的拉鍊", sentence: "筆袋的拉鍊壞了。", key: "拉鍊", pattern: "modifier" };
const ODD: Raw = { text: "裝進筆袋", sentence: "我裝進筆袋了。", key: "裝進" };

/** 仕上げの返事に使う block（塊ごと）。 */
const BLOCKS: Record<string, Array<{ text: string; pos: string }>> = {
  把原子筆放進筆袋裡: [{ text: "把", pos: "Prep" }, { text: "原子筆", pos: "N" }, { text: "放進", pos: "V" }, { text: "筆袋裡", pos: "N" }],
  把鉛筆放進筆袋裡: [{ text: "把", pos: "Prep" }, { text: "鉛筆", pos: "N" }, { text: "放進", pos: "V" }, { text: "筆袋裡", pos: "N" }],
  打開筆袋: [{ text: "打開", pos: "V" }, { text: "筆袋", pos: "N" }],
  筆袋的拉鍊: [{ text: "筆袋", pos: "N" }, { text: "的", pos: "Ptc" }, { text: "拉鍊", pos: "N" }],
};

/**
 * 指示文の中身で、どの呼び出しかを見分ける。審査は候補の数だけ答えを返す（`judge` に無い i は全部 natural・順位は並び順）。
 * 仕上げは塊ごとに block と訳（英語の読者には英語）。
 */
function asker(opts: {
  google: unknown;
  anthropic: unknown;
  judgeByGoogle?: Array<{ i: number; natural: boolean; rank: number | null }>;
  judgeByAnthropic?: Array<{ i: number; natural: boolean; rank: number | null }>;
  fail?: "google" | "anthropic";
  judgeFail?: "google" | "anthropic";
  calls?: string[];
  finishFails?: boolean;
}): AskFn {
  return async (cfg, _model, prompt) => {
    const company = cfg.name ?? "?";
    const kind = prompt.includes("各候補に次を付けてください") ? "finish" : prompt.includes("1 つずつ判定する") ? "judge" : "write";
    opts.calls?.push(`${company}:${kind}`);
    if (kind === "write" && opts.fail === company) throw new Error("boom");
    const lines = [...prompt.matchAll(/^\d+\. 塊: (\S+)　文:/gmu)].map((m) => m[1]);
    if (kind === "judge") {
      if (opts.judgeFail === company) throw new Error("slow");
      const given = company === "google" ? opts.judgeByGoogle : opts.judgeByAnthropic;
      const verdicts = lines.map((_, k) => given?.find((g) => g.i === k + 1) ?? { i: k + 1, natural: true, rank: k + 1 });
      return { verdicts };
    }
    if (kind === "finish") {
      if (opts.finishFails) throw new Error("boom");
      const en = prompt.includes("英語");
      const wantBlocks = prompt.includes("blocks:");
      return {
        items: lines.map((text, k) => ({
          i: k + 1,
          ...(wantBlocks ? { blocks: BLOCKS[text] ?? [{ text, pos: "" }] } : {}),
          ja: en ? `Translation ${k + 1}` : `やく${k + 1}`,
          sentence_ja: en ? `Sentence ${k + 1}.` : `ぶんのやく${k + 1}。`,
          note: en ? "A plain note." : "かいせつです。",
          slot_ja: en ? "pen" : "ボールペン",
          alts_ja: en ? ["pencil", "eraser"] : ["鉛筆", "消しゴム"],
        })),
      };
    }
    return company === "google" ? opts.google : opts.anthropic;
  };
}

const WRITERS = { a: writer("google"), b: writer("anthropic") };

describe("考える量を最小にする（speedOptions）", () => {
  it("Claude Haiku は thinking を切り、Gemini は reasoning_effort を低く、ほかの会社には何も足さない", () => {
    expect(speedOptions({ name: "anthropic" }, "claude-haiku-5-5")).toEqual({ anthropic: { thinking: { type: "disabled" } } });
    expect(speedOptions({ name: "anthropic" }, "claude-sonnet-5-5")).toEqual({ anthropic: { thinking: { type: "between_tools" } } });
    expect(speedOptions({ name: "anthropic" }, "claude-opus-5-5")).toBeUndefined();
    expect(speedOptions({ name: "google" }, "gemini-3.1-flash")).toEqual({ google: { reasoningEffort: "low" } });
    expect(speedOptions({ name: "openrouter" }, "x")).toBeUndefined();
  });
});

describe("2 社に書かせて照合する（runChunksV2Pipeline）", () => {
  it("両方が出した言い方は一致で合格、片方だけの物は逆の会社が自然と言えば加わる。並びは 2 社の順位の平均。訳と block は残った塊にだけ", async () => {
    const calls: string[] = [];
    const r = await runChunksV2Pipeline({
      headword: "筆袋",
      language: "zh-TW",
      explainLang: "ja",
      writers: WRITERS,
      ask: asker({
        google: reply([BA, OPEN, ODD]),
        anthropic: reply([OPEN, BA_B, ZIP]),
        // 候補の並び: 1 把…（一致）2 打開（一致）3 裝進（Google だけ）4 筆袋的拉鍊（Claude だけ）
        judgeByAnthropic: [{ i: 3, natural: false, rank: null }, { i: 1, natural: true, rank: 1 }, { i: 2, natural: true, rank: 2 }, { i: 4, natural: true, rank: 3 }],
        judgeByGoogle: [{ i: 1, natural: true, rank: 1 }, { i: 2, natural: true, rank: 2 }, { i: 3, natural: true, rank: 3 }, { i: 4, natural: true, rank: 4 }],
        calls,
      }),
    });
    expect(r.selected.map((c) => c.text)).toEqual(["把原子筆放進筆袋裡", "打開筆袋", "筆袋的拉鍊"]);
    expect(r.selected.map((c) => c.by)).toEqual(["agreement", "agreement", "judge"]);
    expect(r.rejected.map((c) => [c.text, c.reason])).toEqual([["裝進筆袋", "unnatural"]]);
    // 訳と block は残った塊にだけ付く。
    expect(r.chunks.map((c) => c.ja)).toEqual(["やく1", "やく2", "やく3"]);
    expect(r.chunks[0].blocks.map((b) => `${b.text}/${b.pos}`)).toEqual(["把/Prep", "原子筆/N", "放進/V", "筆袋裡/N"]);
    expect(r.chunks[0].blocks[1].alts?.map((a) => `${a.text}=${a.ja}`)).toEqual(["鉛筆=鉛筆", "橡皮擦=消しゴム"]);
    expect(r.chunks[0].head).toEqual({ block: 3, start: 0, length: 2 });
    expect(r.stats.agreed).toBe(2);
    expect(r.stats.pool).toBe(4);
    expect(r.stats.judgedBy).toBe("both");
    expect(r.stats.providers).toBe("google+anthropic");
    expect(calls.sort()).toEqual(["anthropic:judge", "anthropic:write", "google:finish", "google:judge", "google:write"]);
  });

  it("片方が落ちたら、もう片方の塊は自分の会社の審査で決まる（一致は無い）", async () => {
    const r = await runChunksV2Pipeline({
      headword: "筆袋",
      language: "zh-TW",
      explainLang: "ja",
      writers: WRITERS,
      ask: asker({ google: reply([BA, OPEN, ODD]), anthropic: null, fail: "anthropic", judgeByGoogle: [{ i: 3, natural: false, rank: null }] }),
    });
    expect(r.selected.map((c) => c.text)).toEqual(["把原子筆放進筆袋裡", "打開筆袋"]);
    expect(r.selected.every((c) => c.by === "judge")).toBe(true);
    expect(r.stats.agreed).toBe(0);
    expect(r.stats.judgedBy).toBe("a");
  });

  it("逆の会社の審査が時間切れなら、自分の会社の審査で決める（審査なしで通さない）", async () => {
    const r = await runChunksV2Pipeline({
      headword: "筆袋",
      language: "zh-TW",
      explainLang: "ja",
      writers: WRITERS,
      ask: asker({ google: reply([BA, ODD]), anthropic: reply([ZIP]), judgeFail: "anthropic", judgeByGoogle: [{ i: 1, natural: true, rank: 2 }, { i: 2, natural: false, rank: null }, { i: 3, natural: true, rank: 1 }] }),
    });
    // 候補: 1 把…（A）2 裝進（A）3 拉鍊（B）。Claude の審査が無いので A の塊も Google の審査で決まる。
    expect(r.selected.map((c) => c.text)).toEqual(["筆袋的拉鍊", "把原子筆放進筆袋裡"]);
    expect(r.rejected.map((c) => c.text)).toEqual(["裝進筆袋"]);
    expect(r.stats.judgedBy).toBe("a");
  });

  it("Claude の鍵が無ければ 1 社で書き、仕上げが失敗すれば画面に出す物は空（中国語は block 1 つで残る）", async () => {
    const r = await runChunksV2Pipeline({
      headword: "筆袋",
      language: "zh-TW",
      explainLang: "ja",
      writers: { a: writer("google"), b: null },
      ask: asker({ google: reply([BA]), anthropic: null, finishFails: true }),
    });
    expect(r.selected.map((c) => c.text)).toEqual(["把原子筆放進筆袋裡"]);
    expect(r.selected[0].blocks.map((b) => b.text)).toEqual(["把", "原子筆", "放進筆袋裡"]);
    expect(r.chunks).toEqual([]);
    expect(r.stats.providers).toBe("google");
  });

  it("繁體中文で読む人は訳なしで、block だけ付けて返す", async () => {
    const r = await runChunksV2Pipeline({ headword: "筆袋", language: "zh-TW", explainLang: "zh-TW", writers: WRITERS, ask: asker({ google: reply([OPEN]), anthropic: reply([OPEN]) }) });
    expect(r.chunks.map((c) => c.text)).toEqual(["打開筆袋"]);
    expect(r.chunks[0].ja).toBe("");
    expect(r.chunks[0].blocks.map((b) => b.pos)).toEqual(["V", "N"]);
  });
});

/** DB の偽物: 3 つの表を配列で持ち、使う形の問い合わせだけ答える。 */
function fakeAdmin(seed: { library?: Record<string, unknown>[]; text?: Record<string, unknown>[]; runs?: Record<string, unknown>[] } = {}) {
  const tables: Record<string, Record<string, unknown>[]> = {
    chunk_library: [...(seed.library ?? [])],
    chunk_library_text: [...(seed.text ?? [])],
    chunk_runs: [...(seed.runs ?? [])],
  };
  let nextId = 1;
  const keyOf: Record<string, string[]> = { chunk_library: ["language", "headword", "zh"], chunk_library_text: ["library_id", "explain_lang"], chunk_runs: ["language", "headword"] };
  const admin = {
    from(table: string) {
      const rows = tables[table];
      const filters: Array<(r: Record<string, unknown>) => boolean> = [];
      let single = false;
      const q: Record<string, unknown> = {};
      const result = () => {
        const out = rows.filter((r) => filters.every((f) => f(r)));
        return { data: single ? (out[0] ?? null) : out, error: null };
      };
      q.select = () => q;
      q.eq = (k: string, v: unknown) => {
        filters.push((r) => r[k] === v);
        return q;
      };
      q.in = (k: string, vs: unknown[]) => {
        filters.push((r) => vs.includes(r[k]));
        return q;
      };
      q.order = () => q;
      q.maybeSingle = () => {
        single = true;
        return q;
      };
      q.then = (res: (v: unknown) => unknown, rej?: (e: unknown) => unknown) => Promise.resolve(result()).then(res, rej);
      q.upsert = (value: Record<string, unknown> | Record<string, unknown>[]) => {
        const list = Array.isArray(value) ? value : [value];
        const written: Record<string, unknown>[] = [];
        for (const v of list) {
          const key = keyOf[table];
          const at = rows.findIndex((r) => key.every((k) => r[k] === v[k]));
          const row = { ...(at >= 0 ? rows[at] : { id: `id-${nextId++}` }), ...v };
          if (at >= 0) rows[at] = row;
          else rows.push(row);
          written.push(row);
        }
        const r: Record<string, unknown> = { select: () => Promise.resolve({ data: written, error: null }) };
        r.then = (res: (v: unknown) => unknown) => Promise.resolve({ data: null, error: null }).then(res);
        return r;
      };
      return q;
    },
  };
  return { admin, tables };
}

const LIB_ROW = (over: Record<string, unknown> = {}) => ({
  id: "lib-1",
  language: "zh-TW",
  headword: "筆袋",
  zh: "打開筆袋",
  frame: "打開筆袋",
  blocks: [{ text: "打開", pos: "V" }, { text: "筆袋", pos: "N" }],
  head: { block: 1, start: 0, length: 2 },
  pattern: "object",
  sentence: "幫我打開筆袋。",
  rank: 0,
  frequency: null,
  decided_by: "agreement",
  status: "approved",
  ...over,
});

describe("書庫（chunk_library）", () => {
  it("作った物を書庫に入れ（不自然と落ちた物は rejected で）、次は AI を呼ばずに書庫から返す", async () => {
    const calls: string[] = [];
    const { admin, tables } = fakeAdmin();
    const ask = asker({ google: reply([OPEN, BA, ODD]), anthropic: reply([BA_B, OPEN]), judgeByAnthropic: [{ i: 3, natural: false, rank: null }], calls });
    const first = await startChunksV2Job(admin, { language: "zh-TW", headword: "筆袋", explainLang: "ja", writers: WRITERS, ask });
    expect(first.status).toBe("ready");
    expect(first.fromLibrary).toBe(false);
    // 一致した 2 つ。順位は 2 社の平均（審査の偽物は候補の並び順なので、候補の並び = 一致の順 = A の順）。
    expect(first.chunks.map((c) => c.text)).toEqual(["打開筆袋", "把原子筆放進筆袋裡"]);
    expect(tables.chunk_library.map((r) => [r.zh, r.status, r.rank])).toEqual([["打開筆袋", "approved", 0], ["把原子筆放進筆袋裡", "approved", 1], ["裝進筆袋", "rejected", 100]]);
    expect(tables.chunk_library_text).toHaveLength(2);
    expect(tables.chunk_runs[0]).toMatchObject({ status: "done", approved: 2, providers: "google+anthropic" });
    const before = calls.length;
    const second = await startChunksV2Job(admin, { language: "zh-TW", headword: "筆袋", explainLang: "ja", writers: WRITERS, ask });
    expect(second.status).toBe("ready");
    expect(second.fromLibrary).toBe(true);
    expect(second.chunks.map((c) => c.text)).toEqual(["打開筆袋", "把原子筆放進筆袋裡"]);
    // 入れ替えの候補の意味も戻る。
    expect(second.chunks[1].blocks[1].alts?.map((a) => a.ja)).toEqual(["鉛筆", "消しゴム"]);
    expect(calls.length).toBe(before);
  });

  it("別の表示言語の 2 人目は、訳だけの小さな呼び出し（中国語と block は使い回す）", async () => {
    const calls: string[] = [];
    const { admin, tables } = fakeAdmin({ library: [LIB_ROW()], text: [{ library_id: "lib-1", explain_lang: "ja", ja: "ペンケースを開ける", sentence_ja: "", note: "", blocks_ja: [] }] });
    const r = await startChunksV2Job(admin, { language: "zh-TW", headword: "筆袋", explainLang: "en", writers: WRITERS, ask: asker({ google: null, anthropic: null, calls }) });
    expect(calls).toEqual(["google:finish"]);
    expect(r.status).toBe("ready");
    expect(r.chunks[0].ja).toBe("Translation 1");
    expect(r.chunks[0].blocks.map((b) => b.pos)).toEqual(["V", "N"]);
    expect(tables.chunk_library_text.find((t) => t.explain_lang === "en")?.ja).toBe("Translation 1");
  });

  it("繁體中文で読む人は訳が要らないので、書庫の中国語をそのまま返す", async () => {
    const { admin } = fakeAdmin({ library: [LIB_ROW()] });
    const r = await startChunksV2Job(admin, { language: "zh-TW", headword: "筆袋", explainLang: "zh-TW", writers: WRITERS, ask: asker({ google: null, anthropic: null }) });
    expect(r.status).toBe("ready");
    expect(r.chunks.map((c) => c.text)).toEqual(["打開筆袋"]);
  });

  it("同じ語を作っている最中なら pending、1 つも合格しなかった語は 1 日作り直さない", async () => {
    const fresh = fakeAdmin({ runs: [{ language: "zh-TW", headword: "筆袋", status: "pending", approved: 0, started_at: new Date().toISOString(), finished_at: null }] });
    expect((await startChunksV2Job(fresh.admin, { language: "zh-TW", headword: "筆袋", explainLang: "ja", writers: WRITERS, ask: asker({ google: null, anthropic: null }) })).status).toBe("pending");
    const none = fakeAdmin({ runs: [{ language: "zh-TW", headword: "筆袋", status: "done", approved: 0, started_at: new Date().toISOString(), finished_at: new Date().toISOString() }] });
    expect((await startChunksV2Job(none.admin, { language: "zh-TW", headword: "筆袋", explainLang: "ja", writers: WRITERS, ask: asker({ google: null, anthropic: null }) })).status).toBe("none");
  });

  it("↻（force）は書庫を無視して作り直し、書庫を置き換える", async () => {
    const calls: string[] = [];
    const { admin, tables } = fakeAdmin({ library: [LIB_ROW()] });
    const r = await startChunksV2Job(admin, { language: "zh-TW", headword: "筆袋", explainLang: "ja", force: true, writers: WRITERS, ask: asker({ google: reply([BA]), anthropic: reply([BA_B]), calls }) });
    expect(calls.filter((c) => c.endsWith(":write"))).toHaveLength(2);
    expect(r.chunks.map((c) => c.text)).toEqual(["把原子筆放進筆袋裡"]);
    expect(tables.chunk_library.map((x) => x.zh)).toContain("把原子筆放進筆袋裡");
  });

  it("awaitChunksV2 は pending の間だけ待つ（時間切れなら pending のまま）", async () => {
    const { admin } = fakeAdmin({ runs: [{ language: "zh-TW", headword: "筆袋", status: "pending", approved: 0, started_at: new Date().toISOString(), finished_at: null }] });
    const r = await awaitChunksV2(admin, { language: "zh-TW", headword: "筆袋", explainLang: "ja", writers: WRITERS, ask: asker({ google: null, anthropic: null }) }, 600);
    expect(r.status).toBe("pending");
  });

  it("書庫の読み書きの往復で、block の意味・入れ替えの候補・読みが揃う", async () => {
    const { admin } = fakeAdmin();
    const chunk = {
      text: "把原子筆放進筆袋裡",
      blocks: [{ text: "把", pos: "Ptc" }, { text: "原子筆", pos: "N", slot: true, ja: "ボールペン", alts: [{ text: "鉛筆", ja: "鉛筆" }, { text: "橡皮擦", ja: "消しゴム" }] }, { text: "放進", pos: "V" }, { text: "筆袋裡", pos: "N" }],
      head: { block: 3, start: 0, length: 2 },
      pattern: "coverb",
      ja: "ボールペンをペンケースに入れる",
      note: "いちばん普通の言い方。",
      sentence: "我把原子筆放進筆袋裡了。",
      sentence_ja: "ボールペンをペンケースに入れたよ。",
      frequency: null,
      by: "agreement" as const,
    };
    expect(await writeChunkLibrary(admin, { language: "zh-TW", headword: "筆袋", explainLang: "ja", providers: "google+anthropic" }, [chunk])).toBe(true);
    const lib = await readChunkLibrary(admin, "zh-TW", "筆袋", "ja");
    const back = lib?.chunks[0];
    expect(back?.ja).toBe("ボールペンをペンケースに入れる");
    expect(back?.note).toBe("いちばん普通の言い方。");
    expect(back?.blocks[1].ja).toBe("ボールペン");
    expect(back?.blocks[1].alts?.map((a) => `${a.text}=${a.ja}`)).toEqual(["鉛筆=鉛筆", "橡皮擦=消しゴム"]);
    expect(back?.blocks[3].zhuyin).toBeTruthy();
    expect(back?.head).toEqual({ block: 3, start: 0, length: 2 });
  });
});
