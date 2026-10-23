import { describe, expect, it } from "vitest";
import {
  computeAiModelStats,
  GUEST_FIRST_CATCH_LOOP,
  PICK_ATTRIBUTION_MS,
  type AiStatsRow,
} from "./ai-model-stats";
import { guestRunRows } from "./ai-model-stats.server";

const A = "11111111-1111-4111-8111-111111111111";
const B = "22222222-2222-4222-8222-222222222222";
const FLASH_LITE = "google:gemini-3.5-flash-lite";
const HAIKU = "anthropic:claude-haiku-5-5";
const t0 = Date.UTC(2026, 9, 11, 9);
const at = (ms: number) => new Date(t0 + ms).toISOString();
const opts = { days: 7 as const, mine: false, since: at(-7 * 86_400_000) };

const call = (
  model: string,
  ms: number,
  extra: Record<string, unknown> = {},
  task = "photo_candidates",
): AiStatsRow => ({
  user_id: A,
  loop: "ai_call",
  created_at: at(0),
  meta: { feature: "scan", task, model, ms, ok: true, in: 1000, out: 200, ...extra },
});

describe("computeAiModelStats — speed and outcome per task and model", () => {
  const report = computeAiModelStats(
    [
      call(FLASH_LITE, 2000),
      call(FLASH_LITE, 3000),
      call(FLASH_LITE, 9000, { ok: false, code: "timeout", in: undefined, out: undefined }),
      call(FLASH_LITE, 3000, { ok: false, code: "cancelled" }),
      call(HAIKU, 1500),
      call(HAIKU, 500, { ok: false, code: "http_429" }),
      call(FLASH_LITE, 12000, { feature: "card" }, "card"),
    ],
    opts,
  );

  it("splits by task first, then by model (busiest model first)", () => {
    expect(report.tasks.map((t) => t.task)).toEqual(["photo_candidates", "card"]);
    expect(report.tasks[0].feature).toBe("scan");
    expect(report.tasks[0].models.map((m) => m.model)).toEqual([FLASH_LITE, HAIKU]);
  });

  it("counts a lost hedge as neither a failure nor a timing, and times only answers", () => {
    const lite = report.tasks[0].models[0];
    expect(lite).toMatchObject({ calls: 3, ok: 2, timeouts: 1, failed: 0, cancelled: 1 });
    expect(lite.okPct).toBe(66.7);
    expect(lite.p50).toBe(2000);
    expect(lite.p90).toBe(3000);
    expect(lite.avgIn).toBe(1000);
    // 1000 × $0.30 + 200 × $2.50（100 万トークンあたり）
    expect(lite.costUsd).toBeCloseTo(0.0008, 10);
    const haiku = report.tasks[0].models[1];
    expect(haiku).toMatchObject({ calls: 2, ok: 1, failed: 1 });
    expect(haiku.costUsd).toBeCloseTo(0.0002, 10);
  });

  it("leaves accuracy empty where nothing measures it", () => {
    expect(report.tasks[1].models[0].unusable).toBeNull();
    expect(report.tasks[1].models[0].picks).toBeNull();
  });
});

describe("computeAiModelStats — unusable replies and candidate picks", () => {
  const suggest = (user: string, ms: number, via: string, attempts: unknown[]): AiStatsRow => ({
    user_id: user,
    loop: "capture_suggest",
    created_at: at(ms),
    meta: { ok: true, via, attempts },
  });
  const pick = (user: string, ms: number, via: string, rank?: number): AiStatsRow => ({
    user_id: user,
    loop: "candidate_pick",
    created_at: at(ms),
    meta: { via, ...(rank ? { rank, n: 5 } : {}) },
  });

  const report = computeAiModelStats(
    [
      suggest(A, 0, FLASH_LITE, [{ label: FLASH_LITE, outcome: "ok" }]),
      pick(A, 30_000, "photo", 1),
      suggest(A, 60_000, HAIKU, [
        { label: FLASH_LITE, outcome: "unusable" },
        { label: HAIKU, outcome: "ok" },
      ]),
      pick(A, 90_000, "photo", 3),
      // 一覧に無く、母語で調べ直した（外れ）
      pick(A, 95_000, "native_search"),
      suggest(B, 0, FLASH_LITE, [
        { label: FLASH_LITE, outcome: "ok" },
        { label: HAIKU, outcome: "cancelled" },
      ]),
      // 15 分より後の選択は結び付けない
      pick(B, PICK_ATTRIBUTION_MS + 1, "photo", 1),
      // 打った語・スキャンからの語は精度に入れない
      pick(A, 100_000, "typed", 1),
      {
        user_id: A,
        loop: "card_generate",
        created_at: at(0),
        meta: { ok: true, attempts: [{ label: FLASH_LITE, outcome: "unusable", round: 0 }] },
      },
    ],
    opts,
  );
  const task = (id: string) => report.tasks.find((t) => t.task === id)!;
  const model = (id: string, m: string) => task(id).models.find((x) => x.model === m)!;

  it("rates unusable replies per model from each attempt (cancelled attempts left out)", () => {
    expect(model("photo_candidates", FLASH_LITE).unusable).toEqual({ n: 1, of: 3, pct: 33.3 });
    expect(model("photo_candidates", HAIKU).unusable).toEqual({ n: 0, of: 1, pct: 0 });
    expect(model("card", FLASH_LITE).unusable).toEqual({ n: 1, of: 1, pct: 100 });
  });

  it("credits each pick to the model that answered the user's latest candidates", () => {
    expect(model("photo_candidates", FLASH_LITE).picks).toEqual({
      n: 1,
      top1: 1,
      top3: 1,
      nativeSearch: 0,
      top1Pct: 100,
      top3Pct: 100,
    });
    expect(model("photo_candidates", HAIKU).picks).toEqual({
      n: 2,
      top1: 0,
      top3: 1,
      nativeSearch: 1,
      top1Pct: 0,
      top3Pct: 50,
    });
  });
});

