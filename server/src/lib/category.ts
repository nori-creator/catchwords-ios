/**
 * 図鑑カテゴリーの正規化(共有)。
 *
 * 以前は ai.functions.ts の中にだけ存在し、しかも判定が部分一致だったため
 * 「斑馬線(横断歩道)」が /馬/ に引っかかって**動物**に分類されていた。
 * ここでは
 *   1) 完全一致(EXACT) → 2) 語末一致(SUFFIX) → 3) 部分一致(CONTAINS)
 * の順に見て、部分一致は誤爆しにくい2字以上の語だけに絞っている。
 *
 * カテゴリーキーは DB の categories テーブルに必ず存在させること
 * (存在しないキーは upsertWord が 'other' に落とすため。
 *  20260723090000_seed_missing_categories.sql で54キーを投入済み)。
 */
import { DEX_CATEGORY_GUIDES, DEX_CATEGORY_GUIDE_JA } from "./dex-category-guide";
import { dexCategoryKey } from "./dex-catalog";

export const CATEGORY_KEYS = [
  "fruit",
  "vegetable",
  "drink",
  "food",
  "dessert",
  "vehicle",
  "transport",
  "animal",
  "plant",
  "flower",
  "building",
  "street",
  "sign",
  "shop",
  "home",
  "furniture",
  "appliance",
  "kitchenware",
  "tool",
  "clothes",
  "accessory",
  "shoes",
  "bag",
  "jewelry",
  "stationery",
  "book",
  "tech",
  "gadget",
  "toy",
  "game",
  "sport",
  "instrument",
  "nature",
  "weather",
  "sky",
  "water",
  "mountain",
  "body",
  "face",
  "hand",
  "clothing_part",
  "person",
  "family",
  "job",
  "art",
  "decoration",
  "character",
  "symbol",
  "color",
  "shape",
  "money",
  "document",
  "medicine",
  "other",
] as const;

export type CategoryKey = (typeof CATEGORY_KEYS)[number];

/**
 * **AI に分類を選ばせる時の決まり**（カードの生成・写真の候補・「その他」の語の分け直し
 * `category-backfill.ts` で同じ文を使う）。
 *
 * **図鑑の20のカテゴリー（iOS と同じ）から選ばせる**（2026-10-09 オーナー報告「桃がなぜか景色に
 * 分類されてる…ios版の２０種類を徹底して」）。前は 54 の鍵を英単語で並べるだけで、AI は木に生る
 * 桃を "nature"（＝図鑑の「空・自然」）と答えていた。20 のカテゴリーの名前・定義・表の例は
 * `dex-category-guide.ts`。答えは今までどおり分類の鍵（保存の形は変えない）。
 */
export const CATEGORY_CHOICE_RULES_JA =
  `**図鑑の20のカテゴリーから選ぶ。** まずその物が次の20のどれに入るかを決め、` +
  `その行の category_key（迷ったら行の最初の鍵）を1つ答える:\n` +
  `${DEX_CATEGORY_GUIDE_JA}\n` +
  `- 果物は木に生っていても・切ってあっても 3（fruit）。桃・桃子・水蜜桃を nature/plant にしない。` +
  `花（桃花）は 17、地名（桃園）は 14（building）。\n` +
  `- **花・花束・鉢植え・草木は種類の名前でも 17（植物・花: flower / plant）**。波斯菊・玫瑰・滿天星・花束・捧花・盆栽を ` +
  `"other" にしない。花瓶・花盆（入れ物）は 6（decoration）。\n` +
  `- ケーキ・お菓子・パンは種類や味の名前でも 4（dessert）。料理は 2（food）、飲み物は 1（drink）。\n` +
  `- category_key には**鍵を1つだけ**書く（例 "plant"）。番号・カテゴリーの名前・「plant / flower」のような並びを書かない。\n` +
  `- nature・sky・weather・water・mountain（18 空・自然）は空・天気・山・川・海・岩・景色だけ。` +
  `生き物・食べ物・物に使わない。\n` +
  `- **"other" は最終手段** — 20のどれにも入らない抽象的な語（「見どころ」「考え」）だけ。` +
  `体の部位・日用品・料理・パン・動物の子ども・キノコを "other" にしない。`;

