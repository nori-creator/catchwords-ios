/**
 * **図鑑の20のカテゴリーを、AI に分類を選ばせる時の物差しにする**（オーナー指示 2026-10-09
 * 「桃がなぜか景色に分類されてる。分類のアルゴリズム改善して。ios版の２０種類を徹底して。」）。
 *
 * 前は AI に 54 の分類の鍵（`fruit, vegetable, … nature, weather, sky …`）を英単語で並べて
 * 見せるだけだった。"nature" は「自然の物」と読めるので、AI は木に生る桃を "nature" と答え、
 * 図鑑は nature を「空・自然」に置く — 桃が景色の棚に並んだ。
 *
 * ここでは iOS の図鑑の 20 のカテゴリー（`dex-catalog.ts` の表 = iOS `DexCatalog.swift`）を
 * **名前・ひと言の定義・表に在る物の例**と一緒に見せ、まず 20 のどれかを選ばせてから、その
 * カテゴリーに属する鍵（`DEX_KEY_TO_CATEGORY`）の中から category_key を答えさせる。保存する
 * のは今までどおり `words.category_key`（表の形は変えない）で、図鑑の置き場所は鍵から一意に決まる。
 *
 * 画面の文言ではなく AI への指示文なので、i18n の表には入れない（日本語の名前は
 * `dexcat.N` の ja と同じ — `dex-category-guide.test.ts` が突き合わせる）。
 */
import { DEX_CATEGORIES, DEX_KEY_TO_CATEGORY } from "./dex-catalog";

export type DexCategoryGuide = {
  no: number;
  /** 日本語の名前（i18n `dexcat.N` の ja と同じ）。 */
  ja: string;
  /** ひと言の定義（何を入れて、何を入れないか）。 */
  def: string;
  /** 表に無いが取り違えやすい物の例（表の例の後ろに足す）。 */
  more?: string[];
};

// prettier-ignore
export const DEX_CATEGORY_GUIDES: readonly DexCategoryGuide[] = [
  { no: 1, ja: "飲み物", def: "飲む物（お茶・コーヒー・ジュース・酒・飲む水）。果物の名前が付いても飲み物ならここ" },
  { no: 2, ja: "料理・屋台", def: "食事として食べる料理・ご飯・麺・弁当・屋台の食べ物・卵・豆腐" },
  { no: 3, ja: "果物・野菜", def: "**果物（木に生る実も）**と野菜・芋。生の実・切った実の写真もここ（空・自然や植物・花にしない）", more: ["桃", "水蜜桃", "櫻桃", "荔枝", "龍眼", "蓮霧", "釋迦", "柳丁"] },
  { no: 4, ja: "お菓子・パン", def: "お菓子・デザート・かき氷・パン（クロワッサン・ベーグル）", more: ["可頌", "貝果"] },
  { no: 5, ja: "食器・台所", def: "食器・調理器具・台所で使う物" },
  { no: 6, ja: "家具・インテリア", def: "家具・家の設備（ドア・窓・スイッチ・照明）・時計・飾り", more: ["開關"] },
  { no: 7, ja: "家電", def: "電気で動く家庭の機械（冷蔵庫・エアコン・洗濯機）" },
  { no: 8, ja: "スマホ・パソコン", def: "スマホ・パソコン・周辺機器・充電の物" },
  { no: 9, ja: "文房具・本", def: "文房具・本・紙・書類・色や形の言葉" },
  { no: 10, ja: "洗面・日用品", def: "洗面・掃除の道具・化粧品・顔の手入れ・薬・鍵・お金・カード・袋", more: ["面膜", "刷子"] },
  { no: 11, ja: "服", def: "着る物（上着・ズボン・制服）と服の部分（襟・袖）" },
  { no: 12, ja: "靴・バッグ・小物", def: "靴・鞄・帽子・眼鏡・傘・腕時計・アクセサリー" },
  { no: 13, ja: "乗り物", def: "乗り物（車・バイク・電車・バス・船・飛行機）" },
  { no: 14, ja: "建物・お店", def: "建物・お店・施設・町や地名（駅名・市の名前）" },
  { no: 15, ja: "道・街の物", def: "道路と街に置いてある物（信号・看板・ベンチ・ポスト）・文字や記号" },
  { no: 16, ja: "動物", def: "動物・鳥・魚・虫（子どもの動物も）", more: ["小豬"] },
  { no: 17, ja: "植物・花", def: "生えている植物・木・草・花・きのこ（食べる実は果物・野菜）", more: ["桃花", "蘑菇"] },
  { no: 18, ja: "空・自然", def: "空・天気・山・川・海・岩・景色そのもの（**生き物と食べ物は入れない**）", more: ["淡水河", "觀音山", "女王頭"] },
  { no: 19, ja: "スポーツ・遊び", def: "スポーツ・遊び道具・ゲーム・楽器・映画・絵" },
  { no: 20, ja: "人・体", def: "人・家族・仕事・体の部位（手の甲なども）", more: ["手背"] },
];

/** そのカテゴリーに属する分類の鍵（表の順。最初の鍵が代表）。 */
export function dexCategoryKeys(no: number): string[] {
  return Object.entries(DEX_KEY_TO_CATEGORY)
    .filter(([, n]) => n === no)
    .map(([k]) => k);
}

/** 指示文に載せる例の数（表の最初から）。 */
const EXAMPLES_PER_CATEGORY = 8;

/** そのカテゴリーの例（表の物の台湾華語の見出し語、続けて取り違えやすい物）。 */
export function dexCategoryExamples(no: number): string[] {
  const cat = DEX_CATEGORIES.find((c) => c.no === no);
  const fromTable = (cat?.items ?? []).slice(0, EXAMPLES_PER_CATEGORY).map((it) => it.zh);
  const guide = DEX_CATEGORY_GUIDES.find((g) => g.no === no);
  return [...new Set([...fromTable, ...(guide?.more ?? [])])];
}

/**
 * **AI に渡す 20 のカテゴリーの一覧**（1行に1つ: 番号・名前・定義・例・答える鍵）。
 * カードの生成・写真の候補・「その他」の分け直しの3つで同じ文を使う。
 */
export const DEX_CATEGORY_GUIDE_JA: string = DEX_CATEGORY_GUIDES.map((g) => {
  const keys = dexCategoryKeys(g.no);
  const ex = dexCategoryExamples(g.no).join("・");
  return `${g.no}. ${g.ja} — ${g.def}。例: ${ex} → category_key: ${keys.join(" / ")}`;
}).join("\n");
