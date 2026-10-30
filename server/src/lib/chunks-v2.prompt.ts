import { CHUNK_PATTERNS, type ChunkCandidate, type ChunkPattern, type UsageChunkV2 } from "./chunks-v2";

/**
 * **使い方チャンク v2 の指示文**（設計は `docs/chunk-rules.md` の v2 の節）。
 *
 * - 文 → 塊の順（塊を先に考えさせると作文になり、切れ端になる）。
 * - 名詞の役割の一覧（`CHUNK_PATTERNS`）は、名詞が文の中で立てる場所を全部思い出させるための物。見本は役割ごとに 1 つ。
 *   **過去の失敗例は入れない**（AI は文の決まりより例の形をまねる — v1 は報告のたびに ✗/○ を足して約 60 個になった）。
 * - 書く段は**中国語だけ・軽い形**（文・塊・中心の語・型・入れ替え）。block・品詞・訳は 2 社の照合で残った塊にだけ付ける
 *   （`finishV2Prompt`）。2026-10-30 の採点: 訳まで一度に書かせると 1 語 30〜40 秒、block・品詞を含めても 30 秒前後かかり、
 *   時間切れが出た。返事が短いほど速い。
 * - 同じ文を Gemini と Claude の両方に送る（`chunks-v2.server.ts`）。一致した言い方（同じ中心の語）が正解、片方だけの物は
 *   もう片方の会社が審査。
 * - 長さの字数の上限は置かない（1 行に入るかは画面が見る）。
 */

/** 名詞の役割の一覧（指示文の形）。見本の語は採点セットの語を避ける。 */
export const PATTERN_LINES: Readonly<Record<ChunkPattern, string>> = {
  object: "object — 動詞の目的語: 動詞＋名詞（動詞に 了/過・一下・補語が付く形も）: 開冷氣 / 買到票 / 洗一下杯子",
  subject:
    "subject — 主語・話題: 名詞＋動詞了 / 名詞＋被＋動詞了 / 名詞＋很＋形容詞 / 名詞＋比＋名詞＋形容詞 / 名詞＋動詞＋目的語: 手機沒電了 / 湯很燙 / 蚊子咬我",
  coverb:
    "coverb — 介詞の目的語: 在/到/從/往・用/拿・跟/和・給/對/幫/替・把・被 ＋名詞（＋方位の語）＋動詞: 用吸管喝 / 跟同事吃飯 / 從冰箱裡拿出來 / 把衣服放進洗衣機裡",
  modified: "modified — 修飾される側（その物の決まった種類・性質だけ）: 形容詞(的)＋名詞 / 動詞(的)＋名詞 / 名詞(的)＋名詞: 冰的紅茶 / 剛買的手機",
  modifier: "modifier — 別の名詞を修飾する側（その物の決まった部位・種類だけ）: 名詞的名詞 / 名詞＋名詞: 冷氣的遙控器 / 手機殼",
  locative:
    "locative — 場所として、動詞と一緒に: 動詞＋在/到＋名詞＋裡/裡面/上/上面/下/底下/外/外面/中/旁邊/前面/後面: 放在桌上 / 掉到沙發底下",
  set_phrase: "set_phrase — 決まった言い回し（注文・依頼・質問・感嘆）: 紅茶半糖少冰 / 有沒有衛生紙 / 好可愛的狗",
  other: "other — 上のどれでもないが、ネイティブが塊として言う物（捨てない）",
};

export type ChunksV2PromptInput = {
  headword: string;
  /** 意味の手がかり（無ければ見出し語だけ）。 */
  meaning?: string | null;
  /** 出させる数（多めに出させて、2 社の照合で絞る）。 */
  count?: { min: number; max: number };
};

