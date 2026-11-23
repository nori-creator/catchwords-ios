/**
 * **打った句から物の名前だけを見出し語にする**（オーナー指示 2026-11-23）。
 *
 * > クラスメイトが「リストにない言葉を探す」に「一杯のコーヒー」と入力したら、そのまま単語になった。
 * > 一杯のコーヒーのような物を入力した場合、コーヒーだけを単語として抽出するようにして。
 *
 * 本番では AI が 一杯咖啡 を見出し語に返し、量詞の欄も「一杯」+ 見出し語（一杯咖啡）で量が二重になった。
 * 句（数・量詞・この/その・〜の）の判断は AI の指示文で頼み（`TYPED_HEAD_NOUN_RULE`）、AI がそれでも句を返した時に
 * サーバーで確かめられる形 — **数や指示の語＋量詞が頭に付いた形**（一杯咖啡・兩顆蘋果・這杯咖啡・每一本書）—
 * だけをここで外す。形容詞（紅蘋果）や「〜的」は見出し語として定着した語と見分けられないので、ここでは触らない
 * （AI の指示文だけ）。定着した複合語（珍珠奶茶・雨傘・滾筒黏毛器・三明治・五花肉・九層塔）は割らない:
 * 頭の字が数でも、次の字が量詞の一覧に無ければそのまま。
 */

/** 数（量の頭に付く字）。千・百・萬は語の一部（千層麵・百香果・萬用鍋）に多いので入れない。 */
const NUMERALS = "一二兩三四五六七八九十幾半";
/** 指示・全部の語（這杯・那顆・每一本）。 */
const DEMONSTRATIVES = ["這", "那", "每", "哪"];
/**
 * 量詞（物を数える字）。語の2字目に普通に来る字（層・花・明・角・季・寶・字）は入れない — 九層塔・五花肉・三明治
 * ・三角板・四季豆・八寶粥・十字路口を割らないため。
 */
const MEASURES = new Set(
  "杯個隻張份條本瓶碗盤塊顆片件雙台臺輛支枝把盒包罐袋串朵棵位間家粒根頂座副套盞匹頭株捲疊箱桶壺籃鍋".split(""),
);

export type HeadNoun = {
  /** 見出し語にする物の名前（外す物が無ければ元の語）。 */
  headword: string;
  /** 外した頭（一杯・這杯・每一本）。無ければ空。 */
  stripped: string;
};

/**
 * 頭の「数／指示の語 + 量詞（+ 的）」を外す。外した後が2字に満たない・漢字でない時は外さない（一杯 だけ・一個人 の
 * 人 1字は語として残す — 1字の名詞は単独で言う形が別にあるので、外すと別の語になる）。
 */
export function headNounOf(headword: string): HeadNoun {
  const w = (headword ?? "").trim();
  const chars = Array.from(w);
  let i = 0;
  if (DEMONSTRATIVES.includes(chars[0] ?? "")) i = 1;
  const numStart = i;
  while (i < chars.length && NUMERALS.includes(chars[i])) i++;
  const hadNumber = i > numStart;
  // 量詞の無い「一 + 名詞」は割らない（一般・一樓 などの語がある）。指示の語だけ（這咖啡）も割らない。
  if (!MEASURES.has(chars[i] ?? "")) return { headword: w, stripped: "" };
  if (!hadNumber && i === 0) return { headword: w, stripped: "" };
  i++;
  if (chars[i] === "的") i++;
  const rest = chars.slice(i).join("");
  if (Array.from(rest).length < 2 || !/^\p{Script=Han}+$/u.test(rest)) return { headword: w, stripped: "" };
  return { headword: rest, stripped: chars.slice(0, i).join("") };
}

/**
 * 外した字数だけ、読みの頭も外す。注音は1字1音（空白区切り）。拼音は語ごとにまとめて書かれる（kāfēi）ことがあるが、
 * 数と量詞は必ず1字ずつ別に書かれる（yī bēi）ので、頭から外した字数ぶんの音を外す。音の数が足りない時は空にする
 * （後の読みの確かめ `correctTaiwanReading` と、カード作りが埋める）。
 */
