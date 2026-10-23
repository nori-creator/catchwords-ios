/**
 * Word tree (spec §6): the card's extras are a stock of "branches" that
 * unlock one per completed review, so semantically similar words never
 * appear at the same time (interference avoidance).
 *
 * - Branch plan: frozen into stickers.branch_plan at save time. Connection
 *   branches (collocations, extra examples) come first; sibling branches
 *   (synonyms/antonyms) are additionally locked until the 5th unlock.
 * - Unlock count derives from the number of review_history rows — it only
 *   ever grows, so an SM-2 lapse never re-locks a branch.
 */

export type BranchType = "collocation" | "example" | "synonym" | "antonym";

export type Branch = {
  type: BranchType;
  zh: string;
  ja?: string;
};

export type ResolvedBranches = {
  unlocked: Branch[];
  /** Branches still locked (length only — contents stay hidden). */
  lockedCount: number;
  /** The branch this review just revealed (last unlocked), if any. */
  justUnlocked: Branch | null;
  /** Reviews needed until the next branch opens (0 = next review). */
  reviewsUntilNext: number | null;
};

const SIBLING_UNLOCK_AT = 5;

type ExtrasLike =
  | {
      collocations?: string[];
      synonyms?: string[];
      antonyms?: string[];
      examples_extra?: { zh: string; ja: string }[];
    }
  | null
  | undefined;

export function buildBranchPlan(extras: ExtrasLike): Branch[] {
  if (!extras) return [];
  const plan: Branch[] = [];
  for (const c of (extras.collocations ?? []).slice(0, 4)) {
    if (c) plan.push({ type: "collocation", zh: c });
  }
  for (const ex of (extras.examples_extra ?? []).slice(0, 2)) {
    if (ex?.zh) plan.push({ type: "example", zh: ex.zh, ja: ex.ja });
  }
  for (const s of (extras.synonyms ?? []).slice(0, 3)) {
    if (s) plan.push({ type: "synonym", zh: s });
  }
  for (const a of (extras.antonyms ?? []).slice(0, 2)) {
    if (a) plan.push({ type: "antonym", zh: a });
  }
  return plan;
}

function isSibling(b: Branch): boolean {
  return b.type === "synonym" || b.type === "antonym";
}

/**
 * Which branches are open after `reviewCount` completed reviews.
 * One branch unlocks per review; sibling branches stay shut before the
 * 5th unlock even if their position comes up.
 */
export function resolveBranches(plan: Branch[], reviewCount: number): ResolvedBranches {
  const unlocked: Branch[] = [];
  let budget = Math.max(0, reviewCount);
  for (const b of plan) {
    if (budget <= 0) break;
    if (isSibling(b) && reviewCount < SIBLING_UNLOCK_AT) continue;
    unlocked.push(b);
    budget -= 1;
  }
  const lockedCount = plan.length - unlocked.length;
  return {
    unlocked,
    lockedCount,
    justUnlocked:
      unlocked.length > 0 && reviewCount <= plan.length ? unlocked[unlocked.length - 1] : null,
    reviewsUntilNext: lockedCount > 0 ? 1 : null,
  };
}

/** Normalize an unknown JSONB value (stickers.branch_plan) into a Branch[]. */
export function parseBranchPlan(raw: unknown): Branch[] | null {
  if (!Array.isArray(raw)) return null;
  const out: Branch[] = [];
  for (const item of raw) {
    if (!item || typeof item !== "object") continue;
    const r = item as Record<string, unknown>;
    if (typeof r.zh !== "string" || !r.zh) continue;
    const type = r.type;
    if (type !== "collocation" && type !== "example" && type !== "synonym" && type !== "antonym")
      continue;
    out.push({ type, zh: r.zh, ja: typeof r.ja === "string" ? r.ja : undefined });
  }
  return out;
}
