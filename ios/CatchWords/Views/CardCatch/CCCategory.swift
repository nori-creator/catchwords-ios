import SwiftUI

/// The card's studio colour, one per dex category (owner 2026-10-02: "each category gets its own colour, 20
/// different colours"). b1 = the light centre tone, b2 = the deep edge tone, used exactly like the prototype's
/// `CATS` b1/b2 (docs/prototype/cats.js). Swatches: docs/prototype/palette20.png.
struct CCCategory: Equatable {
    /// DexCatalog category number, 1…20.
    let no: Int

    /// No. → (b1, b2). The 20 colours re-selected with the categories (2026-10-02).
    private static let palette: [Int: (UInt32, UInt32)] = [
        1:  (0xFAE5D4, 0xC49367),  // 飲み物
        2:  (0xFFE4C2, 0xE19B34),  // 料理・屋台
        3:  (0xFFDCD5, 0xE57065),  // 果物・野菜
        4:  (0xFFDCE8, 0xE77FA1),  // お菓子・パン
        5:  (0xCAF5E4, 0x30B792),  // 食器・台所
        6:  (0xF6E6DD, 0xA9836E),  // 家具・インテリア
        7:  (0xE0ECF3, 0x86A3B5),  // 家電
        8:  (0xEDE2FF, 0xA383E3),  // スマホ・パソコン
        9:  (0xFAE8BE, 0xECBE3F),  // 文房具・本
        10: (0xC7F4F0, 0x2DC2BB),  // 洗面・日用品
        11: (0xF9DFFF, 0xBA7DC8),  // 服
        12: (0xFFDCF2, 0xDB78B2),  // 靴・バッグ・小物
        13: (0xDBE9FF, 0x6B86E1),  // 乗り物
        14: (0xD3EFFA, 0x529EB7),  // 建物・お店
        15: (0xE5EAF0, 0x8794A1),  // 道・街の物
        16: (0xFFDFCA, 0xEA8751),  // 動物
        17: (0xD5F4D2, 0x68B460),  // 植物・花
        18: (0xCEEFFF, 0x60BCF4),  // 空・自然
        19: (0xEAEEC0, 0xC1C73F),  // スポーツ・遊び
        20: (0xFAE3E2, 0xC99593),  // 人・体
        21: (0xECEEF2, 0x9AA3AE),  // その他
    ]

    var b1: UInt32 { (Self.palette[no] ?? Self.palette[10]!).0 }
    var b2: UInt32 { (Self.palette[no] ?? Self.palette[10]!).1 }

    /// The card's studio colour for one of the 20 dex categories (DexCatalog).
    static func forDex(_ no: Int) -> CCCategory { CCCategory(no: no) }

    /// The colour for a word: its catalog item's category when the headword is in the catalog, else its
    /// category key's (DexCatalog.keyToCategory).
    static func from(headword: String?, categoryKey key: String?) -> CCCategory {
        forDex(DexCatalog.category(headword: headword, key: key, lang: NativeAPI.targetLanguage))
    }
}
