import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { CANDIDATE_PICK_LOOP, CANDIDATE_PICK_VIA, MAX_CANDIDATE_RANK } from "./funnel-events";

/**
 * **候補を選んだ1回を記録する**（ロードマップ Phase 3.2 の Top-1/Top-3、2026-10-03）。
 *
 * `candidate_picked` の段（`usage_events`、人数・回数のファネル）と、**何番目を選んだか**
 * （`ai_runs`、loop = `candidate_pick`）を1回の呼び出しで両方書く。中身は順位・候補の数・
 * どの道で選んだか（`funnel-events.ts` の `CandidatePickVia`）だけで、**語・写真は送らない**。
 * 集計は `beta-metrics.ts` の `candidateAccuracy`（`/admin/beta` に Top-1 / Top-3 が出る）。
 *
 * `metrics.functions.ts`（段の受け口）は形を変えずに残し、順位はここで受ける。
 */
export const CandidatePickInput = z
  .object({
    via: z.enum(CANDIDATE_PICK_VIA),
    /** 選んだ語が AI の並びで何番目か（1 から）。 */
    rank: z.number().int().min(1).max(MAX_CANDIDATE_RANK),
    /** 並んでいた候補の数。 */
    n: z.number().int().min(1).max(MAX_CANDIDATE_RANK),
  })
  .refine((v) => v.rank <= v.n, "rank must be within n");

/**
 * ファネルの `candidate_picked` に数えるか。写真の候補から選んだ回・母語で調べ直した回は
 * 数える。打った語やスキャンからの語で、選ぶ一覧が無く（1語）そのまま進んだ回は数えない
 * （2026-10-03 より前も、一覧から押した時だけ数えていた）。
 */
export function countsAsFunnelPick(p: { via: string; n: number }): boolean {
  return p.via === "photo" || p.via === "native_search" || p.n > 1;
}

export const logCandidatePick = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => CandidatePickInput.parse(input))
  .handler(async ({ context, data }) => {
    const { supabase, userId } = context;
    await Promise.all([
      // ファネルの「候補を選んだ」は、選ぶ一覧が在った回だけ（今までと同じ数え方）。
      countsAsFunnelPick(data)
        ? supabase.from("usage_events").insert({ user_id: userId, kind: "candidate_picked" })
        : null,
      supabase.from("ai_runs").insert({
        user_id: userId,
        loop: CANDIDATE_PICK_LOOP,
        iterations: 0,
        accepted: data.rank,
        meta: { via: data.via, rank: data.rank, n: data.n },
      }),
    ]);
    return { ok: true };
  });
