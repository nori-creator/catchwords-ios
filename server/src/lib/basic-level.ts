/**
 * **写真のタグは、その物を指す「いちばんふつうの名前」**（基本レベルの語。オーナー指示 2026-10-15）。
 *
 * > 花束の写真のタグが「コスモス」— 細かすぎる。「花」にして。イチゴのショートケーキは「ストロベリーケーキ」
 * > ではなく「ケーキ」。ボクサーパンツは「下着」。
 *
 * タグは**その土地の子どもが最初に口にする日常の名詞**（花・ケーキ・犬・下着・椅子）。種類・品種・味・
 * ブランドの名前（コスモス・ストロベリーケーキ・柴犬・ボクサーパンツ）にしない。逆に上位の分類語
 * （植物・食べ物・動物・衣類）にも上げない。細かい名前は消さずに、その下の候補に「より詳しい言い方」で並べる:
 *
 *   花 → 花（一般的）/ 波斯菊・花束（より詳しい）
 *   ケーキ → 蛋糕（一般的）/ 草莓蛋糕・鮮奶油蛋糕（より詳しい）
 *
 * 指示文でそう頼む（`candidate-register.ts` の `NAME_REGISTER_RULE` / `objectLabelRule`）うえで、ここは
 * **よく取り違える物だけ**を手元の表で確かめる（AI は呼ばない）:
 *
 * - `ensureBasicLevel` — 物（`group`）の1つ目の候補が表の「細かい名前」（波斯菊・草莓蛋糕・柴犬・四角褲）か、
 *   AI の付けたタグが表の基本の名前・細かい名前（ケーキ・ストロベリーケーキ・犬・下着）なのに1つ目がその基本の語で
 *   ないなら、表の基本の語（花・蛋糕・狗・內褲）を一般的な言い方として先頭に入れる（既に在れば先頭へ移す）。
 *   元の1つ目は「より詳しい言い方」に下げ、**意味はそのまま**（草莓蛋糕 は「いちごのショートケーキ」のまま）。
 *   足した基本の語の意味は表の基本の名前（蛋糕 = ケーキ）なので、タグ（1つ目の本当の意味、`applyObjectLabels`）も
 *   ケーキになる。
 *
 * 2026-10-15 の不具合（#184）: ケーキの写真で AI が 草莓蛋糕 を1つだけ返し、タグ「ケーキ」に合わせて 草莓蛋糕 の
 * 意味を「ケーキ」に書き換えていた。候補が1つなので画面は選ばせずに 草莓蛋糕 をキャッチした。
 *
 * 表に無い物は AI の答えのまま（無理に上げない）。表は台湾華語の見出し語だけ（いまの学習者の言語）。
 */
import { coerceCategoryKey, normalizeCategory, type CategoryKey } from "./category";
import { firstGloss } from "./candidate-register";
import type { UiLang } from "./i18n";

export type BasicLevelEntry = {
  /** 学習言語（台湾華語）の基本の語。 */
  headword: string;
  reading_zhuyin: string;
  pinyin: string;
  category: CategoryKey;
  /** 表示言語の基本の名前（写真のタグ）。 */
  label: Record<UiLang, string>;
  /** その基本の語の「細かい名前」か（学習言語の見出し語）。基本の語そのものは当たらない。 */
  narrower: (headword: string) => boolean;
  /** 表示言語のタグがこの物の細かい名前か（ストロベリーケーキ・柴犬・ボクサーパンツ。`entryForLabel`）。 */
  labelNarrower: Partial<Record<UiLang, RegExp>>;
  /**
   * 表示言語で**この物そのもの**を指す別の書き方（ネコ・子猫・cats / イヌ・puppy / パンツ）。タグにも基本の語を
   * 足す手掛かりにもしないが、意味やタグが**どの行の物を指しているか**を見分けるのに使う（`rowNamedBy`）。
   */
  labelAlso?: Partial<Record<UiLang, RegExp>>;
  /**
   * 学習言語で**この物そのもの**を指す口語・愛称（貓咪・小貓 / 狗狗・小狗）。細かい名前ではない（`narrower` は
   * 当たらない）が、その語の意味が別の行の物（貓咪 =「犬」）なら取り違えと分かる（`rowOfHeadword`）。
   */
  forms?: readonly string[];
  /**
   * 表示言語でその名前を打った人に、この基本の語を一般的な言い方として返してよいか（犬 → 狗・ケーキ → 蛋糕。
   * `typed-candidates.ts`）。学習言語の言い方が割れる物（下着 → 內褲・內衣）と、字が同じ物（花・椅子）は false。
   */
  typedFromReader: boolean;
};