describe("computeAiModelStats — fixed-photo tests", () => {
  it("scores each tested model on the labelled photos (failures count as misses)", () => {
    const test = (model: string, rank: number | null, ms: number, ok = true): AiStatsRow => ({
      user_id: A,
      loop: "ai_test",
      created_at: at(ms),
      meta: {
        task: "photo_candidates",
        model,
        ok,
        ms,
        in: 1000,
        out: 200,
        ...(rank ? { rank } : {}),
      },
    });
    const { tests } = computeAiModelStats(
      [
        test(HAIKU, 1, 1000),
        test(HAIKU, 2, 1200),
        test(HAIKU, null, 9000, false),
        test(FLASH_LITE, 1, 2000),
        test(FLASH_LITE, 1, 2500),
      ],
      opts,
    );
    expect(tests.map((t) => t.model)).toEqual([FLASH_LITE, HAIKU]);
    expect(tests[1]).toMatchObject({
      n: 3,
      ok: 2,
      failed: 1,
      top1: 1,
      top3: 2,
      top1Pct: 33.3,
      top3Pct: 66.7,
    });
    expect(tests[1].p50).toBe(1000);
    expect(tests[0]).toMatchObject({ n: 2, top1Pct: 100, p90: 2500 });
    expect(tests[0].lastAt).toBe(at(2500));
    expect(tests[0].variant).toBeNull();
  });

  it("keeps a different way of calling the same model (Claude without thinking) on its own row", () => {
    const row = (variant?: string): AiStatsRow => ({
      user_id: A,
      loop: "ai_test",
      created_at: at(0),
      meta: {
        task: "photo_candidates",
        model: HAIKU,
        ok: true,
        ms: 900,
        rank: 1,
        ...(variant ? { variant } : {}),
      },
    });
    const { tests } = computeAiModelStats([row(), row("thinking-off"), row("thinking-off")], opts);
    expect(tests.map((t) => [t.variant, t.n])).toEqual(
      expect.arrayContaining([
        [null, 1],
        ["thinking-off", 2],
      ]),
    );
  });

  it("keeps each learning language on its own row, and counts photos that got no answer", () => {
    const row = (lang: string, ok: boolean, rank?: number): AiStatsRow => ({
      user_id: A,
      loop: "ai_test",
      created_at: at(0),
      meta: {
        task: "photo_candidates",
        model: HAIKU,
        lang,
        ok,
        ms: ok ? 900 : 30_000,
        ...(rank ? { rank } : {}),
      },
    });
    const { tests } = computeAiModelStats(
      [row("zh-TW", true, 1), row("zh-TW", false), row("en", true, 2)],
      opts,
    );
    // 時間は答えた写真だけ（30 秒の時間切れは入れず、答えなしの数で出す）。
    expect(tests.map((t) => [t.lang, t.n, t.ok, t.failed, t.top1Pct, t.p90])).toEqual([
      ["en", 1, 1, 0, 0, 900],
      ["zh-TW", 2, 1, 1, 50, 900],
    ]);
  });
});

