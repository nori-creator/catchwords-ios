import { describe, it, expect } from "vitest";
import { forgettingCurve, stabilityOf } from "./srs";
import {
  buildRetentionSeries,
  cardStateAt,
  existsFrom,
  retentionOf,
  type RetentionCard,
  type RetentionEvent,
} from "./retention-series";

/**
 * オーナーの報告した不具合の再現:
 *
 * > 「今日朝は48%で、復習したら70%とかになったけど、**70%の1日前が75%**とかで、
 * >  48%から復習したことによってグラフが変化するようになっていない。」
 *
 * 元の実装は「いまの `last_reviewed_at`」を過去の日にも当てていたので、
 * 復習した瞬間に**過去14日が全部100%**になっていた。ここで守るのは
 * 「**過去は復習で動かない**」の一点。
 */

const DAY = 86400_000;
const NOW = Date.parse("2026-08-20T15:00:00Z");
const iso = (msVal: number) => new Date(msVal).toISOString();

function card(over: Partial<RetentionCard> = {}): RetentionCard {
  return {
    sticker_id: "s1",
    taken_at: iso(NOW - 30 * DAY),
    ease: 2.5,
    interval_days: 3,
    last_reviewed_at: null,
    ...over,
  };
}

describe("existsFrom", () => {
  it("出会った日を存在の起点にする", () => {
    expect(existsFrom(card({ taken_at: iso(NOW - 5 * DAY) }), [])).toBe(NOW - 5 * DAY);
  });

  it("出会った日が無ければ最初の復習、それも無ければ最後の復習", () => {
    const ev: RetentionEvent[] = [
      {
        sticker_id: "s1",
        reviewed_at: iso(NOW - 4 * DAY),
        interval_days_after: 1,
        ease_after: 2.5,
      },
    ];
    expect(existsFrom(card({ taken_at: null }), ev)).toBe(NOW - 4 * DAY);
    expect(existsFrom(card({ taken_at: null, last_reviewed_at: iso(NOW - 2 * DAY) }), [])).toBe(
      NOW - 2 * DAY,
    );
  });

  it("何も分からなければ null(数え続ける)", () => {
    expect(existsFrom(card({ taken_at: null }), [])).toBeNull();
  });
});

describe("cardStateAt", () => {
  const events: RetentionEvent[] = [
    { sticker_id: "s1", reviewed_at: iso(NOW - 5 * DAY), interval_days_after: 1, ease_after: 2.5 },
    { sticker_id: "s1", reviewed_at: iso(NOW - 1 * DAY), interval_days_after: 3, ease_after: 2.6 },
    { sticker_id: "s1", reviewed_at: iso(NOW), interval_days_after: 8, ease_after: 2.7 },
  ];

  it("その日までに終わっていた最後の復習を起点にする", () => {
    const s = cardStateAt(card(), events, NOW - 2 * DAY);
    expect(s?.anchorMs).toBe(NOW - 5 * DAY);
  });

  it("**今日の復習は、昨日の状態を書き換えない**(報告された不具合)", () => {
    const yesterday = cardStateAt(card(), events, NOW - 1.5 * DAY);
    // 今日(NOW)の行があっても、昨日から見た起点は5日前のまま。
    expect(yesterday?.anchorMs).toBe(NOW - 5 * DAY);
    expect(retentionOf(yesterday!, NOW - 1.5 * DAY)).toBeLessThan(100);
  });

  it("未来の日から見た最後の復習は、今日の復習になる", () => {
    const s = cardStateAt(card(), events, NOW + 3 * DAY);
    expect(s?.anchorMs).toBe(NOW);
    // 間隔 8 日 = 安定度 8 日（出題日に 90%）。3日後はまだ高い。
    expect(retentionOf(s!, NOW + 3 * DAY)).toBeGreaterThan(90);
  });

  it("まだ存在しない日は null(平均から外す)", () => {
    expect(cardStateAt(card({ taken_at: iso(NOW - 2 * DAY) }), [], NOW - 10 * DAY)).toBeNull();
  });

  it("1度も復習していない期間は、記憶がまだ無い（安定度 0 = 0%）", () => {
    // オーナー指示 2026-10-02「写真を撮ったときはまだ覚えてないから 0% になるように」。
    const s = cardStateAt(card({ taken_at: iso(NOW - 3 * DAY) }), [], NOW);
    expect(s?.anchorMs).toBe(NOW - 3 * DAY);
    expect(s?.stabilityDays).toBe(0);
    expect(retentionOf(s!, NOW)).toBe(0);
    // 数には入る（平均を下げる）。
    const { series } = buildRetentionSeries({
      cards: [card({ taken_at: iso(NOW - 3 * DAY) })],
      events: [],
      nowMs: NOW,
    });
    const today = series.find((p) => p.day_offset === 0)!;
    expect(today.counted).toBe(1);
    expect(today.avg_retention).toBe(0);
  });

  it("記録が無いのに復習済みの古い行は、いまの状態で補う", () => {
    const s = cardStateAt(
      card({ taken_at: null, last_reviewed_at: iso(NOW - 2 * DAY), interval_days: 4, ease: 2.0 }),
      [],
      NOW,
    );
    expect(s?.anchorMs).toBe(NOW - 2 * DAY);
    expect(s?.stabilityDays).toBeCloseTo(stabilityOf(4, 2.0), 6);
  });
});

