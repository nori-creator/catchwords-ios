/**
 * **図鑑の20のカテゴリーと、まだ捕まえていない物の影**（iOS 版 `Models/DexCatalog.swift` の写し。
 * オーナー指示 2026-10-08「iOS版のように図鑑自体にものの影を表示して、それぞれの単語に番号振って」）。
 *
 * iOS と**同じ表**を持つ（id・番号・見出し語・SF Symbol の名前まで同じ）。並びを変えると番号が
 * ずれて、同じ人の iPhone と Web で「No.012」が別の物になる。直すときは iOS 側と一緒に直すこと
 * （`dex-catalog.test.ts` が iOS の表の写し `__fixtures__/ios-dex-catalog.json` と突き合わせる）。
 *
 * - 20 のカテゴリーをこの順に。各カテゴリーの最初の5つが基本の100で、表の順に No.001–100
 *   （カテゴリー1の1〜5 = 001〜005 … カテゴリー20 = 096〜100）。捕まえても捕まえなくても番号は同じ。
 * - 基本の5つの後に、台湾で毎日出会う物を12〜15個、よく出会う順に。カテゴリーの影は、
 *   この順で**まだ捕まえていない最初の5つ**。
 * - 見出し語は学習言語ごと（zh-TW が主、en、ja）。捕まえた語は、学習言語の見出し語が
 *   同じなら、その影の物（`dexItemFor`）。
 * - `symbol` は iOS の SF Symbol の名前（iOS の影の絵）。Web の影は `dex-glyphs.ts` の表（項目 id → 塗りの形）。
 *   null は iOS の needsArt（絵がまだ無い — 角の丸い四角の影）。
 *
 * 見出し語の文字列は**学習する言語のデータ**で、画面の文言ではない（i18n の表には入れない）。
 */

import { DEFAULT_TARGET_LANGUAGE, TARGET_LANGUAGES, type TargetLanguage } from "./target-lang";

/** 図鑑の影の1つ。 */
export type DexItem = {
  id: string;
  zh: string;
  en: string;
  ja: string;
  /** iOS の SF Symbol の名前。null = 絵がまだ無い（needsArt）。 */
  symbol: string | null;
  /** 1〜20。 */
  category: number;
  /** 基本の100は No.001〜100。毎日の物（基本の後ろ）は null。 */
  baseNo: number | null;
};

export type DexCategory = {
  no: number;
  emoji: string;
  base: DexItem[];
  extra: DexItem[];
  /** 基本の5つ、続けて毎日の物（よく出会う順）。 */
  items: DexItem[];
};

/** 図鑑の見出し語を持つ学習言語。 */
export type DexLang = TargetLanguage;

/** カテゴリーごとに出す影の数（iOS `DexBook.shadowCount`）。 */
export const DEX_SHADOW_COUNT = 5;

/** 学習言語を図鑑の3つに寄せる（知らない値は台湾華語）。 */
export function dexLang(lang: string | null | undefined): DexLang {
  return lang === "en" || lang === "ja" ? lang : DEFAULT_TARGET_LANGUAGE;
}

/** その学習言語での見出し語。 */
export function dexHeadword(item: DexItem, lang: string | null | undefined): string {
  const l = dexLang(lang);
  return l === "en" ? item.en : l === "ja" ? item.ja : item.zh;
}

/** カテゴリーの名前の翻訳キー（`i18n.tsx` の `dexcat.1`〜`dexcat.20`）。 */
export function dexCategoryLabelKey(no: number): string {
  return `dexcat.${no >= 1 && no <= 20 ? no : 10}`;
}

/**
 * アプリの分類の鍵 → 図鑑のカテゴリー（1〜20）。iOS `DexCatalog.keyToCategory` と同じ、
 * ただし color・shape は 9（iOS は 10）、そして **`other` は入れない**（2026-10-09 オーナー報告: 蘑菇・小豬が「洗面・日用品」に
 * 並んでいた。札の分類は「その他」なのに、図鑑は other を 10 に寄せていた）。
 * other・知らない鍵は、20 のどれにも入れず図鑑の最後の「その他」の節（`DEX_OTHER_KEY`）へ。
 */
export const DEX_KEY_TO_CATEGORY: Readonly<Record<string, number>> = {
  drink: 1,
  food: 2,
  fruit: 3,
  vegetable: 3,
  dessert: 4,
  kitchenware: 5,
  home: 6,
  furniture: 6,
  decoration: 6,
  appliance: 7,
  tech: 8,
  gadget: 8,
  stationery: 9,
  book: 9,
  document: 9,
  // 色・形の言葉（紅色・圓形）。iOS は 10（洗面・日用品）に置くが、日用品ではない —
  // 「学ぶ物」の棚に寄せる（2026-10-09 オーナー指示「ios版の２０種類を徹底して」で見直し）。
  color: 9,
  shape: 9,
  tool: 10,
  medicine: 10,
  money: 10,
  clothes: 11,
  clothing_part: 11,
  accessory: 12,
  shoes: 12,
  bag: 12,
  jewelry: 12,
  vehicle: 13,
  transport: 13,
  building: 14,
  shop: 14,
  street: 15,
  sign: 15,
  character: 15,
  symbol: 15,
  animal: 16,
  plant: 17,
  flower: 17,
  nature: 18,
  weather: 18,
  sky: 18,
  water: 18,
  mountain: 18,
  toy: 19,
  game: 19,
  sport: 19,
  instrument: 19,
  art: 19,
  body: 20,
  face: 20,
  hand: 20,
  person: 20,
  family: 20,
  job: 20,
};

