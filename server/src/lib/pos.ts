import { DICT, type UiLang } from "./i18n";

/**
 * 品詞(詞類表)ユーティリティ。
 *
 * 台湾の中国語教材(國語教學中心系)の詞類表に準拠した記号を正とする:
 *   N/V/Vi/V-sep/Vs/Vst/Vs-attr/Vs-pred/Vs-sep/Vaux/Vp/Vpt/Vp-sep/
 *   Adv/Conj/Prep/M/Ptc/Det
 * AIにもこの記号で part_of_speech を出させ、表示時に日本語の説明を添える。
 */

export const POS_TABLE: Record<string, string> = {
  N: "名詞",
  V: "動詞（及物）",
  Vi: "動詞（不及物）",
  "V-sep": "離合詞",
  Vs: "状態動詞（形容詞）",
  Vst: "状態動詞（及物）",
  "Vs-attr": "状態動詞（限定用法のみ）",
  "Vs-pred": "状態動詞（述語用法のみ）",
  "Vs-sep": "状態離合詞",
  Vaux: "助動詞",
  Vp: "変化動詞",
  Vpt: "変化動詞（及物）",
  "Vp-sep": "変化離合詞",
  Adv: "副詞",
  Conj: "接続詞",
  Prep: "介詞（前置詞）",
  M: "量詞",
  Ptc: "助詞",
  Det: "限定詞",
};

/**
 * 品詞の名前を**表示言語で**引く（オーナー報告 2026-10-02「英語の表示でも
 * 名詞 / 動詞 / 状態動詞(形容詞) が日本語のまま」）。
 *
 * 名前は `i18n.tsx` の表（`pos.c.*` / `pos.g.*`）が持つ。日本語は前と1字も変えない
 * （下の `POS_TABLE` / `GROUP_LABEL` と同じ文言 — `pos.test.ts` が見張る）。
 * 言語を渡さない呼び出しは日本語のまま（server や古い呼び出しを変えない）。
 */
function dictLabel(key: string, lang: UiLang | null | undefined, fallback: string): string {
  const row = DICT[key];
  return (lang && row?.[lang]) || row?.ja || fallback;
}

/**
 * 日本語で書かれた品詞（旧データ・スキャンの「名詞」など）を、表示言語の名前へ。
 * 表の日本語と**ぴったり同じ**ときだけ訳す（分からない綴りは書き換えない）。
 */
function translateJapanesePos(raw: string, lang: UiLang): string {
  // 古いデータは半角の括弧（「状態動詞(形容詞)」）で書かれている。表は全角なので揃えて比べる。
  const ja = raw.replace(/\(/g, "（").replace(/\)/g, "）");
  for (const [code, label] of Object.entries(POS_TABLE)) {
    if (label === ja) return dictLabel(`pos.c.${code}`, lang, raw);
  }
  for (const [g, label] of Object.entries(GROUP_LABEL)) {
    if (label === ja) return dictLabel(`pos.g.${g}`, lang, raw);
  }
  return raw;
}

/**
 * "Vs" → "Vs · 状態動詞(形容詞)"（英語なら "Vs · Stative verb (adj.)"）。
 * 表に無い表記はそのまま（日本語の「名詞」だけは日本語以外の人に訳して出す）。
 */
export function posDisplay(pos: string | null | undefined, lang?: UiLang | null): string {
  const p = (pos ?? "").trim();
  if (!p) return "";
  const label = POS_TABLE[p];
  if (label) return `${p} · ${dictLabel(`pos.c.${p}`, lang, label)}`;
  return lang && lang !== "ja" ? translateJapanesePos(p, lang) : p;
}

// ---------------------------------------------------------------------------
// チャンク(文のパーツ)の配色 — 復習の添削と単語詳細で同じ色体系を使う。
// 色は第2の手がかり: ラベル文字も必ず一緒に描く(色覚多様性)。
// ---------------------------------------------------------------------------

/**
 * 色を持つ品詞の群。**詞類表の10群(NORI指定)。**
 *
 * ## なぜ2色から10群に戻したか
 * 一時期、塗るのは動詞と目的語だけにしていた(「色を全部に配ると、色は
 * 何も指さなくなる」という独立監査の指摘への答え)。だが実際のカードでは
 * **動詞と目的語しか色が付かず、残りは全部同じ灰色**で、名詞なのか
 * 副詞なのか介詞なのかが読み取れなかった。台湾華語の学習では
 * 「この語は Vs(状態動詞)であって V ではない」ことが語順を決めるので、
 * そこを潰すと教材として成り立たない。
 *
 * 虹にならないようにするのは**色相ではなく明度**の側で担保する —
 * 明度と彩度を固定して色相だけを回すので、10色が対等に並び、
 * どれか1つが勝手に主役に見えることが無い(`--pos-*` を見ること)。
 */
export type PosGroup = "n" | "v" | "vs" | "vaux" | "adv" | "m" | "conj" | "prep" | "ptc" | "det";

export type ChunkStyle = {
  /** 札そのもの。色は `--pos` を経由するので、クラスは2つで足りる。 */
  pill: string;
  /** 凡例の丸。 */
  dot: string;
  label: string;
};

