/**
 * **使い方チャンクの間違いの台帳**（オーナー 2026-10-30「直してはまた失敗…どうすれば間違いが出た時に積み重ねて、
 * AI の出力のクオリティが上がっていくようにできますか」）。
 *
 * 間違いが見つかったら、**ここに1行足すだけ**で次の3つに効く:
 * 1. **門**（`chunk-quality.ts`）— ✗ の型はその語で二度と通らない。
 * 2. **指示文**（`chunkCasesRule`）— その語を作る時は、過去の ✗ と正しい ○ を AI に見せる。どの語を作る時も、
 *    台帳の「教訓」（原因の種類ごとに1つ）を見せる。
 * 3. **試験**（`chunk-cases.test.ts`）— ○ の型は門で落ちず、✗ の型は必ず落ちる。決まりを変えて
 *    正しい型を落とすようになったら、試験が赤くなる（直したら別の所が壊れる、を止める）。
 *
 * 書き方: 型は札を「＋」でつなぎ、札ごとに「字/品詞」（品詞は台湾の詞類表の記号。把 は Ptc、方位の語は Ncd）。
 * `cause` は原因の種類（下の `CHUNK_CAUSE_LESSONS`）。同じ原因の行が増えたら、その教訓の文を直す。
 * ○ の型は**台湾華語の話者が確かめた物**を入れる（確かめていない物は `checked: false` と書き、指示文には出さない）。
 */

export type ChunkCauseKind =
  /** 長さの上限に収めるため、自然な句を切り詰めた（把＋原子筆＋放進＋筆袋＋裡 → 裝進＋筆袋）。 */
  | "truncated"
  /** 頻度の高い言い方より、珍しい動詞を選んだ。 */
  | "rare_verb"
  /** 在・進 ＋ 場所・容器 に 裡・上 が無い。 */
  | "missing_locative"
  /** 語順がネイティブの言う順でない。 */
  | "word_order"
  /** 見出し語を別の物の動作に当てた（刷子 → 刷牙）。 */
  | "wrong_sense"
  /** 1語でない物を1つの札にした・1語を分けた。 */
  | "bad_split"
  /** 容器の 裝 の目的語が中身でない。 */
  | "container_object";

/** 原因の種類ごとの教訓（指示文に出す）。1つの種類に1文。 */
export const CHUNK_CAUSE_LESSONS: Record<ChunkCauseKind, string> = {
  truncated:
    "長さの上限に収めるために自然な句を削らない。把・被 と名詞の後ろの 裡・上 は長さに数えないので、" +
    "ネイティブが言う形のまま書く。それでも入らない型は返さない",
  rare_verb:
    "その語らしさを出すために、ネイティブが最もよく使う動詞（放・收・拿 など）を避けて珍しい動詞を選ばない。①は最も頻度の高い言い方",
  missing_locative:
    "在＋場所の名詞 の後ろには 裡・上・中 などを必ず付ける。放進・收進＋容器 もふつう 裡 を付けて言う（方位の語は別の札）",
  word_order: "パーツを左から読んだ順が、ネイティブが言う語順そのものになるようにする",
  wrong_sense: "見出し語はこのカードの意味の物としてだけ使い、別の物の動作を借りない",
  bad_split: "1語でない物を1つの札にしない。ネイティブが1語として言う物は分けない",
  container_object: "容器の 裝 の目的語は中身（用＋容器＋裝＋中身 / 把＋中身＋放進＋容器＋裡）",
};

export type ChunkCase = {
  headword: string;
  /** 出てしまった間違いの型。 */
  bad: string[];
  /** その語の正しい型（よく使う順）。 */
  good: string[];
  cause: ChunkCauseKind;
  /** その語だけの理由（AI に見せる。読む人の言語ではなく指示文の言語）。 */
  why: string;
  /** 見つかった日・どこから（オーナーの報告・点検 など）。 */
  found: string;
  /** ○ の型を台湾華語の話者が確かめたか。false の行の ○ は指示文に出さない（✗ は門と指示文に効く）。 */
  checked: boolean;
};

