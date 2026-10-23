/**
 * **候補の「どんな言い方か」の印（1本の物差し）**。オーナー指示 2026-10-15:
 *
 * > 写真のタグは台湾の人がふだんいちばんよく使う言い方。詳しい名前・固有名詞にしない。
 * > 候補は「一般的な言い方」を上に、口語・より詳しい言い方・学術的な言い方・固有名詞の順で下へ。
 * > どの候補にも必ず印を付ける: 一般的な言い方 / 口語 / より詳しい言い方 / 学術的な言い方 / 固有名詞。
 *
 * 前は道ごとに別の物差しだった — 写真の候補は `common|casual|specific|proper`、打った語の候補は
 * 文体（`spoken|written|both|technical|signage`）。iOS は写真の4つしか知らないので、打った語の候補
 * （例: ボクサーパンツ → 平口褲 / 四角褲 / 內褲）には**印が1つも出なかった**。いまは全部の候補の
 * `register` がこの5つのどれか（文体は打った語の候補の `style` に移した）。
 *
 * 写真・打った語・スキャン・チュートリアルの候補が全部ここを通る（`finalizeNameRegisters`）。
 */

/** 並びの順（上ほど先）。 */
export const NAME_REGISTERS = ["common", "colloquial", "specific", "academic", "proper"] as const;
export type NameRegister = (typeof NAME_REGISTERS)[number];

const RANK: Record<NameRegister, number> = {
  common: 0,
  colloquial: 1,
  specific: 2,
  academic: 3,
  proper: 4,
};

/** 並べ替えの段（知らない値・空は一般的な言い方と同じ段）。 */
export function nameRegisterRank(r: string | null | undefined): number {
  return RANK[(r ?? "") as NameRegister] ?? 0;
}

/** 画面の札の言葉（オーナーの呼び名）。iOS もこの言葉を使う。 */
export const NAME_REGISTER_LABELS = {
  common: {
    ja: "一般的な言い方",
    en: "Common",
    "zh-TW": "一般說法",
  },
  colloquial: {
    ja: "口語",
    en: "Colloquial",
    "zh-TW": "口語",
  },
  specific: {
    ja: "より詳しい言い方",
    en: "More specific",
    "zh-TW": "更具體的說法",
  },
  academic: {
    ja: "学術的な言い方",
    en: "Academic / technical",
    "zh-TW": "學術說法",
  },
  proper: {
    ja: "固有名詞",
    en: "Proper noun",
    "zh-TW": "專有名詞",
  },
} satisfies Record<NameRegister, Record<string, string>>;

/**
 * AI が返した印を5つのどれかに直す。読めなければ `null`（呼ぶ側が埋める）。
 *
 * 古い印も読む: 写真の `casual` → colloquial、打った語の文体 `spoken` → colloquial、
 * `technical` → academic、`both` / `signage` / `written` → common。
 */
export function normalizeNameRegister(raw: unknown): NameRegister | null {
  if (typeof raw !== "string") return null;
  const v = raw.trim().toLowerCase();
  if (!v) return null;
  if ((NAME_REGISTERS as readonly string[]).includes(v)) return v as NameRegister;
  if (/^(casual|informal|spoken|slang|colloq|口語|口语|俗|くだけ|砕け)/.test(v))
    return "colloquial";
  if (
    /^(academic|technical|scientific|specialist|professional|jargon|學術|学術|学术|專業|専門)/.test(
      v,
    )
  )
    return "academic";
  if (/^(proper|brand|trademark|name of|固有|商標|品牌|專有)/.test(v)) return "proper";
  if (/^(specific|detailed|narrow|precise|formal name|正式|詳しい|くわしい|更具體)/.test(v))
    return "specific";
  if (/^(common|general|standard|neutral|everyday|both|signage|written|一般|普通|ふだん)/.test(v))
    return "common";
  return null;
}

type Groupable = { register?: unknown; group?: number | null };

/**
 * **全部の候補に印を付け、決まった順に並べる**（AI は呼ばない）。
 *
 * - 物ごと（`group`）に分ける。番号が無い候補は全部で1つの物（打った語の候補）。物の並びは AI の順のまま。
 * - 読めない・無い印を埋める: その物の1つ目 → common、2つ目から → specific（同じ物の別の名前は、
 *   ふつうはより詳しい名前）。
 * - 物の中を common → colloquial → specific → academic → proper に並べる。同じ段の中は AI の順（よく使う順）。
 * - **物の1つ目は必ず一般的な言い方**: common が1つも無い物は、固有名詞でない最初の候補を先頭に出して
 *   common にする（タグに詳しい名前・固有名詞を出さない）。全部が固有名詞の物だけはそのまま。
 */
