/**
 * **待つ上限を必ず付ける。** 上限を過ぎたら `fallback` を返す（例外にしない）。
 *
 * iPhone の Safari では、返ってこない約束が実際にある（オーナー報告
 * 2026-09-27「iPhone で撮影後に AI 分析が進まない」）:
 *
 * - `navigator.geolocation.getCurrentPosition` … 位置の許可を聞く窓が出て
 *   いる間は `timeout` の指定が数えられず、答えないと成功も失敗も来ない
 * - `indexedDB.open` … 成功も失敗も呼ばれないことがある
 *
 * どちらも「あれば良い」物なので、止まるくらいなら無しで進む。
 */
export function withDeadline<T, F>(work: Promise<T>, ms: number, fallback: F): Promise<T | F> {
  return new Promise((resolve) => {
    let done = false;
    const timer = setTimeout(() => {
      if (done) return;
      done = true;
      resolve(fallback);
    }, ms);
    work.then(
      (v) => {
        if (done) return;
        done = true;
        clearTimeout(timer);
        resolve(v);
      },
      () => {
        if (done) return;
        done = true;
        clearTimeout(timer);
        resolve(fallback);
      },
    );
  });
}