export const CHUNK_CASES: ReadonlyArray<ChunkCase> = [
  {
    headword: "筆袋",
    bad: ["裝進/V＋筆袋/N"],
    good: [
      "把/Ptc＋原子筆/N＋放進/V＋筆袋/N＋裡/Ncd",
      "把/Ptc＋原子筆/N＋收進/V＋筆袋/N＋裡/Ncd",
      "把/Ptc＋原子筆/N＋裝進/V＋筆袋/N＋裡/Ncd",
      "打開/V＋筆袋/N",
    ],
    cause: "truncated",
    why:
      "物を筆袋に入れる時は 把＋物＋放進／收進＋筆袋＋裡 と言う。裝進＋筆袋 はその形から 把＋物 と 裡 を削った形で、" +
      "裝 は袋や箱を中身で満たす語感が強い",
    found: "2026-10-30 オーナーの報告（別の AI にも不自然と言われた）",
    checked: false,
  },
  {
    headword: "紙箱",
    bad: ["紙箱/N＋裝/V＋東西/N"],
    good: ["用/Prep＋紙箱/N＋裝/V＋書/N", "把/Ptc＋書/N＋放進/V＋紙箱/N＋裡/Ncd"],
    cause: "container_object",
    why: "裝 の目的語は中身。紙箱＋裝＋東西 の語順では言わない",
    found: "2026-10-14 オーナーの報告",
    checked: false,
  },
  {
    headword: "馬克杯",
    bad: ["裝/V＋熱水/N＋馬克杯/N"],
    good: ["用/Prep＋馬克杯/N＋喝/V＋咖啡/N", "用/Prep＋馬克杯/N＋裝/V＋熱水/N"],
    cause: "container_object",
    why: "裝熱水馬克杯 は「熱湯マグカップに入れる」と読めてしまう",
    found: "2026-10-14 オーナーの報告",
    checked: false,
  },
  {
    headword: "刷子",
    bad: ["拿/V＋刷子/N＋刷牙/V"],
    good: ["用/Prep＋刷子/N＋刷/V＋鞋子/N", "用/Prep＋刷子/N＋刷/V＋地板/N"],
    cause: "wrong_sense",
    why: "刷子 は掃除・靴洗いのブラシ。歯を磨く道具は 牙刷",
    found: "2026-10-15 オーナーの報告",
    checked: false,
  },
  {
    headword: "手帕",
    bad: ["擦/V＋手帕/N＋汗水/N"],
    good: ["用/Prep＋手帕/N＋擦汗/V"],
    cause: "word_order",
    why: "擦手帕汗水 は語順が崩れている",
    found: "2026-10-14 オーナーの報告",
    checked: false,
  },
  {
    headword: "手扶梯",
    bad: ["站/V＋在/Prep＋手扶梯/N"],
    good: ["站/V＋在/Prep＋手扶梯/N＋上/Ncd", "搭/V＋手扶梯/N"],
    cause: "missing_locative",
    why: "在＋場所 の後ろには 上 が要る",
    found: "2026-10-14 指示文の例",
    checked: false,
  },
];

/** 「字/品詞＋字/品詞」を札の並びに。品詞の無い札は空の品詞。 */
export function parseCaseChunk(text: string): Array<{ text: string; pos: string }> {
  return text
    .split(/[＋+]/u)
    .map((t) => t.trim())
    .filter(Boolean)
    .map((t) => {
      const [word, pos] = t.split("/");
      return { text: (word ?? "").trim(), pos: (pos ?? "").trim() };
    });
}

/** 札だけを「＋」でつないだ形（指示文に出す形）。 */
function shownCaseChunk(text: string): string {
  return parseCaseChunk(text)
    .map((p) => p.text)
    .join("＋");
}

/** その語の ✗ の型（札をつないだ字）。門が落とす。 */
export function chunkCaseBadTexts(headword: string): string[] {
  const head = headword.trim();
  return CHUNK_CASES.filter((c) => c.headword === head).flatMap((c) =>
    c.bad.map((b) => parseCaseChunk(b).map((p) => p.text).join("")),
  );
}

/**
 * **指示文に足す台帳の部分**: 原因の種類ごとの教訓（どの語でも）と、その語の過去の ✗ / ○（その語の時だけ）。
 * 生成と作り直しの両方がここを通る。
 */
export function chunkCasesRule(headword: string): string {
  const head = headword.trim();
  const kinds = [...new Set(CHUNK_CASES.map((c) => c.cause))];
  const lessons = kinds.map((k, i) => `${i + 1}. ${CHUNK_CAUSE_LESSONS[k]}`);
  const own = CHUNK_CASES.filter((c) => c.headword === head);
  const ownLines = own.map((c) => {
    const bad = c.bad.map((b) => `✗ ${shownCaseChunk(b)}`).join(" / ");
    const good = c.checked ? ` → ${c.good.map((g) => `○ ${shownCaseChunk(g)}`).join(" / ")}` : "";
    return `${bad}${good}（${c.why}）`;
  });
  return (
    `【過去の間違いから決めた教訓 — 全部守る】\n${lessons.join("\n")}` +
    (ownLines.length > 0
      ? `\n【「${head}」で過去に出た間違い — 同じ型は二度と返さない】\n${ownLines.join("\n")}`
      : "")
  );
}