export function finalizeNameRegisters<T extends Groupable>(
  items: readonly T[],
): Array<T & { register: NameRegister }> {
  const order: string[] = [];
  const buckets = new Map<string, Array<T & { register: NameRegister }>>();
  for (const it of items) {
    const key = typeof it.group === "number" ? `g${it.group}` : "all";
    if (!buckets.has(key)) {
      buckets.set(key, []);
      order.push(key);
    }
    const bucket = buckets.get(key)!;
    const register =
      normalizeNameRegister(it.register) ?? (bucket.length === 0 ? "common" : "specific");
    bucket.push({ ...it, register });
  }
  const out: Array<T & { register: NameRegister }> = [];
  for (const key of order) {
    const sorted = buckets
      .get(key)!
      .map((it, i) => ({ it, i }))
      .sort((a, b) => RANK[a.it.register] - RANK[b.it.register] || a.i - b.i)
      .map((x) => x.it);
    if (sorted.length > 0 && sorted[0].register !== "common") {
      const k = sorted.findIndex((c) => c.register !== "proper");
      if (k >= 0) {
        const [promoted] = sorted.splice(k, 1);
        sorted.unshift({ ...promoted, register: "common" });
      }
    }
    out.push(...sorted);
  }
  return out;
}

/** 指示文に入れる印の説明（写真・打った語・スキャンで同じ文）。 */
export const NAME_REGISTER_RULE =
  `register は**どの候補にも必ず1つ**、次のどれか: ` +
  `common（一般的な言い方: その土地の人がその物を指して日常会話でいちばん自然に口にする語）/ ` +
  `colloquial（口語: 会話だけで使うくだけた言い方・略語）/ ` +
  `specific（より詳しい言い方: もっと狭い種類の名前・正式な名前）/ ` +
  `academic（学術的な言い方: 専門用語・学名・業界の言葉）/ ` +
  `proper（固有名詞: 商品名・ブランド・店名）。` +
  `\n並びは common → colloquial → specific → academic → proper。同じ印の中はよく使う順。` +
  `**1つ目は必ず common**（タグとして写真に出るのはこの語）。詳しい名前・固有名詞を1つ目にしない。` +
  `ただし上位の分類語（衣服・肉・飲み物）に逃げない — その物をふだん何と呼ぶかで決める。` +
  `例: ボクサーパンツの写真 → common 內褲（台湾の人がふだんそう呼ぶ。写真のタグは「下着」）、specific 平口褲・四角褲（より狭い種類の名前）。`;

/**
 * **写真の物の1つ目（common）は基本の名詞**（オーナー指示 2026-10-15: コスモスの花束 →「花」、
 * イチゴのショートケーキ →「ケーキ」、ボクサーパンツ →「下着」）。写真・スキャンの指示文に入れる
 * （打った語の候補には入れない — 打った人が選んだ細かい名前はそのまま返す）。手元の確かめは `basic-level.ts`。
 */
export const BASIC_LEVEL_RULE =
  `**物ごとの1つ目（common）は、子どもでも最初に言う基本の名詞**（花・蛋糕・狗・貓・內褲・椅子・麵包）。` +
  `種類・品種・味・ブランドの名前（波斯菊・草莓蛋糕・柴犬・四角褲）は1つ目にせず、同じ group の specific に置く。` +
  `上位の分類語（植物・食物・動物・衣服）にも上げない。` +
  `\n例（common → specific）: コスモスの花束 → 花 → 波斯菊・花束 / イチゴのショートケーキ → 蛋糕 → 草莓蛋糕・鮮奶油蛋糕 / ` +
  `柴犬 → 狗 → 柴犬 / キジトラの猫 → 貓 → 虎斑貓 / ボクサーパンツ → 內褲 → 平口褲・四角褲 / 木の椅子 → 椅子 → 木椅。` +
  `\n**細かい名前しか思いつかない物にも、その上の基本の語を common として必ず足して1つ目に置く。**` +
  `料理の名前（三杯雞・牛肉麵）や服の種類（短袖・T恤）のように、その名前自体がふだんの呼び名の物はそのままでよい。`;

/**
 * 意味の最初の言い方（読点・カンマ・セミコロン・スラッシュの前、括弧書きを除く）。
 * 「下着、パンツ」→「下着」、「underwear, briefs」→「underwear」。中黒（ボクサー・パンツ）では切らない。
 */
export function firstGloss(meaning: string | null | undefined): string {
  return glossesOf(meaning)[0] ?? "";
}

/** 意味の言い方を全部（`firstGloss` と同じ区切り。空は落とす）。「パンツ、下着」→ [パンツ, 下着]。 */
export function glossesOf(meaning: string | null | undefined): string[] {
  return (meaning ?? "")
    .replace(/[（(][^）)]*[）)]/g, "")
    .split(/[、,，;；/／\n]/)
    .map((t) =>
      t
        .trim()
        .replace(/[。.]+$/u, "")
        .trim(),
    )
    .filter(Boolean);
}