/**
 * 「〜花」でも花ではない物（火花 = 火の粉、棉花 = 綿、水花 = 水しぶき、淚花 = 涙、校花・交際花・姊妹花 = 人、
 * 天花 = 天然痘）。`category.ts` の語末の規則では「花」に入るので、ここで外す（花火の写真に「花」を出さない）。
 */
const NOT_FLOWERS = new Set(["火花", "棉花", "水花", "淚花", "校花", "交際花", "姊妹花", "天花"]);

/** 花の種類の名前・花をまとめた物（`category.ts` の規則で「花」に入る物）。花そのものは除く。 */
const isFlowerKind = (h: string) =>
  h !== "花" && !NOT_FLOWERS.has(h) && normalizeCategory(h, null) === "flower";

/**
 * 「〜狗・〜犬」でも犬ではない物（海狗 = オットセイ、天狗 = 天狗、單身狗 = 独り身の人、走狗 = 手先、熱狗 =
 * ホットドッグ）と、犬の口語（狗狗・小狗）。**米克斯**（ミックス）は犬にも猫にも使うので、どちらの細かい名前にも
 * しない（猫の写真の 米克斯 に 狗・「犬」を足していた）。米克斯犬・米克斯貓 は語末で決まる。
 */
const NOT_DOGS = new Set(["狗", "狗狗", "小狗", "熱狗", "犬", "海狗", "天狗", "單身狗", "走狗"]);

/**
 * 「〜貓」でも猫ではない物（熊貓・大熊貓・小熊貓 = パンダ、狸貓 = タヌキ、麝香貓 = ジャコウネコ科、海貓 = ウミネコ
 * （鳥）、山貓 = ヤマネコ・重機の名前、招財貓 = 招き猫、加菲貓 = キャラクター）と、猫の口語（貓咪・小貓）。
 */
const NOT_CATS = new Set([
  "貓",
  "貓咪",
  "小貓",
  "熊貓",
  "大熊貓",
  "小熊貓",
  "狸貓",
  "麝香貓",
  "海貓",
  "山貓",
  "招財貓",
  "加菲貓",
  "貓頭鷹",
]);