describe("computeAiModelStats — picks follow the time the candidates were shown", () => {
  const capture = (ms: number, via: string, answeredAt?: number): AiStatsRow => ({
    user_id: A,
    loop: "capture_suggest",
    created_at: at(ms),
    meta: {
      ok: true,
      via,
      attempts: [{ label: via, outcome: "ok" }],
      ...(answeredAt != null ? { at: t0 + answeredAt } : {}),
    },
  });
  const pick = (ms: number, rank: number): AiStatsRow => ({
    user_id: A,
    loop: "candidate_pick",
    created_at: at(ms),
    meta: { via: "photo", rank, n: 5 },
  });
  const picksOf = (rows: AiStatsRow[]) =>
    Object.fromEntries(
      computeAiModelStats(rows, opts)
        .tasks.find((t) => t.task === "photo_candidates")!
        .models.map((m) => [m.model, m.picks?.n ?? 0]),
    );

  it("credits a fast pick to its own capture although that capture's row was written after it", () => {
    // 撮影 B の行は返事の後に書くので 61.5 秒。B の候補から 60.8 秒に選んだ（古い行: 時刻なし）。
    expect(picksOf([capture(0, FLASH_LITE), capture(61_500, HAIKU), pick(60_800, 1)])).toEqual({
      [FLASH_LITE]: 0,
      [HAIKU]: 1,
    });
  });

  it("uses the time the answer was ready when the row has it", () => {
    // 書き込みが 10 秒遅れても、返事ができた時刻（60.0 秒）で比べる。
    expect(
      picksOf([capture(0, FLASH_LITE, 0), capture(70_000, HAIKU, 60_000), pick(60_500, 1)]),
    ).toEqual({ [FLASH_LITE]: 0, [HAIKU]: 1 });
    // 選んだ後に答えた撮影には結び付けない。
    expect(
      picksOf([capture(0, FLASH_LITE, 0), capture(66_000, HAIKU, 65_000), pick(60_500, 1)]),
    ).toEqual({ [FLASH_LITE]: 1, [HAIKU]: 0 });
  });
});

describe("computeAiModelStats — tutorial runs before sign-up", () => {
  const guest = (action: string, attempts: unknown[], ok = true): AiStatsRow => ({
    user_id: "",
    loop: GUEST_FIRST_CATCH_LOOP,
    created_at: at(0),
    meta: { action, ok, ms: 3000, ...(ok ? { via: HAIKU } : {}), attempts },
  });
  const report = computeAiModelStats(
    [
      guest("suggest", [{ label: FLASH_LITE, ms: 2000, outcome: "ok" }]),
      guest("suggest", [
        { label: FLASH_LITE, ms: 3100, outcome: "cancelled" },
        { label: HAIKU, ms: 900, outcome: "ok", startMs: 3000, hedged: true },
      ]),
      guest("card", [
        { label: FLASH_LITE, ms: 8000, outcome: "unusable" },
        { label: HAIKU, ms: 4000, outcome: "ok" },
      ]),
      guest(
        "lesson",
        [
          { label: FLASH_LITE, ms: 30_000, outcome: "timeout", code: "timeout" },
          { label: HAIKU, ms: 200, outcome: "error", code: "http_429" },
        ],
        false,
      ),
      // ログインした人の「選んだ」は、登録前の人の候補には結び付けない。
      {
        user_id: A,
        loop: "candidate_pick",
        created_at: at(1000),
        meta: { via: "photo", rank: 1, n: 5 },
      },
    ],
    opts,
  );
  const model = (task: string, m: string) =>
    report.tasks.find((t) => t.task === task)!.models.find((x) => x.model === m)!;

  it("counts each attempt as one call (an unusable reply still answered)", () => {
    expect(model("tutorial_candidates", FLASH_LITE)).toMatchObject({
      calls: 1,
      ok: 1,
      cancelled: 1,
      p50: 2000,
    });
    expect(model("tutorial_candidates", HAIKU)).toMatchObject({ calls: 1, ok: 1, p50: 900 });
    expect(model("tutorial_card", FLASH_LITE)).toMatchObject({ calls: 1, ok: 1, p50: 8000 });
    expect(model("tutorial_card", FLASH_LITE).unusable).toEqual({ n: 1, of: 1, pct: 100 });
    expect(model("tutorial_lesson", FLASH_LITE)).toMatchObject({ calls: 1, timeouts: 1 });
    expect(model("tutorial_lesson", HAIKU)).toMatchObject({ calls: 1, failed: 1 });
  });

  it("puts the lesson under its own task in the card feature, and links no picks", () => {
    expect(report.tasks.map((t) => [t.task, t.feature])).toEqual([
      ["tutorial_candidates", "scan"],
      ["tutorial_card", "card"],
      ["tutorial_lesson", "card"],
    ]);
    expect(report.tasks.flatMap((t) => t.models).every((m) => m.picks === null)).toBe(true);
  });

  it("reads only guest run keys inside the period", () => {
    const rows = guestRunRows(
      [
        {
          key: "first-catch-run:2026-10-11:ok:a",
          value: { action: "suggest" },
          updated_at: "2026-10-11T09:00:00.000Z",
        },
        // 期間の前
        {
          key: "first-catch-run:2026-10-03:fail:b",
          value: {},
          updated_at: "2026-10-03T01:00:00.000Z",
        },
        // 枠の予約の行
        { key: "first-catch-budget:2026-10-11:global:1", value: {} },
        // 時刻の無い行は鍵の日付
        { key: "first-catch-run:2026-10-10:fail:c", value: { action: "card" } },
      ],
      "2026-10-04T09:00:00.000Z",
    );
    expect(rows.map((r) => [r.loop, r.user_id, r.created_at])).toEqual([
      [GUEST_FIRST_CATCH_LOOP, "", "2026-10-11T09:00:00.000Z"],
      [GUEST_FIRST_CATCH_LOOP, "", "2026-10-10T00:00:00.000Z"],
    ]);
  });
});