/**
 * **写真のタグ（写っている物の名前）は、その物の1つ目の候補（common）の本当の意味の言い方**
 * （オーナー決定 2026-10-15: ボクサーパンツの写真のタグは「下着」、タップすると 內褲。同日の不具合:
 * ケーキのタグをタップすると 草莓蛋糕 だった —「ショートケーキが草莓蛋糕だよね」）。
 *
 * - 1つ目が表の基本の語（貓・狗・內褲… `basic-level.ts`）なら、タグは表の表示言語の名前（猫 / cat / 貓）—
 *   呼ぶ側が `rowTag` で渡す。基本の語の名前は表が知っているので、AI の label・意味の書き間違い（2026-10-15:
 *   貓 に「犬」）をタグにしない。
 * - それ以外は1つ目の候補の意味の言い方のどれか。AI が付けた `label` がその中に在ればそれ（「パンツ、下着」と
 *   label「下着」→「下着」）、無ければ意味の最初の言い方。読む人の言語でなければ空（画面は見出し語を出す）。
 * - **候補の意味は書き換えない**（#184 は1つ目の意味をタグに書き換えていて、草莓蛋糕 の意味が「ケーキ」に
 *   なった）。タグに合う基本の語（蛋糕 = ケーキ）が候補に無い時は、先に `ensureBasicLevel` が足す。
 * - 物の全部の候補に `object_label`（タグの文字）を付ける。
 *
 * `finalizeNameRegisters`（と写真なら `ensureBasicLevel`）の後に呼ぶ（物の1つ目が common になっている前提）。
 */
export function applyObjectLabels<
  T extends { group?: number | null; meaning_ja?: string; label?: string | null },
>(
  items: readonly T[],
  /** 読む人の言語の言葉か（`common` = その物の1つ目の候補。見出し語の写しを落とすのに使う）。 */
  isReaderText: (text: string, common: T) => boolean,
  /** 1つ目の候補が表の基本の語なら、そのタグ（`rowTagOf`）。無ければ `null`（意味から選ぶ）。 */
  rowTag?: (common: T) => string | null | undefined,
): Array<Omit<T, "label"> & { object_label: string }> {
  const groups = new Map<string, T[]>();
  for (const it of items) {
    const key = typeof it.group === "number" ? `g${it.group}` : "all";
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key)!.push(it);
  }
  const labelOf = new Map<string, string>();
  for (const [key, list] of groups) {
    const common = list[0];
    const fixed = rowTag?.(common)?.trim();
    if (fixed) {
      labelOf.set(key, fixed);
      continue;
    }
    const glosses = glossesOf(common.meaning_ja).filter((g) => isReaderText(g, common));
    const fromModel = list
      .map((c) => firstGloss(c.label ?? ""))
      .find((l) => l && glosses.includes(l));
    labelOf.set(key, fromModel ?? glosses[0] ?? "");
  }
  return items.map((it) => {
    const { label: _label, ...rest } = it;
    void _label;
    const key = typeof it.group === "number" ? `g${it.group}` : "all";
    return { ...rest, object_label: labelOf.get(key) ?? "" } as Omit<T, "label"> & {
      object_label: string;
    };
  });
}

/** 指示文に入れるタグの説明（写真の候補）。`nl` は解説の言語の呼び名。 */
export function objectLabelRule(nl: string): string {
  return (
    `物ごとに、**1つ目（common）の候補に label を付ける**: 写っている物の**${nl}でのいちばん一般的な呼び名**` +
    `（その common の語の${nl}の訳。写真のタグに出る）。${nl}を話す子どもがその物を見て最初に言う基本の名詞にする — ` +
    `種類・品種・味・ブランドの名前、説明、上位の分類語（植物・食べ物・衣類）にしない。` +
    `例: ボクサーパンツ → label「下着」（內褲の訳。英語なら underwear。「ボクサーパンツ」「パンツ」「男性用の下着」にしない）/ ` +
    `コスモスの花束 → 「花」（「コスモス」「花束」にしない）/ イチゴのショートケーキ → 「ケーキ」（「ストロベリーケーキ」` +
    `「イチゴのケーキ」にしない）/ 柴犬 → 「犬」/ キジトラの猫 → 「猫」/ 木の椅子 → 「椅子」。` +
    `label と common の語は同じ物を指す（蛋糕 ↔ ケーキ、花 ↔ 花）。common の候補の meaning_ja も label と同じ言い方から始める。` +
    `**label と meaning_ja は、その写真の物の common の headword そのものを${nl}に訳した語**（上の例の語を写さない。` +
    `例: 貓 → 日本語「猫」・英語 cat、狗 → 日本語「犬」・英語 dog）。`
  );
}