/** 書く段の指示文（中国語だけ・軽い形）。Gemini と Claude に同じ物を送る。 */
export function chunksV2Prompt(input: ChunksV2PromptInput): string {
  const head = input.headword.trim();
  const meaning = (input.meaning ?? "").trim();
  const count = input.count ?? { min: 4, max: 6 };
  const patterns = CHUNK_PATTERNS.map((p) => `   - ${PATTERN_LINES[p]}`).join("\n");
  return [
    `あなたは台北で暮らす台湾華語のネイティブです。学習者が写真に撮った物「${head}」${meaning ? `（${meaning}）` : ""}について、` +
      `台湾の人が日常で実際に口にする言い方を集めます。学習者はこの塊をそのまま覚えて、話す時・書く時に使います。`,
    ``,
    `手順:`,
    `1. 台湾の人が「${head}」について日常でよく口にする一文を、よく言う順に ${count.max} つ書く（sentence）。`,
    `   - 自分が目の前の人に言う一人称のセリフ。説明文・看板・教科書の作文・大陸の言い方は書かない。`,
    `   - 句読点を除いて 10〜22 字。台湾の口語で。`,
    `   - **その物だから言う**動作・状態・組み合わせの文にする。どの物にも言える文（多少錢・是誰的・在哪裡・借我一下・` +
      `我喜歡／我買了／我有／這個）は書かない。`,
    `   - ${count.max} つはそれぞれ別の場面・別の動詞・別の言い方にする（名詞を入れ替えただけの同じ文、同じ動詞の文を並べない）。`,
    `2. それぞれの文から、「${head}」を含む「そのまま言える最小の塊」を切り出す（text）。`,
    `   - 文の一部を**そのまま写す**（字を足さない・削らない・語順を変えない）。`,
    `   - 塊は、その文脈が無くても意味が通り、別の会話でもそのまま使える長さにする。短い切れ端にしない` +
      `（物を入れる言い方なら 把＋物＋動詞＋入れ物 まで、場所なら 方位の語（裡・上・下・旁邊…）まで、動詞があれば動詞まで入れる）。`,
    `   - 量詞（一杯・一把・這個…）は塊に入れない（量詞は別の欄）。`,
    `3. 塊の中で「${head}」と組になる**中心の語を 1 つ**書く（key）: 動詞・形容詞・名詞のどれか（撐・忘記帶・半糖去冰・把手）。` +
      `同じ組み合わせを 2 社が独立に選ぶかで正しさを見るので、塊の意味の中心になる語を正確に。`,
    `4. 塊の中で「${head}」がどの役割に立っているかを一覧から 1 つ選ぶ（pattern）。一覧は、名詞が文の中で立てる場所を` +
      `全部思い出すための物 — **動詞＋名詞に偏らず**、その物についてネイティブがよく言う形なら、どの役割の塊でもよい。` +
      `主語・動詞・目的語を全部書いた文は塊にしない。`,
    patterns,
    `   **一覧の見本の句を、その物に当てはめただけの塊は返さない**（見本は役割を示すためだけの物）。`,
    `5. 残った塊を、ネイティブがその物についてよく言う順に ${count.min}〜${count.max} 個返す（数を揃えるために作らない。確信の無い物は返さない）。`,
    `6. 塊の中で、別の名詞に入れ替えてもよく言う所が 1 か所あれば、その字を slot に（塊の中の字をそのまま。名詞だけ — 動詞・形容詞・` +
      `很・代名詞には付けない。**「${head}」自身は決して slot にしない**）、ネイティブが実際によく入れる別の名詞を alts に 3〜5 個（よく言う順）。` +
      `無ければ slot は null、alts は []。`,
    `訳・解説・読み・品詞は書かない（後で付ける）。`,
    ``,
    `返す形（JSON だけ。前後に文を書かない）:`,
    `{"chunks":[{"sentence":"","text":"","key":"","pattern":"","slot":null,"alts":[]}]}`,
  ].join("\n");
}

/**
 * 審査と並べ替えの指示文: 2 社の候補をまとめて見せ、1 つずつ「台湾の人が日常でこのまま言うか」と、自然な物の中での
 * 「よく言う順」を付けてもらう。書いた会社でない方の「自然」が合否、順位は 2 社の平均（`rankAndSelect`）。
 */
