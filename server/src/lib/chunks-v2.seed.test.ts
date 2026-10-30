import { mkdirSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { DEX_ITEMS } from "./dex-catalog";
import { EXPLAIN_LANGS } from "./explain-languages";

/**
 * **図鑑の影の語を、出す前に書庫に入れる**（`docs/chunk-rules.md` v2 §3-5: 影にある物を撮った時は最初から待ち無し）。
 *
 * 走らせ方（鍵と本番の Supabase の service role が要る。普段の `npm test` では飛ばす）:
 *   CHUNK_SEED=1 SUPABASE_URL=… SUPABASE_SERVICE_ROLE_KEY=… GEMINI_API_KEY=… ANTHROPIC_API_KEY=… npx vitest run chunks-v2.seed
 * - `CHUNK_SEED_LIMIT=20` … 最初の 20 語だけ（費用を見てから全部）。`CHUNK_SEED_LANGS=ja,en` … その表示言語だけ。
 * - `CHUNK_SEED_FORCE=1` … 書庫に有っても作り直して置き換える（モデルや指示文を変えた後。1 つ目の言語だけ force、残りは訳を付け直す）。
 * 1 語につき: 書き 2 回 ＋ 審査 0〜2 回 ＋ 表示言語ごとの訳 1 回（1 つ目の言語は書きと同時）。書庫に有る語は飛ばす。
 */
const ON = process.env.CHUNK_SEED === "1";

describe.skipIf(!ON)("使い方チャンク v2 — 図鑑の影の語を書庫へ", () => {
  it("書庫に入れて報告を書く", { timeout: 6 * 60 * 60 * 1000 }, async () => {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { startChunksV2Job } = await import("./chunks-v2.server");
    const limit = Number(process.env.CHUNK_SEED_LIMIT ?? 0);
    const force = process.env.CHUNK_SEED_FORCE === "1";
    const langs = (process.env.CHUNK_SEED_LANGS ?? EXPLAIN_LANGS.join(",")).split(",").map((s) => s.trim()).filter(Boolean);
    let words = [...new Set(DEX_ITEMS.map((i) => i.zh))];
    if (limit > 0) words = words.slice(0, limit);
    const rows: Array<{ headword: string; lang: string; status: string; n: number; fromLibrary: boolean }> = [];
    const concurrency = Number(process.env.CHUNK_SEED_CONCURRENCY ?? 3);
    let next = 0;
    const jobs = words.flatMap((w) => langs.map((lang) => ({ w, lang })));
    // 同じ語の別の言語は、1 つ目が書庫に入ってから（中国語を使い回すため）: 語ごとに順に。
    const byWord = new Map<string, Array<{ w: string; lang: string }>>();
    for (const j of jobs) byWord.set(j.w, [...(byWord.get(j.w) ?? []), j]);
    const groups = [...byWord.values()];
    await Promise.all(
      Array.from({ length: Math.min(concurrency, groups.length) }, async () => {
        while (next < groups.length) {
          const group = groups[next++];
          for (const [i, { w, lang }] of group.entries()) {
            // force は 1 つ目の言語だけ（中国語を作り直して書庫を置き換える）。残りの言語は新しい塊に訳を付ける。
            const r = await startChunksV2Job(supabaseAdmin, { language: "zh-TW", headword: w, explainLang: lang, ...(force && i === 0 ? { force: true } : {}) });
            rows.push({ headword: w, lang, status: r.status, n: r.chunks.length, fromLibrary: r.fromLibrary });
            console.info(`[seed] ${w} ${lang}: ${r.status} ${r.chunks.length}${r.fromLibrary ? " (library)" : ""}`);
          }
        }
      }),
    );
    const dir = resolve(__dirname, "../../eval-out");
    mkdirSync(dir, { recursive: true });
    const made = rows.filter((r) => !r.fromLibrary && r.status === "ready").length;
    const none = rows.filter((r) => r.status === "none").length;
    const md = [
      `# 書庫への投入（${new Date().toISOString()}）`,
      `- 語 ${words.length} × 言語 ${langs.length} = ${rows.length}。作った ${made}、書庫に有った ${rows.length - made - none}、0 件 ${none}`,
      ``,
      `| 語 | 言語 | 結果 | 塊の数 |`,
      `|---|---|---|---|`,
      ...rows.map((r) => `| ${r.headword} | ${r.lang} | ${r.status}${r.fromLibrary ? "（書庫）" : ""} | ${r.n} |`),
    ].join("\n");
    writeFileSync(resolve(dir, "chunks-v2-seed.md"), md);
    console.info(md.split("\n").slice(0, 2).join("\n"));
    expect(rows.length).toBe(jobs.length);
  });
});
