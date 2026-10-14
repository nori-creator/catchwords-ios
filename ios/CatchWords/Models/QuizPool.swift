import Foundation

// The everyday words that pad the review quiz when the learner's own dex cannot give three distractors.
//
// * No exam levels (owner 2026-10-03: 「単語の検定のレベルのデータは削除して」). A card's own level (`words.level`)
//   is not read on iOS any more, and the pool carries none: it is ranked by the same category key first, then the
//   same room (Models/Category.swift), ties in random order.
//   The server has no word-list endpoint (docs, scripts/check_native_contract.py), so the pool ships in the app.
// * Every word is a concrete everyday noun with one of the app's 54 category keys.
// * One list per learning language, never mixed (R3 「4択が学習言語英語なのに台湾華語の単語が混ざってる」).
//   The reading is what the quiz draws with the word: zhuyin (one syllable per character) for 台湾華語, hiragana
//   for a Japanese word with kanji, none for kana-only Japanese words and English.
// The headword strings are learning-language data, not UI text.

nonisolated struct QuizPoolWord: Sendable, Hashable {
    let headword: String
    /// Zhuyin (台湾華語) or hiragana (日本語); nil for English and kana-only words.
    let reading: String?
    /// One of the 54 category keys.
    let categoryKey: String
}

nonisolated enum QuizPool {
    /// The pool for a learning language ("zh-TW", "en", "ja"; anything else is 台湾華語 like the rest of the app).
    static func words(for target: String) -> [QuizPoolWord] {
        switch target {
        case "en": en
        case "ja": ja
        default: zhTW
        }
    }

    /// The pool ordered for one card: the same category key first, then the same room, then the rest;
    /// ties in random order (the caller caches the drawn choices per card, so they stay put).
    static func ranked(for target: String, categoryKey: String?) -> [QuizPoolWord] {
        let room = Category.room(for: categoryKey)
        return words(for: target)
            .map { w -> (word: QuizPoolWord, kin: Int, tie: Double) in
                let kin = w.categoryKey == categoryKey ? 0 : (Category.room(for: w.categoryKey) == room ? 1 : 2)
                return (w, kin, Double.random(in: 0..<1))
            }
            .sorted { a, b in (a.kin, a.tie) < (b.kin, b.tie) }
            .map { $0.word }
    }

    /// Words that name a whole kind (果物・花・本 …). Next to a word of the same category they are also right for
    /// the photo (a pomelo is a 水果), so they are never a wrong choice there.
    private static let kindWords: [String: Set<String>] = [
        "zh-TW": ["水果", "花", "樹", "鳥", "書", "茶", "果汁"],  // l10n-ignore (target words)
        "en": ["fruit", "flower", "tree", "bird", "book", "tea", "juice"],  // l10n-ignore (target words)
        "ja": ["果物", "花", "本", "虫", "お茶", "ジュース"],  // l10n-ignore (target words)
    ]

    /// Whether `candidate` could also be a right answer for the photo of `correct` (owner 2026-10-14: a new learner's
    /// four choices come mostly from this pool, so none of them may be another name for the same thing):
    /// * the last part of a compound names its kind — 健康便當 is a 便當, 珍珠奶茶 a 茶, "orange juice" a juice;
    /// * a word for the whole kind in the same category — 水果 next to 柚子, 花 next to 玫瑰.
    /// Only these two: a near miss that is a different thing (鳳梨 for 鳳梨酥) stays, it is a fair test.
    static func alsoFits(_ candidate: String, category candidateCategory: String?,
                         correct: String, correctCategory: String?, target: String) -> Bool {
        let english = target == "en"
        let c = candidate.trimmingCharacters(in: .whitespaces)
        let w = correct.trimmingCharacters(in: .whitespaces)
        let cKey = english ? c.lowercased() : c
        let wKey = english ? w.lowercased() : w
        guard !cKey.isEmpty, !wKey.isEmpty, cKey != wKey else { return false }
        let isHead: Bool
        if english {
            isHead = wKey.hasSuffix(" " + cKey) || wKey.hasSuffix("-" + cKey)
        } else {
            isHead = wKey.hasSuffix(cKey)
        }
        if isHead { return true }
        // Japanese: the polite お/ご is not part of the kind (健康弁当 is an お弁当, 緑茶 an お茶).
        let polite: Set<Character> = ["お", "ご"]  // l10n-ignore (target words)
        if target == "ja", let first = cKey.first, polite.contains(first), cKey.count > 2,
           wKey.hasSuffix(String(cKey.dropFirst())) {
            return true
        }
        let kinds = kindWords[english ? "en" : (target == "ja" ? "ja" : "zh-TW")] ?? []
        return kinds.contains(cKey) && candidateCategory != nil && candidateCategory == correctCategory
    }

    private static func w(_ headword: String, _ reading: String?, _ key: String) -> QuizPoolWord {
        QuizPoolWord(headword: headword, reading: reading, categoryKey: key)
    }

    /// 台湾華語.
    private static let zhTW: [QuizPoolWord] = [
        w("蘋果", "ㄆㄧㄥˊ ㄍㄨㄛˇ", "fruit"),  // l10n-ignore (target words)
        w("水果", "ㄕㄨㄟˇ ㄍㄨㄛˇ", "fruit"),  // l10n-ignore (target words)
        w("公車", "ㄍㄨㄥ ㄔㄜ", "vehicle"),  // l10n-ignore (target words)
        w("汽車", "ㄑㄧˋ ㄔㄜ", "vehicle"),  // l10n-ignore (target words)
        w("火車", "ㄏㄨㄛˇ ㄔㄜ", "transport"),  // l10n-ignore (target words)
        w("雨傘", "ㄩˇ ㄙㄢˇ", "accessory"),  // l10n-ignore (target words)
        w("便當", "ㄅㄧㄢˋ ㄉㄤ", "food"),  // l10n-ignore (target words)
        w("雞蛋", "ㄐㄧ ㄉㄢˋ", "food"),  // l10n-ignore (target words)
        w("麵包", "ㄇㄧㄢˋ ㄅㄠ", "dessert"),  // l10n-ignore (target words)
        w("咖啡", "ㄎㄚ ㄈㄟ", "drink"),  // l10n-ignore (target words)
        w("牛奶", "ㄋㄧㄡˊ ㄋㄞˇ", "drink"),  // l10n-ignore (target words)
        w("茶", "ㄔㄚˊ", "drink"),  // l10n-ignore (target words)
        w("手機", "ㄕㄡˇ ㄐㄧ", "tech"),  // l10n-ignore (target words)
        w("電腦", "ㄉㄧㄢˋ ㄋㄠˇ", "tech"),  // l10n-ignore (target words)
        w("電視", "ㄉㄧㄢˋ ㄕˋ", "appliance"),  // l10n-ignore (target words)
        w("書包", "ㄕㄨ ㄅㄠ", "bag"),  // l10n-ignore (target words)
        w("老師", "ㄌㄠˇ ㄕ", "job"),  // l10n-ignore (target words)
        w("學校", "ㄒㄩㄝˊ ㄒㄧㄠˋ", "building"),  // l10n-ignore (target words)
        w("醫院", "ㄧ ㄩㄢˋ", "building"),  // l10n-ignore (target words)
        w("飯店", "ㄈㄢˋ ㄉㄧㄢˋ", "building"),  // l10n-ignore (target words)
        w("貓", "ㄇㄠ", "animal"),  // l10n-ignore (target words)
        w("狗", "ㄍㄡˇ", "animal"),  // l10n-ignore (target words)
        w("花", "ㄏㄨㄚ", "flower"),  // l10n-ignore (target words)
        w("書", "ㄕㄨ", "book"),  // l10n-ignore (target words)
        w("冰箱", "ㄅㄧㄥ ㄒㄧㄤ", "appliance"),  // l10n-ignore (target words)
        w("冷氣", "ㄌㄥˇ ㄑㄧˋ", "appliance"),  // l10n-ignore (target words)
        w("捷運", "ㄐㄧㄝˊ ㄩㄣˋ", "transport"),  // l10n-ignore (target words)
        w("機車", "ㄐㄧ ㄔㄜ", "vehicle"),  // l10n-ignore (target words)
        w("腳踏車", "ㄐㄧㄠˇ ㄊㄚˋ ㄔㄜ", "vehicle"),  // l10n-ignore (target words)
        w("超市", "ㄔㄠ ㄕˋ", "shop"),  // l10n-ignore (target words)
        w("銀行", "ㄧㄣˊ ㄏㄤˊ", "building"),  // l10n-ignore (target words)
        w("郵局", "ㄧㄡˊ ㄐㄩˊ", "building"),  // l10n-ignore (target words)
        w("公園", "ㄍㄨㄥ ㄩㄢˊ", "street"),  // l10n-ignore (target words)
        w("鉛筆", "ㄑㄧㄢ ㄅㄧˇ", "stationery"),  // l10n-ignore (target words)
        w("手錶", "ㄕㄡˇ ㄅㄧㄠˇ", "accessory"),  // l10n-ignore (target words)
        w("眼鏡", "ㄧㄢˇ ㄐㄧㄥˋ", "accessory"),  // l10n-ignore (target words)
        w("襯衫", "ㄔㄣˋ ㄕㄢ", "clothes"),  // l10n-ignore (target words)
        w("牙刷", "ㄧㄚˊ ㄕㄨㄚ", "tool"),  // l10n-ignore (target words)
        w("毛巾", "ㄇㄠˊ ㄐㄧㄣ", "home"),  // l10n-ignore (target words)
        w("香蕉", "ㄒㄧㄤ ㄐㄧㄠ", "fruit"),  // l10n-ignore (target words)
        w("西瓜", "ㄒㄧ ㄍㄨㄚ", "fruit"),  // l10n-ignore (target words)
        w("果汁", "ㄍㄨㄛˇ ㄓ", "drink"),  // l10n-ignore (target words)
        w("蛋糕", "ㄉㄢˋ ㄍㄠ", "dessert"),  // l10n-ignore (target words)
        w("沙發", "ㄕㄚ ㄈㄚ", "furniture"),  // l10n-ignore (target words)
        w("鳥", "ㄋㄧㄠˇ", "animal"),  // l10n-ignore (target words)
        w("樹", "ㄕㄨˋ", "plant"),  // l10n-ignore (target words)
        w("醫生", "ㄧ ㄕㄥ", "job"),  // l10n-ignore (target words)
        w("吸管", "ㄒㄧ ㄍㄨㄢˇ", "kitchenware"),  // l10n-ignore (target words)
        w("紅綠燈", "ㄏㄨㄥˊ ㄌㄩˋ ㄉㄥ", "sign"),  // l10n-ignore (target words)
        w("斑馬線", "ㄅㄢ ㄇㄚˇ ㄒㄧㄢˋ", "street"),  // l10n-ignore (target words)
        w("停車場", "ㄊㄧㄥˊ ㄔㄜ ㄔㄤˇ", "street"),  // l10n-ignore (target words)
        w("加油站", "ㄐㄧㄚ ㄧㄡˊ ㄓㄢˋ", "building"),  // l10n-ignore (target words)
        w("藥局", "ㄧㄠˋ ㄐㄩˊ", "shop"),  // l10n-ignore (target words)
        w("行李箱", "ㄒㄧㄥˊ ㄌㄧˇ ㄒㄧㄤ", "bag"),  // l10n-ignore (target words)
        w("吹風機", "ㄔㄨㄟ ㄈㄥ ㄐㄧ", "appliance"),  // l10n-ignore (target words)
        w("洗衣機", "ㄒㄧˇ ㄧ ㄐㄧ", "appliance"),  // l10n-ignore (target words)
        w("鍵盤", "ㄐㄧㄢˋ ㄆㄢˊ", "gadget"),  // l10n-ignore (target words)
        w("耳機", "ㄦˇ ㄐㄧ", "gadget"),  // l10n-ignore (target words)
        w("筆記本", "ㄅㄧˇ ㄐㄧˋ ㄅㄣˇ", "stationery"),  // l10n-ignore (target words)
        w("外套", "ㄨㄞˋ ㄊㄠˋ", "clothes"),  // l10n-ignore (target words)
        w("圍巾", "ㄨㄟˊ ㄐㄧㄣ", "accessory"),  // l10n-ignore (target words)
        w("鳳梨", "ㄈㄥˋ ㄌㄧˊ", "fruit"),  // l10n-ignore (target words)
        w("芒果", "ㄇㄤˊ ㄍㄨㄛˇ", "fruit"),  // l10n-ignore (target words)
        w("蝴蝶", "ㄏㄨˊ ㄉㄧㄝˊ", "animal"),  // l10n-ignore (target words)
        w("颱風", "ㄊㄞˊ ㄈㄥ", "weather"),  // l10n-ignore (target words)
        w("微波爐", "ㄨㄟ ㄅㄛ ㄌㄨˊ", "appliance"),  // l10n-ignore (target words)
        w("餐巾紙", "ㄘㄢ ㄐㄧㄣ ㄓˇ", "kitchenware"),  // l10n-ignore (target words)
        w("電扇", "ㄉㄧㄢˋ ㄕㄢˋ", "appliance"),  // l10n-ignore (target words)
        w("插頭", "ㄔㄚ ㄊㄡˊ", "appliance"),  // l10n-ignore (target words)
        w("延長線", "ㄧㄢˊ ㄔㄤˊ ㄒㄧㄢˋ", "appliance"),  // l10n-ignore (target words)
        w("遙控器", "ㄧㄠˊ ㄎㄨㄥˋ ㄑㄧˋ", "gadget"),  // l10n-ignore (target words)
        w("保溫瓶", "ㄅㄠˇ ㄨㄣ ㄆㄧㄥˊ", "kitchenware"),  // l10n-ignore (target words)
        w("砧板", "ㄓㄣ ㄅㄢˇ", "kitchenware"),  // l10n-ignore (target words)
        w("釘書機", "ㄉㄧㄥ ㄕㄨ ㄐㄧ", "stationery"),  // l10n-ignore (target words)
        w("口罩", "ㄎㄡˇ ㄓㄠˋ", "medicine"),  // l10n-ignore (target words)
        w("雨衣", "ㄩˇ ㄧ", "clothes"),  // l10n-ignore (target words)
        w("安全帽", "ㄢ ㄑㄩㄢˊ ㄇㄠˋ", "accessory"),  // l10n-ignore (target words)
        w("人行道", "ㄖㄣˊ ㄒㄧㄥˊ ㄉㄠˋ", "street"),  // l10n-ignore (target words)
        w("天橋", "ㄊㄧㄢ ㄑㄧㄠˊ", "street"),  // l10n-ignore (target words)
        w("招牌", "ㄓㄠ ㄆㄞˊ", "sign"),  // l10n-ignore (target words)
        w("消防車", "ㄒㄧㄠ ㄈㄤˊ ㄔㄜ", "vehicle"),  // l10n-ignore (target words)
        w("救護車", "ㄐㄧㄡˋ ㄏㄨˋ ㄔㄜ", "vehicle"),  // l10n-ignore (target words)
        w("蓮霧", "ㄌㄧㄢˊ ㄨˋ", "fruit"),  // l10n-ignore (target words)
        w("芭樂", "ㄅㄚ ㄌㄜˋ", "fruit"),  // l10n-ignore (target words)
        w("松鼠", "ㄙㄨㄥ ㄕㄨˇ", "animal"),  // l10n-ignore (target words)
        w("仙人掌", "ㄒㄧㄢ ㄖㄣˊ ㄓㄤˇ", "plant"),  // l10n-ignore (target words)
        w("水龍頭", "ㄕㄨㄟˇ ㄌㄨㄥˊ ㄊㄡˊ", "home"),  // l10n-ignore (target words)
    ]

    /// English.
    private static let en: [QuizPoolWord] = [
        w("apple", nil, "fruit"),
        w("banana", nil, "fruit"),
        w("bus", nil, "vehicle"),
        w("car", nil, "vehicle"),
        w("train", nil, "transport"),
        w("umbrella", nil, "accessory"),
        w("egg", nil, "food"),
        w("bread", nil, "food"),
        w("coffee", nil, "drink"),
        w("milk", nil, "drink"),
        w("tea", nil, "drink"),
        w("phone", nil, "tech"),
        w("computer", nil, "tech"),
        w("television", nil, "appliance"),
        w("bag", nil, "bag"),
        w("teacher", nil, "job"),
        w("school", nil, "building"),
        w("hospital", nil, "building"),
        w("hotel", nil, "building"),
        w("cat", nil, "animal"),
        w("dog", nil, "animal"),
        w("flower", nil, "flower"),
        w("book", nil, "book"),
        w("chair", nil, "furniture"),
        w("table", nil, "furniture"),
        w("shirt", nil, "clothes"),
        w("fridge", nil, "appliance"),
        w("bicycle", nil, "vehicle"),
        w("taxi", nil, "vehicle"),
        w("supermarket", nil, "shop"),
        w("bank", nil, "building"),
        w("post office", nil, "building"),
        w("park", nil, "street"),
        w("pencil", nil, "stationery"),
        w("watch", nil, "accessory"),
        w("glasses", nil, "accessory"),
        w("jacket", nil, "clothes"),
        w("toothbrush", nil, "tool"),
        w("towel", nil, "home"),
        w("watermelon", nil, "fruit"),
        w("juice", nil, "drink"),
        w("cake", nil, "dessert"),
        w("sandwich", nil, "food"),
        w("sofa", nil, "furniture"),
        w("lamp", nil, "furniture"),
        w("bird", nil, "animal"),
        w("tree", nil, "plant"),
        w("doctor", nil, "job"),
        w("straw", nil, "kitchenware"),
        w("traffic light", nil, "sign"),
        w("crosswalk", nil, "street"),
        w("parking lot", nil, "street"),
        w("gas station", nil, "building"),
        w("pharmacy", nil, "shop"),
        w("suitcase", nil, "bag"),
        w("hair dryer", nil, "appliance"),
        w("washing machine", nil, "appliance"),
        w("microwave", nil, "appliance"),
        w("keyboard", nil, "gadget"),
        w("headphones", nil, "gadget"),
        w("notebook", nil, "stationery"),
        w("scarf", nil, "accessory"),
        w("pineapple", nil, "fruit"),
        w("mango", nil, "fruit"),
        w("butterfly", nil, "animal"),
        w("napkin", nil, "kitchenware"),
        w("helmet", nil, "accessory"),
        w("coat", nil, "clothes"),
        w("electric fan", nil, "appliance"),
        w("plug", nil, "appliance"),
        w("extension cord", nil, "appliance"),
        w("remote control", nil, "gadget"),
        w("thermos", nil, "kitchenware"),
        w("chopping board", nil, "kitchenware"),
        w("stapler", nil, "stationery"),
        w("face mask", nil, "medicine"),
        w("raincoat", nil, "clothes"),
        w("sidewalk", nil, "street"),
        w("footbridge", nil, "street"),
        w("signboard", nil, "sign"),
        w("fire engine", nil, "vehicle"),
        w("ambulance", nil, "vehicle"),
        w("guava", nil, "fruit"),
        w("squirrel", nil, "animal"),
        w("cactus", nil, "plant"),
        w("faucet", nil, "home"),
        w("typhoon", nil, "weather"),
    ]

    /// 日本語.
    private static let ja: [QuizPoolWord] = [
        w("りんご", nil, "fruit"),  // l10n-ignore (target words)
        w("果物", "くだもの", "fruit"),  // l10n-ignore (target words)
        w("バス", nil, "vehicle"),  // l10n-ignore (target words)
        w("車", "くるま", "vehicle"),  // l10n-ignore (target words)
        w("電車", "でんしゃ", "transport"),  // l10n-ignore (target words)
        w("傘", "かさ", "accessory"),  // l10n-ignore (target words)
        w("卵", "たまご", "food"),  // l10n-ignore (target words)
        w("パン", nil, "food"),  // l10n-ignore (target words)
        w("コーヒー", nil, "drink"),  // l10n-ignore (target words)
        w("牛乳", "ぎゅうにゅう", "drink"),  // l10n-ignore (target words)
        w("お茶", "おちゃ", "drink"),  // l10n-ignore (target words)
        w("電話", "でんわ", "tech"),  // l10n-ignore (target words)
        w("テレビ", nil, "appliance"),  // l10n-ignore (target words)
        w("かばん", nil, "bag"),  // l10n-ignore (target words)
        w("先生", "せんせい", "job"),  // l10n-ignore (target words)
        w("学校", "がっこう", "building"),  // l10n-ignore (target words)
        w("病院", "びょういん", "building"),  // l10n-ignore (target words)
        w("猫", "ねこ", "animal"),  // l10n-ignore (target words)
        w("犬", "いぬ", "animal"),  // l10n-ignore (target words)
        w("花", "はな", "flower"),  // l10n-ignore (target words)
        w("本", "ほん", "book"),  // l10n-ignore (target words)
        w("机", "つくえ", "furniture"),  // l10n-ignore (target words)
        w("椅子", "いす", "furniture"),  // l10n-ignore (target words)
        w("時計", "とけい", "accessory"),  // l10n-ignore (target words)
        w("鉛筆", "えんぴつ", "stationery"),  // l10n-ignore (target words)
        w("自転車", "じてんしゃ", "vehicle"),  // l10n-ignore (target words)
        w("お弁当", "おべんとう", "food"),  // l10n-ignore (target words)
        w("空港", "くうこう", "building"),  // l10n-ignore (target words)
        w("地下鉄", "ちかてつ", "transport"),  // l10n-ignore (target words)
        w("美術館", "びじゅつかん", "building"),  // l10n-ignore (target words)
        w("工場", "こうじょう", "building"),  // l10n-ignore (target words)
        w("手袋", "てぶくろ", "accessory"),  // l10n-ignore (target words)
        w("下着", "したぎ", "clothes"),  // l10n-ignore (target words)
        w("着物", "きもの", "clothes"),  // l10n-ignore (target words)
        w("鏡", "かがみ", "furniture"),  // l10n-ignore (target words)
        w("棚", "たな", "furniture"),  // l10n-ignore (target words)
        w("布団", "ふとん", "home"),  // l10n-ignore (target words)
        w("人形", "にんぎょう", "toy"),  // l10n-ignore (target words)
        w("指輪", "ゆびわ", "jewelry"),  // l10n-ignore (target words)
        w("虫", "むし", "animal"),  // l10n-ignore (target words)
        w("島", "しま", "nature"),  // l10n-ignore (target words)
        w("歯医者", "はいしゃ", "job"),  // l10n-ignore (target words)
        w("ケーキ", nil, "dessert"),  // l10n-ignore (target words)
        w("ジュース", nil, "drink"),  // l10n-ignore (target words)
        w("スーパー", nil, "shop"),  // l10n-ignore (target words)
        w("パソコン", nil, "tech"),  // l10n-ignore (target words)
        w("冷蔵庫", "れいぞうこ", "appliance"),  // l10n-ignore (target words)
        w("掃除機", "そうじき", "appliance"),  // l10n-ignore (target words)
        w("洗濯機", "せんたくき", "appliance"),  // l10n-ignore (target words)
        w("信号", "しんごう", "sign"),  // l10n-ignore (target words)
        w("横断歩道", "おうだんほどう", "street"),  // l10n-ignore (target words)
        w("駐車場", "ちゅうしゃじょう", "street"),  // l10n-ignore (target words)
        w("薬局", "やっきょく", "shop"),  // l10n-ignore (target words)
        w("財布", "さいふ", "accessory"),  // l10n-ignore (target words)
        w("毛布", "もうふ", "home"),  // l10n-ignore (target words)
        w("枕", "まくら", "home"),  // l10n-ignore (target words)
        w("台風", "たいふう", "weather"),  // l10n-ignore (target words)
        w("蝶", "ちょう", "animal"),  // l10n-ignore (target words)
        w("ストロー", nil, "kitchenware"),  // l10n-ignore (target words)
        w("イヤホン", nil, "gadget"),  // l10n-ignore (target words)
        w("スーツケース", nil, "bag"),  // l10n-ignore (target words)
        w("ドライヤー", nil, "appliance"),  // l10n-ignore (target words)
        w("マフラー", nil, "accessory"),  // l10n-ignore (target words)
        w("パイナップル", nil, "fruit"),  // l10n-ignore (target words)
        w("扇風機", "せんぷうき", "appliance"),  // l10n-ignore (target words)
        w("炊飯器", "すいはんき", "appliance"),  // l10n-ignore (target words)
        w("電卓", "でんたく", "gadget"),  // l10n-ignore (target words)
        w("消防車", "しょうぼうしゃ", "vehicle"),  // l10n-ignore (target words)
        w("救急車", "きゅうきゅうしゃ", "vehicle"),  // l10n-ignore (target words)
        w("看板", "かんばん", "sign"),  // l10n-ignore (target words)
        w("歩道橋", "ほどうきょう", "street"),  // l10n-ignore (target words)
        w("魔法瓶", "まほうびん", "kitchenware"),  // l10n-ignore (target words)
        w("まな板", "まないた", "kitchenware"),  // l10n-ignore (target words)
        w("蛇口", "じゃぐち", "home"),  // l10n-ignore (target words)
        w("画鋲", "がびょう", "stationery"),  // l10n-ignore (target words)
        w("灯台", "とうだい", "building"),  // l10n-ignore (target words)
        w("雨具", "あまぐ", "clothes"),  // l10n-ignore (target words)
        w("りす", nil, "animal"),  // l10n-ignore (target words)
        w("サボテン", nil, "plant"),  // l10n-ignore (target words)
        w("ホッチキス", nil, "stationery"),  // l10n-ignore (target words)
        w("リモコン", nil, "gadget"),  // l10n-ignore (target words)
        w("マスク", nil, "medicine"),  // l10n-ignore (target words)
    ]
}
