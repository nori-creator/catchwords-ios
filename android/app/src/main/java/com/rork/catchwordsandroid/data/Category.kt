package com.rork.catchwordsandroid.data

import androidx.compose.ui.graphics.Color

/** The dex's 8 rooms (category.ts ROOM_KEYS). */
enum class Room(val accent: Color) {
    EAT(Color(0xFFFF9F43)),
    TOWN(Color(0xFF4EA8FF)),
    HOUSE(Color(0xFFD9B38C)),
    WEAR(Color(0xFFFF7EB6)),
    PLAY(Color(0xFFA78BFA)),
    NATURE(Color(0xFF4ADE80)),
    PEOPLE(Color(0xFFFBBF24)),
    MARKS(Color(0xFF94A3B8));

    val label: String
        get() = when (this) {
            EAT -> tr("食べる", "Food", "飲食")
            TOWN -> tr("街", "Town", "城市")
            HOUSE -> tr("家", "Home", "家")
            WEAR -> tr("身につける", "Wear", "穿戴")
            PLAY -> tr("学び・遊び", "Learn & play", "學習與娛樂")
            NATURE -> tr("自然", "Nature", "自然")
            PEOPLE -> tr("人・体", "People", "人與身體")
            MARKS -> tr("しるし", "Signs", "符號")
        }
}

/** category.ts CATEGORY_META (54 keys → room + emoji). */
object Category {
    private data class Meta(val room: Room, val emoji: String, val ja: String, val en: String, val zh: String)

    private val meta: LinkedHashMap<String, Meta> = linkedMapOf(
        "fruit" to Meta(Room.EAT, "🍎", "果物", "Fruit", "水果"),
        "vegetable" to Meta(Room.EAT, "🥬", "野菜", "Vegetables", "蔬菜"),
        "drink" to Meta(Room.EAT, "🥤", "飲み物", "Drinks", "飲料"),
        "food" to Meta(Room.EAT, "🍜", "食べ物", "Food", "食物"),
        "dessert" to Meta(Room.EAT, "🍰", "スイーツ", "Desserts", "甜點"),
        "vehicle" to Meta(Room.TOWN, "🚗", "乗り物", "Vehicles", "交通工具"),
        "transport" to Meta(Room.TOWN, "🚆", "交通", "Transport", "交通"),
        "building" to Meta(Room.TOWN, "🏢", "建物", "Buildings", "建築"),
        "street" to Meta(Room.TOWN, "🛣️", "街並み", "Streets", "街道"),
        "sign" to Meta(Room.TOWN, "🪧", "看板", "Signs", "招牌"),
        "shop" to Meta(Room.TOWN, "🏪", "お店", "Shops", "商店"),
        "home" to Meta(Room.HOUSE, "🏠", "家", "Home", "家"),
        "furniture" to Meta(Room.HOUSE, "🛋️", "家具", "Furniture", "家具"),
        "appliance" to Meta(Room.HOUSE, "🔌", "家電", "Appliances", "家電"),
        "kitchenware" to Meta(Room.HOUSE, "🍳", "調理器具", "Kitchenware", "廚具"),
        "tool" to Meta(Room.HOUSE, "🔧", "道具", "Tools", "工具"),
        "clothes" to Meta(Room.WEAR, "👕", "服", "Clothes", "衣服"),
        "accessory" to Meta(Room.WEAR, "🧢", "アクセ", "Accessories", "配件"),
        "shoes" to Meta(Room.WEAR, "👟", "靴", "Shoes", "鞋子"),
        "bag" to Meta(Room.WEAR, "👜", "バッグ", "Bags", "包包"),
        "jewelry" to Meta(Room.WEAR, "💍", "ジュエリー", "Jewelry", "珠寶"),
        "clothing_part" to Meta(Room.WEAR, "👔", "服の部分", "Clothing parts", "衣服部位"),
        "stationery" to Meta(Room.PLAY, "✏️", "文房具", "Stationery", "文具"),
        "book" to Meta(Room.PLAY, "📚", "本", "Books", "書"),
        "tech" to Meta(Room.PLAY, "💻", "テック", "Tech", "科技"),
        "gadget" to Meta(Room.PLAY, "🖱️", "ガジェット", "Gadgets", "小工具"),
        "toy" to Meta(Room.PLAY, "🧸", "おもちゃ", "Toys", "玩具"),
        "game" to Meta(Room.PLAY, "🎮", "ゲーム", "Games", "遊戲"),
        "sport" to Meta(Room.PLAY, "⚽", "スポーツ", "Sports", "運動"),
        "instrument" to Meta(Room.PLAY, "🎸", "楽器", "Instruments", "樂器"),
        "art" to Meta(Room.PLAY, "🎨", "アート", "Art", "藝術"),
        "decoration" to Meta(Room.PLAY, "🎊", "装飾", "Decorations", "裝飾"),
        "animal" to Meta(Room.NATURE, "🐾", "動物", "Animals", "動物"),
        "plant" to Meta(Room.NATURE, "🌿", "植物", "Plants", "植物"),
        "flower" to Meta(Room.NATURE, "🌸", "花", "Flowers", "花"),
        "nature" to Meta(Room.NATURE, "🍃", "自然", "Nature", "自然"),
        "weather" to Meta(Room.NATURE, "🌦️", "天気", "Weather", "天氣"),
        "sky" to Meta(Room.NATURE, "☀️", "空", "Sky", "天空"),
        "water" to Meta(Room.NATURE, "💧", "水", "Water", "水"),
        "mountain" to Meta(Room.NATURE, "⛰️", "山", "Mountains", "山"),
        "body" to Meta(Room.PEOPLE, "🖐️", "体の部位", "Body", "身體部位"),
        "face" to Meta(Room.PEOPLE, "😊", "顔", "Face", "臉"),
        "hand" to Meta(Room.PEOPLE, "✋", "手", "Hands", "手"),
        "person" to Meta(Room.PEOPLE, "🧑", "人", "People", "人"),
        "family" to Meta(Room.PEOPLE, "👨‍👩‍👧", "家族", "Family", "家人"),
        "job" to Meta(Room.PEOPLE, "💼", "仕事", "Jobs", "工作"),
        "character" to Meta(Room.MARKS, "🔤", "文字", "Characters", "文字"),
        "symbol" to Meta(Room.MARKS, "🔣", "記号", "Symbols", "符號"),
        "color" to Meta(Room.MARKS, "🎨", "色", "Colors", "顏色"),
        "shape" to Meta(Room.MARKS, "🔷", "形", "Shapes", "形狀"),
        "money" to Meta(Room.MARKS, "💰", "お金", "Money", "錢"),
        "document" to Meta(Room.MARKS, "📄", "書類", "Documents", "文件"),
        "medicine" to Meta(Room.MARKS, "💊", "薬", "Medicine", "藥"),
        "other" to Meta(Room.MARKS, "✨", "その他", "Other", "其他"),
    )

    val orderedKeys: List<String> = meta.keys.toList()

    fun isBuiltin(key: String): Boolean = meta.containsKey(key)

    fun key(raw: String?): String = if (raw != null && meta.containsKey(raw)) raw else "other"

    fun label(key: String?): String = meta[key(key)]?.let { tr(it.ja, it.en, it.zh) } ?: tr("その他", "Other", "其他")

    fun emoji(key: String?): String = meta[key(key)]?.emoji ?: "✨"

    fun room(key: String?): Room = meta[key(key)]?.room ?: Room.MARKS
}