export function dropLeadingSyllables(reading: string, count: number): string {
  if (count <= 0) return reading ?? "";
  const parts = (reading ?? "").trim().split(/\s+/).filter(Boolean);
  if (parts.length <= count) return "";
  return parts.slice(count).join(" ");
}

/** 候補1つに当てる: 見出し語と2つの読みを、物の名前だけの形にそろえる。 */
export function toHeadNoun<T extends { headword: string; reading_zhuyin?: string; pinyin?: string }>(c: T): T {
  const h = headNounOf(c.headword);
  if (!h.stripped) return c;
  const n = Array.from(h.stripped).length; // 的 も1音（de）
  return {
    ...c,
    headword: h.headword,
    reading_zhuyin: dropLeadingSyllables(c.reading_zhuyin ?? "", n),
    pinyin: dropLeadingSyllables(c.pinyin ?? "", n),
  };
}

/**
 * 量詞の欄の1つが、見出し語の頭と同じ量を持っているか（見出し語 一杯咖啡 に 一杯）。古い語（句のまま保存された物）
 * の量詞の欄で、量を二重に出さないための確かめ。
 */
export function measureRepeatsHeadword(measure: string, headword: string): boolean {
  const h = headNounOf(headword);
  if (!h.stripped) return false;
  const m = (measure ?? "").trim();
  const bare = m.replace(new RegExp(`^[${NUMERALS}]+`), "");
  return m === h.stripped || (bare.length > 0 && h.stripped.replace(/的$/, "").endsWith(bare));
}

/**
 * 表示言語の名前（`object_label`）と表の基本の語（`ensureTypedBasic`）を引く時の、打った物の名前。AI が取り出した名前
 * （`query_noun`、「一杯のコーヒー」→「コーヒー」）があればそれ、無ければ打った物のまま。
 */
export function typedNounText(query: string, queryNoun: string | null | undefined): string {
  const n = (queryNoun ?? "").trim();
  return n && Array.from(n).length <= 40 ? n : query;
}

/**
 * AI への指示（`suggestWordCandidates`）。**何を打たれても、覚えたい物の名詞を1つ取り出す**（オーナー 2026-11-23
 * 「ユーザーが検索欄に入力したら、それに基づいて最適な名詞を抽出して」）。前の「品詞を選ばない（動詞なら動詞）」
 * （2026-08-20）はこれで置き換えた — ただし 08-20 の不具合（動詞を打った人に0件 →「学んでいる言語の単語ではありません」）
 * に戻らないよう、**必ず1つ以上返す**ことは残す。
 */
export const TYPED_HEAD_NOUN_RULE = `- **打たれた物から、覚えたい物の名詞を取り出して見出し語にする。** 学習者が打つのは1語とは限らない
  （数・量・入れ物・この/その・持ち主・色や大きさ付き、文、説明、動詞句、別の言語の語:
  「一杯のコーヒー」「a cup of coffee」「2個のりんご」「赤いりんご」「私の傘」「雨の日にさすもの」「コーヒーを飲む」）。
  どれでも、**その入力に基づいて学習者が覚えたい物の名詞**を選び、headword は**その名詞だけ**
  （咖啡・蘋果・雨傘）— 一杯咖啡・兩顆蘋果・紅蘋果・我的雨傘・喝咖啡 のような**句を見出し語にしない**。
  数や量詞・形容詞・動詞は使い方と例文で学ぶので、見出し語には入れない。
  物を指さない語（「走る」「速い」）だけを打たれても、**0件にしない**: その動きや様子をいちばんよく表す名詞（跑步・速度）を返す。
  **それ自体が1つの語として定着している名前は割らない**（珍珠奶茶・雨傘・滾筒黏毛器・三明治・紅茶・黑板）:
  辞書に1語として載る・その物の普通の呼び名なら、そのまま1つの語。
- query_noun には、取り出した物の名前を**学習者が打った言語の短い名前**で書く（「一杯のコーヒー」→「コーヒー」、
  「a cup of coffee」→「coffee」）。打った物がもう名前1つなら、その名前のまま。`;
