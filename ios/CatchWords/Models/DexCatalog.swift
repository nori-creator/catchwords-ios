import Foundation

// The dex's 20 categories and the things they show as shadows (owner decisions 2026-10-02; the 20 categories and
// their colours re-selected the same day — no その他 category).
//
// * 20 categories in this order, each with 5 base items: the base 100, numbered No.001–100 in table order
//   (category 1 items 1–5 = 001–005 … category 20 = 096–100). Base items keep their number caught or not.
// * After the base items, each category lists 12–15 more things people meet every day in Taiwan, most common
//   first ("AI selects things you meet every day" — curated here, shipped in the app; never other users'
//   captures, never rare items). The shadows of a category are its first 5 not-yet-caught items in this order.
// * Headwords for each learning language: zh-TW (primary), en, ja. A caught word matches a shadow when its
//   headword equals the item's headword in the learning language (`DexCatalog.item(headword:lang:)`).
// * `symbol`: an SF Symbol drawn as the shadow (every name exists on iOS 18 — DexCatalogSymbolTests). nil =
//   needsArt: a neutral rounded placeholder until AI silhouette art is made (docs/prototype/needs-art.md);
//   art added to the asset catalog as `dexsil-<id>` is used automatically.
// The headword strings are learning-language data, not UI text.

nonisolated struct DexItem: Sendable, Hashable, Identifiable {
    let id: String
    let zh: String
    let en: String
    let ja: String
    let symbol: String?
    /// 1–20.
    let category: Int
    /// No.001–100 for the base items; nil for the everyday extension items.
    let baseNo: Int?

    var needsArt: Bool { symbol == nil }

    /// The headword in a learning language (zh-TW / en / ja).
    func headword(for lang: String) -> String {
        switch lang {
        case "en": en
        case "ja": ja
        default: zh
        }
    }
}

nonisolated struct DexCategory: Sendable, Identifiable {
    let no: Int
    let emoji: String
    let base: [DexItem]
    let extra: [DexItem]

    var id: Int { no }
    /// Base items first, then the extension list (most common first).
    var items: [DexItem] { base + extra }
    var label: String { DexCatalog.label(no) }
}

