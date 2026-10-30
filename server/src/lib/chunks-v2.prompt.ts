import { CHUNK_PATTERNS, type ChunkPattern, type UsageChunkV2 } from "./chunks-v2";

/**
 * **使い方チャンク v2 の指示文**（設計は `docs/chunk-rules.md` の v2 の節）。
 *
 * - 文 → 塊の順（塊を先に考えさせると作文になり、切れ端になる）。
 * - 型は閉じた一覧（`CHUNK_PATTERNS`）だけを示し、型ごとに見本は 1 つ。**過去の失敗例は入れない**（AI は文の決まりより
 *   例の形をまねる — v1 は報告のたびに ✗/○ を足して約 60 個になり、見本の形に引っぱられた）。
 * - 同じ文を Gemini と Claude の両方に送る（`chunks-v2.server.ts`）。一致した型が正解。
 * - 長さの字数の上限は置かない（1 行に入るかは画面が見る）。
 */

/** 型の一覧（指示文の形）。名前・意味・見本 1 つ。見本の語は採点セットの語を避ける。 */
export const PATTERN_LINES: Readonly<Record<ChunkPattern, string>> = {
  action_vn: "action_vn — 動詞＋名詞（その物にする動作）: 吹電風扇",
  action_ba: "action_ba — 把＋物＋動詞＋名詞（＋裡/上）（物をそこへ入れる・置く）: 把衣服放進洗衣機裡",
  action_tool: "action_tool — 用＋名詞＋動詞（道具として使う）: 用吸管喝",
  action_complement: "action_complement — 動詞＋補語＋名詞 / 動詞＋名詞＋補語: 買到票 / 把拉鍊拉起來",
  state_change: "state_change — 名詞＋動詞/状態＋了（その物に起きること）: 手機沒電了",
  state_degree: "state_degree — 名詞＋很＋形容詞（その物の様子。很 は固定）: 湯很燙",
  modifier_adj: "modifier_adj — 形容詞(的)＋名詞（種類・性質）: 冰的紅茶",
  modifier_noun: "modifier_noun — 名詞＋的＋名詞 / 名詞＋名詞（部位・所属・種類）: 雨傘的把手 / 手機殼",
  place: "place — 在/到＋名詞＋方位（場所として）: 在冰箱裡",
  set_phrase: "set_phrase — 注文・依頼・決まり文句: 紅茶半糖少冰 / 幫我拿一下遙控器",
};

export type ChunksV2PromptInput = {
  headword: string;
  /** 意味の手がかり（読む人の言語か中国語。無ければ見出し語だけ）。 */
  meaning?: string | null;
  /** 読む人の言語の名前（指示文の中の呼び名。例「日本語」「英語」）。 */
  readerName: string;
  /** 読む人の言語が学ぶ言語と同じ（繁體中文で読む人）なら訳は書かせない。 */
  readerIsTarget?: boolean;
  /** 出させる数（多めに出させて一致で絞る）。 */
  count?: { min: number; max: number };
};