describe("retentionOf", () => {
  it("起点が無ければ100", () => {
    expect(retentionOf({ anchorMs: null, stabilityDays: 3 }, NOW)).toBe(100);
  });

  it("起点より前なら100、そこから忘却曲線（`srs.ts` の `forgettingCurve`）で落ちる", () => {
    const s = { anchorMs: NOW, stabilityDays: 2 };
    expect(retentionOf(s, NOW - DAY)).toBe(100);
    expect(retentionOf(s, NOW)).toBe(100);
    // 安定度の日 = 90%（狙いの定着度）。
    expect(retentionOf(s, NOW + 2 * DAY)).toBeCloseTo(90, 4);
    expect(retentionOf(s, NOW + 6 * DAY)).toBeCloseTo(100 * forgettingCurve(6, 2), 6);
  });
  it("安定度が無ければ（未復習）0", () => {
    expect(retentionOf({ anchorMs: NOW - DAY, stabilityDays: 0 }, NOW)).toBe(0);
  });
});

describe("buildRetentionSeries — 報告された不具合", () => {
  /** 5日前にキャッチして、5日前と昨日に復習した語。 */
  const before = {
    cards: [card({ taken_at: iso(NOW - 5 * DAY), interval_days: 3, ease: 2.5 })],
    events: [
      {
        sticker_id: "s1",
        reviewed_at: iso(NOW - 5 * DAY),
        interval_days_after: 1,
        ease_after: 2.5,
      },
      {
        sticker_id: "s1",
        reviewed_at: iso(NOW - 1 * DAY),
        interval_days_after: 3,
        ease_after: 2.5,
      },
    ] as RetentionEvent[],
  };

  it("今日また復習しても、過去の点は1つも動かない", () => {
    const a = buildRetentionSeries({ ...before, nowMs: NOW });

    const after = {
      cards: [card({ taken_at: iso(NOW - 5 * DAY), interval_days: 8, ease: 2.6 })],
      events: [
        ...before.events,
        { sticker_id: "s1", reviewed_at: iso(NOW), interval_days_after: 8, ease_after: 2.6 },
      ],
    };
    const b = buildRetentionSeries({ ...after, nowMs: NOW });

    const past = (s: typeof a.series) => s.filter((p) => p.day_offset < 0);
    expect(past(b.series)).toEqual(past(a.series));

    // 今日の点だけが上がる。これが「復習したら記憶率が上がる」の意味。
    const today = (s: typeof a.series) => s.find((p) => p.day_offset === 0)!.avg_retention!;
    expect(today(b.series)).toBeGreaterThan(today(a.series));
  });

  it("過去の点が100%に張り付かない(元の実装はここで全部100だった)", () => {
    const { series } = buildRetentionSeries({
      cards: [card({ taken_at: iso(NOW - 5 * DAY), interval_days: 8, ease: 2.6 })],
      events: [
        ...before.events,
        { sticker_id: "s1", reviewed_at: iso(NOW), interval_days_after: 8, ease_after: 2.6 },
      ],
      nowMs: NOW,
    });
    // 5日前にキャッチした語なので、数えられる過去の点は -5..-1 の5つ。
    const past = series.filter((p) => p.day_offset < 0 && p.avg_retention != null);
    expect(past.map((p) => p.day_offset)).toEqual([-5, -4, -3, -2, -1]);
    // 復習した**その瞬間**の点(-5 と -1)だけは 100 で正しい。
    // 元の実装は**過去14日が全部** 100 だった。
    expect(past.filter((p) => p.avg_retention! < 100).map((p) => p.day_offset)).toEqual([
      -4, -3, -2,
    ]);
  });

  it("復習の直前は下がりきり、直後に戻る(昨日の谷が残る)", () => {
    const { series } = buildRetentionSeries({ ...before, nowMs: NOW });
    const at = (d: number) => series.find((p) => p.day_offset === d)!.avg_retention!;
    // 5日前に復習(間隔1日=安定度1日) → 昨日までじりじり落ちる
    expect(at(-2)).toBeLessThan(at(-4));
    // 昨日また復習したので、そこで持ち直す
    expect(at(-1)).toBeGreaterThan(at(-2));
  });
});

