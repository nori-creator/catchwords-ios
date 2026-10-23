/**
 * **AI の1回の呼び出しに締め切りを付け、落ちたら別の AI で1回だけやり直す**（監査 2026-10-03）。
 *
 * 公開中のアプリで、チュートリアルの写真の分析が 20〜50 秒かかり、ある回は 4 回続けて
 * 約 45〜50 秒待った末に「もう一度試す」になった。原因の見立て:
 * - 1 回の呼び出しの締め切りが 45 秒で、その中で AI SDK が既定で**2 回まで黙って再送**する
 *   （`maxRetries: 2`、間隔を空けながら）。詰まった相手を 45 秒待ち続けていた。
 * - 締め切りに達しても、別の AI に切り替える道が無かった。
 *
 * ここは通信しない段取りだけ（試験できるように、サーバー専用の物を読み込まない）:
 * 1 回ごとに `timeoutMs` で打ち切り（`AbortSignal` も止める）、だめなら次の候補へ。
 * 全部だめなら `AiAttemptsFailed` を投げ、**何をどれだけ待って、どう落ちたか**を持たせる
 * （記録と、使った回数を数え直すかの判断に使う）。
 *
 * **追いかけ（hedging、2026-10-03 実物確認 run 37105477674）**: `hedgeAfterMs` を渡すと、
 * 1番手が**その時間までに答えなければ**、1番手を待ったまま2番手を**並べて**始め、先に
 * 使える返事をくれた方を取る（負けた方は中断する）。シャッターから候補までが 4.5〜42 秒と
 * ばらついていたのは、1番手（無料枠の Gemini）が詰まった回に 20 秒の締め切りまで待ち、
 * それから2番手を始めていたため。追いかけは**1回だけ**（同時に走るのは最大2つ）、使う枠の
 * 予約は呼ぶ側の1回のまま。1番手がすぐ落ちた時は、今までどおりその場で2番手へ進む。
 */

export type AiAttemptOutcome =
  /** 使える返事が来た。 */
  | "ok"
  /** 締め切りまでに返事が来なかった。 */
  | "timeout"
  /** 返事は来たが形が使えなかった（AI は働いたので、使った回数に数える）。 */
  | "unusable"
  /** 通信・認証・上限・モデル名の誤りなど、返事が来なかった失敗。 */
  | "error"
  /** 追いかけで並べて走らせ、もう片方が先に答えたので中断した。 */
  | "cancelled";

export type AiAttemptRecord = {
  /** 記録用の名前（例 `lovable:google/gemini-3-flash-preview`）。鍵は含めない。 */
  label: string;
  ms: number;
  outcome: AiAttemptOutcome;
  /** 失敗の短い印（長い英文や個人の情報は入れない）。 */
  code?: string;
  /** 回数の上限（429）に当たった時の、どの上限かの印（`attemptQuotaHint`）。 */
  quota?: string;
  /** 依頼の始まりから、この回を始めるまでの ms（追いかけの回は `hedgeAfterMs` 前後）。 */
  startMs?: number;
  /** 1番手を待ったまま並べて始めた回（追いかけ）。 */
  hedged?: boolean;
};

export type AiAttempt<T> = {
  label: string;
  timeoutMs: number;
  run: (signal: AbortSignal) => Promise<T>;
};

export const AI_ATTEMPT_TIMEOUT = "AI_ATTEMPT_TIMEOUT";

export class AiAttemptsFailed extends Error {
  constructor(
    message: string,
    readonly attempts: AiAttemptRecord[],
    readonly lastError: unknown,
    /** 依頼の始まりから失敗が決まるまでの ms（並べて走った回があるので、各回の和ではない）。 */
    readonly ms: number = attempts.reduce((sum, a) => sum + a.ms, 0),
  ) {
    super(message);
    this.name = "AiAttemptsFailed";
  }
  /** どの回も締め切り切れだった。 */
  get timedOut(): boolean {
    return this.attempts.length > 0 && this.attempts.every((a) => a.outcome === "timeout");
  }
  /**
   * 使った回数に数えるか。どの回も**返事を受け取れなかった**（締め切り切れ・通信の失敗）なら
   * 数えない — 利用者が「もう一度試す」を押すたびに枠が2つずつ減らないように。
   */
  get chargeable(): boolean {
    return this.attempts.some((a) => a.outcome === "ok" || a.outcome === "unusable");
  }
}

