import XCTest
@testable import CatchWords

/// Who shares a word's content (owner 2026-10-25, docs/sharing-rules.md S6・S8): readers of another display language
/// share nothing, and a word saved under the band rule shows only its band's examples and chunks. Run on its own by
/// .github/workflows/ios-check.yml.
final class SharingRuleTests: XCTestCase {
    private func word(mark: String) -> Word {
        let obj: [String: Any] = [
            "id": "w1", "headword": "腳踏車", "language": "zh-TW", "meaning_ja": "自転車",
            "example_sentence": "我騎腳踏車上學。", "example_translation": "自転車で通学する。",
            "extras": [
                "explain_lang": mark,
                "usage_chunks": [["parts": [["text": "騎", "pos": "V"], ["text": "腳踏車", "pos": "N"]], "ja": "自転車に乗る"]],
                "measure_words": [["word": "一台", "zhuyin": "", "pinyin": "", "note": "乗り物に"]],
                "taiwan_note": "台湾ではバイクの方が多い。",
            ] as [String: Any],
        ]
        let data = try! JSONSerialization.data(withJSONObject: obj)
        return try! JSONDecoder().decode(Word.self, from: data)
    }

    private func level(_ obj: [String: Any]) -> ReaderLanguage.LevelContent {
        try! JSONDecoder().decode(ReaderLanguage.LevelContent.self, from: JSONSerialization.data(withJSONObject: obj))
    }

    /// S8: a Japanese row gives an English reader nothing — not even the chunks or the measure words.
    func testAnotherDisplayLanguageSharesNothing() {
        let w = ReaderLanguage.resolve(word(mark: "ja"), explanation: nil, readerMeaning: nil, reader: "en")
        XCTAssertEqual(w.meaningJa, "")
        XCTAssertNil(w.exampleTranslation)
        XCTAssertNil(w.extras?.usageChunks)
        XCTAssertNil(w.extras?.measureWords)
        XCTAssertNil(w.extras?.taiwanNote)
        XCTAssertEqual(w.extras?.explainLang, "en")
    }

    /// The same display language still shares every section of a word saved before the band rule.
    func testSameLanguageLegacyWordIsUnchanged() {
        let w = ReaderLanguage.resolve(word(mark: "ja"), explanation: nil, readerMeaning: nil, reader: "ja")
        XCTAssertEqual(w.meaningJa, "自転車")
        XCTAssertEqual(w.exampleSentence, "我騎腳踏車上學。")
        XCTAssertEqual(w.extras?.usageChunks?.count, 1)
        XCTAssertEqual(w.extras?.measureWords?.count, 1)
    }

    /// S6: a word under the band rule shows its band's examples and chunks; the other sections stay the language's.
    func testBandWordShowsOnlyItsBandsExamplesAndChunks() {
        let lv = level([
            "band": "C>C", "example_sentence": "這台腳踏車的變速器壞了。", "example_translation": "この自転車の変速機が壊れた。",
            "extras": ["usage_chunks": [["parts": [["text": "腳踏車", "pos": "N"], ["text": "變速器", "pos": "N"]], "ja": "自転車の変速機"]]],
        ])
        let w = ReaderLanguage.resolve(word(mark: "ja"), explanation: nil, readerMeaning: nil, reader: "ja", level: lv)
        XCTAssertEqual(w.exampleSentence, "這台腳踏車的變速器壞了。")
        XCTAssertEqual(w.exampleTranslation, "この自転車の変速機が壊れた。")
        XCTAssertEqual(w.extras?.usageChunks?.first?.ja, "自転車の変速機")
        XCTAssertEqual(w.extras?.measureWords?.count, 1, "measure words are shared by the whole display language")
        XCTAssertEqual(w.extras?.taiwanNote, "台湾ではバイクの方が多い。")
    }

    /// S6: until the band's examples are written, none of another band's (or the shared row's) show — the page asks.
    func testBandWordWithoutItsBandsRowShowsNoExamples() {
        let empty = ReaderLanguage.LevelContent(band: "A>B")
        let w = ReaderLanguage.resolve(word(mark: "ja"), explanation: nil, readerMeaning: nil, reader: "ja", level: empty)
        XCTAssertNil(w.exampleSentence)
        XCTAssertNil(w.exampleTranslation)
        XCTAssertNil(w.extras?.usageChunks)
        XCTAssertEqual(w.extras?.measureWords?.count, 1)
        XCTAssertTrue(ReaderLanguage.needsGeneration(nil, lang: "ja", l1: "ja", level: empty))
    }

    func testBandKeys() {
        XCTAssertTrue(ReaderLanguage.LevelContent.isBand("A>B"))
        XCTAssertTrue(ReaderLanguage.LevelContent.isBand("C>C"))
        XCTAssertFalse(ReaderLanguage.LevelContent.isBand("legacy"))
        XCTAssertFalse(ReaderLanguage.LevelContent.isBand(nil))
        XCTAssertFalse(ReaderLanguage.LevelContent.isBand("D>A"))
    }
}
