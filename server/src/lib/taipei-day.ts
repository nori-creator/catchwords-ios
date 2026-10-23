/**
 * アプリの「今日」は台湾時間で数える（`YYYY-MM-DD`）。
 *
 * 統計・日記・単語帳・管理画面がそれぞれ同じ1行を写して持っていたので、
 * ここに寄せた（2026-10-01）。
 */
const TAIPEI_DAY = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Taipei" });

export function taipeiDay(at: Date | string = new Date()): string {
  return TAIPEI_DAY.format(typeof at === "string" ? new Date(at) : at);
}

/**
 * アプリの「今日」（台湾の日付）が始まった瞬間を ISO で返す（「今日の復習枚数」などの起点）。
 * 台湾は夏時間が無いので、いつでも `+08:00` の 0:00。
 */
export function startOfAppDay(at: Date | string = new Date()): string {
  return new Date(`${taipeiDay(at)}T00:00:00+08:00`).toISOString();
}
