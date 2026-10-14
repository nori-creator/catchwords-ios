import Foundation

/// The web's `normalizeCategory` / `wordCategoryKey` (category.ts): a word's category decided from its headword first,
/// the stored (AI's) key only when no rule matches. Applied when the dex READS a word, so a word saved with a wrong or
/// missing key (stored as "other" before the rules existed) still sits in the right category, and fixing a rule
/// fixes every old word at once.
///
/// Owner 2026-10-14: 「桃やクロワッサン、キノコ、健康弁当が日用品に分類されてる。スポーツ・遊びに光雕投影が分類されてる」.
/// The web had fixed the same words on 2026-10-09 with these rules; iOS had none of them and drew every "other" word
/// as 洗面・日用品. The headwords are learning-language data (Taiwan Mandarin), not UI text.
nonisolated enum CategoryRules {
    /// The category key for a word: a built-in rule on its headword, else its stored key when it is a real one,
    /// else "other".
    static func normalize(headword: String?, key: String?) -> String {
        let h = (headword ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let stored = Category.key(for: key)
        guard !h.isEmpty else { return stored }
        let cacheKey = h + "|" + stored
        lock.lock()
        if let hit = cache[cacheKey] { lock.unlock(); return hit }
        lock.unlock()
        let out = rule(for: h) ?? stored
        lock.lock()
        cache[cacheKey] = out
        lock.unlock()
        return out
    }

    /// The rule's key for a headword, or nil when no rule matches.
    static func rule(for headword: String) -> String? {
        if let exact = exact[headword] { return exact }
        for (re, key) in beforeSuffix where matches(re, headword) { return key }
        for (re, key) in suffix where matches(re, headword) { return key }
        for (re, key) in contains where matches(re, headword) { return key }
        return nil
    }

    // MARK: - Lookup

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: String] = [:]

    private static func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    private static func rules(_ list: [(String, String)]) -> [(NSRegularExpression, String)] {
        list.compactMap { pattern, key in (try? NSRegularExpression(pattern: pattern)).map { ($0, key) } }
    }

    // MARK: - The rules (category.ts EXACT / BEFORE_SUFFIX / SUFFIX / CONTAINS)

    /// Whole headwords (one-character words, and words a partial match would misfile).
    private static let exact: [String: String] = [
        "手": "body", "腳": "body", "脚": "body", "頭": "body", "髮": "body", "頭髮": "body", "眼": "body", "眼睛": "body",  // l10n-ignore (headword rules)
        "耳": "body", "耳朵": "body", "鼻": "body", "鼻子": "body", "嘴": "body", "嘴巴": "body", "臉": "body", "舌": "body",  // l10n-ignore (headword rules)
        "舌頭": "body", "牙": "body", "牙齒": "body", "指": "body", "手指": "body", "腳趾": "body", "肩": "body",  // l10n-ignore (headword rules)
        "肩膀": "body", "膝": "body", "膝蓋": "body", "肚": "body", "肚子": "body", "背": "body", "胸": "body",  // l10n-ignore (headword rules)
        "腰": "body", "脖": "body", "脖子": "body", "手肘": "body", "手腕": "body", "手臂": "body",  // l10n-ignore (headword rules)
        "太陽": "sky", "月亮": "sky", "星星": "sky", "雲": "weather", "雨": "weather", "風": "weather", "雪": "weather",  // l10n-ignore (headword rules)
        "颱風": "weather", "台風": "weather", "海": "water", "河": "water", "湖": "water", "水": "drink", "山": "mountain",  // l10n-ignore (headword rules)
        "女朋友": "person", "男朋友": "person", "朋友": "person", "老師": "job", "學生": "person", "醫生": "job",  // l10n-ignore (headword rules)
        "護士": "job", "店員": "job", "司機": "job",  // l10n-ignore (headword rules)
        "手背": "body", "手心": "body", "手掌": "body", "掌心": "body", "腳背": "body", "腳底": "body",  // l10n-ignore (headword rules)
        "爸爸": "family", "媽媽": "family", "哥哥": "family", "姐姐": "family", "弟弟": "family", "妹妹": "family",  // l10n-ignore (headword rules)
        "家人": "family", "秘書": "job", "祕書": "job", "銀河": "sky",  // l10n-ignore (headword rules)
    ]

    /// Fruit names met in Taiwan, longest first (葡萄柚 before 葡萄).
    private static let fruitNames = [
        "葡萄柚", "水蜜桃", "奇異果", "火龍果", "百香果", "哈密瓜", "番石榴", "蘋果", "香蕉", "芒果", "鳳梨", "葡萄", "西瓜",  // l10n-ignore (headword rules)
        "草莓", "櫻桃", "柳丁", "柳橙", "橘子", "橙子", "芭樂", "蓮霧", "荔枝", "龍眼", "釋迦", "木瓜", "檸檬", "柿子",  // l10n-ignore (headword rules)
        "水梨", "梨子", "香瓜", "楊桃", "桃子", "李子", "梅子", "藍莓", "榴槤", "山竹", "椰子", "酪梨", "文旦", "柚子",  // l10n-ignore (headword rules)
        "枇杷", "桑椹", "桑葚", "棗子", "蜜棗", "桃", "梨",  // l10n-ignore (headword rules)
    ].joined(separator: "|")

    /// Looked at before the word endings: names with 草・花・葉・鍋・燈 in them that are not plants, kitchen tools or
    /// furniture, and the foods and shows the endings miss.
    private static let beforeSuffix: [(NSRegularExpression, String)] = rules([
        ("^(\(fruitNames))(汁|原汁|牛奶|奶昔|冰沙|茶|綠茶|紅茶|多多|氣泡水|酒|醋)$", "drink"),  // l10n-ignore (headword rules)
        ("^(\(fruitNames))(冰|雪花冰|刨冰|蛋糕|派|塔|乾|酥|果醬|糖|布丁|果凍|冰淇淋|聖代|大福)$", "dessert"),  // l10n-ignore (headword rules)
        ("^(小|大|青|白|黃|愛文|金煌|水)?(\(fruitNames))子?$", "fruit"),  // l10n-ignore (headword rules)
        ("(仙草茶|仙草蜜|青草茶|茶葉)$", "drink"),  // l10n-ignore (headword rules)
        // Milk drinks and yoghurt (麥芽牛乳・優酪乳・巧克力牛奶・拿鐵): one rule so none is left to the AI's key.
        ("(牛乳|鮮乳|牛奶|優酪乳|優格飲|豆漿|拿鐵|奶茶|咖啡|可可|果汁|汽水|可樂)$", "drink"),  // l10n-ignore (headword rules)
        ("(仙草|愛玉|粉圓|豆花|爆米花|雪花冰|綿花糖|棉花糖|花生糖|花生湯)", "dessert"),  // l10n-ignore (headword rules)
        ("(火鍋|麻辣鍋|臭臭鍋|涮涮鍋|鴛鴦鍋|石頭鍋)$", "food"),  // l10n-ignore (headword rules)
        ("(韭菜花|花椰菜|青花菜|蔥花)$", "vegetable"),  // l10n-ignore (headword rules)
        ("^浪花$", "water"),  // l10n-ignore (headword rules)
        ("(紅綠燈|路燈|號誌燈)$", "street"),  // l10n-ignore (headword rules)
        // Light shows and projections on buildings are things seen in the town, not sports or play
        // (owner 2026-10-14: 光雕投影 was under スポーツ・遊び).
        ("(光雕|投影|燈光秀|燈會|燈節|燈飾|聖誕燈|光環境)", "street"),  // l10n-ignore (headword rules)
        ("^雪花$", "weather"),  // l10n-ignore (headword rules)
        ("(烤麵包機|麵包機|烤吐司機)$", "appliance"),  // l10n-ignore (headword rules)
        ("(可頌|貝果|吐司|麵包|司康|馬芬|歐包|餐包|甜甜圈|鬆餅)$", "dessert"),  // l10n-ignore (headword rules)
        ("(便當盒|保鮮盒)$", "kitchenware"),  // l10n-ignore (headword rules)
        ("(健康餐|[早午晚]餐|套餐|輕食餐|餐盒|便當|定食|沙拉)$", "food"),  // l10n-ignore (headword rules)
        ("^(電燈)?(開關|插座)$", "home"),  // l10n-ignore (headword rules)
    ])

    /// Word endings that decide the kind of thing (〜傘, 〜鞋 …).
    private static let suffix: [(NSRegularExpression, String)] = rules([
        ("(花|玫瑰|櫻花|向日葵|鬱金香|百合)$", "flower"),  // l10n-ignore (headword rules)
        ("(樹|竹|草|葉|盆栽)$", "plant"),  // l10n-ignore (headword rules)
        ("(菇|蕈|菌菇)$", "plant"),  // l10n-ignore (headword rules)
        ("(傘|雨傘|陽傘)$", "accessory"),  // l10n-ignore (headword rules)
        ("(鞋|鞋子|運動鞋|拖鞋|靴子|高跟鞋)$", "shoes"),  // l10n-ignore (headword rules)
        ("(包包|背包|皮包|錢包|手提袋|袋子)$", "bag"),  // l10n-ignore (headword rules)
        ("(項鍊|戒指|耳環|手鍊|手錶|錶|手環)$", "jewelry"),  // l10n-ignore (headword rules)
        ("(椅子|桌子|沙發|床|櫃子|書架|書桌|衣櫃)$", "furniture"),  // l10n-ignore (headword rules)
        ("(鍋|平底鍋|刀|叉|筷子|湯匙|盤子|碗|砧板|鍋子|水壺)$", "kitchenware"),  // l10n-ignore (headword rules)
        ("(書|小說|字典|漫畫|雜誌|課本|筆記本)$", "book"),  // l10n-ignore (headword rules)
        ("(證|證件|卡|表格|文件|收據|發票|菜單|地圖)$", "document"),  // l10n-ignore (headword rules)
        ("(燈|小夜燈|檯燈)$", "furniture"),  // l10n-ignore (headword rules)
        ("^(?!(?:拔|過|渡|跳|投)河$).+(河|溪|瀑布)$", "water"),  // l10n-ignore (headword rules)
        ("^(?!(?:爬|登|下|上|開|靠|江)山$).+山$", "mountain"),  // l10n-ignore (headword rules)
        ("(杯|杯子|馬克杯)$", "kitchenware"),  // l10n-ignore (headword rules)
    ])

    /// Parts of the word (two characters or more; one-character words are in `exact`).
    private static let contains: [(NSRegularExpression, String)] = rules([
        ("(滑鼠|鍵盤|電腦|筆電|螢幕|手機|平板|耳機|喇叭|路由器|插頭|充電器|相機|行動電源|USB|手機架)", "tech"),  // l10n-ignore (headword rules)
        ("(汽車|機車|摩托車|腳踏車|自行車|捷運|公車|火車|高鐵|飛機|輪船|計程車)", "transport"),  // l10n-ignore (headword rules)
        ("(狗狗|小狗|貓咪|小貓|兔子|老鼠|綿羊|山羊|烏龜|金魚|熊貓|大象|獅子|老虎|斑馬(?!線))", "animal"),  // l10n-ignore (headword rules)
        ("^(小|大|山|野)?(狗|貓|鳥|魚|馬|牛|羊|豬|雞|鴨|鵝|熊|兔|猴|蛇)(仔|咪)?$", "animal"),  // l10n-ignore (headword rules)
        ("(蘋果|香蕉|橘子|柳丁|葡萄|草莓|西瓜|芒果|鳳梨|木瓜|檸檬|柿子|水梨)", "fruit"),  // l10n-ignore (headword rules)
        ("(高麗菜|白菜|菠菜|紅蘿蔔|馬鈴薯|洋蔥|番茄|茄子|青椒|大蒜|生薑|蔥花)", "vegetable"),  // l10n-ignore (headword rules)
        ("(咖啡|奶茶|果汁|可樂|礦泉水|牛奶|豆漿|啤酒|紅茶|綠茶|珍珠奶茶)", "drink"),  // l10n-ignore (headword rules)
        ("(三明治|炒飯|炒麵|便當|漢堡|披薩|蛋餅|蔥抓餅|滷肉飯|小籠包|水餃|包子|麵包|海帶)", "food"),  // l10n-ignore (headword rules)
        ("(蛋糕|布丁|冰淇淋|甜甜圈|巧克力|餅乾|糖果|雪花冰|豆花|芒果冰)", "dessert"),  // l10n-ignore (headword rules)
        ("(冰箱|洗衣機|微波爐|電視|冷氣|烤箱|吹風機|電風扇|除濕機)", "appliance"),  // l10n-ignore (headword rules)
        ("(衛生紙|面紙|毛巾|清潔劑|洗碗精|洗衣精|沐浴乳|洗髮精|牙膏|牙刷|肥皂|垃圾袋)", "medicine"),  // l10n-ignore (headword rules)
        ("(面膜|洗面乳|洗面奶|化妝水|卸妝|保養品|化妝品)", "medicine"),  // l10n-ignore (headword rules)
        ("(護唇膏|護手霜|乳液|防曬|口罩|藥膏|藥品|OK繃|繃帶|藥水|維他命)", "medicine"),  // l10n-ignore (headword rules)
        ("(指甲剪|剪刀|螺絲|工具|鎚子|梯子|掃把|拖把)", "tool"),  // l10n-ignore (headword rules)
        ("(刷子|鬃刷|馬桶刷|菜瓜布|抹布|畚箕)", "tool"),  // l10n-ignore (headword rules)
        ("(衣服|襯衫|T恤|外套|夾克|大衣|褲子|裙子|洋裝|毛衣|帽子|圍巾|手套|襪子)", "clothes"),  // l10n-ignore (headword rules)
        ("(眼鏡|太陽眼鏡|皮帶|髮飾)", "accessory"),  // l10n-ignore (headword rules)
        ("(鉛筆|原子筆|橡皮擦|尺子|膠水|膠帶|便利貼|螢光筆)", "stationery"),  // l10n-ignore (headword rules)
        ("(硬幣|紙鈔|鈔票|信用卡|零錢)", "money"),  // l10n-ignore (headword rules)
        ("(便利商店|超市|超商|夜市|市場|百貨|書店|餐廳|咖啡店|藥局)", "shop"),  // l10n-ignore (headword rules)
        ("(公園|車站|機場|銀行|醫院|學校|郵局|廟|捷運站)", "building"),  // l10n-ignore (headword rules)
        ("(招牌|標誌|標示|指示牌|路牌|告示)", "sign"),  // l10n-ignore (headword rules)
        ("(斑馬線|紅綠燈|人行道|馬路|巷子|樓梯|電梯)", "street"),  // l10n-ignore (headword rules)
    ])
}
