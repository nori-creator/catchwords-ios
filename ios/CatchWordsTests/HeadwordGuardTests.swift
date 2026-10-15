import XCTest
@testable import CatchWords

/// A headword is saved only when it is written in the learning language alone (owner 2026-10-15: never the display
/// language in a headword, even when the word was typed in it — ボクサーパンツ typed by a Japanese reader came back as a
/// Mandarin headword).
/// Run on its own by .github/workflows/ios-check.yml.
@MainActor
final class HeadwordGuardTests: XCTestCase {
    func testMandarinRefusesKanaAndLatin() {
        for bad in ["ボクサーパンツ", "ボクサー褲", "boxer briefs", "四角褲 (boxer)", "四角褲（ボクサー）", "內褲pants", "文旦JUICE", "", "  "] {
            XCTAssertFalse(LanguageRules.headwordSaveable(bad, target: "zh-TW"), bad)
        }
    }

    func testMandarinKeepsHanWords() {
        for good in ["四角褲", "平口褲", "內褲", "冰火菠蘿油", " 眼鏡 ", "二〇二六年", "3C產品"] {
            XCTAssertTrue(LanguageRules.headwordSaveable(good, target: "zh-TW"), good)
        }
    }

    func testMandarinRefusesKanjiOnlyJapanWrites() {
        // Japanese typed as kanji only: 図 / 駅 are written 圖 / 驛 in Taiwan (the server's kanji-forms.ts).
        XCTAssertFalse(LanguageRules.headwordSaveable("図鑑", target: "zh-TW"))
        XCTAssertFalse(LanguageRules.headwordSaveable("駅", target: "zh-TW"))
        XCTAssertTrue(LanguageRules.headwordSaveable("圖鑑", target: "zh-TW"))
        // Characters Taiwan also uses as standard ones stay.
        XCTAssertTrue(LanguageRules.headwordSaveable("月餅", target: "zh-TW"))
    }

    func testMandarinKeepsCapitalsStuckToHan() {
        // Taiwan writes these with Latin capitals (the server's headwordOk lets them through too).
        XCTAssertTrue(LanguageRules.headwordSaveable("T恤", target: "zh-TW"))
        XCTAssertTrue(LanguageRules.headwordSaveable("卡拉OK", target: "zh-TW"))
        // Lowercase, four or more capitals, or capitals standing apart are not part of the word.
        XCTAssertFalse(LanguageRules.headwordSaveable("t恤", target: "zh-TW"))
        XCTAssertFalse(LanguageRules.headwordSaveable("卡拉 OK", target: "zh-TW"))
        XCTAssertFalse(LanguageRules.headwordSaveable("OK", target: "zh-TW"))
    }

    func testEnglishRefusesCJK() {
        XCTAssertTrue(LanguageRules.headwordSaveable("boxer briefs", target: "en"))
        XCTAssertTrue(LanguageRules.headwordSaveable("don't", target: "en"))
        XCTAssertFalse(LanguageRules.headwordSaveable("ボクサーパンツ", target: "en"))
        XCTAssertFalse(LanguageRules.headwordSaveable("boxer 內褲", target: "en"))
        XCTAssertFalse(LanguageRules.headwordSaveable("123", target: "en"))
    }

    func testJapaneseRefusesEnglish() {
        XCTAssertTrue(LanguageRules.headwordSaveable("ボクサーパンツ", target: "ja"))
        XCTAssertTrue(LanguageRules.headwordSaveable("Tシャツ", target: "ja"))
        XCTAssertTrue(LanguageRules.headwordSaveable("眼鏡", target: "ja"))
        XCTAssertFalse(LanguageRules.headwordSaveable("boxer briefs", target: "ja"))
        XCTAssertFalse(LanguageRules.headwordSaveable("パンツ (pants)", target: "ja"))
    }

    func testTypedLookupNeverOffersAnotherLanguagesHeadword() {
        func word(_ head: String) -> Candidate {
            Candidate(kind: "object", headword: head, zhuyin: "", pinyin: "", meaningJa: "", pos: "N", point: [500, 500],
                      confidence: 0.9, alternatives: [])
        }
        let found = [word("ボクサーパンツ"), word("平口褲"), word("boxer"), word("四角褲")]
        XCTAssertEqual(CaptureViewModel.saveable(found, target: "zh-TW").map(\.headword), ["平口褲", "四角褲"])
        XCTAssertTrue(CaptureViewModel.saveable([word("ボクサーパンツ")], target: "zh-TW").isEmpty)
    }
}