/** 20 のどれにも入らない語の節の鍵（図鑑の最後。見出しは `cat.other`「その他」）。 */
export const DEX_OTHER_KEY = "other";

/**
 * 分類の鍵の図鑑のカテゴリー。other・知らない鍵・鍵が無いときは **null**（「その他」の節）。
 * 前は 10（洗面・日用品）に黙って寄せていて、キノコや子豚が日用品の棚に並んでいた。
 */
export function dexCategoryForKey(key: string | null | undefined): number | null {
  if (!key || !Object.prototype.hasOwnProperty.call(DEX_KEY_TO_CATEGORY, key)) return null;
  return DEX_KEY_TO_CATEGORY[key];
}

/**
 * 図鑑のカテゴリーを代表する分類の鍵（そのカテゴリーへ札を運んだ時に付ける鍵）。
 * 上の表で、そのカテゴリーに最初に出てくる鍵。
 */
export function dexCategoryKey(no: number): string {
  for (const [key, n] of Object.entries(DEX_KEY_TO_CATEGORY)) if (n === no) return key;
  return "other";
}

type Raw = { id: string; zh: string; en: string; ja: string; symbol: string | null };

function r(id: string, zh: string, en: string, ja: string, symbol: string | null = null): Raw {
  return { id, zh, en, ja, symbol };
}

type Table = [no: number, emoji: string, base: Raw[], extra: Raw[]];

