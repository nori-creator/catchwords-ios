/**
 * **AI のモデルを包んで、呼んだ1回ずつを記録する**（表と行の形は `ai-call-log.ts`）。
 *
 * `getAiFor` / `getAiAttemptChain`（`ai-provider.server.ts`）が返すモデルを、AI SDK の
 * middleware（`wrapLanguageModel`）で包む。呼ぶ所（`generateText` など）は何も変えなくてよく、
 * 新しく書いた呼び出しも漏れない。
 *
 * - 時間は AI の会社へ頼んでから返事が揃うまで（流す呼び出しは流し終わるまで）
 * - 記録は返事を返した後（`runAfterResponse`）。**利用者の待ち時間には入らない**
 * - 記録の持ち主は要求の鍵から読む（`callerFromAuthHeader`）。ログインした人の要求でなければ
 *   記録しない（`ai_runs.user_id` は口座に結び付いている）
 * - 記録の失敗で AI の呼び出しを落とさない
 */
import { wrapLanguageModel, type LanguageModelMiddleware } from "ai";
import { createIsomorphicFn } from "@tanstack/react-start";
import { runAfterResponse } from "./after-response";
import {
  aiCallErrorCode,
  aiCallModelLabel,
  aiCallRow,
  callerFromAuthHeader,
  type AiCallRecord,
  type AiCallTag,
} from "./ai-call-log";

// 形は `ai` の middleware の型から取る（`@ai-sdk/provider` を直に入れない）。
type LanguageModelV3 = Parameters<typeof wrapLanguageModel>[0]["model"];
type StreamResult = Awaited<ReturnType<NonNullable<LanguageModelMiddleware["wrapStream"]>>>;
type LanguageModelV3StreamPart = StreamResult["stream"] extends ReadableStream<infer P> ? P : never;
type LanguageModelV3Usage = Awaited<
  ReturnType<NonNullable<LanguageModelMiddleware["wrapGenerate"]>>
>["usage"];
type AnyModel = LanguageModelV3 | string;

/** いまの要求の持ち主（server fn の外・試験・ブラウザでは null）。 */
const currentCaller = createIsomorphicFn()
  .server(async (): Promise<string | null> => {
    try {
      const { getRequest } = await import("@tanstack/react-start/server");
      return callerFromAuthHeader(getRequest()?.headers?.get("authorization"), Date.now());
    } catch {
      return null;
    }
  })
  .client(async (): Promise<string | null> => null);

function usageOf(usage: LanguageModelV3Usage | undefined) {
  return {
    tokensIn: usage?.inputTokens?.total,
    tokensOut: usage?.outputTokens?.total,
    reasoning: usage?.outputTokens?.reasoning,
  };
}

/** 記録を返事の後へ預ける。持ち主が分からなければ何もしない。 */
function save(caller: Promise<string | null>, record: AiCallRecord): void {
  void runAfterResponse("ai_call", async () => {
    const userId = await caller;
    if (!userId) return;
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { error } = await supabaseAdmin.from("ai_runs").insert(aiCallRow(userId, record));
    if (error) console.warn("[ai-call] ai_runs insert failed", error.message);
  });
}

function recorder(tag: AiCallTag): LanguageModelMiddleware {
  const base = (model: LanguageModelV3) => ({
    feature: tag.feature,
    task: tag.task,
    // 合言葉のモデル（`latest-flash` など）は呼んだ後に版付きの ID が分かる（`lazyGeminiModel`）。
    model: aiCallModelLabel(tag.provider, model.modelId),
  });
  return {
    specificationVersion: "v3",
    wrapGenerate: async ({ doGenerate, params, model }) => {
      const caller = currentCaller();
      const started = Date.now();
      try {
        const result = await doGenerate();
        save(caller, {
          ...base(model),
          ms: Date.now() - started,
          ok: true,
          ...usageOf(result.usage),
        });
        return result;
      } catch (e) {
        save(caller, {
          ...base(model),
          ms: Date.now() - started,
          ok: false,
          code: aiCallErrorCode(e, params.abortSignal),
        });
        throw e;
      }
    },
    wrapStream: async ({ doStream, params, model }) => {
      const caller = currentCaller();
      const started = Date.now();
      let opened: Awaited<ReturnType<typeof doStream>>;
      try {
        opened = await doStream();
      } catch (e) {
        save(caller, {
          ...base(model),
          ms: Date.now() - started,
          ok: false,
          code: aiCallErrorCode(e, params.abortSignal),
          stream: true,
        });
        throw e;
      }
      // 流し終わった時に1行（読む側が途中でやめた回は残らない — いまは流す呼び出しが無い）。
      let usage: LanguageModelV3Usage | undefined;
      let failed: unknown = null;
      const watch = new TransformStream<LanguageModelV3StreamPart, LanguageModelV3StreamPart>({
        transform(part, controller) {
          if (part.type === "finish") usage = part.usage;
          if (part.type === "error") failed = part.error;
          controller.enqueue(part);
        },
        flush() {
          const ok = failed == null;
          save(caller, {
            ...base(model),
            ms: Date.now() - started,
            ok,
            ...(ok ? usageOf(usage) : { code: aiCallErrorCode(failed, params.abortSignal) }),
            stream: true,
          });
        },
      });
      return { ...opened, stream: opened.stream.pipeThrough(watch) };
    },
  };
}

/** 1つのモデルを包む（文字列の ID はそのまま — この口では使っていない）。 */
export function measuredModel<M extends AnyModel>(model: M, tag: AiCallTag): M {
  if (typeof model === "string") return model;
  return wrapLanguageModel({ model, middleware: recorder(tag) }) as M;
}

/** ゲートウェイ（`(モデル ID) => モデル`）を包む。ほかの道具（`languageModel` など）はそのまま。 */
export function measuredGateway<G extends (modelId: string) => AnyModel>(
  gateway: G,
  tag: AiCallTag,
): G {
  const wrapped = (modelId: string) => measuredModel(gateway(modelId), tag);
  return Object.assign(wrapped, gateway) as unknown as G;
}
