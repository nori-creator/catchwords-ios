/**
 * 学習言語ごとの**級の目盛り**。
 *
 * オーナー指示 2026-08-24:
 * > 「アプリ内のすべての項目について学習言語、英語と台湾華語で変更すべきことを
 * >  変更して」
 *
 * ## なぜ一般化できるのか — 形が同じだから
 * TOCFL は6級を2つずつ3つの帯(A/B/C)にまとめる。**CEFR も同じ形**:
 * A1 A2 B1 B2 C1 C2 の6段が、A/B/C の3帯に2つずつ入る。
 *
 *     TOCFL   1  2 | 3  4 | 5  6      帯 A | B | C
 *     CEFR   A1 A2 |B1 B2 |C1 C2      帯 A | B | C
 *
 * だから級の読み書き・設定の選択肢・生成の指示は**1つの形で回せる**。
 * 変わるのは「段の名前」と「読み取り方」だけ。
 *
 * ## 級の外を「無い」で済ませない
 * どちらの体系にも載っていない語は珍しくない(固有名詞・新語・方言)。
 * そこを `null`(分からない)と混ぜないよう、**級外という段がある**ことにして、
 * 6段の外側に置く。
 *
 * 外の世界に触れるものをここに入れないこと。
 */

/** 級の外(その体系の語彙表に載っていない語)。 */
export const LEVEL_OUT = "out" as const;
export type LevelOut = typeof LEVEL_OUT;

/** 段のどれか。`null` は「まだ分からない」で、`"out"` とは違う。 */
export type LevelStep = number | LevelOut;

/** 帯。どちらの体系も A / B / C の3つ。 */
export const LEVEL_BANDS = ["A", "B", "C"] as const;
export type LevelBand = (typeof LEVEL_BANDS)[number];

/** 段は6つ。TOCFL も CEFR もここが一致しているので同じ形で扱える。 */
export const LEVEL_INDEXES = [1, 2, 3, 4, 5, 6] as const;
export type LevelIndex = (typeof LEVEL_INDEXES)[number];

export type LevelScale = {
  /** 体系の名前(「TOCFL」「CEFR」)。 */
  id: string;
  /**
   * 段の名前(小さい順に6つ)。
   * TOCFL は `["1","2","3","4","5","6"]`、CEFR は `["A1",…,"C2"]`。
   */
  labels: readonly [string, string, string, string, string, string];
  /**
   * 保存されている文字列からその段の名前を作る。
   * `level_goal` に入る形("TOCFL-2" / "B1")もこれで往復できる。
   */
  toStored: (index: LevelIndex) => string;
  /**
   * **級外**を保存するときの文字列。
   *
   * オーナー指示 2026-08-26「CEFR-J に無い語は級外にして」。級が付いて
   * いない語に「A2」と書くと、公式の級と見分けが付かなくなる。
   * `parseLevelStep` がこれを `LEVEL_OUT` として読み返せること
   * (= 6段の外の数字を持つこと)が条件。
   */
  outStored: string;
  /**
   * 設定の「いまの級 / 目標の級」に並べる文言。
   *
   * **体系ごとに言い方が違う。** TOCFL は `TOCFL Level 3` と書くのが
   * 慣習だが、CEFR に `Level` は付けない(`CEFR B1`)。ここを共通の
   * ひな形にすると、どちらかが慣習から外れた表記になる。
   */
  optionLabel: (label: string) => string;
};

/** 台湾華語: 華語文能力測驗。 */
export const TOCFL_SCALE: LevelScale = {
  id: "TOCFL",
  labels: ["1", "2", "3", "4", "5", "6"],
  toStored: (i) => `TOCFL-${i}`,
  outStored: "TOCFL-0",
  optionLabel: (label) => `TOCFL Level ${label}`,
};

/** 英語: CEFR。 */
export const CEFR_SCALE: LevelScale = {
  id: "CEFR",
  labels: ["A1", "A2", "B1", "B2", "C1", "C2"],
  toStored: (i) => CEFR_SCALE.labels[i - 1],
  // `A1`〜`C2` の綴りに当たらず、数字が 6段の外。**級外として読み返せる**。
  outStored: "CEFR-0",
  // CEFR に `Level` は付けない。`CEFR B1` がその体系の書き方。
  optionLabel: (label) => `CEFR ${label}`,
};

/**
 * 日本語: 日本語能力試験(JLPT)。2026-10-01 に日本語を学習言語に足したとき入れた。
 *
 * ## 5級しか無いのに6段に載せる
 * JLPT は N5(易)〜N1(難)の**5段**で、TOCFL / CEFR の6段と数が合わない。
 * 級の読み替え(`restoreLevel`)・設定の選択肢・生成の指示は全部「6段」を前提に
 * しているので、目盛りの形のほうを変えると、その全部を直すことになる。
 *
 * そこで **N5→1段 … N1→5段**と易しい順に並べ、6段目を「N1+」
 * (N1 を超える語 — 論説・専門書・文学で出る語)にした。CEFR の C2 が
 * 「母語話者に近い」段なのと同じ位置づけで、**作り話の級ではない**ことを
 * 名前に `+` を付けて見せる。
 *
 * ## 数字の向きが逆
 * JLPT は**数字が小さいほど難しい**。保存の形を `JLPT-N5` にしても、
 * `parseLevelStep` が数字だけを拾うと N5 が5段目(上級)になる。
 * だから `parseLevelStep` に `N` 付きの綴りを先に読む道を足してある。
 */
