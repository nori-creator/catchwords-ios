/**
 * 生成に渡す**級の指示文**を、学習言語ごとに組む。
 *
 * ## なぜ切り出したか
 * この文は `ai-provider.server.ts` の中に、TOCFL の帯の説明を6行
 * 直に書いた形で埋まっていた。英語を選べるようにした日(2026-08-25、
 * 第4段)から、**英語の学習者に「TOCFL 準備級・注音」の話が渡る**。
 * AI は言われたとおりに従うので、英語のカードに華語の級の話が混ざる。
 * しかも画面には出ないので、**出来上がった中身を読むまで気づけない**。
 *
 * server の中に置いたままだと試験から触れないので、純粋な物として出す。
 *
 * ## 英語側は CEFR-J の文法項目を実際に並べる
 * 「B1 相当で」とだけ書くと、モデルごとに解釈が揺れる。CEFR-J
 * Grammar Profile(第B段で入れた256項目)が「その級までに出てよい型」を
 * 名指しで持っているので、**その名前をそのまま渡す**。
 * 出典: 投野由紀夫研究室(東京外国語大学)。
 *
 * 外の世界に触れるものをここに入れないこと。
 */

import {
  LEVEL_INDEXES,
  parseLevelStep,
  stepLabel,
  type LevelIndex,
  type LevelScale,
} from "./level-scale";
import { grammarAtOrBelow } from "./grammar-profile";

/**
 * 段ごとの中身の説明。**体系ごとに別に持つ。**
 *
 * 「レベルに合わせて」だけではモデルが解釈を揺らすので、
 * 語彙量・文法・話題まで書き下して再現性を持たせる。
 */
const TOCFL_BANDS: Record<LevelIndex, string> = {
  1: "入門級(準備級1級・語彙約500語)。基本文型 是/有/在、SVO、簡単な疑問詞。",
  2: "基礎級(準備級2級・語彙約1000語)。了/過/在〜、比較句、能願動詞(會/能/可以)。",
  3: "進階級(第1級・語彙約2500語)。把構文、被構文、複文(因為…所以)、程度補語。",
  4: "高階級(第2級・語彙約5000語)。方向補語・可能補語、書面語彙、接続詞の使い分け。",
  5: "流利級(第3級・語彙約8000語)。成語・慣用句、抽象的な議論、書面体。",
  6: "精通級(第4級・語彙約8000語超)。専門的・文学的表現、含意の強い言い回し。",
};

/**
 * CEFR の段。**語彙量は CEFR-J Wordlist の規模に合わせた概数**で、
 * 公式の数字ではない(公式は語数を定めていない)。
 *
 * C1/C2 に CEFR-J の文法項目は無い(CEFR-J は B2 まで)。
 * **無い所は無いと言う** — 埋めるために作り話をしない。
 */
const CEFR_BANDS: Record<LevelIndex, string> = {
  1: "A1(語彙約1000語)。be動詞・一般動詞の現在、複数形、a/an と the、簡単な疑問文。",
  2: "A2(語彙約2000語)。過去形、be going to、比較級・最上級、助動詞(can/must)、頻度の副詞。",
  3: "B1(語彙約4000語)。現在完了、関係代名詞、受動態、不定詞・動名詞、条件文(if)。",
  4: "B2(語彙約6000語)。過去完了、仮定法、分詞構文、複雑な関係節、談話標識。",
  5: "C1(語彙約8000語)。抽象的・専門的な話題、含意やニュアンスの差、書き言葉の言い回し。",
  6: "C2(語彙約8000語超)。母語話者に近い含意・文体の操作、比喩・慣用表現。",
};

/**
 * JLPT の段(`level-scale.ts` の `JLPT_SCALE` と同じ並び: N5→1 … N1→5、6=N1+)。
 *
 * **語彙量は概数**。2010年の改定から JLPT は公式の語彙表を出していないので、
 * 旧出題基準と市販の語彙集で広く使われている規模に合わせた目安。
 * 6段目は JLPT の外(N1 を超える語)なので、**級の名前を作らず**中身で言う。
 */
const JLPT_BANDS: Record<LevelIndex, string> = {
  1: "N5(語彙約800語)。です・ます、基本の助詞(は/が/を/に/で)、動詞のます形・て形、い形容詞・な形容詞の現在。",
  2: "N4(語彙約1500語)。普通形、〜たい/〜たことがある、可能形、〜てもいい/〜てはいけない、簡単な敬語(お〜ください)。",
  3: "N3(語彙約3700語)。受身・使役、〜そう/〜らしい/〜ようだ、条件(ば/たら/なら)、日常の敬語(尊敬語・謙譲語の基本)。",
  4: "N2(語彙約6000語)。書き言葉の接続(〜にもかかわらず/〜に対して)、新聞・説明文の語彙、敬語の使い分け。",
  5: "N1(語彙約10000語)。抽象的・論説的な語彙、慣用句・四字熟語、硬い書き言葉の文型(〜をもって/〜ならでは)。",
  6: "N1+(N1 を超える語)。専門書・文学・論説の語彙、含みの強い言い回し、古風・雅語的な表現。",
};

