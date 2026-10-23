import {
  isMissingColumnError,
  isStatusConstraintError,
  legacyStatus,
  outcomeFromFix,
  type EntryReportRow,
  type ReportOutcome,
  type ReportStatus,
  splitReportNote,
} from "./entry-report";
import { notifyDeveloperOfReport } from "./report-notify.server";

/**
 * `entry_reports` の読み書き（サーバー専用）。**移行前の本番でも落ちない**: 新しい列が無ければ
 * 古い列だけで書き、新しい状態は古い3つに写す（`legacyStatus`）。
 */

type LooseDb = {
  from: (table: string) => {
    insert: (row: Record<string, unknown>) => {
      select: (cols: string) => {
        maybeSingle: () => PromiseLike<{
          data: { id?: string } | null;
          error: { message: string; code?: string } | null;
        }>;
      };
    };
    update: (row: Record<string, unknown>) => {
      eq: (
        col: string,
        v: string,
      ) => PromiseLike<{ error: { message: string; code?: string } | null }>;
    };
    select: (cols: string) => {
      eq: (col: string, v: string) => LooseSelect;
      order: (col: string, o: { ascending: boolean }) => LooseSelect;
    };
  };
};
type LooseSelect = {
  order: (col: string, o: { ascending: boolean }) => LooseSelect;
  limit: (
    n: number,
  ) => PromiseLike<{ data: unknown[] | null; error: { message: string; code?: string } | null }>;
  eq: (col: string, v: string) => LooseSelect;
};

export type NewEntryReport = {
  userId: string;
  headword: string;
  kind: "pronunciation" | "meaning" | "pos" | "other";
  /** `[item:…]` を頭に付けた本文（古い画面と同じ形。項目は別の列にも入れる）。 */
  note: string;
  wordId?: string | null;
  item?: string | null;
  reporterLang?: string | null;
};

/** 報告を1行入れる。失敗しても投げない（報告を入れられないことで、直す道を止めない）。 */
export async function insertEntryReport(db: unknown, r: NewEntryReport): Promise<string | null> {
  const table = (db as LooseDb).from("entry_reports");
  const base = { user_id: r.userId, headword: r.headword, kind: r.kind, note: r.note };
  const full = {
    ...base,
    word_id: r.wordId ?? null,
    item: r.item ?? null,
    reporter_lang: r.reporterLang ?? null,
  };
  try {
    const first = await table.insert(full).select("id").maybeSingle();
    if (!first.error) return first.data?.id ?? null;
    if (!isMissingColumnError(first.error)) {
      console.warn("[report] insert failed:", first.error.message);
      return null;
    }
    const again = await (db as LooseDb)
      .from("entry_reports")
      .insert(base)
      .select("id")
      .maybeSingle();
    if (again.error) console.warn("[report] insert failed:", again.error.message);
    return again.data?.id ?? null;
  } catch (e) {
    console.warn("[report] insert threw:", (e as Error)?.message);
    return null;
  }
}

/** 結果を報告の行に残す（状態・一言・時刻）。列が無ければ状態だけ（古い3つに写して）。 */
export async function recordReportOutcome(
  admin: unknown,
  reportId: string | null | undefined,
  outcome: ReportOutcome & { item?: string | null; wordId?: string | null },
): Promise<void> {
  if (!reportId) return;
  const table = () => (admin as LooseDb).from("entry_reports");
  const now = new Date().toISOString();
  const full: Record<string, unknown> = {
    status: outcome.status,
    outcome: outcome.outcome.slice(0, 500),
    outcome_at: now,
  };
  if (outcome.item) full.item = outcome.item;
  if (outcome.wordId) full.word_id = outcome.wordId;
  try {
    const first = await table().update(full).eq("id", reportId);
    if (!first.error) return;
    if (!isMissingColumnError(first.error) && !isStatusConstraintError(first.error)) {
      console.warn("[report] outcome update failed:", first.error.message);
      return;
    }
    const again = await table()
      .update({ status: legacyStatus(outcome.status) })
      .eq("id", reportId);
    if (again.error) console.warn("[report] outcome update failed:", again.error.message);
  } catch (e) {
    console.warn("[report] outcome update threw:", (e as Error)?.message);
  }
}

/** 開発者に知らせた時刻を残す（列が無ければ何もしない）。 */
async function markNotified(admin: unknown, reportId: string | null | undefined): Promise<void> {
  if (!reportId) return;
  try {
    await (admin as LooseDb)
      .from("entry_reports")
      .update({ notified_at: new Date().toISOString() })
      .eq("id", reportId);
  } catch {
    /* 列が無い・届かない: 知らせたこと自体は済んでいる */
  }
}

