import XCTest
@testable import CatchWords

/// Every candidate says what kind of name it is, and the everyday name comes first (owner 2026-10-15; server
/// candidate-register.ts). Run on its own by .github/workflows/ios-check.yml.
@MainActor
final class NameRegisterTests: XCTestCase {
    private func word(_ head: String, _ register: String?, group: Int? = 0) -> Candidate {
        Candidate(kind: "object", headword: head, zhuyin: "", pinyin: "", meaningJa: "", pos: "N", point: [500, 500],
                  confidence: 0.9, alternatives: [], register: register, group: group)
    }

    func testFiveValuesAndOlderOnesAreRead() {
        XCTAssertEqual(NameRegister.normalize("common"), .common)
        XCTAssertEqual(NameRegister.normalize(" Colloquial "), .colloquial)
        XCTAssertEqual(NameRegister.normalize("specific"), .specific)
        XCTAssertEqual(NameRegister.normalize("academic"), .academic)
        XCTAssertEqual(NameRegister.normalize("proper"), .proper)
        // A photo's older `casual`.
        XCTAssertEqual(NameRegister.normalize("casual"), .colloquial)
        // A typed word's older style values are never a register (server #183 moved them to `style`).
        for style in ["spoken", "written", "both", "technical", "signage"] {
            XCTAssertNil(NameRegister.normalize(style), style)
        }
        XCTAssertNil(NameRegister.normalize(nil))
        XCTAssertNil(NameRegister.normalize(""))
        XCTAssertNil(NameRegister.normalize("whatever"))
    }

    func testOrderIsEverydayFirstThenNarrower() {
        let list = [word("女王頭", "proper"), word("學名", "academic"), word("四角褲", "specific"), word("內褲", "common"),
                    word("小褲褲", "colloquial")]
        let out = NameRegister.finalized(list)
        XCTAssertEqual(out.map(\.headword), ["內褲", "小褲褲", "四角褲", "學名", "女王頭"])
        XCTAssertEqual(out.map { NameRegister.of($0) }, [.common, .colloquial, .specific, .academic, .proper])
    }

    func testSameRegisterKeepsServerOrder() {
        let out = NameRegister.finalized([word("平口褲", "specific"), word("內褲", "common"), word("四角褲", "specific")])
        XCTAssertEqual(out.map(\.headword), ["內褲", "平口褲", "四角褲"])
    }

    func testMissingRegistersAreFilledSoEveryRowHasALabel() {
        // ボクサーパンツ typed: the older server sent a style in `register` (spoken / written), or nothing.
        let out = NameRegister.finalized([word("平口褲", "spoken"), word("四角褲", nil), word("內褲", "written")])
        XCTAssertEqual(out.map(\.headword), ["平口褲", "四角褲", "內褲"])
        XCTAssertEqual(out.map(\.register), ["common", "specific", "specific"])
    }

    func testTypedWordsDecodeWithTheirRegister() throws {
        let json = #"{"candidates":[{"headword":"內褲","register":"common","style":"spoken"},"#
            + #"{"headword":"四角褲","register":"specific","style":"both"},{"headword":"平口褲","register":"specific"}]}"#
        struct Res: Decodable { let candidates: [Candidate] }
        let list = try JSONDecoder().decode(Res.self, from: Data(json.utf8)).candidates
        XCTAssertEqual(NameRegister.finalized(list).map { NameRegister.of($0) }, [.common, .specific, .specific])
    }