/** 生成の指示文。Gemini と Claude に同じ物を送る。 */
export function chunksV2Prompt(input: ChunksV2PromptInput): string {
  const head = input.headword.trim();
  const meaning = (input.meaning ?? "").trim();
  const count = input.count ?? { min: 3, max: 5 };
  const patterns = CHUNK_PATTERNS.map((p) => `   - ${PATTERN_LINES[p]}`).join("\n");
  const translation = input.readerIsTarget
    ? `6. ja・sentence_ja・note は空文字にする（読む人は中国語で読む）。`
    : `6. 各塊に ${input.readerName} の自然な訳（ja）、その文の訳（sentence_ja）、ひと言解説（note: ${input.readerName} で 1 文・40 字まで。` +
      `使う場面・ニュアンス・学習者が間違えやすい所のうち、いちばん役に立つ 1 つ。訳の言い直し・一般論は書かない）。` +
      `slot:true の block と alts にも ${input.readerName} の意味（ja）。${input.readerName} 以外の言語を混ぜない。`;
  return [
    `あなたは台北で暮らす台湾華語のネイティブです。学習者が写真に撮った物「${head}」${meaning ? `（${meaning}）` : ""}について、` +
      `台湾の人が日常で実際に口にする言い方を集めます。学習者はこの塊をそのまま覚えて、話す時・書く時に使います。`,
    ``,
    `手順:`,
    `1. 台湾の人が「${head}」について日常でよく口にする一文を、よく言う順に 6 つ書く（sentence）。`,
    `   - 自分が目の前の人に言う一人称のセリフ。説明文・看板・教科書の作文・大陸の言い方は書かない。`,
    `   - 句読点を除いて 10〜22 字。台湾の口語で。`,
    `   - 6 つはそれぞれ別の場面・別の言い方にする（名詞を入れ替えただけの同じ文を並べない）。`,
    `2. それぞれの文から、「${head}」を含む「そのまま言える最小の塊」を切り出す（text）。`,
    `   - 文の一部を**そのまま写す**（字を足さない・削らない・語順を変えない）。`,
    `   - 塊は、その文脈が無くても意味が通り、別の会話でもそのまま使える長さにする。短い切れ端にしない` +
      `（物を入れる言い方なら 把＋物＋動詞＋入れ物 まで、場所なら 方位の語（裡・上）まで入れる）。`,
    `   - 塊を、ネイティブが一息に言う単位で区切る（blocks）。ネイティブが 1 語として言う物は分けない。`,
    `3. 塊の型を一覧から 1 つ選ぶ（pattern）。一覧に無い型、量詞の型（一個〜・一杯〜）、主語の付いた文は塊にしない。`,
    patterns,
    `4. 同じ型の塊が 2 つ以上あれば、よく言う方 1 つだけ残す。残った塊を、ネイティブがよく言う順に ${count.min}〜${count.max} 個返す` +
      `（数を揃えるために作らない。確信の無い物は返さない）。`,
    `5. 塊の中で、別の名詞に入れ替えてもよく言う所が 1 か所あれば、その block に slot:true と、ネイティブが実際によく入れる` +
      `別の名詞を alts に 3〜6 個（よく言う順）。slot は名詞だけ（動詞・形容詞・很 には付けない）。**「${head}」自身は決して slot にしない。**`,
    translation,
    `pos は台湾の詞類表の記号（N / V / Vs / Adv / Prep / Ptc / Det / Conj）。pinyin・zhuyin は書かない（辞書で付ける）。`,
    ``,
    `返す形（JSON だけ。前後に文を書かない）:`,
    `{"chunks":[{"sentence":"","sentence_ja":"","text":"","blocks":[{"text":"","pos":"","slot":false,"ja":"","alts":[{"text":"","ja":""}]}],"pattern":"","ja":"","note":""}]}`,
  ].join("\n");
}

/** 審査の指示文: 片方の会社だけが出した塊を、もう片方の会社に見せる。 */
export function judgeV2Prompt(headword: string, chunks: ReadonlyArray<Pick<UsageChunkV2, "text" | "sentence">>): string {
  const head = headword.trim();
  const list = chunks.map((c, i) => `${i + 1}. 塊: ${c.text}　文: ${c.sentence}`).join("\n");
  return [
    `あなたは台北で暮らす台湾華語のネイティブです。下の言い方は、学習アプリが「${head}」の使い方として見せる候補です。` +
      `1 つずつ、台湾の人が日常の会話でこのまま言うかを判定してください。`,
    ``,
    `判定:`,
    `- natural: 台湾の日常会話で、この語順・この語の組み合わせで**そのまま**言う → true。` +
      `言わない・書き言葉・大陸の言い方・不自然・意味が通らない・塊として短すぎて使えない → false。`,
    `- frequency: その物について話す時に、この言い方をどれくらいよく使うか 1〜5（5 = 真っ先に出る言い方、3 = よく言う、1 = まれ）。`,
    ``,
    `候補:`,
    list,
    ``,
    `返す形（JSON だけ）: {"verdicts":[{"i":1,"natural":true,"frequency":4}]}`,
  ].join("\n");
}

/**
 * 訳の指示文: 書庫に有る塊（中国語は決まっている）に、別の表示言語の訳・解説を付ける。塊の字は変えさせない。
 */
export function translateV2Prompt(
  headword: string,
  chunks: ReadonlyArray<Pick<UsageChunkV2, "text" | "blocks" | "sentence">>,
  readerName: string,
): string {
  const list = chunks
    .map((c, i) => {
      const slot = c.blocks.find((b) => b.slot);
      const alts = slot?.alts?.map((a) => a.text).join("、") ?? "";
      return `${i + 1}. 塊: ${c.text}　文: ${c.sentence}${slot ? `　入れ替える所: ${slot.text}（候補: ${alts}）` : ""}`;
    })
    .join("\n");
  return [
    `台湾華語の学習アプリ。下の「${headword.trim()}」の言い方（塊）と文に、${readerName} の訳を付けてください。中国語の字は 1 字も変えない。`,
    `各候補に: ja（塊の自然な訳）、sentence_ja（文の自然な訳）、note（${readerName} で 1 文・40 字まで。使う場面・ニュアンス・` +
      `間違えやすい所のうち役に立つ 1 つ。訳の言い直しは書かない）、入れ替える所があれば slot_ja（その語の意味）と alts_ja（候補それぞれの意味、同じ順）。` +
      `${readerName} 以外の言語を混ぜない。`,
    ``,
    list,
    ``,
    `返す形（JSON だけ）: {"items":[{"i":1,"ja":"","sentence_ja":"","note":"","slot_ja":"","alts_ja":[""]}]}`,
  ].join("\n");
}
