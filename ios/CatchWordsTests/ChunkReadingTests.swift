import XCTest
@testable import CatchWords

/// The readings over chunk blocks (server chunk tokens, 2026-10-15: `pinyin` and `zhuyin` on every token): read
/// leniently, kept through the tidy rules, and chosen by the learner's 発音表記. Run on its own by ios-check.yml.
@MainActor
final class ChunkReadingTests: XCTestCase {
    private func chunk(_ json: String) throws -> UsageChunk {
        try JSONDecoder().decode(UsageChunk.self, from: Data(json.utf8))
    }

    func testTokensWithReadingsAreRead() throws {
        let c = try chunk(#"{"parts":[{"text":"點","pos":"V","pinyin":"diǎn","zhuyin":"ㄉㄧㄢˇ"},{"text":"鐵板麵","pos":"N","pinyin":"tiě bǎn miàn","zhuyin":"ㄊㄧㄝˇ ㄅㄢˇ ㄇㄧㄢˋ"}],"ja":"鉄板焼きそばを注文する"}"#)
        XCTAssertEqual(c.parts.count, 2)
        XCTAssertEqual(c.parts[0].pinyin, "diǎn")
        XCTAssertEqual(c.parts[0].zhuyin, "ㄉㄧㄢˇ")
        XCTAssertEqual(c.parts[1].zhuyin, "ㄊㄧㄝˇ ㄅㄢˇ ㄇㄧㄢˋ")
    }

    func testAnOldCardWithoutReadingsStillDecodes() throws {
        let c = try chunk(#"{"parts":[{"text":"點","pos":"V"},{"text":"鐵板麵","pos":"N","pinyin":"","zhuyin":null}],"ja":"x"}"#)
        XCTAssertEqual(c.parts.count, 2)
        XCTAssertNil(c.parts[0].pinyin)
        XCTAssertNil(c.parts[0].zhuyin)
        XCTAssertNil(c.parts[1].pinyin, "an empty reading is no reading")
        XCTAssertNil(c.parts[1].zhuyin)
        XCTAssertNil(ChunkLineView.reading(for: c.parts[0], target: "zh-TW", pref: "zhuyin"))
    }

    func testABrokenReadingNeverBreaksTheChunk() throws {
        let c = try chunk(#"{"parts":[{"text":"點","pos":"V","pinyin":7,"zhuyin":["ㄉ"]}],"ja":"x"}"#)
        XCTAssertEqual(c.parts[0].text, "點")
        XCTAssertNil(c.parts[0].pinyin)
        XCTAssertNil(c.parts[0].zhuyin)
    }

    func testTheLearnersChoiceDecidesWhichReadingShows() {
        let part = ChunkPart(text: "鐵板麵", pos: "N", pinyin: "tiě bǎn miàn", zhuyin: "ㄊㄧㄝˇ ㄅㄢˇ ㄇㄧㄢˋ")
        XCTAssertEqual(ChunkLineView.reading(for: part, target: "zh-TW", pref: "zhuyin"), "ㄊㄧㄝˇ ㄅㄢˇ ㄇㄧㄢˋ")
        XCTAssertEqual(ChunkLineView.reading(for: part, target: "zh-TW", pref: "pinyin"), "tiě bǎn miàn")
        // Only the other reading came: it is shown rather than nothing (pinyin spelled from zhuyin when it can be).
        let zOnly = ChunkPart(text: "點", pos: "V", zhuyin: "ㄉㄧㄢˇ")
        XCTAssertEqual(ChunkLineView.reading(for: zOnly, target: "zh-TW", pref: "zhuyin"), "ㄉㄧㄢˇ")
        XCTAssertEqual(ChunkLineView.reading(for: zOnly, target: "zh-TW", pref: "pinyin"), "diǎn")
        let pOnly = ChunkPart(text: "點", pos: "V", pinyin: "diǎn")
        XCTAssertEqual(ChunkLineView.reading(for: pOnly, target: "zh-TW", pref: "zhuyin"), "diǎn")
        // Never over a Japanese or English chunk.
        XCTAssertNil(ChunkLineView.reading(for: part, target: "ja", pref: "zhuyin"))
        XCTAssertNil(ChunkLineView.reading(for: part, target: "en", pref: "pinyin"))
    }

    func testAMergedCompoundKeepsBothReadings() {
        let parts = [ChunkPart(text: "芒果", pos: "N", pinyin: "máng guǒ", zhuyin: "ㄇㄤˊ ㄍㄨㄛˇ"),
                     ChunkPart(text: "冰", pos: "N", pinyin: "bīng", zhuyin: "ㄅㄧㄥ")]
        let merged = ChunkRules.mergeCompounds(parts, headword: "芒果")
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].text, "芒果冰")
        XCTAssertEqual(merged[0].pinyin, "máng guǒ bīng")
        XCTAssertEqual(merged[0].zhuyin, "ㄇㄤˊ ㄍㄨㄛˇ ㄅㄧㄥ")
        // Half a reading is no reading.
        let half = ChunkRules.mergeCompounds([ChunkPart(text: "芒果", pos: "N", zhuyin: "ㄇㄤˊ ㄍㄨㄛˇ"), ChunkPart(text: "冰", pos: "N")],
                                             headword: "芒果")
        XCTAssertNil(half[0].zhuyin)
        XCTAssertNil(half[0].pinyin)
    }

    func testTidyKeepsTheReadingsOfUntouchedBlocks() {
        let parts = [ChunkPart(text: "點", pos: "V", pinyin: "diǎn", zhuyin: "ㄉㄧㄢˇ"),
                     ChunkPart(text: "鐵板麵", pos: "N", pinyin: "tiě bǎn miàn", zhuyin: "ㄊㄧㄝˇ ㄅㄢˇ ㄇㄧㄢˋ")]
        let tidy = ChunkRules.tidy(parts, headword: "鐵板麵", target: "zh-TW", reader: "ja")
        XCTAssertEqual(tidy.map(\.zhuyin), ["ㄉㄧㄢˇ", "ㄊㄧㄝˇ ㄅㄢˇ ㄇㄧㄢˋ"])
    }
}
