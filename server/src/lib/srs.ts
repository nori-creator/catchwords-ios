/**
 * 復習の間隔を決める計算と、忘却曲線。**FSRS（難しさ・安定度・思い出せる確率）**。
 *
 * ## なぜ別ファイルにしたか
 * これは `reviews.functions.ts` の中にあった。あのファイルは
 * `createServerFn` と Supabase を読み込むので、**この計算だけを取り出して
 * 確かめることができない**。アプリでいちばん間違えたら痛い計算 —
 * 間違えても誰も気づかないまま「いつ出すか」が狂い続ける計算 — が、
 * 試しようのない場所に置かれていた。
 *
 * ここには外の世界に触れるものを一切入れないこと。入れた瞬間に、
 * また試せなくなる。
 *
 * ---
 *
 * # 2026-10-02 SM-2 から FSRS へ（オーナー指示「単語のアルゴリズムを正確に改善したい」）
 *
 * > 「復習を何回もして何回も正解することによって、グラフの角度が変わるようにしたい。
 * >  より滑らかになって復習の頻度が落ちる。長期記憶でも復習で一度間違えたらその傾きが
 * >  また少し急になって復習する頻度が増える。復習した期間・正解した連続数・最初に
 * >  覚えてからどれぐらい経ってるかを元に最適な復習時期と、その単語の記憶の%を出したい」
 * > 「写真を撮ったときはまだ覚えてないから０％になるように」
 *
 * SM-2（1987 年の決め打ちの式）はこれができない: 間隔は ease 倍に伸びるだけで、
 * 忘れ方そのものは変わらず、間違えると間隔が 1 日へ戻るだけだった。
 * FSRS は語ごとに **D（難しさ 1〜10）・S（安定度 = 思い出せる確率が 90% まで落ちる
 * までの日数）** を持ち、正解のたびに S が伸び（曲線がなだらかになる）、間違えると
 * S が縮む（曲線が急になり、次の復習が早く来る）。Anki が採用している式で、
 * 約1万人・約7億件の復習記録から既定値が決まっている（`docs/memory-algorithm-options.md`
 * の A2）。式と既定値は MIT の `ts-fsrs`（FSRS-6、21 個の重み）をそのまま使う —
 * 式を写すと、更新のたびにここだけ古くなる。
 *
 * ## DB の列はそのまま（移行なし）
 *
 * | 列 | いまの意味 |
 * |---|---|
 * | `interval_days` | **S（安定度・日）**。狙いの定着度 90% で出すとき FSRS の間隔は S そのものなので、「次に出すまでの日数」と同じ数になる。列は整数なので、小数は四捨五入し 1 日を下限にする（`storedStability`）。**0 = まだ一度も復習していない**。 |
 * | `ease` | **D を 1.3〜3.0 に写したもの**（`easeToDifficulty` / `difficultyToEase`、一次の対応: ease 3.0 ↔ D 1、ease 1.3 ↔ D 10）。SM-2 の ease と同じ向き（大きいほど覚えやすい）。 |
 * | `repetitions` | 連続で正解した回数（間違えると 0）。出題形式（`modeFor`）に使う。 |
 * | `last_reviewed_at` | 記憶の起点。null なら未復習。 |
 *
 * 既存の値はそのまま読める: SM-2 の間隔は「ease 2.5 の語が出題日に 90%」になるように
 * 安定度を合わせてあったので（2026-09-16）、間隔をそのまま S と読んでも**出題日の値は
 * 90% のまま**。曲線の形だけが指数からべき関数に変わる（遅れた語は少し高く出る）。
 *
 * ## 採点 1〜5 → FSRS の評価
 *
 * 正解 5、ぼかしを見たら −1、8 秒超で −1、ヒント 2、不正解 1（`reviews.functions.ts`）。
 *
 * | 採点 | 評価 |
 * |---|---|
 * | 3 未満 | Again（思い出せなかった） |
 * | 3・4 | Hard（思い出せたが、ぼかし・時間切れ・ヒントの助けがあった） |
 * | 5 | Good |
 *
 * **Easy は使わない。** 4 択で速く当てたことは「簡単だった」の証拠にならない
 * （認識は想起より易しい）。Easy の初期安定度は 8.3 日で、証拠の無い語を遠くへ
 * 飛ばしてしまう。「かんたん」の答え方をアプリが持ったときに足す。
 *
 * ## 撮った直後は 0%
 *
 * 未復習（`interval_days = 0` / `last_reviewed_at = null`）の語は、まだ記憶が
 * 始まっていない: `retentionNow` は 0 を返し、段は「忘れかけ」。最初の復習で
 * 評価に応じた初期安定度（Good 2.3 日・Hard 1.3 日・Again 0.2 日→1 日）が付く。
 *
 * ## 間違えたとき
 *
 * SM-2 は「明日もう一度」の決め打ちだった。FSRS は忘れた後の安定度
 * `S' = w11·D^(−w12)·((S+1)^w13 − 1)·e^(w14·(1−R))`（S を超えない）を使う —
 * 長くもっていた語ほど学び直しも速い（Ebbinghaus の節約）。間隔 90 日の語を
 * 間違えると 4 日ほど、若い語は 1 日（下限）で戻ってくる。
 *
 * ---
 *
 * # 2026-10-03 4択の正解で記憶を言い過ぎない（監査「6回正解で次が3年後」）
 *
 * FSRS の既定の重みは、Anki の**自分で思い出す**カード（表を見て裏を思い出す）の
 * 記録から作られている。このアプリの復習は**4択で見分ける**問い（`LightModeCard`。
 * `modeFor` の形式は画面では使われず、採点はどれも 4択）。見分けられることは
 * 思い出せることより易しく（Kang, McDermott & Roediger 2007: 4択の練習より
 * 短答の練習の方が長くもつ）、当てずっぽうでも 25% 当たる。それなのに正解を
 * 「思い出せた」と同じだけ数えていたので、予定どおり 6 回正解すると
 * 2 → 11 → 46 → 163 → 497 → **1346 日（3.7 年）**になり、% は言い過ぎ、
 * 語は復習から消えていた。
 *
 * ## 直し方（2つ、どちらも控えめな方へ）
 *
 * 1. **4択の正解は、安定度の伸びを半分にする**（`CHOICE_GAIN` 0.5）。
 *    FSRS の正解後の安定度は `S' = S·(1 + (SInc − 1)·w15)`（w15 は Hard のときだけ
 *    0.60、ほかは 1）と、**伸びの分（SInc − 1）に係数を掛ける形**で「弱い正解」を
 *    表している。同じ形で、4択の正解は伸びの分に 0.5 を掛ける — FSRS 自身の Hard
 *    （0.60）より少し弱い証拠と見なす（当てずっぽうの 25% の分）。Hard（ぼかし・
 *    時間切れ）ならさらに w15 が掛かる（0.30）。難しさ D の動きはこれまでどおり
 *    評価で決める（正解を一律 Hard にすると D が上がり続け、「難しい語」と
 *    「見分けただけの語」の区別が消えるのでしない）。
 * 2. **間隔の上限 180 日**（`MAX_INTERVAL_DAYS`。FSRS の既定は 100 年、Anki の
 *    「最大間隔」の設定と同じもの）。見分けただけの証拠で半年より先を約束しない
 *    — 半年に 1 回は顔を見せる。**読むときにも 180 日で頭を打つ**（`stabilityOf`）
 *    ので、もう DB に入っている長い間隔は一括で書き換えずに、% の表示・次の
 *    計算・出題（`effectiveDueMs`: 最後の復習から 180 日で期限が来た扱い）で
 *    180 日として働く。採点し直した時に 180 日以下の値が書かれる。
 *
 * 予定どおり Good を重ねると 2 → 6 → 17 → 42 → 96 → **180（上限）**。
 * 最初の復習（未復習から）はこれまでどおり（Good 2 日・Hard 1 日・Again 1 日）、
 * 間違えたときの縮み方もこれまでどおり。
 *
 * **思い出す形の答え（話す・打つ）を採点するようになったら** `evidence: "recall"`
 * を渡す: 伸びは FSRS のまま（半分にしない）。上限 180 日はどちらにも掛かる —
 * DB に「どの形で答えたか」の列が無く、読むときに見分けられないため（列を足すのは
 * 移行が要るので別の判断）。
 *
 * 出典: open-spaced-repetition/ts-fsrs（MIT）、
 * https://github.com/open-spaced-repetition/fsrs4anki/wiki/The-Algorithm 、
 * `docs/memory-algorithm-options.md` の「2026-10-03」
 */