/** 完全一致(1字語や、部分一致だと誤爆する語はここに置く)。 */
const EXACT: Record<string, CategoryKey> = {
  // 体 — 1字語が多く、部分一致にすると「斑馬線」「手機」等を誤分類する
  手: "body",
  腳: "body",
  脚: "body",
  頭: "body",
  髮: "body",
  頭髮: "body",
  眼: "body",
  眼睛: "body",
  耳: "body",
  耳朵: "body",
  鼻: "body",
  鼻子: "body",
  嘴: "body",
  嘴巴: "body",
  臉: "body",
  舌: "body",
  舌頭: "body",
  牙: "body",
  牙齒: "body",
  指: "body",
  手指: "body",
  腳趾: "body",
  肩: "body",
  肩膀: "body",
  膝: "body",
  膝蓋: "body",
  肚: "body",
  肚子: "body",
  背: "body",
  胸: "body",
  腰: "body",
  脖: "body",
  脖子: "body",
  手肘: "body",
  手腕: "body",
  手臂: "body",
  // 自然・空・水
  太陽: "sky",
  月亮: "sky",
  星星: "sky",
  雲: "weather",
  雨: "weather",
  風: "weather",
  雪: "weather",
  颱風: "weather",
  台風: "weather",
  海: "water",
  河: "water",
  湖: "water",
  水: "drink",
  山: "mountain",
  // 人・家族
  女朋友: "person",
  男朋友: "person",
  朋友: "person",
  老師: "job",
  學生: "person",
  醫生: "job",
  護士: "job",
  店員: "job",
  司機: "job",
  // 手の部位（「手背」は1語でも EXACT に無く「その他」に残っていた。2026-10-09）
  手背: "body",
  手心: "body",
  手掌: "body",
  掌心: "body",
  腳背: "body",
  腳底: "body",
  爸爸: "family",
  媽媽: "family",
  哥哥: "family",
  姐姐: "family",
  弟弟: "family",
  妹妹: "family",
  家人: "family",
  // 「〜書」で本に入っていた（秘書は仕事）、「〜河」で川に入る銀河は空。
  秘書: "job",
  祕書: "job",
  銀河: "sky",
  // 写真の候補で「その他」に残っていた物（本番の候補の控え 2026-10-11〜15）。
  指甲: "body",
  拇指: "body",
  食指: "body",
  中指: "body",
  無名指: "body",
  小指: "body",
  腿毛: "body",
  眉毛: "body",
  睫毛: "body",
  鬍子: "body",
  船: "vehicle",
  尺: "stationery",
  地板: "home",
  天花板: "home",
  牆壁: "home",
  窗戶: "home",
  窗簾: "home",
  煙囪: "home",
  水龍頭: "home",
  手帕: "accessory",
  數字: "symbol",
  商標: "sign",
  品牌: "sign",
  刺繡: "art",
};

/**
 * 果物の名前（台湾でよく出会う物）。図鑑の「果物・野菜」（3）の表の果物に、表に無い桃・荔枝・
 * 龍眼・蓮霧・釋迦などを足す。長い名前を先に（葡萄柚を葡萄で切らない）。
 */
const FRUIT_NAMES = [
  "葡萄柚",
  "水蜜桃",
  "奇異果",
  "火龍果",
  "百香果",
  "哈密瓜",
  "番石榴",
  "蘋果",
  "香蕉",
  "芒果",
  "鳳梨",
  "葡萄",
  "西瓜",
  "草莓",
  "櫻桃",
  "柳丁",
  "柳橙",
  "橘子",
  "橙子",
  "芭樂",
  "蓮霧",
  "荔枝",
  "龍眼",
  "釋迦",
  "木瓜",
  "檸檬",
  "柿子",
  "水梨",
  "梨子",
  "香瓜",
  "楊桃",
  "桃子",
  "李子",
  "梅子",
  "藍莓",
  "榴槤",
  "山竹",
  "椰子",
  "酪梨",
  "文旦",
  "柚子",
  "枇杷",
  "桑椹",
  "桑葚",
  "棗子",
  "蜜棗",
  "桃",
  "梨",
].join("|");

/**
 * **語末の規則より先に見る語**。名前に「草・花・葉・鍋・燈」が入っていても、植物・花・台所道具・
 * 家具ではない物。燒仙草（温かい仙草ゼリー）が「〜草」で**植物・花**の棚に入っていた
 * （オーナー報告 2026-10-08、図鑑の画面）。同じ形の取り違えをまとめて先に拾う。
 */