export type ReportContext = {
  reportId: string | null;
  userId: string;
  wordId: string | null;
  headword: string;
  language: string | null;
  kind: "pronunciation" | "meaning" | "pos" | "other";
  item: string | null;
  note: string;
  reporterLang: string | null;
};

/**
 * **報告の後始末**: 結果を行に残し、開発者に知らせる。直した側（`reportAndFixSection`）と裏の道
 * （`fixReportInBackground`）の両方がここを通る。失敗しても投げない。
 */
export async function finishEntryReport(
  admin: unknown,
  ctx: ReportContext,
  outcome: ReportOutcome,
): Promise<void> {
  await recordReportOutcome(admin, ctx.reportId, {
    ...outcome,
    item: ctx.item,
    wordId: ctx.wordId,
  });
  const sent = await notifyDeveloperOfReport({
    headword: ctx.headword,
    language: ctx.language,
    kind: ctx.kind,
    item: ctx.item,
    note: ctx.note,
    reporterLang: ctx.reporterLang,
    status: outcome.status,
    outcome: outcome.outcome,
    wordId: ctx.wordId,
    reportId: ctx.reportId,
  });
  if (sent === "sent") await markNotified(admin, ctx.reportId);
}

/**
 * **裏で直す**（記録だけで終わっていた報告 — 無料の人・項目が特定できなかった回）。
 * 直す道そのものは `ai.functions.ts` の `fixReportedWordItem`（その場で直す時と同じ関数）。
 * 項目が無ければ AI に探させ（`locateReportedItem`）、見つからなければ確認待ち。
 * どの結果でも開発者に知らせる。
 */
export async function fixReportInBackground(
  context: { supabase: unknown; userId: string },
  ctx: ReportContext,
): Promise<void> {
  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
  try {
    const ai = await import("./ai.functions");
    let item = ctx.item;
    if (!item && ctx.wordId) {
      item = await ai.locateReportedItemForReport(ctx.wordId, ctx.headword, ctx.language, ctx.note);
    }
    if (!item || !ctx.wordId) {
      await finishEntryReport(supabaseAdmin, ctx, {
        status: "needs_review",
        outcome: ctx.wordId
          ? "間違っている項目を特定できなかった"
          : "語の行が分からない（見出し語だけの報告）",
      });
      return;
    }
    const r = await ai.fixReportedWordItem(context as never, {
      wordId: ctx.wordId,
      item: item as never,
      note: ctx.note,
    });
    await finishEntryReport(supabaseAdmin, { ...ctx, item }, outcomeFromFix({ ...r, item }));
  } catch (e) {
    console.warn("[report] background fix failed:", (e as Error)?.message?.slice(0, 200));
    await finishEntryReport(supabaseAdmin, ctx, {
      status: "needs_review",
      outcome: `裏の直しが失敗: ${((e as Error)?.message ?? String(e)).slice(0, 120)}`,
    });
  }
}

/** 管理画面・iOS の開発者画面の一覧（新しい列が無ければ古い列から組む）。 */
export async function listEntryReportRows(
  admin: unknown,
  opts: { status: "open" | "all"; limit: number },
): Promise<EntryReportRow[]> {
  const db = admin as LooseDb;
  const openStatuses = ["open", "needs_review"];
  const read = async (cols: string) => {
    let q = db.from("entry_reports").select(cols).order("created_at", { ascending: false });
    const res = await q.limit(opts.limit);
    void q;
    q = undefined as never;
    return res;
  };
  const full = await read(
    "id, headword, kind, item, note, status, outcome, reporter_lang, word_id, created_at, outcome_at",
  );
  const rows: Record<string, unknown>[] = [];
  if (!full.error) rows.push(...((full.data ?? []) as Record<string, unknown>[]));
  else if (isMissingColumnError(full.error)) {
    const legacy = await read("id, headword, kind, note, status, created_at");
    if (legacy.error) throw new Error(legacy.error.message);
    rows.push(...((legacy.data ?? []) as Record<string, unknown>[]));
  } else throw new Error(full.error.message);
  return rows
    .map((r) => {
      const split = splitReportNote(String(r.note ?? ""));
      return {
        id: String(r.id),
        headword: String(r.headword ?? ""),
        kind: String(r.kind ?? "other"),
        item: (r.item as string | null | undefined) ?? split.item,
        note: split.note,
        status: (r.status as ReportStatus) ?? "open",
        outcome: (r.outcome as string | null | undefined) ?? null,
        reporter_lang: (r.reporter_lang as string | null | undefined) ?? null,
        word_id: (r.word_id as string | null | undefined) ?? null,
        created_at: String(r.created_at ?? ""),
        outcome_at: (r.outcome_at as string | null | undefined) ?? null,
      } satisfies EntryReportRow;
    })
    .filter((r) => opts.status === "all" || openStatuses.includes(r.status));
}