import { FSRSAlgorithm, computeDecayFactor, default_w } from "ts-fsrs";

export type SrsState = {
  /** 覚えやすさ 1.3〜3.0（FSRS の難しさ D を写したもの。大きいほど覚えやすい）。 */
  ease: number;
  /** 安定度 S（日）= 次に出すまでの日数。**0 = 未復習**。 */
  interval_days: number;
  /** 連続で正解した回数。間違えると 0 に戻る。 */
  repetitions: number;
};

/** 間違いと見なす境目。3未満は「思い出せなかった」。 */
export const LAPSE_SCORE = 3;
/** ease の下限（= 難しさ D 10）。 */
export const MIN_EASE = 1.3;
/** ease の上限（= 難しさ D 1）。SM-2 の ease には上限が無かったので、古い値は 3.0 に丸める。 */
export const MAX_EASE = 3.0;
/** 列は整数なので 1 日が下限（「明日」より早くは出さない）。 */
export const MIN_INTERVAL_DAYS = 1;
/**
 * 間隔（= 安定度）の上限。**180 日**（2026-10-03。冒頭の注）。4択で見分けただけの
 * 証拠で、半年より先の約束はしない。読むとき（`stabilityOf`）も書くとき
 * （`storedStability`）もこれで頭を打つ。
 */
