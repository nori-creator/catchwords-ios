import { normalizeNameRegister, type NameRegister } from "./candidate-register";
/**
 * **スキャンの AI の返事を、寛容に読む。**（オーナー報告 2026-09-23「スキャンモード
 * 検出に失敗と出る」）
 *
 * 前は返事全体を厳密な形（zod）で読み、**1つの候補の1か所でも**形が違うと全体を
 * 失敗にしていた。AI の返事は揺れる — 空欄を `null` で返す、確かさを 93 のように
 * 百分率で返す、種類を "Object" と大文字で返す、座標を文字や `{x, y}` で返す、
 * 7つ以上返す。どれも**中身は使える**のに、画面には「検出に失敗しました」と出ていた。
 *
 * ここでは候補を1つずつ直して読み、直せない候補だけを捨てる。語が1つも読めない
 * ときだけ失敗にする。
 */

export type ParsedDetectItem = {
  kind: "object" | "text";
  headword: string;
  zhuyin: string;
  pinyin: string;
  meaning_ja: string;
  pos: string;
  point: [number, number];
  confidence: number;
  alternatives: string[];
  /** どんな言い方か（5つ、`candidate-register.ts`）。スキャンは物ごとに1語なので、無ければ一般的な言い方。 */
  register: NameRegister;
};

const MAX_ITEMS = 6;

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : typeof v === "number" ? String(v) : "";
}

function num(v: unknown): number | null {
  const n = typeof v === "number" ? v : typeof v === "string" ? Number(v.trim()) : NaN;
  return Number.isFinite(n) ? n : null;
}

/** 座標: `[x, y]`・`["512", "340"]`・`{x, y}`。0〜1 の小数なら 0〜1000 に直す。 */
function point(v: unknown): [number, number] | null {
  let x: number | null = null;
  let y: number | null = null;
  if (Array.isArray(v) && v.length >= 2) {
    x = num(v[0]);
    y = num(v[1]);
  } else if (v && typeof v === "object") {
    const o = v as Record<string, unknown>;
    x = num(o.x);
    y = num(o.y);
  }
  if (x == null || y == null) return null;
  if (x <= 1 && y <= 1 && x >= 0 && y >= 0) {
    x *= 1000;
    y *= 1000;
  }
  const clamp = (n: number) => Math.max(0, Math.min(1000, n));
  return [clamp(x), clamp(y)];
}

/** 確かさ: 0〜1。93 や "0.9" も読む。無ければ 0.8。 */
function confidence(v: unknown): number {
  const n = num(v);
  if (n == null) return 0.8;
  const c = n > 1 ? n / 100 : n;
  return Math.max(0, Math.min(1, c));
}

export function normalizeDetectItem(raw: unknown): ParsedDetectItem | null {
  if (!raw || typeof raw !== "object") return null;
  const o = raw as Record<string, unknown>;
  const headword = str(o.headword ?? o.word);
  if (!headword) return null;
  const p = point(o.point ?? o.position ?? o.center);
  if (!p) return null;
  const kind = str(o.kind).toLowerCase() === "text" ? "text" : "object";
  const alternatives = Array.isArray(o.alternatives)
    ? o.alternatives
        .map((a) =>
          typeof a === "string" ? a : str((a as Record<string, unknown> | null)?.headword),
        )
        .filter(Boolean)
    : [];
  return {
    kind,
    headword,
    zhuyin: str(o.zhuyin),
    pinyin: str(o.pinyin),
    meaning_ja: str(o.meaning_ja ?? o.meaning),
    pos: str(o.pos),
    point: p,
    confidence: confidence(o.confidence),
    alternatives,
    register: normalizeNameRegister(o.register) ?? "common",
  };
}

/**
 * 返事全体を読む。`{items: [...]}` でも、配列そのものでも読む。
 * 読める候補が1つも無く、しかも返事の形が分からないときだけ null。
 * （形は正しく、候補が0個なら「何も見つからなかった」で、失敗ではない。）
 */
export function normalizeDetection(raw: unknown): ParsedDetectItem[] | null {
  const list = Array.isArray(raw)
    ? raw
    : raw && typeof raw === "object" && Array.isArray((raw as { items?: unknown }).items)
      ? (raw as { items: unknown[] }).items
      : null;
  if (!list) return null;
  const out: ParsedDetectItem[] = [];
  const seen = new Set<string>();
  for (const r of list) {
    const it = normalizeDetectItem(r);
    if (!it || seen.has(it.headword)) continue;
    seen.add(it.headword);
    out.push(it);
    if (out.length >= MAX_ITEMS) break;
  }
  return out;
}