const BEFORE_SUFFIX: Array<[RegExp, CategoryKey]> = [
  // 果物の名前（**語全体が果物の名前の時だけ**）。桃が規則に当たらず、AI の "nature" のまま
  // 図鑑の「空・自然」に並んでいた（オーナー報告 2026-10-09「桃がなぜか景色に分類されてる」）。
  // 果物の名前の付いた飲み物・お菓子（西瓜汁・芒果冰）を先に見る。桃花（花）・桃園（地名）・
  // 黑桃（トランプ）には当たらない。
  [
    new RegExp(`^(${FRUIT_NAMES})(汁|原汁|牛奶|奶昔|冰沙|茶|綠茶|紅茶|多多|氣泡水|酒|醋)$`),
    "drink",
  ],
  [
    new RegExp(
      `^(${FRUIT_NAMES})(冰|雪花冰|刨冰|蛋糕|派|塔|乾|酥|果醬|糖|布丁|果凍|冰淇淋|聖代|大福)$`,
    ),
    "dessert",
  ],
  [new RegExp(`^(小|大|青|白|黃|愛文|金煌)?(${FRUIT_NAMES})子?$`), "fruit"],
  // 飲み物（仙草茶・青草茶は「茶」、茶葉は「葉」で植物に入っていた）
  [/(仙草茶|仙草蜜|青草茶|茶葉)$/, "drink"],
  // 甘い物（仙草・愛玉・豆花・爆米花・雪花冰・棉花糖 など）
  [/(仙草|愛玉|粉圓|豆花|爆米花|雪花冰|綿花糖|棉花糖|花生糖|花生湯)/, "dessert"],
  // 料理（「〜鍋」は台所道具の規則に当たる — 火鍋は鍋ではなく料理）
  [/(火鍋|麻辣鍋|臭臭鍋|涮涮鍋|鴛鴦鍋|石頭鍋)$/, "food"],
  // 野菜（「〜花」で花に入る食べる花）
  [/(韭菜花|花椰菜|青花菜|蔥花)$/, "vegetable"],
  // 波の花（浪花）は水
  [/^浪花$/, "water"],
  // 花の入れ物は花ではない（「〜花」でなくても先に拾う。花瓶が「その他」だった — 2026-10-15）
  [/(花瓶|花盆|花器)$/, "decoration"],
  // 「〜花」でも花ではない物（ラテアート・花火・切り紙）。拉花が「花」に入っていた（候補の控え 2026-10-15）。
  [/^拉花$/, "drink"],
  [/^(煙花|窗花|印花|繡花)$/, "art"],
  // 野菜（写真の候補で「その他」だった 四季豆・青蔥）
  [/(四季豆|豌豆|毛豆|青蔥|蔥|竹筍|蘆筍|筍)$/, "vegetable"],
  // 街の灯り（「〜燈」は家具の規則に当たる）
  [/(紅綠燈|路燈|號誌燈)$/, "street"],
  // 空・天気
  [/^雪花$/, "weather"],
  // パン（図鑑の表は麵包・吐司を「お菓子・パン」に置く — 鍵は dessert）。語末だけを見る
  // （烤麵包機は家電）。可頌が「その他」に残っていた（オーナー報告 2026-10-09）。
  [/(烤麵包機|麵包機|烤吐司機)$/, "appliance"],
  [/(可頌|貝果|吐司|麵包|司康|馬芬|歐包|餐包)$/, "dessert"],
  // 料理・弁当（「〜餐」。餐具・餐廳は語末が違うので当たらない）。健康餐が「その他」だった。
  [/(便當盒|保鮮盒)$/, "kitchenware"],
  [/(健康餐|[早午晚]餐|套餐|輕食餐|餐盒|便當)$/, "food"],
  // 家の設備（電灯のスイッチ・コンセント）。開關が「その他」だった。
  [/^(電燈)?(開關|插座)$/, "home"],
];

