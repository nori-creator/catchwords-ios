import XCTest
@testable import CatchWords

/// 語源・部首 as boxes (owner 2026-10-15): read leniently from the card, and never an empty or broken diagram — a word
/// that cannot be taken apart gets one character's box or where its sound came from instead.
/// Run on its own by .github/workflows/ios-check.yml.
final class EtymologyDiagramTests: XCTestCase {
    private func extras(_ json: String) throws -> WordExtras {
        try JSONDecoder().decode(WordExtras.self, from: Data(json.utf8))
    }

    func testCompoundWord() throws {
        let e = try extras(#"""
        {"etymology_parts":{"kind":"compound","parts":[
            {"char":"曖","components":["日","愛"],"meaning":"日がかげる"},
            {"char":"昧","components":"日+未","meaning":"夜明け前"}],
          "result":{"word":"曖昧","meaning":"はっきり見えない"}}}
        """#)
        let d = try XCTUnwrap(e.etymologyDiagram?.drawable(for: "曖昧"))
        XCTAssertEqual(d.kind, .compound)
        XCTAssertEqual(d.parts.map(\.char), ["曖", "昧"])
        XCTAssertEqual(d.parts.map(\.components), [["日", "愛"], ["日", "未"]])
        XCTAssertEqual(d.parts.map(\.meaning), ["日がかげる", "夜明け前"])
        XCTAssertEqual(d.word, "曖昧")
        XCTAssertEqual(d.meaning, "はっきり見えない")
    }

    func testWordDefaultsToTheHeadword() throws {
        let e = try extras(#"{"etymology_parts":[{"char":"手","meaning":"て"},{"char":"機","components":["木","幾"]}]}"#)
        let d = try XCTUnwrap(e.etymologyDiagram?.drawable(for: "手機"))
        XCTAssertEqual(d.kind, .compound)
        XCTAssertEqual(d.word, "手機")
    }

    func testLoanwordGetsItsSound() throws {
        let e = try extras(#"{"etymology_parts":{"kind":"loanword","note":"英語 sofa の音から","source":"sofa"}}"#)
        let d = try XCTUnwrap(e.etymologyDiagram?.drawable(for: "沙發"))
        XCTAssertEqual(d.kind, .phonetic)
        XCTAssertEqual(d.word, "沙發")
        XCTAssertEqual(d.note, "英語 sofa の音から")
    }

    func testSingleCharacter() throws {
        let e = try extras(#"{"etymology_parts":{"kind":"single","parts":[{"char":"山","components":["山"],"meaning":"山の形から"}]}}"#)
        let d = try XCTUnwrap(e.etymologyDiagram?.drawable(for: "山"))
        XCTAssertEqual(d.kind, .single)
        XCTAssertEqual(d.parts.map(\.char), ["山"])
    }

    func testNothingBrokenIsDrawn() throws {
        // Boxes with nothing under the character, a character that is not in the word, an empty loanword note.
        XCTAssertNil(try extras(#"{"etymology_parts":{"kind":"compound","parts":[{"char":"曖"},{"char":"昧"}]}}"#)
            .etymologyDiagram?.drawable(for: "曖昧"))
        XCTAssertNil(try extras(#"{"etymology_parts":{"parts":[{"char":"曖","meaning":"x"},{"char":"山","meaning":"y"}]}}"#)
            .etymologyDiagram?.drawable(for: "曖昧"))
        XCTAssertNil(try extras(#"{"etymology_parts":{"kind":"loanword","note":"","source":""}}"#)
            .etymologyDiagram?.drawable(for: "沙發"))
        // Not there, or not an object or a list: no diagram (the prose is shown), and the card still reads.
        let old = try extras(#"{"etymology":"曖は日と愛から。","etymology_parts":"x"}"#)
        XCTAssertNil(old.etymologyDiagram)
        XCTAssertEqual(old.etymology, "曖は日と愛から。")
        XCTAssertNil(try extras(#"{"etymology":"x"}"#).etymologyDiagram)
    }

    func testOneExplainedCharacterOfACompoundIsItsBox() throws {
        let e = try extras(#"{"etymology_parts":{"kind":"compound","parts":[{"char":"山","meaning":"やま"}]}}"#)
        XCTAssertEqual(e.etymologyDiagram?.drawable(for: "山")?.kind, .single)
    }

    func testReaderLanguageTextsAreScrubbed() {
        let d = EtymologyDiagram(kind: .compound,
                                 parts: [.init(char: "曖", components: ["日", "愛"], meaning: "sun hidden"),
                                         .init(char: "昧", components: ["日", "未"], meaning: "夜明け前")],
                                 word: "曖昧", meaning: "unclear", note: "")
        let ja = d.scrubbed { LanguageRules.looksWrong($0, reader: "ja", hanOnlyOk: true) }
        XCTAssertEqual(ja.parts.map(\.meaning), ["", "夜明け前"])
        XCTAssertEqual(ja.meaning, "")
    }
}