// prettier-ignore
const TABLE: Table[] = [
  [
    1,
    "🧋",
    [
      r("bubbletea", "珍珠奶茶", "bubble tea", "タピオカミルクティー"),
      r("coffee", "咖啡", "coffee", "コーヒー", "cup.and.saucer"),
      r("tea", "茶", "tea", "お茶"),
      r("juice", "果汁", "juice", "ジュース"),
      r("water", "水", "water", "水", "waterbottle"),
    ],
    [
      r("soymilk", "豆漿", "soy milk", "豆乳"),
      r("milk", "牛奶", "milk", "牛乳"),
      r("blacktea", "紅茶", "black tea", "紅茶"),
      r("greentea", "綠茶", "green tea", "緑茶"),
      r("milktea", "奶茶", "milk tea", "ミルクティー"),
      r("cola", "可樂", "cola", "コーラ"),
      r("latte", "拿鐵", "latte", "ラテ", "cup.and.heat.waves"),
      r("soda", "汽水", "soda", "炭酸飲料"),
      r("sportsdrink", "運動飲料", "sports drink", "スポーツドリンク"),
      r("beer", "啤酒", "beer", "ビール"),
      r("wintermelontea", "冬瓜茶", "winter melon tea", "冬瓜茶"),
      r("yogurtdrink", "優酪乳", "drinkable yogurt", "飲むヨーグルト"),
      r("hotcocoa", "熱可可", "hot chocolate", "ココア"),
      r("wine", "葡萄酒", "wine", "ワイン", "wineglass"),
    ],
  ],
  [
    2,
    "🍜",
    [
      r("rice", "飯", "rice", "ご飯"),
      r("noodles", "麵", "noodles", "麺"),
      r("bento", "便當", "bento", "弁当"),
      r("dumplings", "水餃", "dumplings", "水餃子"),
      r("bun", "包子", "steamed bun", "肉まん"),
    ],
    [
      r("egg", "蛋", "egg", "卵"),
      r("braisedporkrice", "滷肉飯", "braised pork rice", "魯肉飯"),
      r("friedrice", "炒飯", "fried rice", "チャーハン"),
      r("soup", "湯", "soup", "スープ"),
      r("beefnoodles", "牛肉麵", "beef noodle soup", "牛肉麺"),
      r("danbing", "蛋餅", "egg crepe", "ダンビン"),
      r("sandwich", "三明治", "sandwich", "サンドイッチ"),
      r("tofu", "豆腐", "tofu", "豆腐"),
      r("porridge", "粥", "congee", "お粥"),
      r("friedchicken", "炸雞", "fried chicken", "フライドチキン"),
      r("stinkytofu", "臭豆腐", "stinky tofu", "臭豆腐"),
      r("hotpot", "火鍋", "hot pot", "火鍋"),
      r("scallionpancake", "蔥油餅", "scallion pancake", "ねぎ餅"),
      r("hamburger", "漢堡", "hamburger", "ハンバーガー"),
    ],
  ],
  [
    3,
    "🍎",
    [
      r("apple", "蘋果", "apple", "りんご"),
      r("banana", "香蕉", "banana", "バナナ"),
      r("mango", "芒果", "mango", "マンゴー"),
      r("tomato", "番茄", "tomato", "トマト"),
      r("cabbage", "高麗菜", "cabbage", "キャベツ"),
    ],
    [
      r("orange", "橘子", "orange", "みかん"),
      r("watermelon", "西瓜", "watermelon", "スイカ"),
      r("guava", "芭樂", "guava", "グァバ"),
      r("grapes", "葡萄", "grapes", "ぶどう"),
      r("pineapple", "鳳梨", "pineapple", "パイナップル"),
      r("papaya", "木瓜", "papaya", "パパイヤ"),
      r("carrot", "紅蘿蔔", "carrot", "にんじん", "carrot"),
      r("onion", "洋蔥", "onion", "玉ねぎ"),
      r("sweetpotato", "地瓜", "sweet potato", "さつまいも"),
      r("corn", "玉米", "corn", "とうもろこし"),
      r("strawberry", "草莓", "strawberry", "いちご"),
      r("lemon", "檸檬", "lemon", "レモン"),
      r("cucumber", "小黃瓜", "cucumber", "きゅうり"),
      r("potato", "馬鈴薯", "potato", "じゃがいも"),
    ],
  ],
  [
    4,
    "🍰",
    [
      r("bread", "麵包", "bread", "パン"),
      r("cake", "蛋糕", "cake", "ケーキ", "birthday.cake"),
      r("cookie", "餅乾", "cookie", "クッキー"),
      r("icecream", "冰淇淋", "ice cream", "アイスクリーム"),
      r("pineapplecake", "鳳梨酥", "pineapple cake", "パイナップルケーキ"),
    ],
    [
      r("candy", "糖果", "candy", "飴"),
      r("chocolate", "巧克力", "chocolate", "チョコレート"),
      r("toast", "吐司", "toast", "食パン"),
      r("shavedice", "剉冰", "shaved ice", "かき氷"),
      r("chips", "洋芋片", "potato chips", "ポテトチップス"),
      r("pudding", "布丁", "pudding", "プリン"),
      r("douhua", "豆花", "tofu pudding", "豆花"),
      r("donut", "甜甜圈", "donut", "ドーナツ"),
      r("eggtart", "蛋塔", "egg tart", "エッグタルト"),
      r("mochi", "麻糬", "mochi", "もち"),
      r("taroballs", "芋圓", "taro balls", "タロイモ団子"),
      r("waffle", "鬆餅", "waffle", "ワッフル"),
      r("jelly", "果凍", "jelly", "ゼリー"),
      r("popcorn", "爆米花", "popcorn", "ポップコーン", "popcorn"),
    ],
  ],
  [
    5,
    "🥢",
    [
      r("cup", "杯子", "cup", "コップ", "mug"),
      r("bowl", "碗", "bowl", "お椀"),
      r("chopsticks", "筷子", "chopsticks", "箸"),
      r("plate", "盤子", "plate", "皿"),
      r("spoon", "湯匙", "spoon", "スプーン"),
    ],
    [
      r("fork", "叉子", "fork", "フォーク"),
      r("knife", "刀子", "knife", "ナイフ"),
      r("straw", "吸管", "straw", "ストロー"),
      r("papercup", "紙杯", "paper cup", "紙コップ"),
      r("pot", "鍋子", "pot", "鍋"),
      r("fryingpan", "平底鍋", "frying pan", "フライパン", "frying.pan"),
      r("glass", "玻璃杯", "glass", "グラス"),
      r("kettle", "水壺", "kettle", "やかん"),
      r("cuttingboard", "砧板", "cutting board", "まな板"),
      r("bentobox", "便當盒", "bento box", "弁当箱"),
      r("thermos", "保溫瓶", "thermos", "水筒"),
      r("wok", "炒鍋", "wok", "中華鍋"),
      r("teapot", "茶壺", "teapot", "急須"),
      r("sponge", "菜瓜布", "scrub sponge", "スポンジ"),
      r("dishsoap", "洗碗精", "dish soap", "食器用洗剤"),
    ],
  ],
  [
    6,
    "🛋️",
    [
      r("chair", "椅子", "chair", "椅子", "chair"),
      r("table", "桌子", "table", "テーブル", "table.furniture"),
      r("bed", "床", "bed", "ベッド", "bed.double"),
      r("sofa", "沙發", "sofa", "ソファ", "sofa"),
      r("clock", "時鐘", "clock", "時計", "clock"),
    ],
    [
      r("window", "窗戶", "window", "窓", "window.casement"),
      r("door", "門", "door", "ドア", "door.left.hand.closed"),
      r("light", "電燈", "light", "電気", "lightbulb"),
      r("desk", "書桌", "desk", "机"),
      r("curtain", "窗簾", "curtain", "カーテン", "curtains.closed"),
      r("mirror", "鏡子", "mirror", "鏡"),
      r("pillow", "枕頭", "pillow", "枕"),
      r("blanket", "被子", "blanket", "布団"),
      r("cabinet", "櫃子", "cabinet", "戸棚", "cabinet"),
      r("lamp", "檯燈", "desk lamp", "電気スタンド", "lamp.desk"),
      r("bookshelf", "書架", "bookshelf", "本棚", "books.vertical"),
      r("stairs", "樓梯", "stairs", "階段", "stairs"),
      r("alarmclock", "鬧鐘", "alarm clock", "目覚まし時計", "alarm"),
      r("calendar", "月曆", "calendar", "カレンダー", "calendar"),
    ],
  ],
  [
    7,
    "🔌",
    [
      r("aircon", "冷氣", "air conditioner", "エアコン", "air.conditioner.horizontal"),
      r("refrigerator", "冰箱", "fridge", "冷蔵庫", "refrigerator"),
      r("tv", "電視", "TV", "テレビ", "tv"),
      r("washingmachine", "洗衣機", "washing machine", "洗濯機", "washer"),
      r("fan", "電風扇", "electric fan", "扇風機", "fan.desk"),
    ],
    [
      r("ricecooker", "電鍋", "rice cooker", "炊飯器"),
      r("microwave", "微波爐", "microwave", "電子レンジ", "microwave"),
      r("hairdryer", "吹風機", "hair dryer", "ドライヤー"),
      r("remote", "遙控器", "remote control", "リモコン", "av.remote"),
      r("waterdispenser", "飲水機", "water dispenser", "ウォーターサーバー"),
      r("dehumidifier", "除濕機", "dehumidifier", "除湿機", "dehumidifier"),
      r("vacuum", "吸塵器", "vacuum cleaner", "掃除機"),
      r("hotwaterpot", "熱水瓶", "electric water pot", "電気ポット"),
      r("oven", "烤箱", "oven", "オーブン", "oven"),
      r("airpurifier", "空氣清淨機", "air purifier", "空気清浄機", "air.purifier"),
      r("inductioncooker", "電磁爐", "induction cooker", "IHコンロ", "cooktop"),
      r("clothesdryer", "烘衣機", "clothes dryer", "衣類乾燥機", "dryer"),
      r("iron", "熨斗", "iron", "アイロン"),
      r("toaster", "烤麵包機", "toaster", "トースター"),
    ],
  ],
  [
    8,
    "📱",
    [
      r("phone", "手機", "phone", "スマホ", "iphone"),
      r("computer", "電腦", "computer", "パソコン", "laptopcomputer"),
      r("headphones", "耳機", "headphones", "イヤホン", "headphones"),
      r("charger", "充電器", "charger", "充電器", "powerplug"),
      r("camera", "相機", "camera", "カメラ", "camera"),
    ],
    [
      r("powerbank", "行動電源", "power bank", "モバイルバッテリー"),
      r("chargingcable", "充電線", "charging cable", "充電ケーブル", "cable.connector"),
      r("tablet", "平板", "tablet", "タブレット", "ipad"),
      r("phonecase", "手機殼", "phone case", "スマホケース"),
      r("battery", "電池", "battery", "電池", "battery.100"),
      r("keyboard", "鍵盤", "keyboard", "キーボード", "keyboard"),
      r("computermouse", "滑鼠", "computer mouse", "マウス", "computermouse"),
      r("monitor", "螢幕", "monitor", "モニター", "display"),
      r("speaker", "喇叭", "speaker", "スピーカー", "hifispeaker"),
      r("usbdrive", "隨身碟", "USB flash drive", "USBメモリ"),
      r("printer", "印表機", "printer", "プリンター", "printer"),
      r("smartwatch", "智慧手錶", "smartwatch", "スマートウォッチ", "applewatch"),
      r("microphone", "麥克風", "microphone", "マイク", "mic"),
      r("router", "路由器", "router", "ルーター", "wifi.router"),
    ],
  ],
  [
    9,
    "✏️",
    [
      r("book", "書", "book", "本", "book.closed"),
      r("pen", "筆", "pen", "ペン", "pencil"),
      r("notebook", "筆記本", "notebook", "ノート"),
      r("scissors", "剪刀", "scissors", "はさみ", "scissors"),
      r("eraser", "橡皮擦", "eraser", "消しゴム", "eraser"),
    ],
    [
      r("pencil", "鉛筆", "pencil", "鉛筆"),
      r("paper", "紙", "paper", "紙", "doc"),
      r("comic", "漫畫", "comic", "漫画"),
      r("ruler", "尺", "ruler", "定規", "ruler"),
      r("tape", "膠帶", "tape", "テープ"),
      r("pencilcase", "鉛筆盒", "pencil case", "筆箱"),
      r("marker", "麥克筆", "marker", "マーカー"),
      r("glue", "膠水", "glue", "のり"),
      r("envelope", "信封", "envelope", "封筒", "envelope"),
      r("newspaper", "報紙", "newspaper", "新聞", "newspaper"),
      r("magazine", "雜誌", "magazine", "雑誌", "magazine"),
      r("folder", "資料夾", "folder", "フォルダー", "folder"),
      r("stapler", "釘書機", "stapler", "ホッチキス"),
      r("paperclip", "迴紋針", "paper clip", "クリップ", "paperclip"),
      r("dictionary", "字典", "dictionary", "辞書"),
    ],
  ],
  [
    10,
    "🪥",
    [
      r("toothbrush", "牙刷", "toothbrush", "歯ブラシ"),
      r("towel", "毛巾", "towel", "タオル"),
      r("tissue", "衛生紙", "tissue", "ティッシュ"),
      r("key", "鑰匙", "key", "鍵", "key"),
      r("medicine", "藥", "medicine", "薬", "pills"),
    ],
    [
      r("money", "錢", "money", "お金", "banknote"),
      r("plasticbag", "塑膠袋", "plastic bag", "ビニール袋", "bag"),
      r("toothpaste", "牙膏", "toothpaste", "歯磨き粉"),
      r("coin", "硬幣", "coin", "硬貨"),
      r("soap", "肥皂", "soap", "石けん"),
      r("shampoo", "洗髮精", "shampoo", "シャンプー"),
      r("trashbag", "垃圾袋", "trash bag", "ゴミ袋"),
      r("transitcard", "悠遊卡", "transit card", "交通系ICカード"),
      r("receipt", "發票", "receipt", "レシート"),
      r("toilet", "馬桶", "toilet", "トイレ", "toilet"),
      r("sink", "洗手台", "sink", "洗面台", "sink"),
      r("wetwipes", "濕紙巾", "wet wipes", "ウェットティッシュ"),
      r("creditcard", "信用卡", "credit card", "クレジットカード", "creditcard"),
      r("bandage", "OK繃", "bandage", "絆創膏", "bandage"),
      r("hanger", "衣架", "hanger", "ハンガー", "hanger"),
    ],
  ],
  [
    11,
    "👕",
    [
      r("clothes", "衣服", "clothes", "服", "tshirt"),
      r("pants", "褲子", "pants", "ズボン"),
      r("jacket", "外套", "jacket", "上着", "jacket"),
      r("skirt", "裙子", "skirt", "スカート"),
      r("socks", "襪子", "socks", "靴下"),
    ],
    [
      r("tshirt", "T恤", "T-shirt", "Tシャツ"),
      r("shirt", "襯衫", "shirt", "シャツ"),
      r("shorts", "短褲", "shorts", "短パン"),
      r("jeans", "牛仔褲", "jeans", "ジーンズ"),
      r("dress", "洋裝", "dress", "ワンピース"),
      r("raincoat", "雨衣", "raincoat", "レインコート"),
      r("sweater", "毛衣", "sweater", "セーター"),
      r("hoodie", "帽T", "hoodie", "パーカー"),
      r("uniform", "制服", "uniform", "制服"),
      r("pajamas", "睡衣", "pajamas", "パジャマ"),
      r("tanktop", "背心", "tank top", "タンクトップ"),
      r("underwear", "內衣", "underwear", "下着"),
      r("scarf", "圍巾", "scarf", "マフラー"),
      r("necktie", "領帶", "necktie", "ネクタイ"),
    ],
  ],
  [
    12,
    "👟",
    [
      r("shoes", "鞋子", "shoes", "靴", "shoe"),
      r("hat", "帽子", "hat", "帽子", "hat.cap"),
      r("glasses", "眼鏡", "glasses", "眼鏡", "eyeglasses"),
      r("bag", "包包", "bag", "かばん", "handbag"),
      r("umbrella", "雨傘", "umbrella", "傘", "umbrella"),
    ],
    [
      r("watch", "手錶", "watch", "腕時計", "watch.analog"),
      r("backpack", "背包", "backpack", "リュック", "backpack"),
      r("mask", "口罩", "face mask", "マスク"),
      r("slippers", "拖鞋", "slippers", "スリッパ"),
      r("wallet", "錢包", "wallet", "財布", "wallet.bifold"),
      r("helmet", "安全帽", "helmet", "ヘルメット", "helmet"),
      r("sneakers", "球鞋", "sneakers", "スニーカー", "shoe.2"),
      r("sunglasses", "太陽眼鏡", "sunglasses", "サングラス", "sunglasses"),
      r("suitcase", "行李箱", "suitcase", "スーツケース", "suitcase.rolling"),
      r("belt", "皮帶", "belt", "ベルト"),
      r("hairtie", "髮圈", "hair tie", "ヘアゴム"),
      r("earrings", "耳環", "earrings", "イヤリング"),
      r("necklace", "項鍊", "necklace", "ネックレス"),
      r("ring", "戒指", "ring", "指輪"),
      r("gloves", "手套", "gloves", "手袋"),
    ],
  ],
  [
    13,
    "🛵",
    [
      r("scooter", "機車", "scooter", "バイク", "motorcycle"),
      r("bus", "公車", "bus", "バス", "bus"),
      r("bicycle", "腳踏車", "bicycle", "自転車", "bicycle"),
      r("mrt", "捷運", "subway", "地下鉄", "tram.fill.tunnel"),
      r("taxi", "計程車", "taxi", "タクシー", "car"),
    ],
    [
      r("car", "汽車", "car", "車", "car.side"),
      r("train", "火車", "train", "電車", "train.side.front.car"),
      r("airplane", "飛機", "airplane", "飛行機", "airplane"),
      r("truck", "卡車", "truck", "トラック"),
      r("hsr", "高鐵", "high-speed rail", "新幹線"),
      r("boat", "船", "boat", "船", "ferry"),
      r("garbagetruck", "垃圾車", "garbage truck", "ゴミ収集車"),
      r("ambulance", "救護車", "ambulance", "救急車"),
      r("policecar", "警車", "police car", "パトカー"),
      r("firetruck", "消防車", "fire truck", "消防車"),
      r("kickscooter", "滑板車", "kick scooter", "キックボード", "scooter"),
      r("stroller", "嬰兒車", "stroller", "ベビーカー", "stroller"),
      r("cablecar", "纜車", "cable car", "ロープウェイ", "cablecar"),
    ],
  ],
  [
    14,
    "🏪",
    [
      r("conveniencestore", "便利商店", "convenience store", "コンビニ", "storefront"),
      r("temple", "廟", "temple", "お寺"),
      r("school", "學校", "school", "学校"),
      r("restaurant", "餐廳", "restaurant", "レストラン", "fork.knife"),
      r("nightmarket", "夜市", "night market", "夜市"),
    ],
    [
      r("house", "房子", "house", "家", "house"),
      r("building", "大樓", "building", "ビル", "building.2"),
      r("breakfastshop", "早餐店", "breakfast shop", "朝ごはん屋"),
      r("park", "公園", "park", "公園"),
      r("station", "車站", "station", "駅"),
      r("hospital", "醫院", "hospital", "病院", "cross"),
      r("supermarket", "超市", "supermarket", "スーパー", "cart"),
      r("market", "市場", "market", "市場", "basket"),
      r("bank", "銀行", "bank", "銀行", "building.columns"),
      r("pharmacy", "藥局", "pharmacy", "薬局"),
      r("cafe", "咖啡廳", "café", "カフェ"),
      r("gasstation", "加油站", "gas station", "ガソリンスタンド", "fuelpump"),
      r("postoffice", "郵局", "post office", "郵便局"),
      r("library", "圖書館", "library", "図書館"),
    ],
  ],
  [
    15,
    "🚦",
    [
      r("trafficlight", "紅綠燈", "traffic light", "信号"),
      r("signboard", "招牌", "signboard", "看板", "signpost.right"),
      r("trashcan", "垃圾桶", "trash can", "ゴミ箱", "trash"),
      r("streetlight", "路燈", "streetlight", "街灯"),
      r("crosswalk", "斑馬線", "crosswalk", "横断歩道"),
    ],
    [
      r("road", "馬路", "road", "道路", "road.lanes"),
      r("busstop", "公車站", "bus stop", "バス停"),
      r("bench", "長椅", "bench", "ベンチ"),
      r("mailbox", "郵筒", "mailbox", "ポスト"),
      r("parkinglot", "停車場", "parking lot", "駐車場", "parkingsign"),
      r("bridge", "橋", "bridge", "橋"),
      r("vendingmachine", "販賣機", "vending machine", "自動販売機"),
      r("utilitypole", "電線桿", "utility pole", "電柱"),
      r("sidewalk", "人行道", "sidewalk", "歩道"),
      r("flag", "旗子", "flag", "旗", "flag"),
      r("trafficcone", "三角錐", "traffic cone", "カラーコーン", "cone"),
      r("firehydrant", "消防栓", "fire hydrant", "消火栓"),
      r("atm", "提款機", "ATM", "ATM"),
    ],
  ],
  [
    16,
    "🐾",
    [
      r("dog", "狗", "dog", "犬", "dog"),
      r("cat", "貓", "cat", "猫", "cat"),
      r("bird", "鳥", "bird", "鳥", "bird"),
      r("fish", "魚", "fish", "魚", "fish"),
      r("rabbit", "兔子", "rabbit", "うさぎ", "hare"),
    ],
    [
      r("pigeon", "鴿子", "pigeon", "ハト"),
      r("sparrow", "麻雀", "sparrow", "スズメ"),
      r("mosquito", "蚊子", "mosquito", "蚊"),
      r("ant", "螞蟻", "ant", "アリ", "ant"),
      r("cockroach", "蟑螂", "cockroach", "ゴキブリ"),
      r("gecko", "壁虎", "gecko", "ヤモリ", "lizard"),
      r("butterfly", "蝴蝶", "butterfly", "チョウ"),
      r("chicken", "雞", "chicken", "ニワトリ"),
      r("duck", "鴨子", "duck", "アヒル"),
      r("turtle", "烏龜", "turtle", "カメ", "tortoise"),
      r("squirrel", "松鼠", "squirrel", "リス"),
      r("frog", "青蛙", "frog", "カエル"),
      r("hamster", "倉鼠", "hamster", "ハムスター"),
      r("ladybug", "瓢蟲", "ladybug", "テントウムシ", "ladybug"),
    ],
  ],
  [
    17,
    "🌿",
    [
      r("flower", "花", "flower", "花", "camera.macro"),
      r("tree", "樹", "tree", "木", "tree"),
      r("grass", "草", "grass", "草"),
      r("leaf", "葉子", "leaf", "葉っぱ", "leaf"),
      r("pottedplant", "盆栽", "potted plant", "鉢植え"),
    ],
    [
      r("banyan", "榕樹", "banyan tree", "ガジュマル"),
      r("palmtree", "椰子樹", "palm tree", "ヤシの木"),
      r("cactus", "仙人掌", "cactus", "サボテン"),
      r("rose", "玫瑰", "rose", "バラ"),
      r("bamboo", "竹子", "bamboo", "竹"),
      r("sunflower", "向日葵", "sunflower", "ひまわり"),
      r("moss", "青苔", "moss", "苔"),
      r("mushroom", "香菇", "mushroom", "キノコ"),
      r("cherryblossom", "櫻花", "cherry blossom", "桜"),
      r("orchid", "蘭花", "orchid", "ラン"),
      r("lotus", "蓮花", "lotus", "ハス"),
      r("seed", "種子", "seed", "種"),
    ],
  ],
  [
    18,
    "⛅",
    [
      r("sky", "天空", "sky", "空", "cloud.sun"),
      r("cloud", "雲", "cloud", "雲", "cloud"),
      r("mountain", "山", "mountain", "山", "mountain.2"),
      r("sea", "海", "sea", "海", "water.waves"),
      r("moon", "月亮", "moon", "月", "moon"),
    ],
    [
      r("sun", "太陽", "sun", "太陽", "sun.max"),
      r("rain", "雨", "rain", "雨", "cloud.rain"),
      r("star", "星星", "star", "星", "star"),
      r("river", "河", "river", "川"),
      r("rainbow", "彩虹", "rainbow", "虹", "rainbow"),
      r("sunset", "夕陽", "sunset", "夕日", "sun.horizon"),
      r("stone", "石頭", "stone", "石"),
      r("wind", "風", "wind", "風", "wind"),
      r("beach", "海灘", "beach", "ビーチ", "beach.umbrella"),
      r("lightning", "閃電", "lightning", "雷", "cloud.bolt"),
      r("lake", "湖", "lake", "湖"),
      r("puddle", "水坑", "puddle", "水たまり"),
      r("fire", "火", "fire", "火", "flame"),
      r("sand", "沙子", "sand", "砂"),
    ],
  ],
  [
    19,
    "⚽",
    [
      r("ball", "球", "ball", "ボール", "soccerball"),
      r("toy", "玩具", "toy", "おもちゃ", "teddybear"),
      r("guitar", "吉他", "guitar", "ギター", "guitars"),
      r("gameconsole", "遊戲機", "game console", "ゲーム機", "gamecontroller"),
      r("balloon", "氣球", "balloon", "風船", "balloon"),
    ],
    [
      r("basketball", "籃球", "basketball", "バスケットボール", "basketball"),
      r("badminton", "羽毛球", "badminton", "バドミントン"),
      r("baseball", "棒球", "baseball", "野球", "baseball"),
      r("tabletennis", "桌球", "table tennis", "卓球"),
      r("clawmachine", "夾娃娃機", "claw machine", "クレーンゲーム"),
      r("cards", "撲克牌", "playing cards", "トランプ"),
      r("doll", "娃娃", "doll", "人形"),
      r("puzzle", "拼圖", "jigsaw puzzle", "パズル", "puzzlepiece"),
      r("movie", "電影", "movie", "映画", "film"),
      r("piano", "鋼琴", "piano", "ピアノ", "pianokeys"),
      r("skateboard", "滑板", "skateboard", "スケボー", "skateboard"),
      r("dice", "骰子", "dice", "サイコロ", "dice"),
      r("kite", "風箏", "kite", "凧"),
    ],
  ],
  [
    20,
    "🖐️",
    [
      r("hand", "手", "hand", "手", "hand.raised"),
      r("face", "臉", "face", "顔", "face.smiling"),
      r("eye", "眼睛", "eye", "目", "eye"),
      r("child", "小孩", "child", "子ども", "figure.child"),
      r("friend", "朋友", "friend", "友だち", "person.2"),
    ],
    [
      r("mouth", "嘴巴", "mouth", "口", "mouth"),
      r("nose", "鼻子", "nose", "鼻", "nose"),
      r("ear", "耳朵", "ear", "耳", "ear"),
      r("hair", "頭髮", "hair", "髪"),
      r("foot", "腳", "foot", "足"),
      r("finger", "手指", "finger", "指", "hand.point.up"),
      r("head", "頭", "head", "頭"),
      r("mother", "媽媽", "mother", "お母さん"),
      r("father", "爸爸", "father", "お父さん"),
      r("baby", "嬰兒", "baby", "赤ちゃん"),
      r("student", "學生", "student", "学生"),
      r("teacher", "老師", "teacher", "先生"),
      r("grandmother", "阿嬤", "grandmother", "おばあちゃん"),
      r("shopowner", "老闆", "shop owner", "店主"),
    ],
  ],
];

