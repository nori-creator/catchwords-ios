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

    func testZhuyinSitsBesideEachCharacterLikeTheHeadword() {
        let part = ChunkPart(text: "鐵板麵", pos: "N", pinyin: "tiě bǎn miàn", zhuyin: "ㄊㄧㄝˇ ㄅㄢˇ ㄇㄧㄢˋ")
        XCTAssertEqual(ChunkLineView.sideZhuyin(for: part, target: "zh-TW", pref: "zhuyin"), "ㄊㄧㄝˇ ㄅㄢˇ ㄇㄧㄢˋ")
        // The headword's own pairing: one column per character, the tone beside it.
        let units = ZhuyinLayout.pair(part.text, ChunkLineView.sideZhuyin(for: part, target: "zh-TW", pref: "zhuyin"))
        XCTAssertEqual(units?.map(\.char), ["鐵", "板", "麵"])
        XCTAssertEqual(units?.map(\.tone), ["ˇ", "ˇ", "ˋ"])
        // Pinyin stays one line over the block.
        XCTAssertNil(ChunkLineView.sideZhuyin(for: part, target: "zh-TW", pref: "pinyin"))
        XCTAssertEqual(ChunkLineView.reading(for: part, target: "zh-TW", pref: "pinyin"), "tiě bǎn miàn")
        // Never on a Japanese or English chunk, nor without a zhuyin (pinyin only: its line over the block).
        XCTAssertNil(ChunkLineView.sideZhuyin(for: part, target: "ja", pref: "zhuyin"))
        XCTAssertNil(ChunkLineView.sideZhuyin(for: ChunkPart(text: "點", pos: "V", pinyin: "diǎn"), target: "zh-TW", pref: "zhuyin"))
        // A zhuyin that does not give one syllable per character keeps the line over the block.
        let odd = ChunkPart(text: "鐵板麵", pos: "N", zhuyin: "ㄊㄧㄝˇ ㄅㄢˇ")
        XCTAssertNil(ChunkLineView.sideZhuyin(for: odd, target: "zh-TW", pref: "zhuyin"))
        XCTAssertEqual(ChunkLineView.reading(for: odd, target: "zh-TW", pref: "zhuyin"), "ㄊㄧㄝˇ ㄅㄢˇ")
    }

    func testANeutralToneTheInserted很AndAMergedWordGetTheirZhuyinBeside() {
        let neutral = ChunkPart(text: "刷子", pos: "N", pinyin: "shuā zi", zhuyin: "ㄕㄨㄚ ˙ㄗ")
        let z = ChunkLineView.sideZhuyin(for: neutral, target: "zh-TW", pref: "zhuyin")
        XCTAssertEqual(z, "ㄕㄨㄚ ˙ㄗ")
        XCTAssertEqual(ZhuyinLayout.pair(neutral.text, z)?.map(\.neutral), [false, true])
        // 滷味＋入味 gets 很 with its reading (C8), drawn like the others.
        let withHen = ChunkRules.withDegree([ChunkPart(text: "滷味", pos: "N", zhuyin: "ㄌㄨˇ ㄨㄟˋ"),
                                             ChunkPart(text: "入味", pos: "Vs", zhuyin: "ㄖㄨˋ ㄨㄟˋ")])
        XCTAssertEqual(withHen.map(\.text), ["滷味", "很", "入味"])
        XCTAssertEqual(ChunkLineView.sideZhuyin(for: withHen[1], target: "zh-TW", pref: "zhuyin"), "ㄏㄣˇ")
        let merged = ChunkRules.mergeCompounds([ChunkPart(text: "芒果", pos: "N", zhuyin: "ㄇㄤˊ ㄍㄨㄛˇ"),
                                                ChunkPart(text: "冰", pos: "N", zhuyin: "ㄅㄧㄥ")], headword: "芒果")
        XCTAssertEqual(ChunkLineView.sideZhuyin(for: merged[0], target: "zh-TW", pref: "zhuyin"), "ㄇㄤˊ ㄍㄨㄛˇ ㄅㄧㄥ")
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

    func testSwapChoicesCarryTheirReadingsAndANeutralToneStaysAsSent() throws {
        let c = try chunk(#"{"parts":[{"text":"刷子","pos":"N","pinyin":"shuā zi","zhuyin":"ㄕㄨㄚ ˙ㄗ"},{"text":"鞋子","pos":"N","slot":true,"ja":"shoes","pinyin":"xié zi","zhuyin":"ㄒㄧㄝˊ ˙ㄗ","alts":[{"text":"地板","ja":"floor","pinyin":"dì bǎn","zhuyin":"ㄉㄧˋ ㄅㄢˇ"},{"text":"桌子","ja":"desk"}]}],"ja":"x"}"#)
        XCTAssertEqual(c.parts[0].zhuyin, "ㄕㄨㄚ ˙ㄗ")
        XCTAssertEqual(ChunkLineView.reading(for: c.parts[0], target: "zh-TW", pref: "zhuyin"), "ㄕㄨㄚ ˙ㄗ")
        XCTAssertEqual(ChunkLineView.reading(for: c.parts[0], target: "zh-TW", pref: "pinyin"), "shuā zi")
        let alts = c.parts[1].alts ?? []
        XCTAssertEqual(alts.count, 2)
        XCTAssertEqual(alts[0].zhuyin, "ㄉㄧˋ ㄅㄢˇ")
        XCTAssertEqual(alts[0].pinyin, "dì bǎn")
        XCTAssertNil(alts[1].zhuyin, "an old alt has no reading")
    }

    /// A chunk shrinks to stay on one line (owner 2026-10-16), never under 80% and never a hanzi under 15 pt.
    func testChunkShrinksToALimitBeforeWrapping() {
        let large = ChunkLineView.fitScales(base: 20)
        XCTAssertEqual(large.first, 1)
        XCTAssertEqual(large.last ?? 0, 0.8, accuracy: 0.001)
        XCTAssertEqual(large, large.sorted(by: >), "largest first")
        XCTAssertGreaterThanOrEqual(20 * (large.last ?? 0), 15)
        let mid = ChunkLineView.fitScales(base: 17)
        XCTAssertEqual(17 * (mid.last ?? 0), 15, accuracy: 0.01)
        XCTAssertEqual(ChunkLineView.fitScales(base: 15), [1], "a compact chunk is at 15 pt already: it only wraps")
        XCTAssertEqual(ChunkLineView.fitScales(base: 40).last ?? 0, 0.8, accuracy: 0.001)
    }

    /// The colour of each server POS (owner 2026-10-22: 「品詞をより高い精度に」): 助詞 (Ptc) and 接続詞 (Conj) were drawn
    /// as 名詞, and the old cards' role C (接続・介詞) as 状態動詞.
    func testEachPartOfSpeechHasItsColour() {
        XCTAssertEqual(ChunkKind(pos: "Prep"), .particle, "用 in 用＋湯匙＋吃飯 (教育部 [介], TBCL Prep)")
        XCTAssertEqual(ChunkKind(pos: "Ptc"), .particle, "的・了・嗎・把")
        XCTAssertEqual(ChunkKind(pos: "Conj"), .particle)
        XCTAssertEqual(ChunkKind(pos: "C"), .particle, "the old role code 接続・介詞, as on the web")
        XCTAssertEqual(ChunkKind(pos: "Det"), .particle)
        XCTAssertEqual(ChunkKind(pos: "V"), .verb)
        XCTAssertEqual(ChunkKind(pos: "Vi"), .verb)
        XCTAssertEqual(ChunkKind(pos: "V-sep"), .verb)
        XCTAssertEqual(ChunkKind(pos: "Vaux"), .verb)
        XCTAssertEqual(ChunkKind(pos: "Vs"), .stative)
        XCTAssertEqual(ChunkKind(pos: "Vs-attr"), .stative)
        XCTAssertEqual(ChunkKind(pos: "Vst"), .stative)
        XCTAssertEqual(ChunkKind(pos: "Adv"), .adverb)
        XCTAssertEqual(ChunkKind(pos: "N"), .noun)
        XCTAssertEqual(ChunkKind(pos: "S"), .noun, "the old role code 主語")
        XCTAssertEqual(ChunkKind(pos: "O"), .noun, "the old role code 目的語")
    }
}