export const BASIC_LEVEL_ZH_TW: readonly BasicLevelEntry[] = [
  {
    headword: "花",
    typedFromReader: false,
    reading_zhuyin: "ㄏㄨㄚ",
    pinyin: "huā",
    category: "flower",
    label: {
      ja: "花",
      en: "flower",
      "zh-TW": "花",
    },
    narrower: isFlowerKind,
    labelNarrower: {
      ja: /^(.+の花|.+花束|花束|ブーケ|コスモス|バラ|薔薇|チューリップ|ヒマワリ|ひまわり|向日葵|ユリ|百合|カーネーション|アジサイ|紫陽花|ラベンダー|マーガレット|デイジー|カスミソウ|かすみ草)$/,
      en: /^(.+ flowers?|bouquet|.+ bouquet|roses?|tulips?|sunflowers?|lil(y|ies)|daisies|daisy|cosmos|carnations?)$/i,
      "zh-TW": /^(.+花束|花束|捧花|玫瑰|波斯菊|向日葵|鬱金香|百合|康乃馨|滿天星)$/,
    },
    labelAlso: {
      ja: /^(はな|ハナ|お花)$/,
      en: /^(flowers|blossoms?)$/i,
      "zh-TW": /^(花朵|花兒|鮮花)$/,
    },
    forms: ["花朵", "花兒"],
  },
  {
    headword: "蛋糕",
    typedFromReader: true,
    reading_zhuyin: "ㄉㄢˋ ㄍㄠ",
    pinyin: "dàngāo",
    category: "dessert",
    label: {
      ja: "ケーキ",
      en: "cake",
      "zh-TW": "蛋糕",
    },
    // 草莓蛋糕・鮮奶油蛋糕・起司蛋糕・生日蛋糕（味・種類の名前）。雞蛋糕（台湾の屋台のお菓子）は別の物。
    narrower: (h) => h.length > 2 && h.endsWith("蛋糕") && h !== "雞蛋糕",
    labelNarrower: {
      // パンケーキ・ホットケーキは別の物（ケーキに直さない）。
      ja: /^(?!.*(パンケーキ|ホットケーキ)).+ケーキ$/,
      en: /^.+ cakes?$/i,
      "zh-TW": /^.+蛋糕$/,
    },
    labelAlso: { en: /^cakes$/i },
  },
  {
    headword: "狗",
    typedFromReader: true,
    reading_zhuyin: "ㄍㄡˇ",
    pinyin: "gǒu",
    category: "animal",
    label: {
      ja: "犬",
      en: "dog",
      "zh-TW": "狗",
    },
    // 犬の種類（柴犬・柯基・貴賓狗…）。犬ではない「〜狗」・口語の言い方・米克斯は `NOT_DOGS` の注。
    narrower: (h) =>
      !NOT_DOGS.has(h) &&
      (/^(柴犬|柯基|柯基犬|威爾斯柯基犬|哈士奇|貴賓|貴賓狗|貴賓犬|黃金獵犬|拉布拉多|吉娃娃|博美|臘腸狗|法鬥|法國鬥牛犬|雪納瑞|馬爾濟斯|秋田犬)$/.test(
        h,
      ) ||
        /^.{1,4}(犬|狗)$/.test(h)),
    labelNarrower: {
      ja: /^(?!.*(ホットドッグ|子犬|小犬)).+犬$|^(コーギー|プードル|チワワ|ハスキー|ダックスフンド|ポメラニアン|ゴールデンレトリバー|ラブラドール|シュナウザー|マルチーズ)$/,
      en: /^(?!hot ?dog).+ dogs?$|^(corgis?|poodles?|chihuahuas?|huskies|husky|dachshunds?|pomeranians?|golden retrievers?|labradors?|shiba inu)$/i,
    },
    labelAlso: {
      ja: /^(イヌ|いぬ|ワンちゃん|わんちゃん|ワンコ|わんこ|子犬|仔犬|小犬)$/,
      en: /^(dogs|doggy|doggie|pupp(y|ies)|pups?)$/i,
      "zh-TW": /^(狗狗|小狗|犬)$/,
    },
    forms: ["狗狗", "小狗"],
  },
  {
    headword: "貓",
    typedFromReader: true,
    reading_zhuyin: "ㄇㄠ",
    pinyin: "māo",
    category: "animal",
    label: {
      ja: "猫",
      en: "cat",
      "zh-TW": "貓",
    },
    // 猫の種類（波斯貓・英國短毛貓・橘貓・虎斑貓）。猫ではない「〜貓」・口語の言い方は `NOT_CATS` の注。
    narrower: (h) => !NOT_CATS.has(h) && /^.{1,5}貓$/.test(h),
    labelNarrower: {
      ja: /^(?!.*(招き猫|子猫|仔猫)).+猫$/,
      en: /^(?!.*bobcat).+ cats?$/i,
    },
    labelAlso: {
      ja: /^(ネコ|ねこ|猫ちゃん|ネコちゃん|ねこちゃん|にゃんこ|ニャンコ|子猫|仔猫|子ネコ|こねこ)$/,
      en: /^(cats|kitty|kitties|kittens?|pussycats?)$/i,
      // 台湾の字で読む人にとって「猫」は簡体字・日本の字の同じ物（タグには表の「貓」を出す）。
      "zh-TW": /^(猫|貓咪|小貓)$/,
    },
    forms: ["貓咪", "小貓"],
  },
  {
    headword: "內褲",
    typedFromReader: false,
    reading_zhuyin: "ㄋㄟˋ ㄎㄨˋ",
    pinyin: "nèikù",
    category: "clothes",
    label: {
      ja: "下着",
      en: "underwear",
      "zh-TW": "內褲",
    },
    // ボクサーパンツ（平口褲・四角褲）・ブリーフ（三角褲）など。
    narrower: (h) =>
      h !== "內褲" && /^(平口褲|四角褲|三角褲|丁字褲|男用內褲|女用內褲|.{1,4}內褲)$/.test(h),
    labelNarrower: {
      ja: /^(ボクサーパンツ|ボクサーブリーフ|トランクス|ブリーフ|ショーツ|.+用下着|.+の下着|男性用パンツ|女性用パンツ)$/,
      en: /^(boxer briefs|boxer shorts|boxers|briefs|panties|.+ underwear)$/i,
      "zh-TW": /^(平口褲|四角褲|三角褲|丁字褲)$/,
    },
    labelAlso: { ja: /^(パンツ)$/, en: /^(underpants|undies|knickers)$/i },
  },
  {
    headword: "椅子",
    typedFromReader: false,
    reading_zhuyin: "ㄧˇ ˙ㄗ",
    pinyin: "yǐzi",
    category: "furniture",
    label: {
      ja: "椅子",
      en: "chair",
      "zh-TW": "椅子",
    },
    // 木椅・辦公椅・餐椅・摺疊椅（種類の名前）。輪椅（車椅子）は別の物なので除く。
    narrower: (h) => !["椅子", "輪椅"].includes(h) && /^.{1,4}椅(子)?$/.test(h),
    labelNarrower: {
      ja: /^(?!.*車椅子).+椅子$|^.+チェア$/,
      en: /^(?!.*wheel).+ chairs?$/i,
    },
    labelAlso: { ja: /^(いす|イス|チェア)$/, en: /^chairs$/i },
  },
  {
    headword: "麵包",
    typedFromReader: true,
    reading_zhuyin: "ㄇㄧㄢˋ ㄅㄠ",
    pinyin: "miànbāo",
    category: "dessert",
    label: {
      ja: "パン",
      en: "bread",
      "zh-TW": "麵包",
    },
    // 抹茶麵包・全麥麵包（味・種類の名前）。
    narrower: (h) => h.length > 2 && h.endsWith("麵包"),
    labelNarrower: {
      ja: /^(?!.*(フライパン|ジーパン|短パン|海パン|長パン)).+の?パン$/,
      en: /^.+ bread$/i,
      "zh-TW": /^.+麵包$/,
    },
    labelAlso: { en: /^(breads|loaf|loaves)$/i },
  },
  {
    headword: "冰淇淋",
    typedFromReader: true,
    reading_zhuyin: "ㄅㄧㄥ ㄑㄧˊ ㄌㄧㄣˊ",
    pinyin: "bīngqílín",
    category: "dessert",
    label: {
      ja: "アイスクリーム",
      en: "ice cream",
      "zh-TW": "冰淇淋",
    },
    narrower: (h) => h.length > 3 && h.endsWith("冰淇淋"),
    labelNarrower: {
      ja: /^.+(アイスクリーム|アイス)$/,
      en: /^.+ ice cream$/i,
      "zh-TW": /^.+冰淇淋$/,
    },
    labelAlso: { ja: /^(アイス)$/, en: /^(ice-cream|icecream|ice creams)$/i },
  },
];

