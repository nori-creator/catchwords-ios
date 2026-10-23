/**
 * **AI が失敗した時の控え**（オーナー依頼 2026-10-14「すべての AI 機能が失敗したときのバックアップを
 * 作って」）。
 *
 * 2026-10-11 から Google が残高切れ（HTTP 402）で全部の呼び出しを断っていた間、控えを持つ
 * 2つの用途（写真の候補・単語カード）だけが Lovable の口へ切り替わって動き、ほかの用途
 * （項目の作り直し・報告の直し・母語の候補・画像の確認…）は全部失敗した（報告の 500 もこれ）。
 *
 * そこで `getAiFor` が返すモデルを AI SDK の middleware（`wrapLanguageModel`）で包み、
 * **1番手が失敗したら同じ依頼を控えのモデルへもう1回送る**。呼ぶ所（`generateText` など）は
 * 何も変えなくてよく、新しく書いた呼び出しも漏れない。
 *
 * - 控えに回さない失敗: 呼ぶ側が止めた・締め切りが来た（`abortSignal`）。止めた依頼をほかの会社へ
 *   送り直すと、待ち時間の約束（`runAiAttempts` の締め切りなど）を破る。
 * - 控えは1回だけ。控えも失敗したら、その失敗をそのまま返す（1番手の失敗はサーバの記録に残す）。
 * - どちらの呼び出しも `ai_call` に記録される（包む前に `measuredModel` で包んである）ので、
 *   開発者の表で「どれだけ控えに回ったか」が見える。
 */
import { wrapLanguageModel, type LanguageModelMiddleware } from "ai";

type LanguageModelV3 = Parameters<typeof wrapLanguageModel>[0]["model"];
type AnyModel = LanguageModelV3 | string;

/** 控えに回してよい失敗か（止めた・締め切りが来た依頼は回さない）。 */
export function shouldTryBackup(error: unknown, signal?: AbortSignal | null): boolean {
  if (signal?.aborted) return false;
  const name = (error as { name?: unknown } | null)?.name;
  return name !== "AbortError" && name !== "TimeoutError";
}

function shortMessage(e: unknown): string {
  return (e instanceof Error ? e.message : String(e ?? "")).slice(0, 160);
}

/**
 * モデルを、落ちたら `backup()` のモデルへ回す形に包む。`backup` が null を返せばそのまま失敗。
 * `label` はサーバの記録に出す名前（例 `card/section_regen → lovable:google/gemini-2.5-flash`）。
 */
export function withBackupModel<M extends AnyModel>(
  primary: M,
  backup: () => AnyModel | null,
  label = "",
): M {
  if (typeof primary === "string") return primary;
  const pick = (e: unknown, signal: AbortSignal | undefined): LanguageModelV3 | null => {
    if (!shouldTryBackup(e, signal)) return null;
    const b = backup();
    if (!b || typeof b === "string") return null;
    console.warn(`[ai] ${label} failed (${shortMessage(e)}) — trying the backup`);
    return b;
  };
  const middleware: LanguageModelMiddleware = {
    specificationVersion: "v3",
    wrapGenerate: async ({ doGenerate, params }) => {
      try {
        return await doGenerate();
      } catch (e) {
        const b = pick(e, params.abortSignal);
        if (!b) throw e;
        return b.doGenerate(params);
      }
    },
    wrapStream: async ({ doStream, params }) => {
      try {
        return await doStream();
      } catch (e) {
        const b = pick(e, params.abortSignal);
        if (!b) throw e;
        return b.doStream(params);
      }
    },
  };
  return wrapLanguageModel({ model: primary, middleware }) as M;
}

/**
 * ゲートウェイ（`(モデル ID) => モデル`）を包む。出てくるモデルは全部 `withBackupModel`。
 * ほかの道具（`languageModel` など）はそのまま（`measuredGateway` と同じ形）。
 */
export function backedGateway<G extends (modelId: string) => AnyModel>(
  gateway: G,
  backup: () => AnyModel | null,
  label: string,
): G {
  const wrapped = (modelId: string) => withBackupModel(gateway(modelId), backup, label);
  return Object.assign(wrapped, gateway) as unknown as G;
}