describe("buildRetentionSeries — 存在しなかった日", () => {
  it("その日にまだ無かった語は平均に入らない", () => {
    const old = card({
      sticker_id: "old",
      taken_at: iso(NOW - 20 * DAY),
      last_reviewed_at: iso(NOW - 10 * DAY),
      interval_days: 1,
      ease: 2.5,
    });
    const fresh = card({ sticker_id: "fresh", taken_at: iso(NOW) });
    const { series } = buildRetentionSeries({ cards: [old, fresh], events: [], nowMs: NOW });

    expect(series.find((p) => p.day_offset === -5)!.counted).toBe(1);
    expect(series.find((p) => p.day_offset === 0)!.counted).toBe(2);
  });

  it("**始めた日より前は返さない**(オーナー指示 2026-08-26)", () => {
    // 「私は英語は昨日から始めたから、グラフは昨日より前は表示しないで。
    //  始めた日から表示させるようにして。」
    const { series } = buildRetentionSeries({
      cards: [card({ taken_at: iso(NOW) })],
      events: [],
      nowMs: NOW,
    });
    // 今日から始めた人の線は今日から。**14日ぶんの空っぽの左側を描かない。**
    expect(series[0].day_offset).toBe(0);
    expect(series.some((p) => p.day_offset < 0)).toBe(false);
    // 頭を落としただけで、残った日の数え方は変えていない。
    expect(series[0].counted).toBe(1);
  });

  it("**途中で 0 になる日は残す**(そこは本当に何も無かった日)", () => {
    // 落とすのは頭の連なりだけ。中を抜くと、線が繋がっているように見える。
    const { series } = buildRetentionSeries({
      cards: [card({ sticker_id: "a", taken_at: iso(NOW - 3 * DAY) })],
      events: [],
      nowMs: NOW,
    });
    expect(series[0].day_offset).toBe(-3);
    expect(series.every((p) => p.counted > 0)).toBe(true);
  });

  it("カードが1枚も無ければ**空**(線の切れ端も出さない)", () => {
    const { series, avg_retention } = buildRetentionSeries({
      cards: [],
      events: [],
      nowMs: NOW,
    });
    expect(avg_retention).toBeNull();
    expect(series).toEqual([]);
  });

  it("前後2週間ぶん、29点を返す", () => {
    const { series } = buildRetentionSeries({ cards: [card()], events: [], nowMs: NOW });
    expect(series).toHaveLength(29);
    expect(series[0].day_offset).toBe(-14);
    expect(series[28].day_offset).toBe(14);
  });
});