/** 記録に残す短い印。エラー文の先頭の英数字の記号だけ（中身の文や鍵を残さない）。 */
export function attemptErrorCode(error: unknown): string {
  if (!(error instanceof Error)) return "unknown";
  const status = (error as { statusCode?: unknown }).statusCode;
  if (typeof status === "number") return `http_${status}`;
  const code = error.message.match(/^[A-Z][A-Z0-9_]{2,60}$/)?.[0];
  if (code) return code;
  if (error.name === "AbortError" || error.name === "TimeoutError") return "aborted";
  return error.name && error.name !== "Error" ? error.name.slice(0, 40) : "error";
}

/**
 * **回数の上限（429）に当たった時、どの上限かを短く残す**（実測 2026-10-10: 本番のカード生成が
 * Google の「Too Many Requests」で落ちていた。1分あたりか1日あたりか、無料枠かで直し方が違う）。
 *
 * 返事の本文から**決まった形の所だけ**を拾う: 上限の ID（`quotaId`、例
 * `GenerateRequestsPerDayPerProjectPerModel-FreeTier`）、「Quota exceeded for metric: …, limit: 20,
 * model: …」の名前・値・モデル、「Please retry in 33.1s」の秒。文・鍵・番号は残さない。
 * 拾えなければ `undefined`。
 */
export function attemptQuotaHint(error: unknown): string | undefined {
  const body = responseBodyOf(error) ?? responseBodyOf((error as { cause?: unknown })?.cause);
  if (!body) return undefined;
  const hints = new Set<string>();
  for (const m of body.matchAll(/"quotaId"\s*:\s*"([A-Za-z0-9_-]{1,80})"/g)) hints.add(m[1]);
  for (const m of body.matchAll(
    /Quota exceeded for metric: (?:[\w.-]+\/)?([\w-]{1,80}), limit: (\d{1,12})(?:, model: ([\w.-]{1,60}))?/g,
  )) {
    hints.add([m[1], m[2], m[3]].filter(Boolean).join("/"));
  }
  const retry = body.match(/retry in (\d{1,5}(?:\.\d+)?)s/i)?.[1];
  if (retry) hints.add(`retry_${Math.round(Number(retry))}s`);
  return hints.size > 0 ? [...hints].slice(0, 4).join(" ").slice(0, 200) : undefined;
}

function responseBodyOf(error: unknown): string | undefined {
  const body = (error as { responseBody?: unknown } | null | undefined)?.responseBody;
  return typeof body === "string" && body.length > 0 ? body : undefined;
}

/**
 * 追いかけを始めるまでの ms を環境変数から読む（`AI_HEDGE_AFTER_MS`）。
 * 未設定・読めない値は `fallback`。`0` 以下は「追いかけない」（前の順番どおりの動き）。
 */
export function hedgeAfterFromEnv(raw: string | undefined, fallback: number): number | undefined {
  if (raw == null || raw.trim() === "") return fallback;
  const n = Number(raw);
  if (!Number.isFinite(n)) return fallback;
  return n > 0 ? Math.round(n) : undefined;
}

export type AiAttemptsResult<T> = {
  value: T;
  attempts: AiAttemptRecord[];
  /** 依頼の始まりから使える返事までの ms。 */
  ms: number;
  /** 答えた AI の名前（記録用）。 */
  via: string;
  /** 追いかけの回が走ったか（勝ち負けは問わない）。 */
  hedged: boolean;
};