export const MAX_INTERVAL_DAYS = 180;
/** FSRS の計算そのものの上限（ts-fsrs の既定 100 年）。上限は外で `MAX_INTERVAL_DAYS` を掛ける。 */
const FSRS_MAX_INTERVAL_DAYS = 36500;
/**
 * 4択の正解で、安定度の伸びの分（`S' − S`）に掛ける係数（2026-10-03。冒頭の注）。
 * FSRS の Hard の係数 w15（0.60）と同じ形で、それより少し弱い。
 */
export const CHOICE_GAIN = 0.5;

/**
 * 答えの証拠の強さ。
 * - `choice`: 4択で見分けた（いまの復習はすべてこれ）。伸びは `CHOICE_GAIN` 倍。
 * - `recall`: 自分で思い出して話した・打った。伸びは FSRS のまま。
 */
export type SrsEvidence = "choice" | "recall";

/**
 * 狙いの定着度。**出題日にこれくらい残っているようにする。**
 * SuperMemo / Anki / FSRS と同じ 0.9（90%）。FSRS の S はこの値で定義されて
 * いるので、出す日 = S の日。
 */
export const TARGET_RETENTION = 0.9;

/** FSRS-6 の既定の重み。学習の段（短期の学び直し）は持たないので長期の式だけ使う。 */
const fsrs = new FSRSAlgorithm({
  w: [...default_w],
  request_retention: TARGET_RETENTION,
  enable_short_term: false,
  enable_fuzz: false,
  maximum_interval: FSRS_MAX_INTERVAL_DAYS,
});

/** べき関数の忘却曲線の定数（FSRS-6: decay = −w20、factor = 0.9^(1/decay) − 1）。 */
const { decay: DECAY, factor: FACTOR } = computeDecayFactor(default_w);

const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));

/** FSRS の評価。1 = Again（思い出せなかった）、2 = Hard、3 = Good。Easy（4）は使わない（上の注）。 */
export type SrsRating = 1 | 2 | 3;

/** 採点 1〜5 → 評価。 */
export function ratingOf(score: number): SrsRating {
  if (score < LAPSE_SCORE) return 1;
  if (score >= 5) return 3;
  return 2;
}

/** ease 1.3〜3.0 → 難しさ D 10〜1（一次。範囲の外は端に寄せる）。 */
export function easeToDifficulty(ease: number): number {
  const e = clamp(Number.isFinite(ease) ? ease : 2.5, MIN_EASE, MAX_EASE);
  return 1 + (9 * (MAX_EASE - e)) / (MAX_EASE - MIN_EASE);
}

