import { parseJevAnswers, type JevEntry, type JevQuestion, type JevResult } from "./jev";

/**
 * Jev への通信（`jev.ts` の注に仕様の出どころ）。**サーバー専用** —
 * 鍵を画面側へ出さない。
 */

const DEFAULT_BASE_URL = "https://api.typesafe.ai";
const DEFAULT_MODEL = "jev-latest";
/**
 * 1回の待ち時間の上限。公式は 70〜500ms を掲げている。**待ちすぎない** —
 * ここで詰まると、候補の並べ替えや報告の確認がそのぶん遅れる。
 * 間に合わなければ従来の処理に戻る。
 */
const TIMEOUT_MS = 4_000;

/**
 * 鍵の名前。オーナーは「シークレットに追加した」とだけ言っており、名前は
 * 分からない。SDK が読む `TYPESAFE_API_KEY` を先頭に、ありそうな別名も見る
 * （`ai-provider.server.ts` の `KEY_ALIASES` と同じ考え方 —
 * 2026-07-28 に鍵の名前の決め打ちでスキャンが全滅した）。
 */
export const JEV_KEY_ALIASES = [
  "TYPESAFE_API_KEY",
  "TYPESAFE_KEY",
  "TYPESAFE_AI_API_KEY",
  "JEV_API_KEY",
  "JEV_KEY",
] as const;

export function findJevKey(): { env: string; value: string } | null {
  for (const name of JEV_KEY_ALIASES) {
    const v = process.env[name];
    if (v && v.trim()) return { env: name, value: v.trim() };
  }
  return null;
}

export function jevAvailable(): boolean {
  return findJevKey() !== null;
}

/**
 * 問いをまとめて聞く。**失敗は投げずに `null`**（鍵が無い・時間切れ・
 * 相手のエラー・形の違う答え）。呼ぶ側は必ず従来の処理に戻れること。
 */
export async function askJev(
  state: JevEntry,
  questions: Record<string, JevQuestion>,
  opts: { timeoutMs?: number; model?: string } = {},
): Promise<JevResult | null> {
  const key = findJevKey();
  if (!key) return null;
  if (Object.keys(questions).length === 0) return null;
  const baseURL = (process.env.TYPESAFE_BASE_URL || DEFAULT_BASE_URL).replace(/\/+$/, "");
  const model = opts.model || process.env.TYPESAFE_DEFAULT_MODEL || DEFAULT_MODEL;
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), opts.timeoutMs ?? TIMEOUT_MS);
  try {
    const res = await fetch(`${baseURL}/v1/systemone`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        Authorization: `Bearer ${key.value}`,
      },
      body: JSON.stringify({ model, state, questions }),
      signal: ctrl.signal,
    });
    if (!res.ok) {
      // 本文は記録しない（入力に利用者の語が入っている）。状態だけ残す。
      console.warn(`[jev] HTTP ${res.status} (${res.headers.get("x-typesafe-request-id") ?? "-"})`);
      return null;
    }
    const body = (await res.json()) as unknown;
    const answers = parseJevAnswers(body);
    if (Object.keys(answers).length === 0) return null;
    const b = body as { model?: unknown; usage?: JevResult["usage"] };
    return {
      model: typeof b.model === "string" ? b.model : model,
      answers,
      usage: b.usage,
    };
  } catch (e) {
    console.warn("[jev] unavailable:", (e as Error)?.name ?? "error");
    return null;
  } finally {
    clearTimeout(timer);
  }
}