export const GROUP_LABEL: Record<PosGroup, string> = {
  n: "名詞",
  v: "動詞",
  vs: "状態動詞（形容詞）",
  vaux: "助動詞",
  adv: "副詞",
  m: "量詞",
  conj: "接続詞",
  prep: "介詞",
  ptc: "助詞",
  det: "限定詞",
};

/**
 * 詞類表の記号 → 群。**長い記号から先に見る。**
 * `Vs-attr` を `V` より先に判定しないと、状態動詞が全部ただの動詞になる。
 */
const EXACT: Record<string, PosGroup> = {
  N: "n",
  V: "v",
  Vi: "v",
  "V-sep": "v",
  Vp: "v",
  Vpt: "v",
  "Vp-sep": "v",
  Vs: "vs",
  Vst: "vs",
  "Vs-attr": "vs",
  "Vs-pred": "vs",
  "Vs-sep": "vs",
  Vaux: "vaux",
  Adv: "adv",
  Conj: "conj",
  Prep: "prep",
  M: "m",
  Ptc: "ptc",
  Det: "det",
};

/**
 * 古いデータの役割記号。**production に既に入っている語を壊さない。**
 * S(主語)と O(目的語)はふつう名詞句なので名詞の色に落とす。
 * C は補語、P は助詞として書かれていた。
 */
const LEGACY: Record<string, PosGroup> = {
  S: "n",
  O: "n",
  C: "prep",
  P: "ptc",
};

export function posGroup(pos: string): PosGroup {
  const p = (pos || "").trim();
  if (!p) return "ptc";
  const exact = EXACT[p];
  if (exact) return exact;
  // V1 / V2 / O1 / O2 のような番号付き。番号を落として引き直す。
  const numless = p.replace(/[0-9０-９]+$/, "");
  const byNum = EXACT[numless] ?? LEGACY[numless];
  if (byNum) return byNum;
  const legacy = LEGACY[p];
  if (legacy) return legacy;
  // 表に無い綴り。**長い順に前方一致**で拾う(Vs-attr → Vs → V の順)。
  const prefixes: Array<[RegExp, PosGroup]> = [
    [/^Vaux/i, "vaux"],
    [/^Vs/i, "vs"],
    [/^Vst/i, "vs"],
    [/^V/i, "v"],
    [/^Adv/i, "adv"],
    [/^Conj/i, "conj"],
    [/^Prep/i, "prep"],
    [/^Det/i, "det"],
    [/^Ptc/i, "ptc"],
    [/^M/i, "m"],
    [/^N/i, "n"],
  ];
  for (const [re, g] of prefixes) if (re.test(p)) return g;
  return "ptc";
}

/** 群の名前（表示言語。言語を渡さなければ日本語）。 */
export function posGroupLabel(g: PosGroup, lang?: UiLang | null): string {
  return dictLabel(`pos.g.${g}`, lang, GROUP_LABEL[g]);
}

export function chunkStyle(pos: string, lang?: UiLang | null): ChunkStyle {
  const g = posGroup(pos);
  return { pill: `chunk-pill pos-${g}`, dot: `pos-dot pos-${g}`, label: posGroupLabel(g, lang) };
}

/**
 * 凡例。**その文に実際に出てきた群だけ**を、詞類表の並びで出す。
 * 出ていない群まで並べると、色と語の対応を探す手間だけが増える。
 */
const GROUP_ORDER: PosGroup[] = ["n", "v", "vs", "vaux", "adv", "m", "conj", "prep", "ptc", "det"];

export function chunkLegendFor(
  poses: string[],
  lang?: UiLang | null,
): Array<{ key: PosGroup; style: ChunkStyle }> {
  const seen = new Set(poses.map(posGroup));
  return GROUP_ORDER.filter((g) => seen.has(g)).map((g) => ({
    key: g,
    style: {
      pill: `chunk-pill pos-${g}`,
      dot: `pos-dot pos-${g}`,
      label: posGroupLabel(g, lang),
    },
  }));
}

/**
 * 日本語で書かれた品詞が**物(名詞)を指しているか**。
 *
 * ## なぜ `posGroup` と別なのか
 * `posGroup` が読むのは台湾の詞類表の記号(`N` / `Vs` / `Ptc` …)。
 * こちらが読むのは**スキャンが返す日本語**(「名詞」「動詞」「形容詞」)。
 * 語彙が違うものを1つの関数に詰めると、どちらの規則も曖昧になる。
 *
 * ## なぜ要るのか
 * カメラのスキャンは名詞だけを返す約束になった(オーナー指示 2026-08-20:
 * 絵を用意できるのが物だけのため)。だが**プロンプトは指示であって強制ではない**。
 * 「名詞だけ」と書いても動詞は返ってくるので、返ってきた物を実際に絞る。
 *
 * 品詞が空のものは**通す**。スキャンは写っている物を挙げているので、
 * 札が付いていないだけで落とすと本物の候補が消える。
 */
export function isNounLike(pos: string | null | undefined): boolean {
  const p = (pos ?? "").trim();
  if (!p) return true; // 札が無い = 分からない。分からないことを理由に捨てない
  if (/名詞|名詞句|固有名/.test(p)) return true;
  return !/動詞|形容詞|副詞|助詞|助動詞|接続|介詞|量詞|限定詞/.test(p);
}