export async function runAiAttempts<T>(
  attempts: AiAttempt<T>[],
  options: {
    /** 返事は来たが使えなかった失敗か（例: JSON の形が崩れていた）。 */
    isUnusableReply?: (error: unknown) => boolean;
    /** 全部が締め切り切れだったときに投げる印。 */
    timeoutMessage?: string;
    /**
     * 1番手がこの ms までに答えなければ、2番手を並べて始める（1回だけ）。
     * 渡さなければ追いかけない（1番手が落ちてから2番手）。
     */
    hedgeAfterMs?: number;
    now?: () => number;
    onAttemptFailed?: (record: AiAttemptRecord, next: string | null) => void;
    /** 追いかけを始めた時（記録用）。 */
    onHedge?: (label: string, afterMs: number) => void;
  } = {},
): Promise<AiAttemptsResult<T>> {
  const now = options.now ?? (() => Date.now());
  const started = now();
  const records: Array<AiAttemptRecord | undefined> = [];
  const controllers: Array<AbortController | undefined> = [];
  const begins: number[] = [];
  const hedgedFlags: boolean[] = [];
  let lastError: unknown = new Error("NO_AI_ATTEMPT");
  let lastReal: unknown = null;
  let next = 0;
  let running = 0;
  let settled = false;
  let hedgedAny = false;
  let hedgeTimer: ReturnType<typeof setTimeout> | undefined;

  return new Promise<AiAttemptsResult<T>>((resolve, reject) => {
    const compact = () => records.filter((r): r is AiAttemptRecord => !!r);
    const fail = () => {
      settled = true;
      clearTimeout(hedgeTimer);
      const list = compact();
      const allTimedOut = list.length > 0 && list.every((r) => r.outcome === "timeout");
      const message = allTimedOut
        ? (options.timeoutMessage ?? AI_ATTEMPT_TIMEOUT)
        : lastReal instanceof Error
          ? lastReal.message
          : "AI_UNAVAILABLE";
      reject(new AiAttemptsFailed(message, list, lastReal ?? lastError, now() - started));
    };
    const launch = (hedged: boolean): boolean => {
      if (settled || next >= attempts.length) return false;
      const i = next++;
      const attempt = attempts[i];
      const controller = new AbortController();
      controllers[i] = controller;
      const begin = now();
      begins[i] = begin;
      hedgedFlags[i] = hedged;
      if (hedged) hedgedAny = true;
      running++;
      let timedOut = false;
      let timer: ReturnType<typeof setTimeout> | undefined;
      const deadline = new Promise<never>((_, rej) => {
        timer = setTimeout(() => {
          timedOut = true;
          const error = new Error(AI_ATTEMPT_TIMEOUT);
          controller.abort(error);
          rej(error);
        }, attempt.timeoutMs);
      });
      const base = {
        label: attempt.label,
        startMs: begin - started,
        ...(hedged ? { hedged } : {}),
      };
      // 相手が中断に応じなくても、締め切りで必ず先へ進む。
      Promise.race([Promise.resolve().then(() => attempt.run(controller.signal)), deadline])
        .then(
          (value) => {
            running--;
            if (settled) return;
            settled = true;
            clearTimeout(hedgeTimer);
            records[i] = { ...base, ms: now() - begin, outcome: "ok" };
            // 負けた側（まだ走っている回）を止める。返事が後から来ても使わない。
            controllers.forEach((c, j) => {
              if (j === i || !c || c.signal.aborted || records[j]) return;
              records[j] = {
                label: attempts[j].label,
                startMs: begins[j] - started,
                ...(hedgedFlags[j] ? { hedged: true } : {}),
                ms: now() - begins[j],
                outcome: "cancelled",
              };
              c.abort();
            });
            resolve({
              value,
              attempts: compact(),
              ms: now() - started,
              via: attempt.label,
              hedged: hedgedAny,
            });
          },
          (error: unknown) => {
            running--;
            if (settled) return;
            lastError = error;
            const outcome: AiAttemptOutcome = timedOut
              ? "timeout"
              : options.isUnusableReply?.(error)
                ? "unusable"
                : "error";
            if (outcome !== "timeout") lastReal = error;
            const quota = outcome === "timeout" ? undefined : attemptQuotaHint(error);
            const record: AiAttemptRecord = {
              ...base,
              ms: now() - begin,
              outcome,
              code: outcome === "timeout" ? "timeout" : attemptErrorCode(error),
              ...(quota ? { quota } : {}),
            };
            records[i] = record;
            // もう片方がまだ走っているなら、それを待つ。何も走っていなければ次の回へ。
            const willLaunch = running === 0 && next < attempts.length;
            options.onAttemptFailed?.(record, willLaunch ? attempts[next].label : null);
            if (running > 0) return;
            if (!launch(false)) fail();
          },
        )
        .finally(() => {
          clearTimeout(timer);
          if (!controller.signal.aborted) controller.abort();
        });
      return true;
    };
    if (!launch(false)) {
      fail();
      return;
    }
    const hedgeAt = options.hedgeAfterMs;
    if (hedgeAt != null && hedgeAt > 0 && attempts.length > 1) {
      hedgeTimer = setTimeout(() => {
        // 1番手がまだ答えていない（そして2番手をまだ始めていない）時だけ、1回だけ並べる。
        if (settled || running === 0 || next >= attempts.length) return;
        options.onHedge?.(attempts[next].label, hedgeAt);
        launch(true);
      }, hedgeAt);
    }
  });
}