    /// The typed search's answer (server #185): every name carries its register, its category, its short meaning
    /// (`gloss`) and the typed thing's name (`object_label`) — 犬 typed in Japanese lists 狗 first and 犬 only as a marked
    /// name. A name that does not read is dropped without losing the others; nothing is rewritten (the row shows the
    /// gloss, the meaning kept is the server's), and a word saved before its card lands on its own category's shelf.
    func testTypedAnswerReadsEveryNewField() throws {
        let saved = L10n.lang
        defer { L10n.lang = saved }
        L10n.lang = "ja"
        let json = #"""
        {"query_is_target": false, "query_lang": "display", "object_label": "犬", "candidates": [
          {"headword": "狗", "reading_zhuyin": "ㄍㄡˇ", "pinyin": "gǒu", "meaning_ja": "犬、イヌ", "distinction": "",
           "register": "common", "style": "spoken", "scene": "", "usage": "common", "image_query": "dog",
           "category_key": "animal", "gloss": "犬", "object_label": "犬"},
          {"headword": "", "meaning_ja": "読めない候補"},
          {"headword": "犬", "reading_zhuyin": "ㄑㄩㄢˇ", "pinyin": "quǎn", "meaning_ja": "犬（警犬・導盲犬などの複合語で）",
           "register": "academic", "style": "technical", "category_key": "animal", "gloss": "犬", "object_label": "犬"}
        ]}
        """#
        let res = try JSONDecoder().decode(AIService.WordCandidates.self, from: Data(json.utf8))
        XCTAssertEqual(res.queryLang, "display")
        XCTAssertEqual(res.objectLabel, "犬")
        let list = res.candidates
        XCTAssertEqual(list.map(\.headword), ["狗", "犬"])
        XCTAssertEqual(list.map(\.zhuyin), ["ㄍㄡˇ", "ㄑㄩㄢˇ"])
        XCTAssertEqual(list.map(\.objectLabel), ["犬", "犬"])
        XCTAssertEqual(NameRegister.finalized(list).map { NameRegister.of($0) }, [.common, .academic])
        XCTAssertEqual(list.map(\.shownMeaning), ["犬", "犬"])
        XCTAssertEqual(list[1].meaningJa, "犬（警犬・導盲犬などの複合語で）")
        XCTAssertEqual(list.map(\.categoryKey), ["animal", "animal"])
        // 犬 has no headword rule: its shelf is the category it came with.
        XCTAssertEqual(CategoryRules.normalize(headword: list[1].headword, key: list[1].categoryKey), "animal")
        // Kept with a 「保存待ち」 catch: the gloss survives the trip to the phone's storage.
        let back = try JSONDecoder().decode(Candidate.self, from: JSONEncoder().encode(list[0]))
        XCTAssertEqual(back.gloss, "犬")
        XCTAssertEqual(back.categoryKey, "animal")
    }

    func testFirstNameIsAlwaysEveryday() {
        // No common name: the first name that is not a proper noun is the tag, as the common name.
        let out = NameRegister.finalized([word("愛文芒果", "specific"), word("芒果冰", "proper"), word("檨仔", "colloquial")])
        XCTAssertEqual(out.first?.headword, "檨仔")
        XCTAssertEqual(out.first.map { NameRegister.of($0) }, .common)
        XCTAssertEqual(out.map(\.headword), ["檨仔", "愛文芒果", "芒果冰"])
        // Only proper nouns: left as they are.
        let brands = NameRegister.finalized([word("女王頭", "proper"), word("101", "proper")])
        XCTAssertEqual(brands.map(\.headword), ["女王頭", "101"])
        XCTAssertEqual(brands.map { NameRegister.of($0) }, [.proper, .proper])
    }

    func testLabelsAreTheOwnersWords() {
        let saved = L10n.lang
        defer { L10n.lang = saved }
        L10n.lang = "ja"
        XCTAssertEqual(NameRegister.allCases.map(\.label), ["一般的な言い方", "口語", "より詳しい言い方", "学術的な言い方", "固有名詞"])
        L10n.lang = "en"
        XCTAssertEqual(NameRegister.allCases.map(\.label), ["Common", "Casual", "More specific", "Technical", "Proper noun"])
        L10n.lang = "zh-TW"
        XCTAssertEqual(NameRegister.allCases.map(\.label), ["常用說法", "口語", "更精確的說法", "學術說法", "專有名詞"])
    }

    /// The tag on the photo is the everyday name's meaning in the reader's language (owner 2026-10-15: boxer briefs →
    /// 「下着」, the meaning of 內褲), never a more specific name's meaning and never the learning-language word.
    func testCameraTagIsTheEverydayNamesMeaning() {
        let saved = L10n.lang
        defer { L10n.lang = saved }
        L10n.lang = "ja"
        func named(_ head: String, _ register: String?, _ meaning: String, category: String? = nil) -> Candidate {
            Candidate(kind: "object", headword: head, zhuyin: "", pinyin: "", meaningJa: meaning, pos: "N", point: [500, 500],
                      confidence: 0.9, alternatives: [], register: register, group: 0, categoryKey: category)
        }
        let boxers = NameRegister.finalized([named("平口褲", "specific", "ボクサーパンツ"), named("內褲", "common", "下着"),
                                             named("四角褲", "specific", "トランクス")])
        XCTAssertEqual(boxers.map(\.headword), ["內褲", "平口褲", "四角褲"])
        XCTAssertEqual(CandidatePickerView.tagLabel(boxers).text, "下着")
        XCTAssertTrue(CandidatePickerView.tagLabel(boxers).isName)
        // No meaning in the reader's language: the thing's category, never the headword (and never merged).
        let bare = NameRegister.finalized([named("內褲", "common", "", category: "clothes"), named("四角褲", "specific", "")])
        let tag = CandidatePickerView.tagLabel(bare)
        XCTAssertEqual(tag.text, L("服"))
        XCTAssertFalse(tag.isName)
        XCTAssertNotEqual(tag.text, "內褲")
    }

    /// The server's `object_label` (server #184) is the tag when it is there; empty (an older server), the first gloss
    /// of the common name's meaning.
    func testCameraTagUsesTheServersObjectLabel() throws {
        let saved = L10n.lang
        defer { L10n.lang = saved }
        L10n.lang = "ja"
        struct Res: Decodable { let suggestions: [Candidate] }
        let withLabel = #"{"suggestions":["#
            + #"{"headword":"內褲","meaning_ja":"下着（パンツ類）","register":"common","group":0,"object_label":"下着"},"#
            + #"{"headword":"平口褲","meaning_ja":"ボクサーパンツ","register":"specific","group":0,"object_label":"下着"}]}"#
        let labelled = try JSONDecoder().decode(Res.self, from: Data(withLabel.utf8)).suggestions
        XCTAssertEqual(labelled.map(\.objectLabel), ["下着", "下着"])
        XCTAssertEqual(CandidatePickerView.tagLabel(NameRegister.finalized(labelled)).text, "下着")

        let older = #"{"suggestions":["#
            + #"{"headword":"平口褲","meaning_ja":"ボクサーパンツ","register":"specific","group":0,"object_label":""},"#
            + #"{"headword":"內褲","meaning_ja":"下着、パンツ","register":"common","group":0}]}"#
        let plain = try JSONDecoder().decode(Res.self, from: Data(older.utf8)).suggestions
        XCTAssertEqual(plain.map(\.objectLabel), ["", ""])
        let tag = CandidatePickerView.tagLabel(NameRegister.finalized(plain))
        XCTAssertEqual(tag.text, "下着")
        XCTAssertTrue(tag.isName)
    }
}
