import XCTest
@testable import CatchWords

/// Pinyin over each character (Views/ZhuyinWordView.swift `PinyinLayout`, Utilities/PinyinZhuyin.swift
/// `syllables(ofPinyin:want:)`) and the headword rules of the dex categories (Models/CategoryRules.swift).
/// Run on its own by .github/workflows/ios-check.yml.
final class ReadingAndCategoryTests: XCTestCase {
    // MARK: - Pinyin cut into one syllable per character (owner 2026-10-14)

    func testPinyinSyllables() {
        XCTAssertEqual(PinyinZhuyin.syllables(ofPinyin: "shǒu biǎo", want: 2), ["shǒu", "biǎo"])
        XCTAssertEqual(PinyinZhuyin.syllables(ofPinyin: "mángguǒ", want: 2), ["máng", "guǒ"])
        XCTAssertEqual(PinyinZhuyin.syllables(ofPinyin: "bìguàjìng", want: 3), ["bì", "guà", "jìng"])
        XCTAssertEqual(PinyinZhuyin.syllables(ofPinyin: "Xī'ān", want: 2), ["Xī", "ān"])
        XCTAssertEqual(PinyinZhuyin.syllables(ofPinyin: "xian", want: 2), ["xi", "an"])
        XCTAssertEqual(PinyinZhuyin.syllables(ofPinyin: "xian", want: 1), ["xian"])
        XCTAssertEqual(PinyinZhuyin.syllables(ofPinyin: "shou3biao3", want: 2), ["shou3", "biao3"])
        XCTAssertEqual(PinyinZhuyin.syllables(ofPinyin: "lǜchá", want: 2), ["lǜ", "chá"])
        // Not pinyin, or not that many syllables: one line over the word instead.
        XCTAssertNil(PinyinZhuyin.syllables(ofPinyin: "hello", want: 2))
        XCTAssertNil(PinyinZhuyin.syllables(ofPinyin: "shǒu biǎo", want: 1))
        XCTAssertNil(PinyinZhuyin.syllables(ofPinyin: "", want: 1))
    }

    func testPinyinOverEachCharacter() {
        let own = PinyinLayout.pair("手錶", pinyin: "shǒu biǎo", zhuyin: nil)
        XCTAssertEqual(own?.map(\.char), ["手", "錶"])
        XCTAssertEqual(own?.map(\.reading), ["shǒu", "biǎo"])
        // No pinyin of its own: spelled from the zhuyin.
        let spelled = PinyinLayout.pair("手錶", pinyin: nil, zhuyin: "ㄕㄡˇ ㄅㄧㄠˇ")
        XCTAssertEqual(spelled?.map(\.reading), ["shǒu", "biǎo"])
        // The zhuyin comes first (one syllable at a time); its own pinyin only without one.
        let fromZhuyin = PinyinLayout.pair("手錶", pinyin: "shoubiaoxx", zhuyin: "ㄕㄡˇ ㄅㄧㄠˇ")
        XCTAssertEqual(fromZhuyin?.map(\.reading), ["shǒu", "biǎo"])
        // A character without a reading keeps its place (nothing over it).
        let mixed = PinyinLayout.pair("T恤", pinyin: "xù", zhuyin: nil)
        XCTAssertEqual(mixed?.map(\.reading), [nil, "xù"])
        XCTAssertNil(PinyinLayout.pair("手錶", pinyin: "shǒu", zhuyin: nil))
        XCTAssertNil(PinyinLayout.pair("apple", pinyin: "apple", zhuyin: nil))
    }

    // MARK: - Dex categories from the headword (owner 2026-10-14)

    func testCategoryRules() {
        let cases: [(String, String)] = [
            ("桃", "fruit"), ("水蜜桃", "fruit"), ("文旦", "fruit"), ("柚子", "fruit"),
            ("可頌", "dessert"), ("蘑菇", "plant"), ("杏鮑菇", "plant"),
            ("健康餐", "food"), ("健康便當", "food"), ("光雕投影", "street"),
            ("麥芽牛乳", "drink"), ("優酪乳", "drink"), ("巧克力牛奶", "drink"), ("拿鐵", "drink"), ("鮮乳", "drink"),
            ("桃花", "flower"), ("插座", "home"), ("抹布", "tool"), ("燒仙草", "dessert"),
        ]
        for (headword, key) in cases {
            XCTAssertEqual(CategoryRules.rule(for: headword), key, headword)
        }
        // No rule: the stored key stands; an unknown one is "other".
        XCTAssertNil(CategoryRules.rule(for: "尺"))
        XCTAssertEqual(CategoryRules.normalize(headword: "尺", key: "stationery"), "stationery")
        XCTAssertEqual(CategoryRules.normalize(headword: "尺", key: "not-a-key"), "other")
        // A rule wins over a wrong stored key.
        XCTAssertEqual(CategoryRules.normalize(headword: "桃", key: "nature"), "fruit")
    }

    func testOtherIsNotDailyGoods() {
        XCTAssertEqual(DexCatalog.category(forKey: "other"), DexCatalog.otherNo)
        XCTAssertEqual(DexCatalog.category(forKey: nil), DexCatalog.otherNo)
        XCTAssertEqual(DexCatalog.category(forKey: "medicine"), 10)
        XCTAssertEqual(DexCatalog.withOther.last?.no, DexCatalog.otherNo)
        XCTAssertEqual(DexCatalog.categories.count, 20)
    }

    /// 発音のコツ・語源・覚え方・台湾メモ are drawn one sentence per line (owner 2026-10-14).
    @MainActor
    func testTipsSplitIntoSentences() {
        XCTAssertEqual(WordDetailView.sentences("舌を上げる。息を強く出す！\n部首: 木"),
                       ["舌を上げる。", "息を強く出す！", "部首: 木"])
        XCTAssertEqual(WordDetailView.sentences("「好吃。」と言う。次"), ["「好吃。」と言う。", "次"])
        XCTAssertEqual(WordDetailView.sentences("Stress the first syllable. Then relax."),
                       ["Stress the first syllable.", "Then relax."])
        XCTAssertEqual(WordDetailView.sentences("  "), [])
    }
}