/** 学習言語の基本の語の表（いまは台湾華語だけ。他の言語は空 — 何もしない）。 */
export function basicLevelTable(targetLanguage: string): readonly BasicLevelEntry[] {
  return targetLanguage.toLowerCase().startsWith("zh") ? BASIC_LEVEL_ZH_TW : [];
}

/** その見出し語が、表のどの基本の語の「細かい名前」か（無ければ `null`）。 */
export function basicLevelOf(headword: string, targetLanguage: string): BasicLevelEntry | null {
  const h = (headword ?? "").trim();
  if (!h) return null;
  return basicLevelTable(targetLanguage).find((e) => e.narrower(h)) ?? null;
}

/**
 * AI の付けたタグ（表示言語）が指す表の基本の語（「ケーキ」「ストロベリーケーキ」→ 蛋糕、「下着」「ボクサーパンツ」→ 內褲）。
 * 表のどれにも当たらなければ `null`。
 */
export function entryForLabel(
  label: string | null | undefined,
  reader: UiLang,
  targetLanguage: string,
): BasicLevelEntry | null {
  const l = (label ?? "").trim();
  if (!l) return null;
  return (
    basicLevelTable(targetLanguage).find(
      (e) => e.label[reader] === l || (e.labelNarrower[reader]?.test(l) ?? false),
    ) ?? null
  );
}

/**
 * **表示言語の言い方（意味の1つ・タグ）が、表のどの行の物を指しているか**（犬・イヌ・柴犬 → 狗、猫・ネコ・キジトラ猫 →
 * 貓、パンツ・ボクサーパンツ → 內褲）。`entryForLabel` に、その物そのものの別の書き方（`labelAlso`）を足した物。
 * 当たらなければ `null`（表に無い物・どの行とも言えない言い方）。
 *
 * **字だけで同じ物と見なさない。** 日本語の「猫」は台湾の字の「貓」の写しではなく、読む人の言語の名前
 * （`kanji-forms.ts` の新字体）。ここは表に書いた言い方だけを見る。
 */
