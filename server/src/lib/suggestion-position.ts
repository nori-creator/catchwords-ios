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

/**
 * **枠の無い物は、枠だけをもう一度聞く**（2026-10-26 オーナー報告: 「カメラでスキャンした時に物の上に名前のタグが
 * 出ない」。公園の写真で 空・ビル・木・草 のタグが写真の上に格子のように並び、ブランコの写真ではブランコのタグを
 * 押すと人が切り抜かれた）。
 *
 * 原因は端末ではなく AI の答え。`ai_runs` の `positions` を読むと、写真の候補の AI（`gemini-3.5-flash-lite`）は
 * 指示に box_2d を書いても**枠を1つも返さない回がある**（iOS の本番 10 回中 6 回、Android が呼ぶ Lovable の
 * サーバーでも 65 回中 21 回。返す回は全部の物に返し、返さない回は全部に返さない）。枠が無いと iOS は物の場所が
 * 分からず、タグを写真に散らし（`TagPlacement.spreadSpots`）、切り抜きも物を探せない。Android の手の写真は、
 * たまたま枠が返った回だった。
 *
 * 枠の無い物（同じ物の別の物と同じ枠になった物も）だけを、**物を囲む枠を返すだけの短い指示**で同じ AI にもう一度
 * 聞く（Google の画像の理解の資料の物の検出と同じ形: [ymin, xmin, ymax, xmax]、0〜1000）。名前を書き出す長い指示より、
 * 枠だけの指示の方が確かに返る。
 */
export type LocatableItem = {
  headword: string;
  group?: number | null;
  label?: string | null;
  box_2d?: Box2d;
  point?: [number, number];
};

/** 2つの点がこれより近ければ、同じ場所（iOS の `TagPlacement.distinct` の 0.02 と同じ）。 */
const SAME_PLACE = 20;

/**
 * 枠を聞き直す物（`group` の番号）。枠の無い物と、前の物と同じ場所の枠を持つ物（別々の物に同じ枠を書いた回）。
 * 番号の無い候補は1つずつ別の物（iOS の `CatchObject.groups` と同じ）なので、その時は並びの番号を使う。
 */
export function objectsNeedingBoxes(items: readonly LocatableItem[]): number[] {
  const seen = new Set<number>();
  const placed: Array<[number, number]> = [];
  const need: number[] = [];
  items.forEach((it, i) => {
    const key = objectKey(it, i);
    if (seen.has(key)) return;
    seen.add(key);
    const p = it.point;
    if (!p || placed.some((q) => Math.hypot(q[0] - p[0], q[1] - p[1]) <= SAME_PLACE)) {
      need.push(key);
      return;
    }
    placed.push(p);
  });
  return need;
}

function objectKey(it: LocatableItem, index: number): number {
  return typeof it.group === "number" ? it.group : 10_000 + index;
}

/** 枠だけを聞く指示文。物ごとに番号・見出し語・ふだんの呼び名（あれば）を並べる。 */
export function locateInstruction(items: readonly LocatableItem[], keys: readonly number[]): string {
  const lines = keys.map((key) => {
    const names = items
      .filter((it, i) => objectKey(it, i) === key)
      .flatMap((it) => [it.headword, it.label ?? ""])
      .map((s) => s.trim())
      .filter((s, i, all) => s && all.indexOf(s) === i);
    return `- id ${key}: ${names.join(" / ")}`;
  });
  return `この写真の中で、次の物がそれぞれどこに写っているかを答えてください。
${lines.join("\n")}

- 物ごとに、その物**だけ**を囲む枠を box_2d = [ymin, xmin, ymax, xmax]（0〜1000、写真の左上が原点）で。
- 物の前にある物・物の上の人は枠の中心にしない。物そのものを囲む。
- 写っていない物は書かない。
必ずJSONだけを返す。形式: {"boxes":[{"id":0,"box_2d":[ymin,xmin,ymax,xmax]}]}`;
}

/** 聞き直しの答え（`{"boxes":[{"id","box_2d"}]}`）から、番号ごとの枠。形の崩れた物は捨てる。 */
export function readLocatedBoxes(raw: unknown, keys: readonly number[]): Map<number, Box2d> {
  const out = new Map<number, Box2d>();
  const list = (raw as { boxes?: unknown } | null)?.boxes;
  if (!Array.isArray(list)) return out;
  for (const entry of list) {
    const e = entry as { id?: unknown; box_2d?: unknown } | null;
    const id = typeof e?.id === "number" ? e.id : Number(e?.id);
    const box = validBox2d(e?.box_2d);
    if (!box || !keys.includes(id) || out.has(id)) continue;
    out.set(id, box);
  }
  return out;
}

/**
 * 聞き直した枠を物の全部の呼び方に付ける。まだ枠の付いていない物の中心と同じ場所になる枠は使わない
 * （同じ場所に2つのタグは置かない）。
 */
export function withLocatedBoxes<T extends LocatableItem>(items: readonly T[], boxes: Map<number, Box2d>): T[] {
  if (boxes.size === 0) return [...items];
  const taken: Array<[number, number]> = [];
  const keyed = items.map((it, i) => ({ it, key: objectKey(it, i) }));
  const firstPoint = new Map<number, [number, number]>();
  for (const { it, key } of keyed) {
    if (it.point && !boxes.has(key) && !firstPoint.has(key)) firstPoint.set(key, it.point);
  }
  taken.push(...firstPoint.values());
  const use = new Map<number, Box2d>();
  for (const [key, box] of boxes) {
    const c = boxCenter(box);
    if (taken.some((q) => Math.hypot(q[0] - c[0], q[1] - c[1]) <= SAME_PLACE)) continue;
    taken.push(c);
    use.set(key, box);
  }
  return keyed.map(({ it, key }) => {
    const box = use.get(key);
    return box ? { ...it, box_2d: box, point: boxCenter(box) } : it;
  });
}
