import XCTest
@testable import CatchWords

/// しらべる (the dictionary): the server's answer reads whatever it has, and the learner's own words match what is typed.
final class LookupTests: XCTestCase {
    func testAnEntryThatDoesNotReadIsDroppedNotTheAnswer() throws {
        let json = #"""
        {"query":"傘","mode":"display","entries":[
          {"headword":"雨傘","pinyin":"yǔ sǎn","reading_zhuyin":"ㄩˇ ㄙㄢˇ","gloss":"傘","senses":["雨がさ"],"proper":false,
           "usage":"everyday","nuance":"","chars":[{"char":"雨","pinyin":"yǔ","meaning":"あめ"},{"char":"傘","pinyin":"sǎn","meaning":"かさ"}],
           "why":"雨をよける傘","example":"外面下雨，記得帶雨傘。","example_translation":"外は雨だから、傘を忘れずに。",
           "image_query":"umbrella","category_key":"daily"},
          {"headword":42},
          {"gloss":"見出しが無い"},
          {"headword":"陽傘","gloss":"日傘"}
        ]}
        """#
        let r = try JSONDecoder().decode(LookupResult.self, from: Data(json.utf8))
        XCTAssertEqual(r.entries.map(\.headword), ["雨傘", "陽傘"])
        let first = try XCTUnwrap(r.entries.first)
        XCTAssertEqual(first.chars.map(\.char), ["雨", "傘"])
        XCTAssertEqual(first.exampleTranslation, "外は雨だから、傘を忘れずに。")
        // A field the server did not send reads as empty, never as a failure.
        XCTAssertEqual(r.entries[1].chars, [])
        XCTAssertEqual(r.entries[1].usageLabel, nil)
    }

    func testAnAnswerWithoutEntriesReadsAsNone() throws {
        let r = try JSONDecoder().decode(LookupResult.self, from: Data(#"{"query":"x"}"#.utf8))
        XCTAssertEqual(r.entries, [])
        XCTAssertEqual(r.mode, "display")
    }

    func testTheCandidateKeepsTheHeadwordAndItsReading() {
        let e = LookupEntry(headword: "雨傘", pinyin: "yǔ sǎn", zhuyin: "ㄩˇ ㄙㄢˇ", gloss: "傘", proper: true, categoryKey: "daily")
        let c = e.candidate
        XCTAssertEqual(c.headword, "雨傘")
        XCTAssertEqual(c.zhuyin, "ㄩˇ ㄙㄢˇ")
        XCTAssertEqual(c.pinyin, "yǔ sǎn")
        XCTAssertEqual(c.register, "proper")
        XCTAssertEqual(c.categoryKey, "daily")
    }

    func testAReadingWithoutTonesMatches() {
        XCTAssertEqual(LookupMatch.plainReading("yǔ sǎn"), "yusan")
        XCTAssertEqual(LookupMatch.plainReading("Zhé dié sǎn"), "zhediesan")
    }

    func testOwnWordsMatchTheHeadwordFirst() throws {
        func sticker(_ id: String, _ head: String, _ meaning: String, _ pinyin: String) throws -> Sticker {
            let word = #"{"id":"w\#(id)","headword":"\#(head)","meaning_ja":"\#(meaning)","pinyin":"\#(pinyin)","language":"zh-TW"}"#
            let json = #"{"id":"\#(id)","word_id":"w\#(id)","taken_at":"2026-11-08T00:00:00Z","capture_type":"text","word":\#(word)}"#
            return try SupabaseDate.decoder.decode(Sticker.self, from: Data(json.utf8))
        }
        let list = [
            try sticker("1", "陽傘", "日傘", "yáng sǎn"),
            try sticker("2", "雨傘", "傘", "yǔ sǎn"),
            try sticker("3", "芒果", "マンゴー", "máng guǒ"),
        ]
        XCTAssertEqual(LookupMatch.own(list, query: "雨傘").map { $0.word?.headword }, ["雨傘"])
        XCTAssertEqual(LookupMatch.own(list, query: "yusan").map { $0.word?.headword }, ["雨傘"])
        XCTAssertEqual(LookupMatch.own(list, query: "マンゴー").map { $0.word?.headword }, ["芒果"])
        // 傘 is in two headwords: both, in the dex's order.
        XCTAssertEqual(LookupMatch.own(list, query: "傘").map { $0.word?.headword }, ["陽傘", "雨傘"])
        XCTAssertEqual(LookupMatch.own(list, query: "  "), [])
    }

    func testALookedUpWordWithoutAPhotoStaysOffTheAlbum() throws {
        let json = #"{"id":"s1","word_id":"w1","taken_at":"2026-11-08T00:00:00Z","capture_type":"text"}"#
        let s = try SupabaseDate.decoder.decode(Sticker.self, from: Data(json.utf8))
        XCTAssertTrue(DexStore.isLookupOnly(s))
        var withPhoto = s
        withPhoto.cutoutImageUrl = "u/1-cutout.png"
        XCTAssertFalse(DexStore.isLookupOnly(withPhoto))
    }
}
