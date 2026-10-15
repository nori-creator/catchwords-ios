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
}