/** 20 のカテゴリー。基本の物に No.001〜100 を表の順に振る。 */
export const DEX_CATEGORIES: readonly DexCategory[] = (() => {
  let no = 0;
  return TABLE.map(([cat, emoji, base, extra]) => {
    const b = base.map((raw) => ({ ...raw, category: cat, baseNo: ++no }));
    const e = extra.map((raw) => ({ ...raw, category: cat, baseNo: null }));
    return { no: cat, emoji, base: b, extra: e, items: [...b, ...e] };
  });
})();

/** 全部の影（カテゴリーの順、その中は基本 → 毎日の物）。 */
export const DEX_ITEMS: readonly DexItem[] = DEX_CATEGORIES.flatMap((c) => c.items);

/**
 * 見出し語の比べ方（iOS `DexCatalog.norm`）。前後の空白を落として小文字に。日本語は
 * カタカナをひらがなに、英語は頭の冠詞を落とす — りんご / リンゴ、"an apple" / "Apple" が同じ物。
 */
export function normDexHeadword(s: string | null | undefined, lang: string | null | undefined) {
  const l = dexLang(lang);
  let t = (s ?? "").trim().toLowerCase();
  if (l === "ja") t = t.replace(/[ァ-ヶ]/g, (c) => String.fromCharCode(c.charCodeAt(0) - 0x60));
  if (l === "en") {
    for (const a of ["a ", "an ", "the "]) {
      if (t.startsWith(a)) {
        t = t.slice(a.length);
        break;
      }
    }
  }
  return t;
}