/** 難しさ D 1〜10 → ease 3.0〜1.3（`easeToDifficulty` の逆）。 */
export function difficultyToEase(difficulty: number): number {
  const d = clamp(Number.isFinite(difficulty) ? difficulty : 5, 1, 10);
  return MAX_EASE - ((d - 1) * (MAX_EASE - MIN_EASE)) / 9;
}

/** 安定度を列に入れる形（整数の日・1 以上）。 */
export function storedStability(stability: number): number {
  if (!Number.isFinite(stability)) return MIN_INTERVAL_DAYS;
  return clamp(Math.round(stability), MIN_INTERVAL_DAYS, MAX_INTERVAL_DAYS);
}

/**
 * 採点(0〜5)から次の状態を出す。
 *
 * - 未復習（`interval_days` 0）: 評価に応じた初期の D・S（FSRS の `init_*`）。
 * - 復習済み: 前回からの経過日数で「答える直前に思い出せる確率 R」を出し、
 *   正解なら S を伸ばす（R が低いほど・D が小さいほど大きく伸びる。Hard は w15 で控えめ）、
 *   間違えたら S を縮める。D は評価で動き、平均へ少し戻る（mean reversion）。
 *
 * `elapsedDays` が分からないときは予定どおり（経過 = S、R = 90%）と見なす。
 * 同じ日に二度答えても R ≈ 1 なので S はほとんど動かない（二重採点に強い）。
 */
export function nextSrs(
  prev: SrsState,
  score: number,
  opts: {
    /** 前の復習から実際に経った日数（分かる時だけ）。 */
    elapsedDays?: number | null;
    /** 答えの証拠の強さ。既定は `choice`（4択。いまの復習はすべてこれ）。 */
    evidence?: SrsEvidence;
  } = {},
): SrsState {
  const rating = ratingOf(score);
  const learned = prev.interval_days > 0;
  const memory = learned
    ? { difficulty: easeToDifficulty(prev.ease), stability: stabilityOf(prev.interval_days) }
    : null;
  const elapsed = learned ? Math.max(0, opts.elapsedDays ?? stabilityOf(prev.interval_days)) : 0;
  const next = fsrs.next_state(memory, elapsed, rating);
  let stability = next.stability;
  // 4択の正解は伸びの分を半分に（FSRS の Hard の w15 と同じ形。冒頭の注）。
  // 未復習からの初期値と、間違えたときの縮み方には掛けない。
  if (memory && rating > 1 && (opts.evidence ?? "choice") === "choice") {
    stability = memory.stability + (next.stability - memory.stability) * CHOICE_GAIN;
  }
  return {
    ease: difficultyToEase(next.difficulty),
    interval_days: storedStability(stability),
    repetitions: rating === 1 ? 0 : prev.repetitions + 1,
  };
}

/**
 * 記憶の安定度(日)。**列の `interval_days` そのもの**（0 = 未復習 = 安定度なし）を
 * `MAX_INTERVAL_DAYS`（180 日）で頭打ちにしたもの。2026-10-03 より前に書かれた
 * 長い間隔（4択の正解だけで数年）は、DB を書き換えずに**ここで 180 日として読む**
 * — % の表示も、次の間隔の計算も、これを通る。
 *
 * 第2引数は以前の `S = 間隔 × ease × K` の名残で、呼ぶ側の形を変えないために
 * 残してある。難しさは次の S の伸び方に効き、いまの曲線の形には効かない（FSRS）。
 */
export function stabilityOf(interval_days: number, _ease?: number): number {
  if (!Number.isFinite(interval_days) || interval_days <= 0) return 0;
  return clamp(interval_days, MIN_INTERVAL_DAYS, MAX_INTERVAL_DAYS);
}

/**
 * 実際に出題する時刻（ミリ秒）。`due_at` と「最後の復習 + 180 日」の早い方。
 *
 * 2026-10-03 より前に書かれた `due_at` は数年先のことがある（4択の正解だけで
 * 伸びた間隔）。DB を一括で書き換えずに、読むときにここで上限を掛ける。
 * どちらも無ければ null（出題の予定が無い）。
 */
