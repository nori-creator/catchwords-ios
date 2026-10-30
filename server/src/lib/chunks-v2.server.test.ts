import { describe, expect, it } from "vitest";
import {
  awaitChunksV2,
  readChunkLibrary,
  runChunksV2Pipeline,
  startChunksV2Job,
  writeChunkLibrary,
  type AskFn,
  type ChunkWriter,
} from "./chunks-v2.server";

/** 書き手の偽物（会社の名前だけが要る。`ask` を差し替えるので gateway は呼ばれない）。 */
function writer(company: string): ChunkWriter {
  return { company, model: `${company}-model`, cfg: { provider: "openai-compatible", name: company, gateway: (() => ({})) as never, modelFast: "m", modelRich: "m", modelRichPremium: "m" } };
}

function reply(chunks: Array<{ text: string; blocks: Array<Record<string, unknown>>; sentence: string; ja?: string; sentence_ja?: string; pattern?: string }>) {
  return { chunks: chunks.map((c) => ({ ja: "訳", sentence_ja: "文の訳", note: "解説です。", pattern: "object", ...c })) };
}

const BA = { text: "把原子筆放進筆袋裡", sentence: "我把原子筆放進筆袋裡了。", pattern: "coverb", blocks: [{ text: "把", pos: "Ptc" }, { text: "原子筆", pos: "N", slot: true, ja: "ボールペン", alts: [{ text: "鉛筆", ja: "鉛筆" }, { text: "橡皮擦", ja: "消しゴム" }] }, { text: "放進", pos: "V" }, { text: "筆袋裡", pos: "N" }] };
const BA_B = { ...BA, text: "把鉛筆放進筆袋裡", sentence: "把鉛筆放進筆袋裡吧。", blocks: [{ text: "把", pos: "Ptc" }, { text: "鉛筆", pos: "N", slot: true, ja: "鉛筆", alts: [{ text: "原子筆", ja: "ボールペン" }, { text: "尺", ja: "定規" }] }, { text: "放進", pos: "V" }, { text: "筆袋裡", pos: "N" }] };
const OPEN = { text: "打開筆袋", sentence: "幫我打開筆袋。", blocks: [{ text: "打開", pos: "V" }, { text: "筆袋", pos: "N" }] };
const ZIP = { text: "筆袋的拉鍊", sentence: "筆袋的拉鍊壞了。", pattern: "modifier", blocks: [{ text: "筆袋", pos: "N" }, { text: "的", pos: "Ptc" }, { text: "拉鍊", pos: "N" }] };
const ODD = { text: "裝進筆袋", sentence: "我裝進筆袋了。", blocks: [{ text: "裝進", pos: "V" }, { text: "筆袋", pos: "N" }] };

/** 指示文の中身で、どの呼び出しかを見分ける。 */
function asker(opts: {
  google: unknown;
  anthropic: unknown;
  judgeByGoogle?: unknown;
  judgeByAnthropic?: unknown;
  fail?: "google" | "anthropic";
  calls?: string[];
}): AskFn {
  return async (cfg, _model, prompt) => {
    const company = cfg.name ?? "?";
    const kind = prompt.includes("候補:") ? "judge" : prompt.includes("訳を付けてください") ? "translate" : "write";
    opts.calls?.push(`${company}:${kind}`);
    if (kind === "write" && opts.fail === company) throw new Error("boom");
    if (kind === "judge") return company === "google" ? (opts.judgeByGoogle ?? { verdicts: [] }) : (opts.judgeByAnthropic ?? { verdicts: [] });
    if (kind === "translate") return { items: [{ i: 1, ja: "Open the pencil case", sentence_ja: "Open the pencil case for me.", note: "A plain request." }] };
    return company === "google" ? opts.google : opts.anthropic;
  };
}

const WRITERS = { a: writer("google"), b: writer("anthropic") };

