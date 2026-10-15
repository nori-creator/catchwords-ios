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
        {"etymology_diagram":{"kind":"compound","parts":[
            {"text":"曖","components":["日","愛"],"meaning":"日がかげる"},
            {"text":"昧","components":"日+未","meaning":"夜明け前"}],
          "result_meaning":"はっきり見えない","source":"","note":""}}
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
        let e = try extras(#"{"etymology_diagram":[{"char":"手","meaning":"て"},{"char":"機","components":["木","幾"]}]}"#)
        let d = try XCTUnwrap(e.etymologyDiagram?.drawable(for: "手機"))
        XCTAssertEqual(d.kind, .compound)
        XCTAssertEqual(d.word, "手機")
    }

    func testLoanwordGetsItsSound() throws {
        let e = try extras(#"{"etymology_diagram":{"kind":"loanword_phonetic","parts":[],"result_meaning":"","note":"英語 sofa の音から","source":"sofa"}}"#)
        let d = try XCTUnwrap(e.etymologyDiagram?.drawable(for: "沙發"))
        XCTAssertEqual(d.kind, .loanword)
        XCTAssertEqual(d.source, "sofa")
        XCTAssertEqual(d.word, "沙發")
        XCTAssertEqual(d.note, "英語 sofa の音から")
    }

    func testSingleCharacter() throws {
        let e = try extras(#"{"etymology_diagram":{"kind":"single_char","parts":[{"text":"山","components":["山"],"meaning":"山の形から"}],"note":"山の形"}}"#)
        let d = try XCTUnwrap(e.etymologyDiagram?.drawable(for: "山"))
        XCTAssertEqual(d.kind, .single)
        XCTAssertEqual(d.parts.map(\.char), ["山"])
    }

    func testNothingBrokenIsDrawn() throws {
        // Boxes with nothing under the character, a character that is not in the word, an empty loanword note.
        XCTAssertNil(try extras(#"{"etymology_diagram":{"kind":"compound","parts":[{"char":"曖"},{"char":"昧"}]}}"#)
            .etymologyDiagram?.drawable(for: "曖昧"))
        XCTAssertNil(try extras(#"{"etymology_diagram":{"parts":[{"char":"曖","meaning":"x"},{"char":"山","meaning":"y"}]}}"#)
            .etymologyDiagram?.drawable(for: "曖昧"))
        XCTAssertNil(try extras(#"{"etymology_diagram":{"kind":"loanword_phonetic","note":"","source":""}}"#)
            .etymologyDiagram?.drawable(for: "沙發"))
        XCTAssertNil(try extras(#"{"etymology_diagram":{"kind":"other","parts":[],"note":""}}"#)
            .etymologyDiagram?.drawable(for: "咖啡"))
        XCTAssertNil(try extras(#"{"etymology_diagram":null}"#).etymologyDiagram)
        // Not there, or not an object or a list: no diagram (the prose is shown), and the card still reads.
        let old = try extras(#"{"etymology":"曖は日と愛から。","etymology_diagram":"x"}"#)
        XCTAssertNil(old.etymologyDiagram)
        XCTAssertEqual(old.etymology, "曖は日と愛から。")
        XCTAssertNil(try extras(#"{"etymology":"x"}"#).etymologyDiagram)
    }

    func testOneExplainedCharacterOfACompoundIsItsBox() throws {
        let e = try extras(#"{"etymology_diagram":{"kind":"compound","parts":[{"char":"山","meaning":"やま"}]}}"#)
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

    func testBrandAndOtherShowTheirNote() throws {
        let brand = try extras(#"{"etymology_diagram":{"kind":"proper","parts":[],"note":"台湾のお菓子の商品名"}}"#)
        XCTAssertEqual(brand.etymologyDiagram?.drawable(for: "乖乖")?.kind, .proper)
        let other = try extras(#"{"etymology_diagram":{"kind":"other","parts":[],"note":"由来ははっきりしない"}}"#)
        XCTAssertEqual(other.etymologyDiagram?.drawable(for: "龜毛")?.kind, .other)
        // Broken boxes with a note to say: the note.
        let broken = try extras(#"{"etymology_diagram":{"kind":"compound","parts":[{"text":"曖"},{"text":"昧"}],"note":"二つの字から"}}"#)
        XCTAssertEqual(broken.etymologyDiagram?.drawable(for: "曖昧")?.kind, .other)
    }
}
