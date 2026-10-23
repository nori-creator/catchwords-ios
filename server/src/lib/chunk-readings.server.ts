import type { ChunkPart, UsageChunk, WordExtrasDTO } from "./extras";
import { checkTaiwanReading } from "./tw-reading.server";
import { normalizeTargetLanguage } from "./target-lang";

/**
 * **チャンクの札ごとの読み（拼音・注音）を検めて埋める**（2026-10-15 オーナー「チャンクに拼音と注音を」）。
 *
 * - AI には同じ呼び出しで札ごとの `pinyin` / `zhuyin` を書かせる（`ai.functions.ts`、AI の呼び出しは増やさない）。
 * - ここで札ごとに `checkTaiwanReading`（見出し語の読みと同じ検め方: 音節の数 = 字の数、字ごとのありうる読み、
 *   台湾の読み）を通す。外れていれば・無ければ**辞書の読み**（pinyin-pro + 台湾の表）に差し替える。
 * - 漢字でない札（T恤・3C・英字）は AI の書いた物をそのまま残す（検められない物は悪くしない）。
 * - 台湾華語以外の言語は触らない。
 *
 * 古いカードは読みを持っていない。読む所（単語の詳細・その人向けの解説）で同じ関数を通せば、作り直さなくても
 * 読みが付く（`withChunkReadingsInExtras`）。サーバー専用（辞書が大きい）。
 */

const HAN = /\p{Script=Han}/u;

function readingFor(
  text: string,
  pinyin: string,
  zhuyin: string,
): { pinyin: string; zhuyin: string } {
  const r = checkTaiwanReading(text, pinyin, zhuyin);
  return { pinyin: r.pinyin, zhuyin: r.zhuyin };
}

/** 札1つの読み。漢字を含む札だけ検める。 */
export function withPartReadings(part: ChunkPart, language: string | null | undefined): ChunkPart {
  if (!normalizeTargetLanguage(language).startsWith("zh")) return part;
  const text = (part.text ?? "").trim();
  const next: ChunkPart = { ...part };
  if (HAN.test(text)) {
    const r = readingFor(text, part.pinyin ?? "", part.zhuyin ?? "");
    if (r.pinyin) next.pinyin = r.pinyin;
    if (r.zhuyin) next.zhuyin = r.zhuyin;
  }
  if (next.alts?.length) {
    next.alts = next.alts.map((a) => {
      if (!HAN.test(a.text ?? "")) return a;
      const r = readingFor(a.text.trim(), a.pinyin ?? "", a.zhuyin ?? "");
      return {
        ...a,
        ...(r.pinyin ? { pinyin: r.pinyin } : {}),
        ...(r.zhuyin ? { zhuyin: r.zhuyin } : {}),
      };
    });
  }
  return next;
}

/** 型の全部の札（と入れ替えの候補）に読みを付ける。 */
export function withChunkReadings<T extends UsageChunk>(
  chunks: ReadonlyArray<T> | null | undefined,
  language: string | null | undefined,
): T[] {
  if (!normalizeTargetLanguage(language).startsWith("zh")) return [...(chunks ?? [])];
  return (chunks ?? []).map((c) => ({
    ...c,
    parts: (c.parts ?? []).map((p) => withPartReadings(p, language)),
  }));
}

/**
 * **漢字の札に読みがそろっているか**（札の数と読みの数が合う・空が無い）。生成の後の確かめと、
 * 読む所で「もう付いているなら触らない」の判定に使う。
 */
export function chunkReadingsComplete(
  chunk: { parts?: ReadonlyArray<ChunkPart> | null },
  language: string | null | undefined,
): boolean {
  if (!normalizeTargetLanguage(language).startsWith("zh")) return true;
  return (chunk.parts ?? []).every(
    (p) => !HAN.test(p.text ?? "") || (!!p.pinyin?.trim() && !!p.zhuyin?.trim()),
  );
}

/**
 * 読む所で使う: `usage_chunks` と `example_chunks` の札に読みを付けた extras を返す。
 * 読みがもうそろっている型は触らない。失敗しても元の物を返す（読みが無いだけで、カードは出る）。
 */
export function withChunkReadingsInExtras<T extends Partial<WordExtrasDTO> | null | undefined>(
  extras: T,
  language: string | null | undefined,
): T {
  if (!extras || !normalizeTargetLanguage(language).startsWith("zh")) return extras;
  try {
    const usage = (extras.usage_chunks ?? []).map((c) =>
      chunkReadingsComplete(c, language)
        ? c
        : { ...c, parts: (c.parts ?? []).map((p) => withPartReadings(p, language)) },
    );
    const example = (extras.example_chunks ?? []).map((p) =>
      HAN.test(p.text ?? "") && (!p.pinyin?.trim() || !p.zhuyin?.trim())
        ? withPartReadings(p, language)
        : p,
    );
    const fill = (p: ChunkPart) =>
      HAN.test(p.text ?? "") && (!p.pinyin?.trim() || !p.zhuyin?.trim())
        ? withPartReadings(p, language)
        : p;
    const extra = (extras.examples_extra ?? []).map((e) => ({
      ...e,
      chunks: (e.chunks ?? []).map(fill),
    }));
    // 入っていた欄だけを返す（無い欄を空の配列で足さない — 作り直しの差分に混ざる）。
    return {
      ...extras,
      ...("usage_chunks" in extras ? { usage_chunks: usage } : {}),
      ...("example_chunks" in extras ? { example_chunks: example } : {}),
      ...("examples_extra" in extras ? { examples_extra: extra } : {}),
    };
  } catch (e) {
    console.warn("chunk-readings: 読みを付けられなかった", (e as Error)?.message);
    return extras;
  }
}
