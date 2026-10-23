/**
 * **写真のどこに写っている物か**を候補に付ける（2026-10-10）。
 *
 * iOS は名前を写真の物の輪郭（端末の Vision が切り出した物）に1つずつ結び付ける。結び付けは
 * 候補ごとの点（`point`、0〜1000 の [x, y]）に一番近い物で決める（`CatchObject.build`）。
 * ところが撮った後の候補（`suggestWords`）は位置を返しておらず、iOS は全部の物を写真の
 * 真ん中（[500, 500]）として扱っていた — 輪郭は**真ん中に近い順に**配られ、AI が名付けた物と
 * 囲まれた物が一致する保証が無かった（コップの名前がスクーターに付く、など）。
 *
 * AI には物ごとに Gemini の枠の形（`box_2d` = [ymin, xmin, ymax, xmax]、0〜1000、左上が原点。
 * Google の画像の理解の資料と同じ形）で答えさせ、ここで:
 * - 形の崩れた枠（4つの数でない・0〜1000 の外・幅や高さが無い）を捨てる
 * - 同じ物（同じ `group`）の呼び方には、その物の最初の枠を配る（並べ替えで先頭が替わっても揃う）
 * - 枠の真ん中を `point`（[x, y]、0〜1000 — 今の iOS がそのまま読む形）にする
 *
 * 枠の無い物は `point` も付けない（iOS は今までどおり真ん中として扱う）。
 */

export type Box2d = [number, number, number, number];

/** 0〜1000 の4つの数で、上が下より上・左が右より左の枠だけを通す。 */
export function validBox2d(raw: unknown): Box2d | null {
  if (!Array.isArray(raw) || raw.length !== 4) return null;
  const n = raw.map((v) => (typeof v === "number" ? v : Number.NaN));
  if (n.some((v) => !Number.isFinite(v) || v < 0 || v > 1000)) return null;
  const [ymin, xmin, ymax, xmax] = n;
  if (ymax <= ymin || xmax <= xmin) return null;
  return [Math.round(ymin), Math.round(xmin), Math.round(ymax), Math.round(xmax)];
}

/** 枠の真ん中（[x, y]、0〜1000）。 */
export function boxCenter([ymin, xmin, ymax, xmax]: Box2d): [number, number] {
  return [Math.round((xmin + xmax) / 2), Math.round((ymin + ymax) / 2)];
}

export function withObjectPoints<T extends { group?: number | null; box_2d?: unknown }>(
  items: readonly T[],
): Array<Omit<T, "box_2d"> & { box_2d?: Box2d; point?: [number, number] }> {
  const byGroup = new Map<number, Box2d>();
  for (const it of items) {
    const box = validBox2d(it.box_2d);
    if (box && typeof it.group === "number" && !byGroup.has(it.group)) byGroup.set(it.group, box);
  }
  return items.map((it) => {
    const { box_2d: raw, ...rest } = it;
    /**
     * **自分の枠が在ればそれ、無ければ同じ物の枠**（2026-10-15 オーナー報告: タブレット・コップ・ペン・
     * ティッシュの4つのタグが全部タブレットの真ん中に重なった）。前は同じ `group` の**最初の枠**を全員に配って
     * いた。モデルが別々の物に同じ番号を付けた回（4つとも group 0）は、4つの枠が全部1つ目の枠に潰れ、
     * タグが1か所に重なる。自分の枠を持つ候補はその枠を使えば、番号の付け間違いが位置まで壊さない。
     * 枠の無い別名（珍奶）は今までどおり同じ物の枠を受け継ぐ。
     */
    const own = validBox2d(raw);
    const box = own ?? (typeof it.group === "number" ? byGroup.get(it.group) : null) ?? null;
    return box ? { ...rest, box_2d: box, point: boxCenter(box) } : rest;
  });
}

/**
 * 位置の付き方のまとめ（`ai_runs` の記録用。語は入れない）。次に「タグが重なる」と言われた時に、
 * モデルが枠を返したか・何個の物に分かれたか・点が何か所に散ったかを後から読める。
 */
export function positionStats(
  items: ReadonlyArray<{ group?: number | null; point?: [number, number] | undefined }>,
): { n: number; groups: number; with_point: number; distinct_points: number } {
  const groups = new Set<number>();
  const points = new Set<string>();
  let withPoint = 0;
  for (const it of items) {
    if (typeof it.group === "number") groups.add(it.group);
    if (it.point) {
      withPoint += 1;
      points.add(it.point.join(","));
    }
  }
  return {
    n: items.length,
    groups: groups.size,
    with_point: withPoint,
    distinct_points: points.size,
  };
}