export function effectiveDueMs(
  dueAt: string | null | undefined,
  lastReviewedAt: string | null | undefined,
): number | null {
  const due = dueAt ? new Date(dueAt).getTime() : NaN;
  const last = lastReviewedAt ? new Date(lastReviewedAt).getTime() : NaN;
  const capped = Number.isFinite(last) ? last + MAX_INTERVAL_DAYS * 86400_000 : NaN;
  if (Number.isFinite(due) && Number.isFinite(capped)) return Math.min(due, capped);
  if (Number.isFinite(due)) return due;
  // 期限が無い札は今まで通り出題の予定なし（最後の復習だけで期限を作らない）。
  return null;
}

/** `effectiveDueMs` の ISO 文字列版（画面に出す「次の復習日」用）。 */
export function effectiveDueIso(
  dueAt: string | null | undefined,
  lastReviewedAt: string | null | undefined,
): string | null {
  const ms = effectiveDueMs(dueAt, lastReviewedAt);
  return ms == null ? null : new Date(ms).toISOString();
}

/**
 * 「いま出せる札」を DB で選ぶ PostgREST の `or` 条件（`.or(...)` にそのまま渡す）。
 * `due_at <= 今` か、`last_reviewed_at <= 今 − 180 日`（`effectiveDueMs` と同じ規則）。
 * どちらも `due_at` のある札だけ（期限の無い札は今まで通り出さない）。
 */
export function dueNowOrFilter(nowMs: number): string {
  const nowIso = new Date(nowMs).toISOString();
  const staleIso = new Date(nowMs - MAX_INTERVAL_DAYS * 86400_000).toISOString();
  return `due_at.lte."${nowIso}",and(due_at.not.is.null,last_reviewed_at.lte."${staleIso}")`;
}

/**
 * 忘却曲線（0〜1）。FSRS-6 のべき関数 `R = (1 + FACTOR·t/S)^DECAY`。
 * 学習者全体の平均は指数より**べき関数**に近い（Wixted & Ebbesen 1991）。
 * 安定度が無い（未復習）なら 0。
 */
export function forgettingCurve(elapsedDays: number, stability: number): number {
  if (!(stability > 0)) return 0;
  if (!(elapsedDays > 0)) return 1;
  return clamp(Math.pow(1 + (FACTOR * elapsedDays) / stability, DECAY), 0, 1);
}

/**
 * 保持率が `r`（0〜1）まで落ちるのは起点から何日後か（`forgettingCurve` の逆）。
 * 安定度が無ければ 0（もう来ている）。
 */
export function daysUntilRetention(stability: number, r: number): number {
  if (!(stability > 0)) return 0;
  const rr = clamp(r, 1e-6, 1);
  return Math.max(0, (stability * (Math.pow(rr, 1 / DECAY) - 1)) / FACTOR);
}

/**
 * いまの定着度(0〜100)。
 *
 * `lastReviewMs` は**最後に復習した時刻**。null（未復習）か `interval_days` が 0 なら
 * まだ覚えていない語なので **0**（オーナー指示 2026-10-02「写真を撮ったときはまだ
 * 覚えてないから 0% になるように」）。復習の直後は 100。
 */
export function retentionNow(
  interval_days: number,
  _ease: number,
  lastReviewMs: number | null,
  nowMs: number,
): number {
  const s = stabilityOf(interval_days);
  if (s <= 0 || lastReviewMs == null) return 0;
  const dt = (nowMs - lastReviewMs) / 86400_000;
  if (dt <= 0) return 100;
  return Math.max(0, Math.min(100, 100 * forgettingCurve(dt, s)));
}

export type ReviewMode = "recognition" | "listening" | "reverse" | "production";

/**
 * 何回目の復習かで出題形式を変える。
 * 見て分かる → 聞いて分かる → 意味から言える → 使える、の順に上げていく。
 */
export function modeFor(repetitions: number): ReviewMode {
  if (repetitions <= 1) return "recognition";
  if (repetitions <= 3) return "listening";
  if (repetitions <= 5) return "reverse";
  return "production";
}