/** 言語ごとの「見出し語 → 影」。同じ見出し語が2つあれば後ろが勝つ（iOS と同じ）。 */
const INDEX: Record<DexLang, Map<string, DexItem>> = (() => {
  const out = {} as Record<DexLang, Map<string, DexItem>>;
  for (const l of TARGET_LANGUAGES) {
    const m = new Map<string, DexItem>();
    for (const it of DEX_ITEMS) m.set(normDexHeadword(dexHeadword(it, l), l), it);
    out[l] = m;
  }
  return out;
})();

/** 学習言語のこの見出し語が、図鑑のどの影か（無ければ null）。 */
export function dexItemFor(
  headword: string | null | undefined,
  lang: string | null | undefined,
): DexItem | null {
  if (!headword) return null;
  const l = dexLang(lang);
  return INDEX[l].get(normDexHeadword(headword, l)) ?? null;
}

/**
 * 見出し語の**言い方の揺れ**（表の物と同じ物の言い方）。台湾華語だけ:
 * - 簡体字で打った語（猫 → 貓）。表の見出し語に使う字だけの小さな対応表。
 * - 「小〜」「〜仔」「〜兒」「〜咪」の付いた呼び方（小貓 → 貓、狗仔 → 狗）。
 *
 * 揺れは**カテゴリーを決めるためだけ**に使う。番号・影を埋めるのは見出し語が同じ時だけ
 * （`dexItemFor`）— 言い方が違う語に基本の100の番号を渡すと、iOS と番号の意味がずれる。
 */