const BANDS: Record<string, Record<LevelIndex, string>> = {
  TOCFL: TOCFL_BANDS,
  CEFR: CEFR_BANDS,
  JLPT: JLPT_BANDS,
};

/** 段の説明。知らない体系・読めない段は既定の段(2)に落とす。 */
export function bandDescription(scale: LevelScale, index: LevelIndex): string {
  const table = BANDS[scale.id] ?? TOCFL_BANDS;
  return table[index] ?? table[2];
}

/**
 * その級までに出てよい文法項目を、名前で並べた一言。
 *
 * CEFR 以外の体系では**何も返さない**。CEFR-J は英語の文法の表なので、
 * 華語の級に当てると全く別の言語の型を渡すことになる。
 *
 * 項目は多いので(B2 まで256個)、名前だけを読点で繋ぐ。
 * `limit` を超える分は落として「ほか N 項目」と言う — プロンプトが
 * 長くなるほど、他の指示の効きが薄くなる。
 */
export function grammarAllowance(scale: LevelScale, index: LevelIndex, limit = 40): string {
  if (scale.id !== "CEFR") return "";
  const items = grammarAtOrBelow(index);
  if (items.length === 0) return "";
  const shown = items.slice(0, limit).map((g) => g.ja);
  const rest = items.length - shown.length;
  const tail = rest > 0 ? `、ほか${rest}項目` : "";
  return (
    `この級までに出てよい文法(CEFR-J Grammar Profile / 投野由紀夫研究室): ` +
    `${shown.join("、")}${tail}。**これより上の型は使わない。**`
  );
}

/**
 * 生成に渡す級の指示文をまるごと組む。
 *
 * `current` / `goal` は保存されている形(`"TOCFL-2"` / `"B1"`)で受ける。
 * 読めない値は既定の段に落とす — **未知の級のまま生成させない**。
 */
export function levelRuleText(
  scale: LevelScale,
  current: string,
  goal: string,
  vocabAuthority: string,
): string {
  const goalIndex = indexOf(goal, 2);
  const currentIndex = indexOf(current, Math.max(1, goalIndex - 1) as LevelIndex);
  const currentName = `${scale.id} ${stepLabel(scale, currentIndex)}`;
  const goalName = `${scale.id} ${stepLabel(scale, goalIndex)}`;
  const grammar = grammarAllowance(scale, goalIndex);
  return (
    `学習者の現在レベル: ${currentName}、目標レベル: ${goalName}。` +
    `目標レベルの目安 — ${bandDescription(scale, goalIndex)} ` +
    `解説・注記の**語彙・文法・話題はこの範囲に収める**。${vocabAuthority}に無いような難語や、` +
    `目標級より上の文法をわざわざ使わない。どうしても必要なときだけ短い注釈を添える。` +
    // 2026-10-15 オーナー「例文はTOCFLのある程度検定の難易度に合わせて。ただし最も重要なのはネイティブが最も自然に使う例文。」
    `例文と使い方の型は別 — **ネイティブが最も自然に言う形を最優先**にし、級は目安（例文の指示に従う）。` +
    (grammar ? ` ${grammar}` : "")
  );
}

/** 保存されている級から段を読む。6段の外・読めない物は `fallback`。 */
function indexOf(raw: string | null | undefined, fallback: LevelIndex): LevelIndex {
  const step = parseLevelStep(raw);
  return typeof step === "number" && (LEVEL_INDEXES as readonly number[]).includes(step)
    ? (step as LevelIndex)
    : fallback;
}

/**
 * **例文1文の目安を段ごとに書き下した表**（オーナー報告 2026-10-15「眼鏡の例文と場面が合わない」と同時の指示:
 * 「パターンごとの例文の語彙・文法は、設定したレベルに合わせて」）。
 *
 * `TOCFL_BANDS` などは語彙量と文法項目の名前だけで、**1文の長さ**も**使ってはいけない型**も言っていなかった。
 * 例文はそこが一番ぶれる（入門の人に複文・補語の入った長い文が出る）ので、例文だけの目安を別に持つ。
 * 字数・語数は目安（検定の公式の数字ではない）。
 */
