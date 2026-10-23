import { createServerFn } from "@tanstack/react-start";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { z } from "zod";
import type { EntryReportRow, ReportStatus } from "./entry-report";

/**
 * 辞書エラー報告 (A8)。「発音・意味・品詞が違う」をユーザーがその場で
 * 報告 → entry_reports に積み、管理画面のレビューキュー(自己改善パネル)で
 * 人間が確認する。ランダム監査では拾えない実利用者の指摘の受け皿。
 *
 * 2026-10-15: 報告は積むだけでなく、**結果を行に残し、開発者に知らせる**（`entry-report.server.ts`）。
 * 単語の詳細からの報告（項目つき・自動で直す）は `ai.functions.ts` の `reportAndFixSection`。
 * ここは見出し語だけの古い口と、管理画面・iOS の開発者画面の一覧。
 */

export type EntryReportKind = "pronunciation" | "meaning" | "pos" | "other";

const ReportInput = z.object({
  headword: z.string().min(1).max(80),
  kind: z.enum(["pronunciation", "meaning", "pos", "other"]),
  note: z.string().max(500).default(""),
});

export const reportEntry = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => ReportInput.parse(input))
  .handler(async ({ context, data }) => {
    const { supabase, userId } = context;
    const [
      { insertEntryReport, finishEntryReport },
      { getExplanationLanguage },
      { runAfterResponse },
    ] = await Promise.all([
      import("./entry-report.server"),
      import("./ai-provider.server"),
      import("./after-response"),
    ]);
    const reporterLang = await getExplanationLanguage(userId).catch(() => null);
    const id = await insertEntryReport(supabase, {
      userId,
      headword: data.headword,
      kind: data.kind,
      note: data.note,
      reporterLang,
    });
    if (!id) throw new Error("報告を保存できませんでした");
    // 見出し語だけの報告は語の行が分からないので自動では直さない。開発者に知らせて確認待ちに。
    void runAfterResponse("reportEntry: notify", async () => {
      const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
      await finishEntryReport(
        supabaseAdmin,
        {
          reportId: id,
          userId,
          wordId: null,
          headword: data.headword,
          language: null,
          kind: data.kind,
          item: null,
          note: data.note,
          reporterLang,
        },
        {
          status: "needs_review",
          outcome: "見出し語だけの報告（語の行が分からないので自動では直さない）",
        },
      );
    });
    return { ok: true };
  });

export type EntryReport = EntryReportRow;

async function assertAdmin(supabase: unknown, userId: string): Promise<void> {
  const { data: isAdmin, error } = await (
    supabase as {
      rpc: (
        fn: string,
        args: object,
      ) => Promise<{ data: boolean | null; error: { message: string } | null }>;
    }
  ).rpc("has_role", { _user_id: userId, _role: "admin" });
  if (error) throw new Error(error.message);
  if (!isAdmin) throw new Error("Forbidden: admin role required");
}

const ListInput = z
  .object({
    /** `open` = 未対応と確認待ち（既定）/ `all` = 最近の全部（直した物・却下も）。 */
    status: z.enum(["open", "all"]).default("open"),
    limit: z.number().int().min(1).max(200).default(100),
  })
  .default({ status: "open", limit: 100 });

/**
 * 管理画面・iOS の開発者画面用: 報告の一覧(service role・admin限定)。
 * 各行に状態（open / fixed / needs_review / resolved / dismissed）・結果の一言・項目・報告者の言語・語の id。
 */
export const listEntryReports = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => ListInput.parse(input ?? undefined))
  .handler(async ({ context, data }): Promise<EntryReport[]> => {
    await assertAdmin(context.supabase, context.userId);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { listEntryReportRows } = await import("./entry-report.server");
    return listEntryReportRows(supabaseAdmin, { status: data.status, limit: data.limit });
  });

const ResolveInput = z.object({
  id: z.string().uuid(),
  status: z.enum(["open", "resolved", "dismissed"]),
});

/** 管理画面用: 報告を処理済み/却下/未対応に戻す(admin限定)。 */
export const resolveEntryReport = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => ResolveInput.parse(input))
  .handler(async ({ context, data }) => {
    await assertAdmin(context.supabase, context.userId);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { recordReportOutcome } = await import("./entry-report.server");
    await recordReportOutcome(supabaseAdmin, data.id, {
      status: data.status as ReportStatus,
      outcome:
        data.status === "resolved"
          ? "開発者が対応済みにした"
          : data.status === "dismissed"
            ? "開発者が却下した"
            : "開発者が未対応に戻した",
    });
    return { ok: true };
  });

/**
 * 管理画面用: 溜まっている報告を AI に判定させ、確かなものだけ直す(admin限定)。
 *
 * 実体は `lexicon.server.ts: triageEntryReports`。毎日の自己改善からも
 * 同じ関数が呼ばれるので、**手で押したときと自動のときで挙動が違う**
 * ということが起きない。
 */
export const triageEntryReportsNow = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    await assertAdmin(context.supabase, context.userId);
    const lex = await import("./lexicon.server");
    return await lex.triageEntryReports(10);
  });