describe("2 社に書かせて照合する（runChunksV2Pipeline）", () => {
  it("両方が出した型は一致で合格、片方だけの型は逆の会社の審査に通れば加わる", async () => {
    const calls: string[] = [];
    const r = await runChunksV2Pipeline({
      headword: "筆袋",
      language: "zh-TW",
      explainLang: "ja",
      writers: WRITERS,
      ask: asker({
        google: reply([BA, OPEN, ODD]),
        anthropic: reply([OPEN, BA_B, ZIP]),
        // Google だけの 裝進筆袋 → Claude が審査して不合格。Claude だけの 筆袋的拉鍊 → Google が審査して合格。
        judgeByAnthropic: { verdicts: [{ i: 1, natural: false, frequency: 2 }] },
        judgeByGoogle: { verdicts: [{ i: 1, natural: true, frequency: 4 }] },
        calls,
      }),
    });
    expect(r.chunks.map((c) => c.text)).toEqual(["把原子筆放進筆袋裡", "打開筆袋", "筆袋的拉鍊"]);
    expect(r.chunks.map((c) => c.by)).toEqual(["agreement", "agreement", "judge"]);
    expect(r.rejected.map((c) => c.text)).toEqual(["裝進筆袋"]);
    expect(r.stats.agreed).toBe(2);
    expect(r.stats.providers).toBe("google+anthropic");
    expect(calls.sort()).toEqual(["anthropic:judge", "anthropic:write", "google:judge", "google:write"]);
  });

  it("片方が落ちたら、もう片方の塊を全部その逆の会社に審査してもらう（一致は無い）", async () => {
    const r = await runChunksV2Pipeline({
      headword: "筆袋",
      language: "zh-TW",
      explainLang: "ja",
      writers: WRITERS,
      ask: asker({
        google: reply([BA, OPEN]),
        anthropic: null,
        fail: "anthropic",
        judgeByAnthropic: { verdicts: [{ i: 1, natural: true, frequency: 5 }, { i: 2, natural: true, frequency: 3 }] },
      }),
    });
    expect(r.chunks.map((c) => c.text)).toEqual(["把原子筆放進筆袋裡", "打開筆袋"]);
    expect(r.chunks.every((c) => c.by === "judge")).toBe(true);
    expect(r.stats.agreed).toBe(0);
  });

  it("Claude の鍵が無ければ 1 社で書き、同じ会社が審査する（記録に残る）", async () => {
    const r = await runChunksV2Pipeline({
      headword: "筆袋",
      language: "zh-TW",
      explainLang: "ja",
      writers: { a: writer("google"), b: null },
      ask: asker({ google: reply([OPEN]), anthropic: null, judgeByGoogle: { verdicts: [{ i: 1, natural: true, frequency: 4 }] } }),
    });
    expect(r.chunks.map((c) => c.text)).toEqual(["打開筆袋"]);
    expect(r.stats.providers).toBe("google");
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
  it("作った物を書庫に入れ、次は AI を呼ばずに書庫から返す", async () => {
    const calls: string[] = [];
    const { admin, tables } = fakeAdmin();
    const ask = asker({ google: reply([OPEN, BA]), anthropic: reply([BA_B, OPEN]), calls });
    const first = await startChunksV2Job(admin, { language: "zh-TW", headword: "筆袋", explainLang: "ja", writers: WRITERS, ask });
    expect(first.status).toBe("ready");
    expect(first.fromLibrary).toBe(false);
    expect(first.chunks.map((c) => c.text)).toEqual(["打開筆袋", "把原子筆放進筆袋裡"]);
    expect(tables.chunk_library.map((r) => [r.zh, r.status, r.rank])).toEqual([["打開筆袋", "approved", 0], ["把原子筆放進筆袋裡", "approved", 1]]);
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

  it("別の表示言語の 2 人目は、訳だけの小さな呼び出し（中国語は使い回す）", async () => {
    const calls: string[] = [];
    const { admin, tables } = fakeAdmin({ library: [LIB_ROW()], text: [{ library_id: "lib-1", explain_lang: "ja", ja: "ペンケースを開ける", sentence_ja: "", note: "", blocks_ja: [] }] });
    const r = await startChunksV2Job(admin, { language: "zh-TW", headword: "筆袋", explainLang: "en", writers: WRITERS, ask: asker({ google: null, anthropic: null, calls }) });
    expect(calls).toEqual(["google:translate"]);
    expect(r.status).toBe("ready");
    expect(r.chunks[0].ja).toBe("Open the pencil case");
    expect(tables.chunk_library_text.find((t) => t.explain_lang === "en")?.ja).toBe("Open the pencil case");
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