export function rowNamedBy(
  text: string | null | undefined,
  reader: UiLang,
  targetLanguage: string,
): BasicLevelEntry | null {
  const t = (text ?? "").trim();
  if (!t) return null;
  return (
    entryForLabel(t, reader, targetLanguage) ??
    basicLevelTable(targetLanguage).find((e) => e.labelAlso?.[reader]?.test(t) ?? false) ??
    null
  );
}

/**
 * **学習言語の見出し語が、表のどの行の物か**: 基本の語そのもの（貓）、口語・愛称（貓咪 — `forms`）、細かい名前
 * （虎斑貓 — `narrower`）。どれでもなければ `null`。
 */
export function rowOfHeadword(headword: string, targetLanguage: string): BasicLevelEntry | null {
  const h = (headword ?? "").trim();
  if (!h) return null;
  const table = basicLevelTable(targetLanguage);
  return (
    table.find((e) => e.headword === h) ??
    table.find((e) => e.forms?.includes(h) ?? false) ??
    basicLevelOf(h, targetLanguage)
  );
}

/**
 * **その語が物の1つ目の時の写真のタグ**（表の基本の語そのもの・その口語なら、表の表示言語の名前: 貓 → 猫 / cat /
 * 貓、狗 → 犬 / dog / 狗、內褲 → 下着）。表の外の語・細かい名前は `null`（`applyObjectLabels` が意味から選ぶ）。
 *
 * 基本の語の表示言語の名前は表が知っている。AI のタグ（label）や意味の書き間違い（貓 に「犬」）をタグにしない。
 */
export function rowTagOf(headword: string, reader: UiLang, targetLanguage: string): string | null {
  const h = (headword ?? "").trim();
  const row = rowOfHeadword(h, targetLanguage);
  if (!row || (row.headword !== h && !(row.forms?.includes(h) ?? false))) return null;
  return row.label[reader] || null;
}

/**
 * **候補の意味は、その語の物の意味だけ**（2026-10-15 本番: キジトラの猫の写真で 貓 の意味が「犬」、タグも「犬」）。
 *
 * AI は 貓 に label・meaning_ja「犬」を付けて返した（指示文の動物の例が「柴犬 → 犬」だけだった）。前の確かめは
 * 「基本の語の意味が同じ行の細かい名前か」（內褲 =「ボクサーパンツ」）しか見ておらず、**別の行の物の名前**
 * （犬 = 狗 の行）をそのまま通していた。いまは:
 *
 * - 表の基本の語（貓）の意味が、空・同じ行の細かい名前・**別の行の物の名前**なら、表の表示言語の名前（猫）にする。
 *   同じ物の別の書き方（ネコ）はそのまま。
 * - 細かい名前・口語（虎斑貓・貓咪）の意味が**別の行の物の名前**なら空にする（別の物の名前を出すより、意味なしの
 *   方がよい — 表は細かい名前の意味を知らないので書き換えない）。
 * - 表の外の語には何もしない。
 *
 * 写真の候補（`finishPhotoCandidates`）と打った語の候補（`suggestWordCandidates`）が通る。表示言語に揃えた後
 * （`fitSuggestionsToReader`）に呼ぶ — 別の言語で返って空になった基本の語の意味も、ここで表から埋まる。
 */
export function alignRowMeanings<T extends { headword: string; meaning_ja?: string }>(
  items: readonly T[],
  reader: UiLang,
  targetLanguage: string,
): T[] {
  if (basicLevelTable(targetLanguage).length === 0) return [...items];
  return items.map((c) => {
    const head = (c.headword ?? "").trim();
    const row = rowOfHeadword(head, targetLanguage);
    if (!row) return c;
    const gloss = firstGloss(c.meaning_ja);
    const named = rowNamedBy(gloss, reader, targetLanguage);
    const otherObject = named !== null && named !== row;
    if (row.headword === head) {
      const narrow = !!gloss && (row.labelNarrower[reader]?.test(gloss) ?? false);
      return !gloss || otherObject || narrow ? { ...c, meaning_ja: row.label[reader] } : c;
    }
    return otherObject ? { ...c, meaning_ja: "" } : c;
  });
}

type Candidate = {
  headword: string;
  reading_zhuyin?: string;
  pinyin?: string;
  meaning_ja?: string;
  distinction?: string;
  category_key?: string;
  register?: string;
  label?: string | null;
  group?: number | null;
};