const TOCFL_EXAMPLE: Record<LevelIndex, string> = {
  1: "1文・8〜12字ほど。是/有/在/要/想/喜歡/去 などの基本動詞、很＋形容詞、嗎/呢 の疑問、這/那/我的、文末の了。把・被・複文・補語は使わない。",
  2: "1文・10〜15字ほど。動詞＋了/過、在＋動詞、比、會/能/可以、有一點、太…了。把・被・複文は使わない。",
  3: "1〜2文・20字ほどまで。把・被、因為…所以、雖然…但是、程度補語（得）、結果補語まで。成語・書き言葉は使わない。",
  4: "25〜30字ほどまで。方向補語・可能補語、不但…而且・如果…就 などの接続詞、よく使う書き言葉の語まで。成語は日常で口にする物だけ。",
  5: "35字ほどまで。成語・慣用句・抽象的な語も使ってよい。ただし話し言葉として自然な文。",
  6: "長さの制限なし。含みのある言い回し・文語的な表現も使ってよい。ただし話し言葉として自然な文。",
};

const CEFR_EXAMPLE: Record<LevelIndex, string> = {
  1: "1文・5〜8語。現在形の be 動詞・一般動詞、like/have/want、簡単な疑問文。過去形・完了形・関係詞は使わない。",
  2: "1文・6〜10語。過去形、be going to、can/must、比較級、頻度の副詞まで。完了形・関係詞・受動態は使わない。",
  3: "1文・8〜14語。現在完了、受動態、if、関係代名詞、不定詞・動名詞まで。",
  4: "18語ほどまで。過去完了、仮定法、分詞構文、談話標識まで。",
  5: "長さの制限は緩め。抽象的な語・慣用表現も使ってよい。ただし話し言葉として自然な文。",
  6: "長さの制限なし。比喩・慣用表現・文体の使い分けも使ってよい。ただし話し言葉として自然な文。",
};

const JLPT_EXAMPLE: Record<LevelIndex, string> = {
  1: "1文・15字ほど。です・ます、は/が/を/に/で、ます形・て形、い形容詞・な形容詞の現在。普通形・敬語・複文は使わない。",
  2: "1文・20字ほど。普通形、〜たい/〜たことがある、可能形、〜てもいい、〜から/〜けど まで。",
  3: "25字ほどまで。受身・使役、〜そう/〜らしい、ば/たら/なら、基本の敬語まで。",
  4: "35字ほどまで。書き言葉の接続、敬語の使い分けまで。",
  5: "長さの制限は緩め。慣用句・四字熟語・硬い表現も使ってよい。ただし話し言葉として自然な文。",
  6: "長さの制限なし。ただし話し言葉として自然な文。",
};

const EXAMPLE_BANDS: Record<string, Record<LevelIndex, string>> = {
  TOCFL: TOCFL_EXAMPLE,
  CEFR: CEFR_EXAMPLE,
  JLPT: JLPT_EXAMPLE,
};

/** 例文1文の目安。知らない体系は TOCFL の表、読めない段は既定の段(2)。 */
export function exampleBandDescription(scale: LevelScale, index: LevelIndex): string {
  const table = EXAMPLE_BANDS[scale.id] ?? TOCFL_EXAMPLE;
  return table[index] ?? table[2];
}

/**
 * 例文に掛ける級の指示（カード生成と例文の作り直しで同じ文）。
 *
 * 狙いは**現在の級で読める文**、上限は**目標の級**（`levelRuleText` の「例文は現在レベルでも読めることを優先」と同じ考え）。
 * 見出し語そのものは級より上でもそのまま使う — その語を覚えるための例文なので。
 */
export function exampleLevelRule(
  scale: LevelScale,
  current: string,
  goal: string,
  headword: string,
): string {
  const goalIndex = indexOf(goal, 2);
  const currentIndex = Math.min(
    indexOf(current, Math.max(1, goalIndex - 1) as LevelIndex),
    goalIndex,
  ) as LevelIndex;
  const currentName = `${scale.id} ${stepLabel(scale, currentIndex)}`;
  const goalName = `${scale.id} ${stepLabel(scale, goalIndex)}`;
  return (
    `例文のレベル（目安）: 現在 ${currentName} の人が読める文を目指す — ${exampleBandDescription(scale, currentIndex)}` +
    (goalIndex > currentIndex
      ? ` 目標 ${goalName} の範囲（${exampleBandDescription(scale, goalIndex)}）までは自由に使ってよい。`
      : "") +
    // 2026-10-15 オーナー「例文はTOCFLのある程度検定の難易度に合わせて。ただし最も重要なのはネイティブが最も自然に使う例文。」
    ` **ただし、いちばん大事なのは「ネイティブがその場面で最も自然に言う一文」であること。** ` +
    `レベルに合わせるために言い換えて不自然になるなら、自然な文のまま書く（級より上の語 — 例: 防曬乳 の文の 質地・黏膩 — が要るなら、そのまま使う）。` +
    `同じくらい自然な言い方が2つあれば、レベルに合う方を選ぶ。難しい語を**わざわざ**選ばない。` +
    ` 見出し語「${headword}」はレベルに関係なくそのまま使う（言い換えない）。`
  );
}
