/**
 * 「何日続いているか」を数える所。
 *
 * ## 肝: 日にちの計算に時差を持ち込まない
 * これまでは `new Date()`(端末の地方時)を作り、`setUTCDate` で1日戻し、
 * それを台北時間で書式化していた。3つの時間帯が1つの繰り返しの中に混ざる。
 * 日付が変わる前後で1日ずれても、動かして気づける類の間違いではない。
 *
 * **先に台北の暦日(`YYYY-MM-DD`)へ落としてから数える。** そこまで来れば
 * 「1日戻す」はただの暦の計算で、時差はもう関係無い。だからこの関数は
 * 文字列の集合しか受け取らない — 時計を持たないので、試験も素直に書ける。
 *
 * ## 今日がまだ空でも途切れていない
 * 朝いちばんに開いた人の連続を 0 と言ってはいけない。今日の分がまだ無ければ
 * **昨日から**数える。今日も昨日も無いときだけ 0。
 */

/** `YYYY-MM-DD` を1日戻す。暦の計算だけなので時差は関わらない。 */
export function previousDay(dayKey: string): string {
  const [y, m, d] = dayKey.split("-").map((n) => parseInt(n, 10));
  if (!Number.isFinite(y) || !Number.isFinite(m) || !Number.isFinite(d)) return dayKey;
  // UTC で作って UTC で戻す。暦日そのものを動かしたいだけなので、
  // どの時間帯で作るかは結果に影響しない(ずれない側を選ぶ)。
  const t = Date.UTC(y, m - 1, d) - 86_400_000;
  return new Date(t).toISOString().slice(0, 10);
}

/**
 * 続いている日数。
 *
 * @param days   何かをした日の暦日(`YYYY-MM-DD`)。重複していてよい
 * @param today  今日の暦日(呼ぶ側が台北時間で作る)
 * @param maxDays ここで打ち切る。壊れた入力で回り続けないための止め木
 */
export function countStreak(days: Iterable<string>, today: string, maxDays = 366): number {
  const set = new Set(days);
  if (set.size === 0) return 0;
  // 今日がまだ空なら、昨日から数え始める(朝の人を 0 にしない)。
  let cursor = set.has(today) ? today : previousDay(today);
  let n = 0;
  while (set.has(cursor) && n < maxDays) {
    n += 1;
    cursor = previousDay(cursor);
  }
  return n;
}