/**
 * **物ごとに、1つ目（一般的な言い方）を基本の語にする**（`finalizeNameRegisters` の後に呼ぶ）。
 *
 * 物の基本の語（表の行）は次のどちらかで決まる:
 * 1. 物の1つ目が表の細かい名前（波斯菊・草莓蛋糕・柴犬・四角褲）。
 * 2. AI の付けたタグが表の基本の名前・細かい名前（ケーキ・ストロベリーケーキ）で、1つ目の分類がその基本の語と
 *    同じ（花瓶に「花」と付いても 花 を足さない — 分類が違う）。ただし1つ目の語（貓咪 = 貓 の口語）か意味
 *    （「猫」）が**別の行の物**を指していれば、タグの方が取り違え（猫の写真に「犬」）なので使わない。
 *
 * - その物の候補に基本の語が在れば先頭へ移し、無ければ足す（読み・分類・意味は表から）。
 * - 元の1つ目は「より詳しい言い方」（specific）へ下げる（口語 — 貓咪・狗狗 — なら「口語」）。
 *   **どの候補の意味も書き換えない**（基本の語の意味の確かめは `alignRowMeanings`）。
 * - 物の番号（`group`）が無い候補（打った語の候補）には何もしない — 打った人が選んだ細かい名前はそのまま返す。
 */
export function ensureBasicLevel<T extends Candidate>(
  items: readonly T[],
  targetLanguage: string,
  reader: UiLang,
): T[] {
  if (basicLevelTable(targetLanguage).length === 0) return [...items];
  const order: number[] = [];
  const groups = new Map<number, T[]>();
  const loose: T[] = [];
  for (const it of items) {
    if (typeof it.group !== "number") {
      loose.push(it);
      continue;
    }
    if (!groups.has(it.group)) {
      groups.set(it.group, []);
      order.push(it.group);
    }
    groups.get(it.group)!.push(it);
  }
  if (groups.size === 0) return [...items];
  const out: T[] = [];
  for (const g of order) {
    const list = groups.get(g)!;
    const first = list[0];
    const head = first.headword.trim();
    const fromLabel = (() => {
      const label = list.map((c) => c.label ?? "").find((l) => l.trim());
      const e = entryForLabel(label, reader, targetLanguage);
      if (!e || e.headword === head) return null;
      // 1つ目の語・意味が別の行の物を指すなら、タグの方が取り違え（貓咪・「猫」に label「犬」）。
      const headRow = rowOfHeadword(head, targetLanguage);
      if (headRow && headRow !== e) return null;
      const meaningRow = rowNamedBy(firstGloss(first.meaning_ja), reader, targetLanguage);
      if (meaningRow && meaningRow !== e) return null;
      const category = normalizeCategory(head, coerceCategoryKey(first.category_key));
      return category === e.category ? e : null;
    })();
    // 1つ目が表の基本の語そのもの（內褲・貓）なら並びはそのまま。意味の確かめ（內褲 =「ボクサーパンツ」、
    // 貓 =「犬」）は表示言語に揃えた後の `alignRowMeanings`。
    if (basicLevelTable(targetLanguage).some((e) => e.headword === head)) {
      out.push(...list);
      continue;
    }
    const entry = basicLevelOf(head, targetLanguage) ?? fromLabel;
    if (!entry) {
      out.push(...list);
      continue;
    }
    const label = entry.label[reader];
    // 下げる語が基本の語の口語（貓咪・狗狗）なら「口語」、それ以外は「より詳しい言い方」。
    const demoted = {
      ...first,
      register: (entry.forms?.includes(head) ?? false) ? "colloquial" : "specific",
    } as T;
    const k = list.findIndex((c) => c.headword.trim() === entry.headword);
    if (k > 0) {
      const promoted = {
        ...list[k],
        register: "common",
        label,
        category_key: list[k].category_key || entry.category,
      } as T;
      const rest = list.filter((_, i) => i !== 0 && i !== k);
      out.push(promoted, demoted, ...rest);
    } else {
      const basic = {
        ...first,
        headword: entry.headword,
        reading_zhuyin: entry.reading_zhuyin,
        pinyin: entry.pinyin,
        meaning_ja: label,
        distinction: "",
        category_key: entry.category,
        register: "common",
        label,
      } as T;
      out.push(basic, demoted, ...list.slice(1));
    }
  }
  // 物の番号の無い候補は後ろへ（写真の候補では普通は無い）。
  out.push(...loose);
  return out;
}