/** 語末一致(「〜傘」「〜鞋」など、末尾で種類が決まるもの)。 */
const SUFFIX: Array<[RegExp, CategoryKey]> = [
  // 花・花束（オーナー報告 2026-10-15: 花束が「その他」に入った。写真の候補では波斯菊が "other"）。
  // 花の種類の名前（〜菊・玫瑰・滿天星…）と、花をまとめた物（花束・捧花・花籃・花圈）。図鑑の「植物・花」。
  [
    /(花|花束|捧花|花籃|花圈|玫瑰|櫻花|向日葵|鬱金香|百合|菊|康乃馨|繡球|薰衣草|牡丹|杜鵑|茉莉|水仙|滿天星|洋桔梗|海芋|蝴蝶蘭|紫羅蘭|蒲公英)$/,
    "flower",
  ],
  [/(樹|竹|草|葉|盆栽|多肉|仙人掌|盆栽植物|植物)$/, "plant"],
  // キノコ（蘑菇・香菇・金針菇…）。図鑑の表は香菇を「植物・花」に置くので、それに合わせる
  // （2026-10-09 オーナー報告: 野のキノコの写真の蘑菇が「その他」になり、日用品に並んでいた）。
  [/(菇|蕈|菌菇)$/, "plant"],
  [/(傘|雨傘|陽傘)$/, "accessory"],
  [/(鞋|鞋子|運動鞋|拖鞋|靴子|高跟鞋)$/, "shoes"],
  [/(包包|背包|皮包|錢包|手提袋|袋子)$/, "bag"],
  [/(項鍊|戒指|耳環|手鍊|手錶|錶|手環)$/, "jewelry"],
  [/(椅子|椅|桌子|桌|沙發|床|櫃子|櫃|書架|書桌|衣櫃)$/, "furniture"],
  [/(船|帆船|漁船|遊艇)$/, "vehicle"],
  [/(直尺|塑膠尺|三角尺)$/, "stationery"],
  [/(鍋|平底鍋|刀|叉|筷子|湯匙|盤子|碗|砧板|鍋子|水壺)$/, "kitchenware"],
  [/(書|小說|字典|漫畫|雜誌|課本|筆記本)$/, "book"],
  [/(證|證件|卡|表格|文件|收據|發票|菜單|地圖)$/, "document"],
  [/(燈|小夜燈|檯燈)$/, "furniture"],
  // 川・山（淡水河・觀音山 → 図鑑の「空・自然」）。1字の「河」「山」は EXACT。
  // 「拔河」（綱引き）や「過河・渡河・跳河」（川を渡る・飛び込む行い）は川の名ではない。
  [/^(?!(?:拔|過|渡|跳|投)河$).+(河|溪|瀑布)$/, "water"],
  // 「爬山」「登山」「下山」「上山」は山に行く行い（動詞）なので山の名にしない。
  [/^(?!(?:爬|登|下|上|開|靠|江)山$).+山$/, "mountain"],
  [/(杯|杯子|馬克杯)$/, "kitchenware"],
];

