import { stabilityOf } from "./srs";

/**
 * 記憶レベル(2026-07-25 再設計)。
 * 信号3色では「撮った直後に覚えている」と「1ヶ月後も覚えている」が
 * 区別できない — 記憶率×間隔から6段階に分け、色は連続したスケールにする。
 * どの画面でも同じ関数を使う(復習一覧・カードバッジ・忘却曲線モーダル)。
 */

export type MemoryLevelInfo = {
  /** 0(忘れかけ)〜5(はっきり) */
  level: 0 | 1 | 2 | 3 | 4 | 5;
  /** 既定(日本語)のラベル。表示は i18n の memory.level<N> を優先する。 */
  label: string;
  /** i18n キー(memory.level0 … memory.level5)。 */
  labelKey: string;
  /** 塗り(バー・帯グラフ用) */
  bar: string;
  /** テキスト色 */
  text: string;
  /** バッジ用の薄い背景 */
  chip: string;
  dot: string;
};

/**
 * 記憶の6段階。**色は素の Tailwind の番号ではなくトークンで持つ。**
 *
 * 以前は `text-red-600` / `bg-red-100 text-red-700` のように直に書いていた。
 * これには2つの問題があった:
 *  ・**暗いテーマに一切追従しない。** 明るい前提の固定色なので、暗い面では
 *    薄桃色の塊が浮くだけになる(テーマを6つ持っているのに1つ分しか無い)。
 *  ・11px の文字として 2.97〜4.18:1 しか無く、本文の下限 4.5:1 を割っていた。
 *
 * `mem-lv-N` を付けると `--mem` がその段の色になり、`mem-text` / `mem-bar` /
 * `mem-chip` がそれぞれの役目で使う。明暗の値は styles.css 側で持つ。
 */
const LEVELS: MemoryLevelInfo[] = [
  {
    level: 0,
    label: "忘れかけ",
    labelKey: "memory.level0",
    bar: "mem-lv-0 mem-bar",
    text: "mem-lv-0 mem-text",
    chip: "mem-lv-0 mem-chip",
    dot: "🔴",
  },
  {
    level: 1,
    label: "あやうい",
    labelKey: "memory.level1",
    bar: "mem-lv-1 mem-bar",
    text: "mem-lv-1 mem-text",
    chip: "mem-lv-1 mem-chip",
    dot: "🟠",
  },
  {
    level: 2,
    label: "うろ覚え",
    labelKey: "memory.level2",
    bar: "mem-lv-2 mem-bar",
    text: "mem-lv-2 mem-text",
    chip: "mem-lv-2 mem-chip",
    dot: "🟡",
  },
  {
    level: 3,
    label: "薄れぎみ",
    labelKey: "memory.level3",
    bar: "mem-lv-3 mem-bar",
    text: "mem-lv-3 mem-text",
    chip: "mem-lv-3 mem-chip",
    dot: "🟢",
  },
  {
    level: 4,
    label: "覚えている",
    labelKey: "memory.level4",
    bar: "mem-lv-4 mem-bar",
    text: "mem-lv-4 mem-text",
    chip: "mem-lv-4 mem-chip",
    dot: "💚",
  },
  {
    level: 5,
    label: "はっきり",
    labelKey: "memory.level5",
    bar: "mem-lv-5 mem-bar",
    text: "mem-lv-5 mem-text",
    chip: "mem-lv-5 mem-chip",
    dot: "🔵",
  },
];

