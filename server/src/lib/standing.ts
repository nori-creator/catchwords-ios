/**
 * **全利用者の中での位置**（iOS の「ほめる演出」、オーナー指示 2026-10-25「あなたはこのアプリの上位何%のユーザーです…
 * この単語を獲得したのは全ユーザーのなかであなたが初めてです」）。
 *
 * 数え方を純粋な関数にして試せるようにする（`standing.test.ts`）。読む所は `standing.functions.ts`。
 *
 * - 比べる相手は「1語以上集めた人」だけ（登録しただけの人を入れると、誰でも上位に見えて数字が嘘になる）。
 * - 順位は「自分より多い人の数 + 1」。同じ数の人は同じ順位（自分に不利に数えない／有利にもしない）。
 * - 上位 % は 順位 ÷ 人数 を切り上げ、1% より小さくはしない（「上位0%」は出さない）。
 */

export type Standing = {
  /** 1 から。 */
  rank: number;
  /** 比べた人数（自分を含む）。 */
  total: number;
  /** 上位何 %（1〜100）。 */
  topPercent: number;
};

/**
 * `counts`: 利用者ごとの数（自分を含んでいてもいなくてもよい）。`mine`: 自分の数。
 * 自分の数が 0 なら比べない（null）。
 */
export function standingOf(
  mine: number,
  counts: Map<string, number>,
  userId: string,
): Standing | null {
  if (mine <= 0) return null;
  let above = 0;
  let total = 1;
  for (const [uid, n] of counts) {
    if (uid === userId || n <= 0) continue;
    total += 1;
    if (n > mine) above += 1;
  }
  const rank = above + 1;
  const topPercent = Math.min(
    100,
    Math.max(1, Math.ceil((rank / total) * 100)),
  );
  return { rank, total, topPercent };
}

/** 行を利用者ごとに数える。 */
export function countByUser(rows: { user_id: string }[]): Map<string, number> {
  const m = new Map<string, number>();
  for (const r of rows) m.set(r.user_id, (m.get(r.user_id) ?? 0) + 1);
  return m;
}

/** 利用者ごとの「使った日」（日付の文字列）の数。同じ日に何回使っても1日。 */
export function distinctDaysByUser(
  rows: { user_id: string; day: string }[],
): Map<string, number> {
  const days = new Map<string, Set<string>>();
  for (const r of rows) {
    let s = days.get(r.user_id);
    if (!s) days.set(r.user_id, (s = new Set()));
    s.add(r.day);
  }
  return new Map([...days].map(([uid, s]) => [uid, s.size]));
}

/** 継続率を比べるのは、使い始めてこの日数以上の人だけ（1日目の人は誰でも 100% になるため）。 */
export const RETENTION_MIN_DAYS = 7;

/**
 * **継続率**（オーナー指示 2026-10-25「継続率が全ユーザーの何位何％タイプも入れて」）:
 * 使い始めた日（台湾の暦日）から今日までの日数のうち、使った日（撮った日か復習した日）の割合（%、0〜100）。
 * 使い始めて `RETENTION_MIN_DAYS` 日未満の人は入れない。
 */
export function retentionByUser(
  activeDays: Map<string, number>,
  startDay: Map<string, string>,
  today: string,
): Map<string, { rate: number; active: number; days: number }> {
  const out = new Map<string, { rate: number; active: number; days: number }>();
  const dayMs = 86_400_000;
  const t = Date.parse(`${today}T00:00:00Z`);
  for (const [uid, start] of startDay) {
    const s = Date.parse(`${start}T00:00:00Z`);
    if (!Number.isFinite(s) || !Number.isFinite(t)) continue;
    const days = Math.floor((t - s) / dayMs) + 1;
    if (days < RETENTION_MIN_DAYS) continue;
    const active = Math.min(days, activeDays.get(uid) ?? 0);
    if (active <= 0) continue;
    out.set(uid, { rate: Math.round((active / days) * 100), active, days });
  }
  return out;
}