/** 部分一致(2字以上の具体語のみ。1字語は EXACT 側で扱う)。 */
const CONTAINS: Array<[RegExp, CategoryKey]> = [
  // テック・ガジェット
  [
    /(滑鼠|鍵盤|電腦|筆電|螢幕|手機|平板|耳機|喇叭|路由器|插頭|充電器|充電線|傳輸線|相機|鏡頭|行動電源|USB|手機架)/,
    "tech",
  ],
  // 交通
  [/(汽車|機車|摩托車|腳踏車|自行車|捷運|公車|火車|高鐵|飛機|輪船|計程車)/, "transport"],
  // 動物(「斑馬線」を誤爆しないよう2字以上の動物名だけ)
  [/(狗狗|小狗|貓咪|小貓|兔子|老鼠|綿羊|山羊|烏龜|金魚|熊貓|大象|獅子|老虎|斑馬(?!線))/, "animal"],
  // 1字の動物と、その「小〜」「山〜・野〜」「〜仔」「〜咪」（小豬・山豬・豬仔・小雞）。
  // 小豬（子豚の写真）が「その他」になり、図鑑で日用品に並んでいた（2026-10-09）。
  [/^(小|大|山|野)?(狗|貓|鳥|魚|馬|牛|羊|豬|雞|鴨|鵝|熊|兔|猴|蛇)(仔|咪)?$/, "animal"],
  // 果物・野菜・飲食
  [/(蘋果|香蕉|橘子|柳丁|葡萄|草莓|西瓜|芒果|鳳梨|木瓜|檸檬|柿子|水梨)/, "fruit"],
  [/(高麗菜|白菜|菠菜|紅蘿蔔|馬鈴薯|洋蔥|番茄|茄子|青椒|大蒜|生薑|蔥花)/, "vegetable"],
  [/(咖啡|奶茶|果汁|可樂|礦泉水|牛奶|豆漿|啤酒|紅茶|綠茶|珍珠奶茶)/, "drink"],
  [/(三明治|炒飯|炒麵|便當|漢堡|披薩|蛋餅|蔥抓餅|滷肉飯|小籠包|水餃|包子|麵包|海帶)/, "food"],
  [/(蛋糕|布丁|冰淇淋|甜甜圈|巧克力|餅乾|糖果|雪花冰|豆花|芒果冰)/, "dessert"],
  // 家電・調理・日用品
  [/(冰箱|洗衣機|微波爐|電視|冷氣|烤箱|吹風機|電風扇|除濕機)/, "appliance"],
  [
    /(衛生紙|面紙|毛巾|清潔劑|洗碗精|洗衣精|沐浴乳|洗髮精|牙膏|牙刷|肥皂|垃圾袋|塑膠袋)/,
    "medicine",
  ],
  // 顔の手入れ（面膜が「その他」に残っていた。2026-10-09）
  [/(面膜|洗面乳|洗面奶|化妝水|卸妝|保養品|化妝品)/, "medicine"],
  [/(護唇膏|護手霜|乳液|防曬|口罩|藥膏|藥品|OK繃|繃帶|藥水|維他命)/, "medicine"],
  [/(指甲剪|剪刀|螺絲|工具|鎚子|梯子|掃把|拖把|黏毛器)/, "tool"],
  // 掃除の道具（刷子が「その他」に残っていた。牙刷は上の洗面の規則が先に拾う）
  [/(刷子|鬃刷|馬桶刷|菜瓜布|抹布|畚箕)/, "tool"],
  // 服・アクセ
  [/(衣服|襯衫|T恤|外套|夾克|大衣|褲子|裙子|洋裝|毛衣|帽子|圍巾|手套|襪子)/, "clothes"],
  [/(眼鏡|太陽眼鏡|皮帶|髮飾)/, "accessory"],
  // 文房具・お金・場所
  [/(鉛筆|原子筆|橡皮擦|尺子|膠水|膠帶|便利貼|螢光筆)/, "stationery"],
  [/(硬幣|紙鈔|鈔票|信用卡|零錢)/, "money"],
  [/(便利商店|超市|超商|夜市|市場|百貨|書店|餐廳|咖啡店|藥局)/, "shop"],
  [/(公園|車站|機場|銀行|醫院|學校|郵局|廟|捷運站)/, "building"],
  [/(招牌|標誌|標示|指示牌|路牌|告示)/, "sign"],
  [/(斑馬線|紅綠燈|人行道|馬路|巷子|樓梯|電梯)/, "street"],
];

/**
 * AIが返したカテゴリーを、見出し語から確実に補正する。
 * ルールに当たらなければAIの答えを尊重し、未知キーだけ 'other' にする。
 */
export function normalizeCategory(headword: string, cat: string | null | undefined): CategoryKey {
  const h = (headword ?? "").trim();
  if (h) {
    // **自分が持っている鍵だけを認める。**
    // `EXACT[h]` は継承したプロパティにも当たるので、見出し語が
    // `"constructor"` や `"toString"` だと Object.prototype の**関数**が
    // 返り、それが真なのでそのまま「カテゴリー」として返っていた。
    // 型は `CategoryKey` と言っているのに中身は関数、という嘘の値になる。
    //
    // 同じ穴は `asCategoryKey` で一度潰したのに、**すぐ隣のこの引きを
    // 見落としていた**。1箇所直したら同じ形を探すこと。
    // (文字キャッチは見出し語を人が打てるので、机上の話ではない)
    const exact = Object.prototype.hasOwnProperty.call(EXACT, h) ? EXACT[h] : undefined;
    if (exact) return exact;
    for (const [re, key] of BEFORE_SUFFIX) if (re.test(h)) return key;
    for (const [re, key] of SUFFIX) if (re.test(h)) return key;
    for (const [re, key] of CONTAINS) if (re.test(h)) return key;
  }
  const c = cat as CategoryKey;
  if (c && (CATEGORY_KEYS as readonly string[]).includes(c)) return c;
  return "other";
}

/** 図鑑の20のカテゴリーの日本語の名前 → その代表の鍵。 */
const DEX_NAME_TO_KEY: Array<[string, string]> = DEX_CATEGORY_GUIDES.map(
  (g) => [g.ja, dexCategoryKey(g.no)] as [string, string],
);