// prettier-ignore
const SIMPLIFIED_TO_TRADITIONAL: Readonly<Record<string, string>> = {
  猫: "貓", 鸟: "鳥", 鱼: "魚", 鸡: "雞", 鸭: "鴨", 龟: "龜", 鸽: "鴿", 蚁: "蟻",
  树: "樹", 叶: "葉", 兰: "蘭", 莲: "蓮", 樱: "櫻", 种: "種", 苹: "蘋", 车: "車",
  书: "書", 笔: "筆", 电: "電", 脑: "腦", 机: "機", 视: "視", 灯: "燈", 伞: "傘",
  头: "頭", 脸: "臉", 云: "雲", 风: "風", 阳: "陽", 气: "氣", 饭: "飯", 汤: "湯",
};

function headwordVariants(h: string): string[] {
  const out = new Set<string>();
  const trad = [...h].map((c) => SIMPLIFIED_TO_TRADITIONAL[c] ?? c).join("");
  for (const w of [h, trad]) {
    out.add(w);
    const core = w.replace(/^小(?=.)/, "").replace(/(?<=.)(仔|兒|咪)$/, "");
    if (core) out.add(core);
  }
  out.delete(h);
  return [...out];
}

/**
 * 表から引いた図鑑のカテゴリー（見出し語 → 言い方の揺れ の順）。表に無ければ null。
 */
export function dexCatalogCategory(
  headword: string | null | undefined,
  lang: string | null | undefined,
): number | null {
  const exact = dexItemFor(headword, lang);
  if (exact) return exact.category;
  if (!headword || dexLang(lang) !== DEFAULT_TARGET_LANGUAGE) return null;
  for (const v of headwordVariants(headword.trim())) {
    const it = dexItemFor(v, lang);
    if (it) return it.category;
  }
  return null;
}

/**
 * 語の図鑑のカテゴリー: 表に在る見出し語（とその言い方の揺れ）ならその物のカテゴリー、
 * 無ければ分類の鍵から。どれでもなければ null（図鑑の「その他」の節）。
 */
export function dexCategoryOf(
  headword: string | null | undefined,
  key: string | null | undefined,
  lang: string | null | undefined,
): number | null {
  return dexCatalogCategory(headword, lang) ?? dexCategoryForKey(key);
}