export function judgeV2Prompt(headword: string, chunks: ReadonlyArray<Pick<ChunkCandidate, "text" | "sentence">>): string {
  const head = headword.trim();
  const list = chunks.map((c, i) => `${i + 1}. 塊: ${c.text}　文: ${c.sentence}`).join("\n");
  return [
    `あなたは台北で暮らす台湾華語のネイティブです。下の言い方は、学習アプリが「${head}」の使い方として見せる候補です。` +
      `学習者はこの塊をそのまま覚えて話す・書く時に使うので、台湾の日常会話で本当によく言う物だけを残したい。`,
    ``,
    `1 つずつ判定する:`,
    `- natural: 台湾の日常会話で、この語順・この語の組み合わせで**そのまま**言う → true。` +
      `言わない・書き言葉・大陸の言い方・不自然・意味が通らない・塊として短すぎて使えない → false。` +
      `**自然かどうかだけ**を見る（その物らしいか・よく言うかは rank で表す。普通に言える物を false にしない）。`,
    `- rank: natural が true の物だけに、その物について話す時に**よく言う順**の順位（1 = いちばんよく言う。同じ順位を付けない）。false の物は null。` +
      `どの物にも言える言い方（多少錢・是誰的・在哪裡・借我一下）や、場面が限られる言い方は後ろに。`,
    `  似た言い方が 2 つあっても、それぞれ単独で判定する（1 つに絞るのはこちらでする）。`,
    ``,
    `候補:`,
    list,
    ``,
    `返す形（JSON だけ）: {"verdicts":[{"i":1,"natural":true,"rank":2}]}`,
  ].join("\n");
}

/**
 * 仕上げの指示文: 決まった塊（中国語は決まっている）に、**ネイティブが一息に言う単位の区切り（blocks）と品詞**、
 * 読む人の言語の訳・解説を付ける。塊の字は変えさせない。`readerName` が null なら訳は要らない（繁體中文で読む人、
 * または書庫に既に有る塊の別の言語の訳）。block が既に有る塊（書庫の物）には区切りを聞かない。
 */
export function finishV2Prompt(
  headword: string,
  chunks: ReadonlyArray<Pick<ChunkCandidate, "text" | "sentence" | "slot" | "alts"> | Pick<UsageChunkV2, "text" | "sentence" | "blocks">>,
  readerName: string | null,
  opts: { blocks?: boolean } = {},
): string {
  const wantBlocks = opts.blocks !== false;
  const list = chunks
    .map((c, i) => {
      let slot: string | null = null;
      let alts: string[] = [];
      if ("blocks" in c && c.blocks) {
        const s = c.blocks.find((b) => b.slot);
        if (s) {
          slot = s.text;
          alts = (s.alts ?? []).map((a) => a.text);
        }
      } else if ("slot" in c) {
        slot = c.slot;
        alts = c.alts;
      }
      return `${i + 1}. 塊: ${c.text}　文: ${c.sentence}${slot ? `　入れ替える所: ${slot}（候補: ${alts.join("、")}）` : ""}`;
    })
    .join("\n");
  const asks: string[] = [];
  if (wantBlocks) {
    asks.push(
      `blocks: 塊を、台湾のネイティブが一息に言う単位で区切る（ネイティブが 1 語として言う物 — 筆袋裡・半糖去冰・一下 — は分けない。` +
        `入れ替える所がある塊は、その字が 1 つの block になるように切る）。block の字を全部つなぐと塊と 1 字も違わないこと。` +
        `各 block に pos（台湾の詞類表の記号: N / V / Vs / Adv / Prep / Ptc / Det / Conj）。`,
    );
  }
  if (readerName) {
    asks.push(
      `ja（塊の自然な ${readerName} 訳）、sentence_ja（文の自然な ${readerName} 訳）、note（${readerName} で 1 文・40 字まで。使う場面・ニュアンス・` +
        `間違えやすい所のうち役に立つ 1 つ。訳の言い直し・一般論は書かない）、入れ替える所があれば slot_ja（その語の意味）と alts_ja` +
        `（候補それぞれの意味、同じ順）。${readerName} 以外の言語を混ぜない。`,
    );
  }
  const shape = [
    `"i":1`,
    ...(wantBlocks ? [`"blocks":[{"text":"","pos":""}]`] : []),
    ...(readerName ? [`"ja":""`, `"sentence_ja":""`, `"note":""`, `"slot_ja":""`, `"alts_ja":[""]`] : []),
  ].join(",");
  return [
    `台湾華語の学習アプリ。下の「${headword.trim()}」の言い方（塊）と文について、各候補に次を付けてください。中国語の字は 1 字も変えない。`,
    ...asks.map((a) => `- ${a}`),
    ``,
    list,
    ``,
    `返す形（JSON だけ）: {"items":[{${shape}}]}`,
  ].join("\n");
}