/**
 * **AI の答えた分類を鍵1つに読み直す**（2026-10-15、写真の候補の控えで「その他」が写真ごとにまとまって
 * 出ていた: 花束の写真の 波斯菊・花瓶・木桌・木櫃 が全部 "other"）。
 *
 * 指示文は20のカテゴリーを「→ category_key: home / furniture / decoration」の形で見せるので、モデルが
 * その並びを写す・番号（"6"）やカテゴリーの名前（「家具・インテリア」）を答える回がある。`z.enum` は
 * それを全部 "other" に落としていた。読めた最初の鍵を使い、どれでもなければ "other"。
 */
export function coerceCategoryKey(raw: unknown): CategoryKey {
  if (typeof raw !== "string") return "other";
  const v = raw.trim().toLowerCase();
  if (!v) return "other";
  const keys = CATEGORY_KEYS as readonly string[];
  if (keys.includes(v)) return v as CategoryKey;
  // 「home / furniture」「plant|flower」「"plant", "flower"」— 読める最初の鍵。
  const tokens = v.split(/[\s/|,，、・;；:：→>()（）"'「」]+/).filter(Boolean);
  for (const t of tokens) {
    if (keys.includes(t)) return t as CategoryKey;
    // 複数形（plants・flowers）
    if (t.endsWith("s") && keys.includes(t.slice(0, -1))) return t.slice(0, -1) as CategoryKey;
  }
  // 図鑑の番号（"17"・"17."・"No.17"）
  const no = v.match(/^(?:no\.?\s*)?(\d{1,2})\.?(?:\D|$)/);
  if (no) {
    const k = dexCategoryKey(Number(no[1]));
    if (keys.includes(k)) return k as CategoryKey;
  }
  // 図鑑のカテゴリーの名前そのもの（「植物・花」「家具・インテリア」。部分一致にしない — 「服」が「服務」に当たる）
  const name = raw.trim();
  for (const [dexName, key] of DEX_NAME_TO_KEY) {
    if (name === dexName && keys.includes(key)) return key as CategoryKey;
  }
  return "other";
}

/**
 * **同じ物の別の呼び方から分類を借りる**（写真の候補。`group` が同じ候補は同じ物）。
 * 波斯菊が "other"、同じ物の 花 が flower なら、波斯菊も flower。借りる物が無ければそのまま。
 */
export function shareCategoryWithinGroups<
  T extends { group?: number | null; category_key?: string | null },
>(items: readonly T[]): T[] {
  const best = new Map<number, string>();
  for (const it of items) {
    if (typeof it.group !== "number") continue;
    const k = it.category_key ?? "";
    if (k && k !== "other" && !best.has(it.group)) best.set(it.group, k);
  }
  return items.map((it) =>
    typeof it.group === "number" && (it.category_key ?? "other") === "other" && best.has(it.group)
      ? { ...it, category_key: best.get(it.group)! }
      : it,
  );
}

/* ─────────────────────────────────────────────────────────────────
   部屋(room) — 図鑑を「棚」として見せるための上位のまとまり。

   54個のカテゴリーをそのまま棚として縦に並べると、ただ長いだけで
   「あの単語はあのへん」という手がかりにならない。人が place を
   覚えるときの粒度はもっと粗いので、まず8つの部屋に入れて、
   部屋の中に棚(カテゴリー)を置く。

   ここが図鑑の**唯一の正**。以前は3箇所に割れていた:
     - CATEGORY_KEYS (54個、Zodのenum)
     - dex.tsx の KNOWN_CATEGORIES (56個、place/object を勝手に追加)
     - i18n.tsx の cat.* (56個、絵文字がラベル文字列に直書き)
   絵文字をラベルから剥がしてここに置いたので、絵文字だけ大きく出す、
   といった扱いができるようになる。
   ───────────────────────────────────────────────────────────────── */

export const ROOM_KEYS = [
  "eat",
  "town",
  "house",
  "wear",
  "play",
  "nature",
  "people",
  "marks",
] as const;

export type RoomKey = (typeof ROOM_KEYS)[number];

/** 分類の部屋ごとの色（図鑑のスライドの光、暦の写真の縁など）。 */
export const ROOM_ACCENT: Record<RoomKey, string> = {
  eat: "#ff9f43",
  town: "#4ea8ff",
  house: "#d9b38c",
  wear: "#ff7eb6",
  play: "#a78bfa",
  nature: "#4ade80",
  people: "#fbbf24",
  marks: "#94a3b8",
};

export type CategoryMeta = {
  /** どの部屋の棚か。 */
  room: RoomKey;
  /** 棚の見出しに添える絵文字(i18n のラベルからは剥がしてある)。 */
  emoji: string;
};

/**
 * カテゴリー → 部屋と絵文字。**CATEGORY_KEYS の全54キーを覆うこと**
 * (型で強制しているので、キーを足したらここもコンパイルが通らなくなる)。
 * 並び順は CATEGORY_KEYS ではなくこの定義順を使う — 部屋ごとに固まる。
 */
export const CATEGORY_META: Record<CategoryKey, CategoryMeta> = {
  // 食べる
  fruit: { room: "eat", emoji: "🍎" },
  vegetable: { room: "eat", emoji: "🥬" },
  drink: { room: "eat", emoji: "🥤" },
  food: { room: "eat", emoji: "🍜" },
  dessert: { room: "eat", emoji: "🍰" },
  // 街
  vehicle: { room: "town", emoji: "🚗" },
  transport: { room: "town", emoji: "🚆" },
  building: { room: "town", emoji: "🏢" },
  street: { room: "town", emoji: "🛣️" },
  sign: { room: "town", emoji: "🪧" },
  shop: { room: "town", emoji: "🏪" },
  // 家
  home: { room: "house", emoji: "🏠" },
  furniture: { room: "house", emoji: "🛋️" },
  appliance: { room: "house", emoji: "🔌" },
  kitchenware: { room: "house", emoji: "🍳" },
  tool: { room: "house", emoji: "🔧" },
  // 身につける
  clothes: { room: "wear", emoji: "👕" },
  accessory: { room: "wear", emoji: "🧢" },
  shoes: { room: "wear", emoji: "👟" },
  bag: { room: "wear", emoji: "👜" },
  jewelry: { room: "wear", emoji: "💍" },
  clothing_part: { room: "wear", emoji: "👔" },
  // 学び・遊び
  stationery: { room: "play", emoji: "✏️" },
  book: { room: "play", emoji: "📚" },
  tech: { room: "play", emoji: "💻" },
  gadget: { room: "play", emoji: "🖱️" },
  toy: { room: "play", emoji: "🧸" },
  game: { room: "play", emoji: "🎮" },
  sport: { room: "play", emoji: "⚽" },
  instrument: { room: "play", emoji: "🎸" },
  art: { room: "play", emoji: "🎨" },
  decoration: { room: "play", emoji: "🎊" },
  // 自然
  animal: { room: "nature", emoji: "🐾" },
  plant: { room: "nature", emoji: "🌿" },
  flower: { room: "nature", emoji: "🌸" },
  nature: { room: "nature", emoji: "🍃" },
  weather: { room: "nature", emoji: "🌦️" },
  sky: { room: "nature", emoji: "☀️" },
  water: { room: "nature", emoji: "💧" },
  mountain: { room: "nature", emoji: "⛰️" },
  // 人・体
  body: { room: "people", emoji: "🖐️" },
  face: { room: "people", emoji: "😊" },
  hand: { room: "people", emoji: "✋" },
  person: { room: "people", emoji: "🧑" },
  family: { room: "people", emoji: "👨‍👩‍👧" },
  job: { room: "people", emoji: "💼" },
  // しるし
  character: { room: "marks", emoji: "🔤" },
  symbol: { room: "marks", emoji: "🔣" },
  color: { room: "marks", emoji: "🎨" },
  shape: { room: "marks", emoji: "🔷" },
  money: { room: "marks", emoji: "💰" },
  document: { room: "marks", emoji: "📄" },
  medicine: { room: "marks", emoji: "💊" },
  other: { room: "marks", emoji: "✨" },
};

/** 部屋 → その部屋に属するカテゴリー(CATEGORY_META の定義順)。 */
export const ROOM_CATEGORIES: Record<RoomKey, CategoryKey[]> = ROOM_KEYS.reduce(
  (acc, room) => {
    acc[room] = (Object.keys(CATEGORY_META) as CategoryKey[]).filter(
      (k) => CATEGORY_META[k].room === room,
    );
    return acc;
  },
  {} as Record<RoomKey, CategoryKey[]>,
);

/**
 * 未知のキーを安全に受ける。DBには古いキー(place / object など、
 * CATEGORY_KEYS に無いもの)が残っている可能性があるため、
 * 画面側は必ずこれを通してから CATEGORY_META を引く。
 */
export function asCategoryKey(key: string | null | undefined): CategoryKey {
  const k = (key ?? "").trim() as CategoryKey;
  // `in` は継承したプロパティにも当たるので、`"constructor"` や
  // `"toString"` のような Object.prototype の名前が「既知のカテゴリー」
  // として素通りしてしまう。そのまま CATEGORY_META を引くと関数が
  // 返り、`.emoji` で落ちる。自分が持っている鍵だけを認める。
  return k && Object.prototype.hasOwnProperty.call(CATEGORY_META, k) ? k : "other";
}

/**
 * **語の分類を、読む時にも見出し語で直す。** 保存済みの鍵は、保存した時の規則のまま
 * （燒仙草 = plant のような古い取り違えが残る）。見出し語があれば `normalizeCategory` を
 * 通し、規則を直せば過去の札もその場で正しい棚に並ぶ。見出し語が無ければ `asCategoryKey`。
 */
export function wordCategoryKey(word: {
  category_key?: string | null;
  headword?: string | null;
}): CategoryKey {
  const h = (word.headword ?? "").trim();
  return h
    ? normalizeCategory(h, asCategoryKey(word.category_key))
    : asCategoryKey(word.category_key);
}

/** そのカテゴリーの絵文字。 */
export function categoryEmoji(key: string | null | undefined): string {
  return CATEGORY_META[asCategoryKey(key)].emoji;
}

/* ─────────────────────────────────────────────────────────────────
   出会う確率のための「場面」— 部屋をそのまま使う。

   語がどこで出るかと、その人がどこに居るかを**同じ鍵**で並べないと、
   内積(`lib/rarity.ts` の `sceneOverlap`)は意味を持たない。
   場面の語彙を新しく作らず、図鑑の部屋をそのまま流用する。
   ───────────────────────────────────────────────────────────────── */

/** 未知の部屋名を安全に受ける。 */
export function isRoomKey(key: string): key is RoomKey {
  return (ROOM_KEYS as readonly string[]).includes(key);
}

/**
 * AI が出した場面の分布を、**知っている部屋だけに畳んで合計1に直す**。
 *
 * 生成側には「8つの鍵だけを使え」と書いてあるが、書いてあることと
 * 返ってくる物は別。知らない鍵をそのまま内積に入れると、片方にしか
 * 無い鍵は必ず 0 を掛けることになり、**まじめに答えた語ほど低く出る**。
 *
 * 使える物が1つも無ければ null を返す(補正を掛けない、が正しい姿)。
 */
export function normalizeRoomWeights(
  input: Record<string, number> | null | undefined,
): Record<RoomKey, number> | null {
  if (!input) return null;
  const kept: Partial<Record<RoomKey, number>> = {};
  let sum = 0;
  for (const [k, v] of Object.entries(input)) {
    if (!isRoomKey(k)) continue;
    const n = typeof v === "number" ? v : Number(v);
    if (!Number.isFinite(n) || n <= 0) continue;
    kept[k] = (kept[k] ?? 0) + n;
    sum += n;
  }
  if (sum <= 0) return null;
  const out = {} as Record<RoomKey, number>;
  for (const [k, v] of Object.entries(kept)) out[k as RoomKey] = v / sum;
  return out;
}

/**
 * その人が撮ったもののカテゴリーから、**どの部屋によく居る人か**を出す。
 *
 * 撮った物が1枚も無いうちは null(= 補正を掛けない)。
 * ここで一様分布を返してもよさそうに見えるが、それは
 * 「全部の部屋に均等に居る」と**言い切る**ことになる。知らないなら黙る。
 */
export function roomMixFromCategories(
  categoryKeys: ReadonlyArray<string | null | undefined>,
): Record<RoomKey, number> | null {
  const counts: Partial<Record<RoomKey, number>> = {};
  let total = 0;
  for (const key of categoryKeys) {
    const room = CATEGORY_META[asCategoryKey(key)].room;
    counts[room] = (counts[room] ?? 0) + 1;
    total += 1;
  }
  if (total === 0) return null;
  const out = {} as Record<RoomKey, number>;
  for (const [k, v] of Object.entries(counts)) out[k as RoomKey] = v / total;
  return out;
}