export const JLPT_SCALE: LevelScale = {
  id: "JLPT",
  labels: ["N5", "N4", "N3", "N2", "N1", "N1+"],
  toStored: (i) => `JLPT-${JLPT_SCALE.labels[i - 1]}`,
  // `N` が付かず数字が 6段の外。**級外として読み返せる**(CEFR-0 と同じ形)。
  outStored: "JLPT-0",
  // 慣習どおり `JLPT N3`。`Level` は付けない。
  optionLabel: (label) => `JLPT ${label}`,
};

/**
 * 保存されている値から段を読む。
 *
 * TOCFL は数字を拾う。CEFR は `A1`〜`C2` の綴りを拾う。
 * **どちらの形も受ける** — 学ぶ言語を切り替えた人の古い `level_goal` が
 * 残っていても、知らない形として静かに落ちるだけで壊れない。
 *
 * - 6段の外(0 や 7)は級ではない → `LEVEL_OUT`
 * - 数字も綴りも無い(`"級外"` `"unknown"` `""`)→ `null`(分からない)
 *
 * **「範囲外」と「分からない」を混ぜない。** 混ぜると、辞書の取りこぼしと
 * 本当に級外の語が同じ見た目になり、どちらを直せばいいか分からなくなる。
 */
export function parseLevelStep(raw: string | number | null | undefined): LevelStep | null {
  if (raw == null) return null;
  const s = String(raw).trim();
  if (!s) return null;
  // **JLPT の綴りをいちばん先に見る。** `JLPT-N5` の数字だけを拾うと
  // 5段目(上級)になる — JLPT は数字が小さいほど難しい。`N1+` は
  // 6段目(N1 を超える語)。TOCFL / CEFR の保存形に `N`+数字は無いので、
  // ここを先に置いても既存の値の読み方は1つも変わらない。
  const jlpt = s.toUpperCase().match(/(?:^|[^A-Z])N([1-5])(\+?)(?![0-9])/);
  if (jlpt) {
    if (jlpt[1] === "1" && jlpt[2] === "+") return 6;
    return (6 - Number(jlpt[1])) as LevelIndex;
  }
  // CEFR の綴りを先に見る。"A1" は数字も持っているので、数字から先に
  // 読むと 1 級と取り違える。
  const cefr = s.toUpperCase().match(/\b([ABC])([12])\b/);
  if (cefr) {
    const band = LEVEL_BANDS.indexOf(cefr[1] as LevelBand);
    if (band >= 0) return (band * 2 + Number(cefr[2])) as LevelIndex;
  }
  // **マイナスを読まない。** `TOCFL-2` のハイフンは区切りであって符号では
  // ないので、`-?` を付けると 2級が -2 になり、丸ごと級外へ落ちる。
  const m = s.match(/\d+/);
  if (!m) return null;
  const n = Number(m[0]);
  if (!Number.isFinite(n)) return null;
  return (LEVEL_INDEXES as readonly number[]).includes(n) ? (n as LevelIndex) : LEVEL_OUT;
}

/** その段の名前(画面に出す文字)。級外は呼ぶ側が別に出す。 */
export function stepLabel(scale: LevelScale, index: LevelIndex): string {
  return scale.labels[index - 1] ?? String(index);
}

/**
 * 設定の「いまの級 / 目標の級」に並べる6つ。
 *
 * **保存する形と見せる形を1箇所で作る。** 以前この2つは、片方が
 * `.replace()` で作った表記、もう片方が手書きの6行で、同じ文字列を
 * 別々に作っていた(ずれても誰も気づかない形)。
 */
export function levelOptions(scale: LevelScale): { value: string; label: string }[] {
  return LEVEL_INDEXES.map((n) => ({
    value: scale.toStored(n),
    label: scale.optionLabel(stepLabel(scale, n)),
  }));
}

/**
 * 保存されている級を、**その目盛りの表記に載せ替える**。
 *
 * ## なぜ要るか
 * 学習言語を切り替えられるようにした日(2026-08-25、第4段)から、
 * 同じ人の `level_goal` に `"TOCFL-2"` と `"A2"` の両方があり得る。
 * 台湾華語で2級だった人が英語に切り替えると、`"TOCFL-2"` は CEFR の
 * 一覧に**無い値**になり、設定の選択が空に見えて保存もできない。
 *
 * 段の数(1〜6)は目盛りをまたいで同じ意味なので、**段だけ引き継いで
 * 表記を載せ替える**。2級だった人は英語でも2段目(A2)から始まる。
 *
 * ## 段が読めないとき
 * `null`(分からない)も `"out"`(6段の外)も、その目盛りの中の段では
 * ないので `fallback` に落とす。**0 や 7 を段として扱わない** —
 * `toStored(7)` は一覧に無い値を作るので、同じ穴に落ちる。
 */
export function restoreLevel(
  scale: LevelScale,
  saved: string | number | null | undefined,
  fallback: LevelIndex,
): string {
  const step = parseLevelStep(saved);
  const index = typeof step === "number" ? (step as LevelIndex) : fallback;
  return scale.toStored(index);
}