/**
 * **画面に出る数は1つだけ: 「いま思い出せる確率」(0〜100%)。**
 *
 * （オーナー指示 2026-09-23「ユーザーが混乱しないように、単語の数値は
 *  1つに統一したい」／`PRODUCT.md`「語に出す数は、いま思い出せる確率。
 *  あいまいな熟練度の % ではない」）
 *
 * 以前は2つの % があった:
 *  ・バッジ・一覧 … **記憶の強さ**（定着度 × 熟し。2026-09-16〜）
 *  ・忘却曲線の縦軸 … **いま思い出せる見込み**（定着度）
 * 同じ語なのに、右上は 70%、グラフの今日の点は 97%、と食い違っていた。
 *
 * いまは**どこでも定着度そのもの**を出す。段（色と名前）も同じ数から
 * 決めるので、**段が上がれば % も必ず上がる**（2026-09-16 の約束は残る）。
 *
 * 「どれだけ長くもつか」は % にしない。次の復習の日（Jev が決める間隔）
 * として別に出す。2つ目の % を作らないため。
 *
 * | 語 | 定着度 = 画面の % | 段 |
 * |---|---|---|
 * | 撮っただけでまだ復習していない | **0%** | 忘れかけ |
 * | 復習した直後（どの語も） | 100% | はっきり |
 * | 出題日（狙いどおり） | 90% | 覚えている |
 * | 出題日を大きく過ぎた | 60% | うろ覚え |
 *
 * 撮った直後が 0% なのはオーナー指示 2026-10-02「写真を撮ったときはまだ覚えてないから
 * 0% になるように」。最初の復習で記憶が始まる（`srs.ts` の `retentionNow`）。
 */
export function memoryPercent(retention: number): number {
  if (!Number.isFinite(retention)) return 0;
  return Math.max(0, Math.min(100, Math.round(retention)));
}

/**
 * 段は**画面の % だけ**から決める。境目は重ならない。
 *
 * 以前は「長期記憶 … 間隔30日以上 かつ 定着度80%以上」のように条件の軸が
 * 段ごとに違い、**長期記憶(80%)が覚えた(85%)より低い**逆転が起きていた
 * （オーナー報告 2026-09-16）。1本の数を6つに区切るだけなので、逆転しない。
 */
export function memoryLevel(percent: number): MemoryLevelInfo {
  if (percent < 30) return LEVELS[0];
  if (percent < 50) return LEVELS[1];
  if (percent < 70) return LEVELS[2];
  if (percent < 85) return LEVELS[3];
  if (percent < 95) return LEVELS[4];
  return LEVELS[5];
}

/** 段と % を出すのに要る最小限。画面ごとに持っている型が違う。 */
export type MemoryInput = {
  /** いまの定着度 0〜100。 */
  retention: number;
  interval_days: number;
  /** 覚えやすさ（難しさ D を写した 1.3〜3.0）。並べ替えには効かない。 */
  ease?: number;
  /** 安定度(日)。無ければ `interval_days`（= 安定度）から出す。 */
  stability_days?: number;
};

/**
 * **段と % を1か所で出す。** バッジ・一覧・忘却曲線が全部ここを通る。
 * 画面ごとに計算すると、片方だけ直した時に食い違う。
 */
export function memoryOf(w: MemoryInput): { percent: number; level: MemoryLevelInfo } {
  const percent = memoryPercent(w.retention);
  return { percent, level: memoryLevel(percent) };
}

const stabilityFor = (w: MemoryInput) => w.stability_days ?? stabilityOf(w.interval_days, w.ease);

export const MEMORY_LEVELS = LEVELS;

/** 並べ替えに要る所だけ。画面ごとに持っている型が違うので、必要な形で受ける。 */
export type MemorySortable = MemoryInput & {
  repetitions?: number;
  headword?: string;
};

/**
 * **思い出せる確率が低いものを上、高いものを下に並べる。**（オーナー指示
 * 2026-09-15「より記憶してるものを下に整頓させて」／2026-09-16「一番下に
 * 行けば行くほど、記憶の状態がより高く % も高くして」）
 *
 * 段も % から出しているので、下へ行くほど段も % も上がる。**逆転しない。**
 *
 * 同じ % のときは**もちが短い語を上**に置く。復習の直後はどの語も 100% に
 * なるので、今日キャッチした語と半年もつ語が並ぶ — 先に忘れるのは前者。
 * それでも同じなら見出し語で決める（開くたびに順が変わらないように）。
 */
export function compareByMemory(a: MemorySortable, b: MemorySortable): number {
  const pa = memoryOf(a).percent;
  const pb = memoryOf(b).percent;
  if (pa !== pb) return pa - pb;
  const sa = stabilityFor(a);
  const sb = stabilityFor(b);
  if (sa !== sb) return sa - sb;
  return (a.headword ?? "").localeCompare(b.headword ?? "");
}