nonisolated enum DexCatalog {
    private struct Raw: Sendable {
        let id: String, zh: String, en: String, ja: String, symbol: String?
    }

    private static func r(_ id: String, _ zh: String, _ en: String, _ ja: String, _ symbol: String? = nil) -> Raw {
        Raw(id: id, zh: zh, en: en, ja: ja, symbol: symbol)
    }

    /// The category name (ja / en / zh-TW through `L`).
    static func label(_ no: Int) -> String {
        switch no {
        case 1: L("飲み物")
        case 2: L("料理・屋台")
        case 3: L("果物・野菜")
        case 4: L("お菓子・パン")
        case 5: L("食器・台所")
        case 6: L("家具・インテリア")
        case 7: L("家電")
        case 8: L("スマホ・パソコン")
        case 9: L("文房具・本")
        case 10: L("洗面・日用品")
        case 11: L("服")
        case 12: L("靴・バッグ・小物")
        case 13: L("乗り物")
        case 14: L("建物・お店")
        case 15: L("道・街の物")
        case 16: L("動物")
        case 17: L("植物・花")
        case 18: L("空・自然")
        case 19: L("スポーツ・遊び")
        case 20: L("人・体")
        default: L("その他")
        }
    }

    /// Every one of the app's 54 category keys (Models/Category.swift) → its dex category (1–20).
    static let keyToCategory: [String: Int] = [
        "drink": 1, "food": 2, "fruit": 3, "vegetable": 3, "dessert": 4, "kitchenware": 5, "home": 6, "furniture": 6,
        "decoration": 6, "appliance": 7, "tech": 8, "gadget": 8, "stationery": 9, "book": 9, "document": 9,
        "tool": 10, "medicine": 10, "money": 10, "color": 10, "shape": 10, "other": otherNo, "clothes": 11,
        "clothing_part": 11, "accessory": 12, "shoes": 12, "bag": 12, "jewelry": 12, "vehicle": 13, "transport": 13,
        "building": 14, "shop": 14, "street": 15, "sign": 15, "character": 15, "symbol": 15, "animal": 16,
        "plant": 17, "flower": 17, "nature": 18, "weather": 18, "sky": 18, "water": 18, "mountain": 18, "toy": 19,
        "game": 19, "sport": 19, "instrument": 19, "art": 19, "body": 20, "face": 20, "hand": 20, "person": 20,
        "family": 20, "job": 20,
    ]

    /// The dex category of a category key; anything unknown (an old custom key, a missing key) goes with "other"
    /// into その他 at the end. It used to go into 10 (洗面・日用品), so 桃・可頌・蘑菇・健康餐 saved as "other" sat among the
    /// towels (owner 2026-10-14; the web made the same change on 2026-10-09).
    static func category(forKey key: String?) -> Int {
        guard let key else { return otherNo }
        return keyToCategory[key] ?? otherNo
    }

    /// その他: after the 20 categories, only for words no rule or key places. It has no shadows and is shown only
    /// when a word is in it.
    static let otherNo = 21
    static let other = DexCategory(no: otherNo, emoji: "✨", base: [], extra: [])
    /// The 20 categories, then その他.
    static var withOther: [DexCategory] { categories + [other] }

    /// Where a word belongs: the catalog item's category when its headword is in the catalog, else its key's.
    static func category(headword: String?, key: String?, lang: String) -> Int {
        item(headword: headword, lang: lang)?.category ?? category(forKey: key)
    }

    private typealias Table = (no: Int, emoji: String, base: [Raw], extra: [Raw])

    private static let c1: Table = (1, "🧋", [
        r("bubbletea", "珍珠奶茶", "bubble tea", "タピオカミルクティー"),  // l10n-ignore (catalog headwords)
        r("coffee", "咖啡", "coffee", "コーヒー", "cup.and.saucer"),  // l10n-ignore (catalog headwords)
        r("tea", "茶", "tea", "お茶"),  // l10n-ignore (catalog headwords)
        r("juice", "果汁", "juice", "ジュース"),  // l10n-ignore (catalog headwords)
        r("water", "水", "water", "水", "waterbottle"),  // l10n-ignore (catalog headwords)
    ], [
        r("soymilk", "豆漿", "soy milk", "豆乳"),  // l10n-ignore (catalog headwords)
        r("milk", "牛奶", "milk", "牛乳"),  // l10n-ignore (catalog headwords)
        r("blacktea", "紅茶", "black tea", "紅茶"),  // l10n-ignore (catalog headwords)
        r("greentea", "綠茶", "green tea", "緑茶"),  // l10n-ignore (catalog headwords)
        r("milktea", "奶茶", "milk tea", "ミルクティー"),  // l10n-ignore (catalog headwords)
        r("cola", "可樂", "cola", "コーラ"),  // l10n-ignore (catalog headwords)
        r("latte", "拿鐵", "latte", "ラテ", "cup.and.heat.waves"),  // l10n-ignore (catalog headwords)
        r("soda", "汽水", "soda", "炭酸飲料"),  // l10n-ignore (catalog headwords)
        r("sportsdrink", "運動飲料", "sports drink", "スポーツドリンク"),  // l10n-ignore (catalog headwords)
        r("beer", "啤酒", "beer", "ビール"),  // l10n-ignore (catalog headwords)
        r("wintermelontea", "冬瓜茶", "winter melon tea", "冬瓜茶"),  // l10n-ignore (catalog headwords)
        r("yogurtdrink", "優酪乳", "drinkable yogurt", "飲むヨーグルト"),  // l10n-ignore (catalog headwords)
        r("hotcocoa", "熱可可", "hot chocolate", "ココア"),  // l10n-ignore (catalog headwords)
        r("wine", "葡萄酒", "wine", "ワイン", "wineglass"),  // l10n-ignore (catalog headwords)
    ])

    private static let c2: Table = (2, "🍜", [
        r("rice", "飯", "rice", "ご飯"),  // l10n-ignore (catalog headwords)
        r("noodles", "麵", "noodles", "麺"),  // l10n-ignore (catalog headwords)
        r("bento", "便當", "bento", "弁当"),  // l10n-ignore (catalog headwords)
        r("dumplings", "水餃", "dumplings", "水餃子"),  // l10n-ignore (catalog headwords)
        r("bun", "包子", "steamed bun", "肉まん"),  // l10n-ignore (catalog headwords)
    ], [
        r("egg", "蛋", "egg", "卵"),  // l10n-ignore (catalog headwords)
        r("braisedporkrice", "滷肉飯", "braised pork rice", "魯肉飯"),  // l10n-ignore (catalog headwords)
        r("friedrice", "炒飯", "fried rice", "チャーハン"),  // l10n-ignore (catalog headwords)
        r("soup", "湯", "soup", "スープ"),  // l10n-ignore (catalog headwords)
        r("beefnoodles", "牛肉麵", "beef noodle soup", "牛肉麺"),  // l10n-ignore (catalog headwords)
        r("danbing", "蛋餅", "egg crepe", "ダンビン"),  // l10n-ignore (catalog headwords)
        r("sandwich", "三明治", "sandwich", "サンドイッチ"),  // l10n-ignore (catalog headwords)
        r("tofu", "豆腐", "tofu", "豆腐"),  // l10n-ignore (catalog headwords)
        r("porridge", "粥", "congee", "お粥"),  // l10n-ignore (catalog headwords)
        r("friedchicken", "炸雞", "fried chicken", "フライドチキン"),  // l10n-ignore (catalog headwords)
        r("stinkytofu", "臭豆腐", "stinky tofu", "臭豆腐"),  // l10n-ignore (catalog headwords)
        r("hotpot", "火鍋", "hot pot", "火鍋"),  // l10n-ignore (catalog headwords)
        r("scallionpancake", "蔥油餅", "scallion pancake", "ねぎ餅"),  // l10n-ignore (catalog headwords)
        r("hamburger", "漢堡", "hamburger", "ハンバーガー"),  // l10n-ignore (catalog headwords)
    ])

    private static let c3: Table = (3, "🍎", [
        r("apple", "蘋果", "apple", "りんご"),  // l10n-ignore (catalog headwords)
        r("banana", "香蕉", "banana", "バナナ"),  // l10n-ignore (catalog headwords)
        r("mango", "芒果", "mango", "マンゴー"),  // l10n-ignore (catalog headwords)
        r("tomato", "番茄", "tomato", "トマト"),  // l10n-ignore (catalog headwords)
        r("cabbage", "高麗菜", "cabbage", "キャベツ"),  // l10n-ignore (catalog headwords)
    ], [
        r("orange", "橘子", "orange", "みかん"),  // l10n-ignore (catalog headwords)
        r("watermelon", "西瓜", "watermelon", "スイカ"),  // l10n-ignore (catalog headwords)
        r("guava", "芭樂", "guava", "グァバ"),  // l10n-ignore (catalog headwords)
        r("grapes", "葡萄", "grapes", "ぶどう"),  // l10n-ignore (catalog headwords)
        r("pineapple", "鳳梨", "pineapple", "パイナップル"),  // l10n-ignore (catalog headwords)
        r("papaya", "木瓜", "papaya", "パパイヤ"),  // l10n-ignore (catalog headwords)
        r("carrot", "紅蘿蔔", "carrot", "にんじん", "carrot"),  // l10n-ignore (catalog headwords)
        r("onion", "洋蔥", "onion", "玉ねぎ"),  // l10n-ignore (catalog headwords)
        r("sweetpotato", "地瓜", "sweet potato", "さつまいも"),  // l10n-ignore (catalog headwords)
        r("corn", "玉米", "corn", "とうもろこし"),  // l10n-ignore (catalog headwords)
        r("strawberry", "草莓", "strawberry", "いちご"),  // l10n-ignore (catalog headwords)
        r("lemon", "檸檬", "lemon", "レモン"),  // l10n-ignore (catalog headwords)
        r("cucumber", "小黃瓜", "cucumber", "きゅうり"),  // l10n-ignore (catalog headwords)
        r("potato", "馬鈴薯", "potato", "じゃがいも"),  // l10n-ignore (catalog headwords)
    ])

    private static let c4: Table = (4, "🍰", [
        r("bread", "麵包", "bread", "パン"),  // l10n-ignore (catalog headwords)
        r("cake", "蛋糕", "cake", "ケーキ", "birthday.cake"),  // l10n-ignore (catalog headwords)
        r("cookie", "餅乾", "cookie", "クッキー"),  // l10n-ignore (catalog headwords)
        r("icecream", "冰淇淋", "ice cream", "アイスクリーム"),  // l10n-ignore (catalog headwords)
        r("pineapplecake", "鳳梨酥", "pineapple cake", "パイナップルケーキ"),  // l10n-ignore (catalog headwords)
    ], [
        r("candy", "糖果", "candy", "飴"),  // l10n-ignore (catalog headwords)
        r("chocolate", "巧克力", "chocolate", "チョコレート"),  // l10n-ignore (catalog headwords)
        r("toast", "吐司", "toast", "食パン"),  // l10n-ignore (catalog headwords)
        r("shavedice", "剉冰", "shaved ice", "かき氷"),  // l10n-ignore (catalog headwords)
        r("chips", "洋芋片", "potato chips", "ポテトチップス"),  // l10n-ignore (catalog headwords)
        r("pudding", "布丁", "pudding", "プリン"),  // l10n-ignore (catalog headwords)
        r("douhua", "豆花", "tofu pudding", "豆花"),  // l10n-ignore (catalog headwords)
        r("donut", "甜甜圈", "donut", "ドーナツ"),  // l10n-ignore (catalog headwords)
        r("eggtart", "蛋塔", "egg tart", "エッグタルト"),  // l10n-ignore (catalog headwords)
        r("mochi", "麻糬", "mochi", "もち"),  // l10n-ignore (catalog headwords)
        r("taroballs", "芋圓", "taro balls", "タロイモ団子"),  // l10n-ignore (catalog headwords)
        r("waffle", "鬆餅", "waffle", "ワッフル"),  // l10n-ignore (catalog headwords)
        r("jelly", "果凍", "jelly", "ゼリー"),  // l10n-ignore (catalog headwords)
        r("popcorn", "爆米花", "popcorn", "ポップコーン", "popcorn"),  // l10n-ignore (catalog headwords)
    ])

    private static let c5: Table = (5, "🥢", [
        r("cup", "杯子", "cup", "コップ", "mug"),  // l10n-ignore (catalog headwords)
        r("bowl", "碗", "bowl", "お椀"),  // l10n-ignore (catalog headwords)
        r("chopsticks", "筷子", "chopsticks", "箸"),  // l10n-ignore (catalog headwords)
        r("plate", "盤子", "plate", "皿"),  // l10n-ignore (catalog headwords)
        r("spoon", "湯匙", "spoon", "スプーン"),  // l10n-ignore (catalog headwords)
    ], [
        r("fork", "叉子", "fork", "フォーク"),  // l10n-ignore (catalog headwords)
        r("knife", "刀子", "knife", "ナイフ"),  // l10n-ignore (catalog headwords)
        r("straw", "吸管", "straw", "ストロー"),  // l10n-ignore (catalog headwords)
        r("papercup", "紙杯", "paper cup", "紙コップ"),  // l10n-ignore (catalog headwords)
        r("pot", "鍋子", "pot", "鍋"),  // l10n-ignore (catalog headwords)
        r("fryingpan", "平底鍋", "frying pan", "フライパン", "frying.pan"),  // l10n-ignore (catalog headwords)
        r("glass", "玻璃杯", "glass", "グラス"),  // l10n-ignore (catalog headwords)
        r("kettle", "水壺", "kettle", "やかん"),  // l10n-ignore (catalog headwords)
        r("cuttingboard", "砧板", "cutting board", "まな板"),  // l10n-ignore (catalog headwords)
        r("bentobox", "便當盒", "bento box", "弁当箱"),  // l10n-ignore (catalog headwords)
        r("thermos", "保溫瓶", "thermos", "水筒"),  // l10n-ignore (catalog headwords)
        r("wok", "炒鍋", "wok", "中華鍋"),  // l10n-ignore (catalog headwords)
        r("teapot", "茶壺", "teapot", "急須"),  // l10n-ignore (catalog headwords)
        r("sponge", "菜瓜布", "scrub sponge", "スポンジ"),  // l10n-ignore (catalog headwords)
        r("dishsoap", "洗碗精", "dish soap", "食器用洗剤"),  // l10n-ignore (catalog headwords)
    ])

    private static let c6: Table = (6, "🛋️", [
        r("chair", "椅子", "chair", "椅子", "chair"),  // l10n-ignore (catalog headwords)
        r("table", "桌子", "table", "テーブル", "table.furniture"),  // l10n-ignore (catalog headwords)
        r("bed", "床", "bed", "ベッド", "bed.double"),  // l10n-ignore (catalog headwords)
        r("sofa", "沙發", "sofa", "ソファ", "sofa"),  // l10n-ignore (catalog headwords)
        r("clock", "時鐘", "clock", "時計", "clock"),  // l10n-ignore (catalog headwords)
    ], [
        r("window", "窗戶", "window", "窓", "window.casement"),  // l10n-ignore (catalog headwords)
        r("door", "門", "door", "ドア", "door.left.hand.closed"),  // l10n-ignore (catalog headwords)
        r("light", "電燈", "light", "電気", "lightbulb"),  // l10n-ignore (catalog headwords)
        r("desk", "書桌", "desk", "机"),  // l10n-ignore (catalog headwords)
        r("curtain", "窗簾", "curtain", "カーテン", "curtains.closed"),  // l10n-ignore (catalog headwords)
        r("mirror", "鏡子", "mirror", "鏡"),  // l10n-ignore (catalog headwords)
        r("pillow", "枕頭", "pillow", "枕"),  // l10n-ignore (catalog headwords)
        r("blanket", "被子", "blanket", "布団"),  // l10n-ignore (catalog headwords)
        r("cabinet", "櫃子", "cabinet", "戸棚", "cabinet"),  // l10n-ignore (catalog headwords)
        r("lamp", "檯燈", "desk lamp", "電気スタンド", "lamp.desk"),  // l10n-ignore (catalog headwords)
        r("bookshelf", "書架", "bookshelf", "本棚", "books.vertical"),  // l10n-ignore (catalog headwords)
        r("stairs", "樓梯", "stairs", "階段", "stairs"),  // l10n-ignore (catalog headwords)
        r("alarmclock", "鬧鐘", "alarm clock", "目覚まし時計", "alarm"),  // l10n-ignore (catalog headwords)
        r("calendar", "月曆", "calendar", "カレンダー", "calendar"),  // l10n-ignore (catalog headwords)
    ])

    private static let c7: Table = (7, "🔌", [
        r("aircon", "冷氣", "air conditioner", "エアコン", "air.conditioner.horizontal"),  // l10n-ignore (catalog headwords)
        r("refrigerator", "冰箱", "fridge", "冷蔵庫", "refrigerator"),  // l10n-ignore (catalog headwords)
        r("tv", "電視", "TV", "テレビ", "tv"),  // l10n-ignore (catalog headwords)
        r("washingmachine", "洗衣機", "washing machine", "洗濯機", "washer"),  // l10n-ignore (catalog headwords)
        r("fan", "電風扇", "electric fan", "扇風機", "fan.desk"),  // l10n-ignore (catalog headwords)
    ], [
        r("ricecooker", "電鍋", "rice cooker", "炊飯器"),  // l10n-ignore (catalog headwords)
        r("microwave", "微波爐", "microwave", "電子レンジ", "microwave"),  // l10n-ignore (catalog headwords)
        r("hairdryer", "吹風機", "hair dryer", "ドライヤー"),  // l10n-ignore (catalog headwords)
        r("remote", "遙控器", "remote control", "リモコン", "av.remote"),  // l10n-ignore (catalog headwords)
        r("waterdispenser", "飲水機", "water dispenser", "ウォーターサーバー"),  // l10n-ignore (catalog headwords)
        r("dehumidifier", "除濕機", "dehumidifier", "除湿機", "dehumidifier"),  // l10n-ignore (catalog headwords)
        r("vacuum", "吸塵器", "vacuum cleaner", "掃除機"),  // l10n-ignore (catalog headwords)
        r("hotwaterpot", "熱水瓶", "electric water pot", "電気ポット"),  // l10n-ignore (catalog headwords)
        r("oven", "烤箱", "oven", "オーブン", "oven"),  // l10n-ignore (catalog headwords)
        r("airpurifier", "空氣清淨機", "air purifier", "空気清浄機", "air.purifier"),  // l10n-ignore (catalog headwords)
        r("inductioncooker", "電磁爐", "induction cooker", "IHコンロ", "cooktop"),  // l10n-ignore (catalog headwords)
        r("clothesdryer", "烘衣機", "clothes dryer", "衣類乾燥機", "dryer"),  // l10n-ignore (catalog headwords)
        r("iron", "熨斗", "iron", "アイロン"),  // l10n-ignore (catalog headwords)
        r("toaster", "烤麵包機", "toaster", "トースター"),  // l10n-ignore (catalog headwords)
    ])

    private static let c8: Table = (8, "📱", [
        r("phone", "手機", "phone", "スマホ", "iphone"),  // l10n-ignore (catalog headwords)
        r("computer", "電腦", "computer", "パソコン", "laptopcomputer"),  // l10n-ignore (catalog headwords)
        r("headphones", "耳機", "headphones", "イヤホン", "headphones"),  // l10n-ignore (catalog headwords)
        r("charger", "充電器", "charger", "充電器", "powerplug"),  // l10n-ignore (catalog headwords)
        r("camera", "相機", "camera", "カメラ", "camera"),  // l10n-ignore (catalog headwords)
    ], [
        r("powerbank", "行動電源", "power bank", "モバイルバッテリー"),  // l10n-ignore (catalog headwords)
        r("chargingcable", "充電線", "charging cable", "充電ケーブル", "cable.connector"),  // l10n-ignore (catalog headwords)
        r("tablet", "平板", "tablet", "タブレット", "ipad"),  // l10n-ignore (catalog headwords)
        r("phonecase", "手機殼", "phone case", "スマホケース"),  // l10n-ignore (catalog headwords)
        r("battery", "電池", "battery", "電池", "battery.100"),  // l10n-ignore (catalog headwords)
        r("keyboard", "鍵盤", "keyboard", "キーボード", "keyboard"),  // l10n-ignore (catalog headwords)
        r("computermouse", "滑鼠", "computer mouse", "マウス", "computermouse"),  // l10n-ignore (catalog headwords)
        r("monitor", "螢幕", "monitor", "モニター", "display"),  // l10n-ignore (catalog headwords)
        r("speaker", "喇叭", "speaker", "スピーカー", "hifispeaker"),  // l10n-ignore (catalog headwords)
        r("usbdrive", "隨身碟", "USB flash drive", "USBメモリ"),  // l10n-ignore (catalog headwords)
        r("printer", "印表機", "printer", "プリンター", "printer"),  // l10n-ignore (catalog headwords)
        r("smartwatch", "智慧手錶", "smartwatch", "スマートウォッチ", "applewatch"),  // l10n-ignore (catalog headwords)
        r("microphone", "麥克風", "microphone", "マイク", "mic"),  // l10n-ignore (catalog headwords)
        r("router", "路由器", "router", "ルーター", "wifi.router"),  // l10n-ignore (catalog headwords)
    ])

    private static let c9: Table = (9, "✏️", [
        r("book", "書", "book", "本", "book.closed"),  // l10n-ignore (catalog headwords)
        r("pen", "筆", "pen", "ペン", "pencil"),  // l10n-ignore (catalog headwords)
        r("notebook", "筆記本", "notebook", "ノート"),  // l10n-ignore (catalog headwords)
        r("scissors", "剪刀", "scissors", "はさみ", "scissors"),  // l10n-ignore (catalog headwords)
        r("eraser", "橡皮擦", "eraser", "消しゴム", "eraser"),  // l10n-ignore (catalog headwords)
    ], [
        r("pencil", "鉛筆", "pencil", "鉛筆"),  // l10n-ignore (catalog headwords)
        r("paper", "紙", "paper", "紙", "doc"),  // l10n-ignore (catalog headwords)
        r("comic", "漫畫", "comic", "漫画"),  // l10n-ignore (catalog headwords)
        r("ruler", "尺", "ruler", "定規", "ruler"),  // l10n-ignore (catalog headwords)
        r("tape", "膠帶", "tape", "テープ"),  // l10n-ignore (catalog headwords)
        r("pencilcase", "鉛筆盒", "pencil case", "筆箱"),  // l10n-ignore (catalog headwords)
        r("marker", "麥克筆", "marker", "マーカー"),  // l10n-ignore (catalog headwords)
        r("glue", "膠水", "glue", "のり"),  // l10n-ignore (catalog headwords)
        r("envelope", "信封", "envelope", "封筒", "envelope"),  // l10n-ignore (catalog headwords)
        r("newspaper", "報紙", "newspaper", "新聞", "newspaper"),  // l10n-ignore (catalog headwords)
        r("magazine", "雜誌", "magazine", "雑誌", "magazine"),  // l10n-ignore (catalog headwords)
        r("folder", "資料夾", "folder", "フォルダー", "folder"),  // l10n-ignore (catalog headwords)
        r("stapler", "釘書機", "stapler", "ホッチキス"),  // l10n-ignore (catalog headwords)
        r("paperclip", "迴紋針", "paper clip", "クリップ", "paperclip"),  // l10n-ignore (catalog headwords)
        r("dictionary", "字典", "dictionary", "辞書"),  // l10n-ignore (catalog headwords)
    ])

    private static let c10: Table = (10, "🪥", [
        r("toothbrush", "牙刷", "toothbrush", "歯ブラシ"),  // l10n-ignore (catalog headwords)
        r("towel", "毛巾", "towel", "タオル"),  // l10n-ignore (catalog headwords)
        r("tissue", "衛生紙", "tissue", "ティッシュ"),  // l10n-ignore (catalog headwords)
        r("key", "鑰匙", "key", "鍵", "key"),  // l10n-ignore (catalog headwords)
        r("medicine", "藥", "medicine", "薬", "pills"),  // l10n-ignore (catalog headwords)
    ], [
        r("money", "錢", "money", "お金", "banknote"),  // l10n-ignore (catalog headwords)
        r("plasticbag", "塑膠袋", "plastic bag", "ビニール袋", "bag"),  // l10n-ignore (catalog headwords)
        r("toothpaste", "牙膏", "toothpaste", "歯磨き粉"),  // l10n-ignore (catalog headwords)
        r("coin", "硬幣", "coin", "硬貨"),  // l10n-ignore (catalog headwords)
        r("soap", "肥皂", "soap", "石けん"),  // l10n-ignore (catalog headwords)
        r("shampoo", "洗髮精", "shampoo", "シャンプー"),  // l10n-ignore (catalog headwords)
        r("trashbag", "垃圾袋", "trash bag", "ゴミ袋"),  // l10n-ignore (catalog headwords)
        r("transitcard", "悠遊卡", "transit card", "交通系ICカード"),  // l10n-ignore (catalog headwords)
        r("receipt", "發票", "receipt", "レシート"),  // l10n-ignore (catalog headwords)
        r("toilet", "馬桶", "toilet", "トイレ", "toilet"),  // l10n-ignore (catalog headwords)
        r("sink", "洗手台", "sink", "洗面台", "sink"),  // l10n-ignore (catalog headwords)
        r("wetwipes", "濕紙巾", "wet wipes", "ウェットティッシュ"),  // l10n-ignore (catalog headwords)
        r("creditcard", "信用卡", "credit card", "クレジットカード", "creditcard"),  // l10n-ignore (catalog headwords)
        r("bandage", "OK繃", "bandage", "絆創膏", "bandage"),  // l10n-ignore (catalog headwords)
        r("hanger", "衣架", "hanger", "ハンガー", "hanger"),  // l10n-ignore (catalog headwords)
    ])

    private static let c11: Table = (11, "👕", [
        r("clothes", "衣服", "clothes", "服", "tshirt"),  // l10n-ignore (catalog headwords)
        r("pants", "褲子", "pants", "ズボン"),  // l10n-ignore (catalog headwords)
        r("jacket", "外套", "jacket", "上着", "jacket"),  // l10n-ignore (catalog headwords)
        r("skirt", "裙子", "skirt", "スカート"),  // l10n-ignore (catalog headwords)
        r("socks", "襪子", "socks", "靴下"),  // l10n-ignore (catalog headwords)
    ], [
        r("tshirt", "T恤", "T-shirt", "Tシャツ"),  // l10n-ignore (catalog headwords)
        r("shirt", "襯衫", "shirt", "シャツ"),  // l10n-ignore (catalog headwords)
        r("shorts", "短褲", "shorts", "短パン"),  // l10n-ignore (catalog headwords)
        r("jeans", "牛仔褲", "jeans", "ジーンズ"),  // l10n-ignore (catalog headwords)
        r("dress", "洋裝", "dress", "ワンピース"),  // l10n-ignore (catalog headwords)
        r("raincoat", "雨衣", "raincoat", "レインコート"),  // l10n-ignore (catalog headwords)
        r("sweater", "毛衣", "sweater", "セーター"),  // l10n-ignore (catalog headwords)
        r("hoodie", "帽T", "hoodie", "パーカー"),  // l10n-ignore (catalog headwords)
        r("uniform", "制服", "uniform", "制服"),  // l10n-ignore (catalog headwords)
        r("pajamas", "睡衣", "pajamas", "パジャマ"),  // l10n-ignore (catalog headwords)
        r("tanktop", "背心", "tank top", "タンクトップ"),  // l10n-ignore (catalog headwords)
        r("underwear", "內衣", "underwear", "下着"),  // l10n-ignore (catalog headwords)
        r("scarf", "圍巾", "scarf", "マフラー"),  // l10n-ignore (catalog headwords)
        r("necktie", "領帶", "necktie", "ネクタイ"),  // l10n-ignore (catalog headwords)
    ])

    private static let c12: Table = (12, "👟", [
        r("shoes", "鞋子", "shoes", "靴", "shoe"),  // l10n-ignore (catalog headwords)
        r("hat", "帽子", "hat", "帽子", "hat.cap"),  // l10n-ignore (catalog headwords)
        r("glasses", "眼鏡", "glasses", "眼鏡", "eyeglasses"),  // l10n-ignore (catalog headwords)
        r("bag", "包包", "bag", "かばん", "handbag"),  // l10n-ignore (catalog headwords)
        r("umbrella", "雨傘", "umbrella", "傘", "umbrella"),  // l10n-ignore (catalog headwords)
    ], [
        r("watch", "手錶", "watch", "腕時計", "watch.analog"),  // l10n-ignore (catalog headwords)
        r("backpack", "背包", "backpack", "リュック", "backpack"),  // l10n-ignore (catalog headwords)
        r("mask", "口罩", "face mask", "マスク"),  // l10n-ignore (catalog headwords)
        r("slippers", "拖鞋", "slippers", "スリッパ"),  // l10n-ignore (catalog headwords)
        r("wallet", "錢包", "wallet", "財布", "wallet.bifold"),  // l10n-ignore (catalog headwords)
        r("helmet", "安全帽", "helmet", "ヘルメット", "helmet"),  // l10n-ignore (catalog headwords)
        r("sneakers", "球鞋", "sneakers", "スニーカー", "shoe.2"),  // l10n-ignore (catalog headwords)
        r("sunglasses", "太陽眼鏡", "sunglasses", "サングラス", "sunglasses"),  // l10n-ignore (catalog headwords)
        r("suitcase", "行李箱", "suitcase", "スーツケース", "suitcase.rolling"),  // l10n-ignore (catalog headwords)
        r("belt", "皮帶", "belt", "ベルト"),  // l10n-ignore (catalog headwords)
        r("hairtie", "髮圈", "hair tie", "ヘアゴム"),  // l10n-ignore (catalog headwords)
        r("earrings", "耳環", "earrings", "イヤリング"),  // l10n-ignore (catalog headwords)
        r("necklace", "項鍊", "necklace", "ネックレス"),  // l10n-ignore (catalog headwords)
        r("ring", "戒指", "ring", "指輪"),  // l10n-ignore (catalog headwords)
        r("gloves", "手套", "gloves", "手袋"),  // l10n-ignore (catalog headwords)
    ])

    private static let c13: Table = (13, "🛵", [
        r("scooter", "機車", "scooter", "バイク", "motorcycle"),  // l10n-ignore (catalog headwords)
        r("bus", "公車", "bus", "バス", "bus"),  // l10n-ignore (catalog headwords)
        r("bicycle", "腳踏車", "bicycle", "自転車", "bicycle"),  // l10n-ignore (catalog headwords)
        r("mrt", "捷運", "subway", "地下鉄", "tram.fill.tunnel"),  // l10n-ignore (catalog headwords)
        r("taxi", "計程車", "taxi", "タクシー", "car"),  // l10n-ignore (catalog headwords)
    ], [
        r("car", "汽車", "car", "車", "car.side"),  // l10n-ignore (catalog headwords)
        r("train", "火車", "train", "電車", "train.side.front.car"),  // l10n-ignore (catalog headwords)
        r("airplane", "飛機", "airplane", "飛行機", "airplane"),  // l10n-ignore (catalog headwords)
        r("truck", "卡車", "truck", "トラック"),  // l10n-ignore (catalog headwords)
        r("hsr", "高鐵", "high-speed rail", "新幹線"),  // l10n-ignore (catalog headwords)
        r("boat", "船", "boat", "船", "ferry"),  // l10n-ignore (catalog headwords)
        r("garbagetruck", "垃圾車", "garbage truck", "ゴミ収集車"),  // l10n-ignore (catalog headwords)
        r("ambulance", "救護車", "ambulance", "救急車"),  // l10n-ignore (catalog headwords)
        r("policecar", "警車", "police car", "パトカー"),  // l10n-ignore (catalog headwords)
        r("firetruck", "消防車", "fire truck", "消防車"),  // l10n-ignore (catalog headwords)
        r("kickscooter", "滑板車", "kick scooter", "キックボード", "scooter"),  // l10n-ignore (catalog headwords)
        r("stroller", "嬰兒車", "stroller", "ベビーカー", "stroller"),  // l10n-ignore (catalog headwords)
        r("cablecar", "纜車", "cable car", "ロープウェイ", "cablecar"),  // l10n-ignore (catalog headwords)
    ])

    private static let c14: Table = (14, "🏪", [
        r("conveniencestore", "便利商店", "convenience store", "コンビニ", "storefront"),  // l10n-ignore (catalog headwords)
        r("temple", "廟", "temple", "お寺"),  // l10n-ignore (catalog headwords)
        r("school", "學校", "school", "学校"),  // l10n-ignore (catalog headwords)
        r("restaurant", "餐廳", "restaurant", "レストラン", "fork.knife"),  // l10n-ignore (catalog headwords)
        r("nightmarket", "夜市", "night market", "夜市"),  // l10n-ignore (catalog headwords)
    ], [
        r("house", "房子", "house", "家", "house"),  // l10n-ignore (catalog headwords)
        r("building", "大樓", "building", "ビル", "building.2"),  // l10n-ignore (catalog headwords)
        r("breakfastshop", "早餐店", "breakfast shop", "朝ごはん屋"),  // l10n-ignore (catalog headwords)
        r("park", "公園", "park", "公園"),  // l10n-ignore (catalog headwords)
        r("station", "車站", "station", "駅"),  // l10n-ignore (catalog headwords)
        r("hospital", "醫院", "hospital", "病院", "cross"),  // l10n-ignore (catalog headwords)
        r("supermarket", "超市", "supermarket", "スーパー", "cart"),  // l10n-ignore (catalog headwords)
        r("market", "市場", "market", "市場", "basket"),  // l10n-ignore (catalog headwords)
        r("bank", "銀行", "bank", "銀行", "building.columns"),  // l10n-ignore (catalog headwords)
        r("pharmacy", "藥局", "pharmacy", "薬局"),  // l10n-ignore (catalog headwords)
        r("cafe", "咖啡廳", "café", "カフェ"),  // l10n-ignore (catalog headwords)
        r("gasstation", "加油站", "gas station", "ガソリンスタンド", "fuelpump"),  // l10n-ignore (catalog headwords)
        r("postoffice", "郵局", "post office", "郵便局"),  // l10n-ignore (catalog headwords)
        r("library", "圖書館", "library", "図書館"),  // l10n-ignore (catalog headwords)
    ])

    private static let c15: Table = (15, "🚦", [
        r("trafficlight", "紅綠燈", "traffic light", "信号"),  // l10n-ignore (catalog headwords)
        r("signboard", "招牌", "signboard", "看板", "signpost.right"),  // l10n-ignore (catalog headwords)
        r("trashcan", "垃圾桶", "trash can", "ゴミ箱", "trash"),  // l10n-ignore (catalog headwords)
        r("streetlight", "路燈", "streetlight", "街灯"),  // l10n-ignore (catalog headwords)
        r("crosswalk", "斑馬線", "crosswalk", "横断歩道"),  // l10n-ignore (catalog headwords)
    ], [
        r("road", "馬路", "road", "道路", "road.lanes"),  // l10n-ignore (catalog headwords)
        r("busstop", "公車站", "bus stop", "バス停"),  // l10n-ignore (catalog headwords)
        r("bench", "長椅", "bench", "ベンチ"),  // l10n-ignore (catalog headwords)
        r("mailbox", "郵筒", "mailbox", "ポスト"),  // l10n-ignore (catalog headwords)
        r("parkinglot", "停車場", "parking lot", "駐車場", "parkingsign"),  // l10n-ignore (catalog headwords)
        r("bridge", "橋", "bridge", "橋"),  // l10n-ignore (catalog headwords)
        r("vendingmachine", "販賣機", "vending machine", "自動販売機"),  // l10n-ignore (catalog headwords)
        r("utilitypole", "電線桿", "utility pole", "電柱"),  // l10n-ignore (catalog headwords)
        r("sidewalk", "人行道", "sidewalk", "歩道"),  // l10n-ignore (catalog headwords)
        r("flag", "旗子", "flag", "旗", "flag"),  // l10n-ignore (catalog headwords)
        r("trafficcone", "三角錐", "traffic cone", "カラーコーン", "cone"),  // l10n-ignore (catalog headwords)
        r("firehydrant", "消防栓", "fire hydrant", "消火栓"),  // l10n-ignore (catalog headwords)
        r("atm", "提款機", "ATM", "ATM"),  // l10n-ignore (catalog headwords)
    ])

    private static let c16: Table = (16, "🐾", [
        r("dog", "狗", "dog", "犬", "dog"),  // l10n-ignore (catalog headwords)
        r("cat", "貓", "cat", "猫", "cat"),  // l10n-ignore (catalog headwords)
        r("bird", "鳥", "bird", "鳥", "bird"),  // l10n-ignore (catalog headwords)
        r("fish", "魚", "fish", "魚", "fish"),  // l10n-ignore (catalog headwords)
        r("rabbit", "兔子", "rabbit", "うさぎ", "hare"),  // l10n-ignore (catalog headwords)
    ], [
        r("pigeon", "鴿子", "pigeon", "ハト"),  // l10n-ignore (catalog headwords)
        r("sparrow", "麻雀", "sparrow", "スズメ"),  // l10n-ignore (catalog headwords)
        r("mosquito", "蚊子", "mosquito", "蚊"),  // l10n-ignore (catalog headwords)
        r("ant", "螞蟻", "ant", "アリ", "ant"),  // l10n-ignore (catalog headwords)
        r("cockroach", "蟑螂", "cockroach", "ゴキブリ"),  // l10n-ignore (catalog headwords)
        r("gecko", "壁虎", "gecko", "ヤモリ", "lizard"),  // l10n-ignore (catalog headwords)
        r("butterfly", "蝴蝶", "butterfly", "チョウ"),  // l10n-ignore (catalog headwords)
        r("chicken", "雞", "chicken", "ニワトリ"),  // l10n-ignore (catalog headwords)
        r("duck", "鴨子", "duck", "アヒル"),  // l10n-ignore (catalog headwords)
        r("turtle", "烏龜", "turtle", "カメ", "tortoise"),  // l10n-ignore (catalog headwords)
        r("squirrel", "松鼠", "squirrel", "リス"),  // l10n-ignore (catalog headwords)
        r("frog", "青蛙", "frog", "カエル"),  // l10n-ignore (catalog headwords)
        r("hamster", "倉鼠", "hamster", "ハムスター"),  // l10n-ignore (catalog headwords)
        r("ladybug", "瓢蟲", "ladybug", "テントウムシ", "ladybug"),  // l10n-ignore (catalog headwords)
    ])

    private static let c17: Table = (17, "🌿", [
        r("flower", "花", "flower", "花", "camera.macro"),  // l10n-ignore (catalog headwords)
        r("tree", "樹", "tree", "木", "tree"),  // l10n-ignore (catalog headwords)
        r("grass", "草", "grass", "草"),  // l10n-ignore (catalog headwords)
        r("leaf", "葉子", "leaf", "葉っぱ", "leaf"),  // l10n-ignore (catalog headwords)
        r("pottedplant", "盆栽", "potted plant", "鉢植え"),  // l10n-ignore (catalog headwords)
    ], [
        r("banyan", "榕樹", "banyan tree", "ガジュマル"),  // l10n-ignore (catalog headwords)
        r("palmtree", "椰子樹", "palm tree", "ヤシの木"),  // l10n-ignore (catalog headwords)
        r("cactus", "仙人掌", "cactus", "サボテン"),  // l10n-ignore (catalog headwords)
        r("rose", "玫瑰", "rose", "バラ"),  // l10n-ignore (catalog headwords)
        r("bamboo", "竹子", "bamboo", "竹"),  // l10n-ignore (catalog headwords)
        r("sunflower", "向日葵", "sunflower", "ひまわり"),  // l10n-ignore (catalog headwords)
        r("moss", "青苔", "moss", "苔"),  // l10n-ignore (catalog headwords)
        r("mushroom", "香菇", "mushroom", "キノコ"),  // l10n-ignore (catalog headwords)
        r("cherryblossom", "櫻花", "cherry blossom", "桜"),  // l10n-ignore (catalog headwords)
        r("orchid", "蘭花", "orchid", "ラン"),  // l10n-ignore (catalog headwords)
        r("lotus", "蓮花", "lotus", "ハス"),  // l10n-ignore (catalog headwords)
        r("seed", "種子", "seed", "種"),  // l10n-ignore (catalog headwords)
    ])

    private static let c18: Table = (18, "⛅", [
        r("sky", "天空", "sky", "空", "cloud.sun"),  // l10n-ignore (catalog headwords)
        r("cloud", "雲", "cloud", "雲", "cloud"),  // l10n-ignore (catalog headwords)
        r("mountain", "山", "mountain", "山", "mountain.2"),  // l10n-ignore (catalog headwords)
        r("sea", "海", "sea", "海", "water.waves"),  // l10n-ignore (catalog headwords)
        r("moon", "月亮", "moon", "月", "moon"),  // l10n-ignore (catalog headwords)
    ], [
        r("sun", "太陽", "sun", "太陽", "sun.max"),  // l10n-ignore (catalog headwords)
        r("rain", "雨", "rain", "雨", "cloud.rain"),  // l10n-ignore (catalog headwords)
        r("star", "星星", "star", "星", "star"),  // l10n-ignore (catalog headwords)
        r("river", "河", "river", "川"),  // l10n-ignore (catalog headwords)
        r("rainbow", "彩虹", "rainbow", "虹", "rainbow"),  // l10n-ignore (catalog headwords)
        r("sunset", "夕陽", "sunset", "夕日", "sun.horizon"),  // l10n-ignore (catalog headwords)
        r("stone", "石頭", "stone", "石"),  // l10n-ignore (catalog headwords)
        r("wind", "風", "wind", "風", "wind"),  // l10n-ignore (catalog headwords)
        r("beach", "海灘", "beach", "ビーチ", "beach.umbrella"),  // l10n-ignore (catalog headwords)
        r("lightning", "閃電", "lightning", "雷", "cloud.bolt"),  // l10n-ignore (catalog headwords)
        r("lake", "湖", "lake", "湖"),  // l10n-ignore (catalog headwords)
        r("puddle", "水坑", "puddle", "水たまり"),  // l10n-ignore (catalog headwords)
        r("fire", "火", "fire", "火", "flame"),  // l10n-ignore (catalog headwords)
        r("sand", "沙子", "sand", "砂"),  // l10n-ignore (catalog headwords)
    ])

    private static let c19: Table = (19, "⚽", [
        r("ball", "球", "ball", "ボール", "soccerball"),  // l10n-ignore (catalog headwords)
        r("toy", "玩具", "toy", "おもちゃ", "teddybear"),  // l10n-ignore (catalog headwords)
        r("guitar", "吉他", "guitar", "ギター", "guitars"),  // l10n-ignore (catalog headwords)
        r("gameconsole", "遊戲機", "game console", "ゲーム機", "gamecontroller"),  // l10n-ignore (catalog headwords)
        r("balloon", "氣球", "balloon", "風船", "balloon"),  // l10n-ignore (catalog headwords)
    ], [
        r("basketball", "籃球", "basketball", "バスケットボール", "basketball"),  // l10n-ignore (catalog headwords)
        r("badminton", "羽毛球", "badminton", "バドミントン"),  // l10n-ignore (catalog headwords)
        r("baseball", "棒球", "baseball", "野球", "baseball"),  // l10n-ignore (catalog headwords)
        r("tabletennis", "桌球", "table tennis", "卓球"),  // l10n-ignore (catalog headwords)
        r("clawmachine", "夾娃娃機", "claw machine", "クレーンゲーム"),  // l10n-ignore (catalog headwords)
        r("cards", "撲克牌", "playing cards", "トランプ"),  // l10n-ignore (catalog headwords)
        r("doll", "娃娃", "doll", "人形"),  // l10n-ignore (catalog headwords)
        r("puzzle", "拼圖", "jigsaw puzzle", "パズル", "puzzlepiece"),  // l10n-ignore (catalog headwords)
        r("movie", "電影", "movie", "映画", "film"),  // l10n-ignore (catalog headwords)
        r("piano", "鋼琴", "piano", "ピアノ", "pianokeys"),  // l10n-ignore (catalog headwords)
        r("skateboard", "滑板", "skateboard", "スケボー", "skateboard"),  // l10n-ignore (catalog headwords)
        r("dice", "骰子", "dice", "サイコロ", "dice"),  // l10n-ignore (catalog headwords)
        r("kite", "風箏", "kite", "凧"),  // l10n-ignore (catalog headwords)
    ])

    private static let c20: Table = (20, "🖐️", [
        r("hand", "手", "hand", "手", "hand.raised"),  // l10n-ignore (catalog headwords)
        r("face", "臉", "face", "顔", "face.smiling"),  // l10n-ignore (catalog headwords)
        r("eye", "眼睛", "eye", "目", "eye"),  // l10n-ignore (catalog headwords)
        r("child", "小孩", "child", "子ども", "figure.child"),  // l10n-ignore (catalog headwords)
        r("friend", "朋友", "friend", "友だち", "person.2"),  // l10n-ignore (catalog headwords)
    ], [
        r("mouth", "嘴巴", "mouth", "口", "mouth"),  // l10n-ignore (catalog headwords)
        r("nose", "鼻子", "nose", "鼻", "nose"),  // l10n-ignore (catalog headwords)
        r("ear", "耳朵", "ear", "耳", "ear"),  // l10n-ignore (catalog headwords)
        r("hair", "頭髮", "hair", "髪"),  // l10n-ignore (catalog headwords)
        r("foot", "腳", "foot", "足"),  // l10n-ignore (catalog headwords)
        r("finger", "手指", "finger", "指", "hand.point.up"),  // l10n-ignore (catalog headwords)
        r("head", "頭", "head", "頭"),  // l10n-ignore (catalog headwords)
        r("mother", "媽媽", "mother", "お母さん"),  // l10n-ignore (catalog headwords)
        r("father", "爸爸", "father", "お父さん"),  // l10n-ignore (catalog headwords)
        r("baby", "嬰兒", "baby", "赤ちゃん"),  // l10n-ignore (catalog headwords)
        r("student", "學生", "student", "学生"),  // l10n-ignore (catalog headwords)
        r("teacher", "老師", "teacher", "先生"),  // l10n-ignore (catalog headwords)
        r("grandmother", "阿嬤", "grandmother", "おばあちゃん"),  // l10n-ignore (catalog headwords)
        r("shopowner", "老闆", "shop owner", "店主"),  // l10n-ignore (catalog headwords)
    ])

    static let categories: [DexCategory] = {
        let table: [Table] = [c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12, c13, c14, c15, c16, c17, c18, c19, c20]
        var no = 0
        return table.map { c in
            let base = c.2.map { raw -> DexItem in
                no += 1
                return DexItem(id: raw.id, zh: raw.zh, en: raw.en, ja: raw.ja, symbol: raw.symbol, category: c.0, baseNo: no)
            }
            let extra = c.3.map { DexItem(id: $0.id, zh: $0.zh, en: $0.en, ja: $0.ja, symbol: $0.symbol, category: c.0, baseNo: nil) }
            return DexCategory(no: c.0, emoji: c.1, base: base, extra: extra)
        }
    }()

    static var allItems: [DexItem] { categories.flatMap(\.items) }

    /// Headwords are compared trimmed and case-folded; Japanese also with katakana folded to hiragana, and
    /// English without a leading article — so りんご / リンゴ and "an apple" / "Apple" find the same item.
    /// Katakana written as hiragana exactly as ICU's Katakana-Hiragana transform writes it: ァ–ヶ, ヽヾ → ぁ–ゖ, ゝゞ (the same
    /// letters 0x60 apart), and the long-vowel mark after a katakana written as that kana's vowel (コーヒー → こおひい,
    /// チャーハン → ちゃあはん). The transform itself took tens of milliseconds a call (it builds an ICU transliterator each
    /// time): the catalog's index called it for every Japanese item on the first open of the 図鑑 — 22 s on the UI tour's
    /// cold simulator — and the dex called it for every word on every redraw for Japanese learners. DexCatalogSymbolTests
    /// checks it gives the transform's result for every catalog word.
    static func katakanaToHiragana(_ s: String) -> String {
        guard s.unicodeScalars.contains(where: { isKatakana($0.value) }) else { return s }
        var out = String.UnicodeScalarView()
        /// The vowel of the last kana written from katakana (nil after anything else).
        var vowel: Unicode.Scalar?
        for u in s.unicodeScalars {
            if isKatakana(u.value), let h = Unicode.Scalar(u.value - 0x60) {
                out.append(h)
                vowel = vowels[h]
            } else if u.value == 0x30FC, let v = vowel {
                out.append(v)   // ー after a katakana: its vowel (and again after a second ー)
            } else {
                out.append(u)
                vowel = nil
            }
        }
        return String(out)
    }

    private static func isKatakana(_ v: UInt32) -> Bool { (0x30A1...0x30F6).contains(v) || v == 0x30FD || v == 0x30FE }

    /// Each hiragana's vowel (small kana too); ん, っ and the iteration marks have none.
    private static let vowels: [Unicode.Scalar: Unicode.Scalar] = {
        let rows: [(String, Unicode.Scalar)] = [
            ("あかさたなはまやらわがざだばぱぁゃゎゕ", "あ"), ("いきしちにひみりぎじぢびぴぃゐ", "い"),
            ("うくすつぬふむゆるぐずづぶぷぅゅゔ", "う"), ("えけせてねへめれげぜでべぺぇゑゖ", "え"),
            ("おこそとのほもよろをごぞどぼぽぉょ", "お"),
        ]
        var m: [Unicode.Scalar: Unicode.Scalar] = [:]
        for (letters, v) in rows { for u in letters.unicodeScalars { m[u] = v } }
        return m
    }()

    static func norm(_ s: String, lang: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lang == "ja" { t = katakanaToHiragana(t) }
        if lang == "en" {
            for a in ["a ", "an ", "the "] where t.hasPrefix(a) {
                t = String(t.dropFirst(a.count))
                break
            }
        }
        return t
    }

    private static let index: [String: [String: DexItem]] = {
        var out: [String: [String: DexItem]] = [:]
        for lang in ["zh-TW", "en", "ja"] {
            var m: [String: DexItem] = [:]
            for it in allItems { m[norm(it.headword(for: lang), lang: lang)] = it }
            out[lang] = m
        }
        return out
    }()

    /// The catalog item whose headword (in the learning language) is this word, if any.
    static func item(headword: String?, lang: String) -> DexItem? {
        guard let headword, !headword.isEmpty else { return nil }
        let l = lang == "en" || lang == "ja" ? lang : "zh-TW"
        return index[l]?[norm(headword, lang: l)]
    }
}
