import XCTest
@testable import CatchWords

/// The word page's prose drawn one sentence per row (Utilities/Sentences.swift, owner 2026-10-14 / 2026-10-15).
/// Run on its own by .github/workflows/ios-check.yml.
final class SentencesTests: XCTestCase {
    func testJapaneseAndChineseEndings() {
        XCTAssertEqual(Sentences.split("舌を上げる。息を強く出す！\n部首: 木"), ["舌を上げる。", "息を強く出す！", "部首: 木"])
        XCTAssertEqual(Sentences.split("本当！？うそ。"), ["本当！？", "うそ。"])
        XCTAssertEqual(Sentences.split("一聲是高平調。二聲往上揚？對。"), ["一聲是高平調。", "二聲往上揚？", "對。"])
        XCTAssertEqual(Sentences.split("すごい!次はこれ。"), ["すごい!", "次はこれ。"])
    }

    func testQuotesAndBracketsStayInTheirSentence() {
        XCTAssertEqual(Sentences.split("「好吃。」と言う。次"), ["「好吃。」と言う。", "次"])
        XCTAssertEqual(Sentences.split("他說：「好。」然後走了。"), ["他說：「好。」然後走了。"])
        XCTAssertEqual(Sentences.split("台湾では（例：好。）と書く。次の文。"), ["台湾では（例：好。）と書く。", "次の文。"])
        XCTAssertEqual(Sentences.split("He said \"Hi.\" Then he left."), ["He said \"Hi.\"", "Then he left."])
        XCTAssertEqual(Sentences.split("(See above.) Next one."), ["(See above.)", "Next one."])
        XCTAssertEqual(Sentences.split("Don't stop. It's fine."), ["Don't stop.", "It's fine."])
        // A bracket that is never closed does not swallow the rest.
        XCTAssertEqual(Sentences.split("閉じない「かっこ。次の文。"), ["閉じない「かっこ。", "次の文。"])
    }

    func testEnglishPeriodsThatDoNotEndASentence() {
        XCTAssertEqual(Sentences.split("Stress the first syllable. Then relax."), ["Stress the first syllable.", "Then relax."])
        XCTAssertEqual(Sentences.split("Mr. Smith is 3.5 m tall. Really?! Yes."), ["Mr. Smith is 3.5 m tall.", "Really?!", "Yes."])
        XCTAssertEqual(Sentences.split("e.g. apples, i.e. fruit. Next."), ["e.g. apples, i.e. fruit.", "Next."])
        XCTAssertEqual(Sentences.split("See No. 5 for details. Done."), ["See No. 5 for details.", "Done."])
        XCTAssertEqual(Sentences.split("J. K. Rowling wrote it. So did I. Then we left."),
                       ["J. K. Rowling wrote it.", "So did I.", "Then we left."])
        XCTAssertEqual(Sentences.split("apples, pears, etc. are fruit."), ["apples, pears, etc. are fruit."])
        XCTAssertEqual(Sentences.split("Wait... and then. Wait... Then it rained."), ["Wait... and then.", "Wait...", "Then it rained."])
        XCTAssertEqual(Sentences.split("Yahoo!知恵袋で見る。"), ["Yahoo!知恵袋で見る。"])
    }

    func testEmptyAndWhitespace() {
        XCTAssertEqual(Sentences.split("  "), [])
        XCTAssertEqual(Sentences.split("\n\n文。\r\n"), ["文。"])
        XCTAssertEqual(Sentences.split("最後に句点なし"), ["最後に句点なし"])
    }

    /// The owner's sentence may break between any two characters, but never before 。 or a small kana.
    func testWrappableAddsBreaksBetweenLettersOnly() {
        let zw: Character = "\u{200B}"
        let s = Sentences.wrappable("意識しましょう。")
        XCTAssertEqual(s.filter { $0 != zw }, "意識しましょう。")
        XCTAssertFalse(s.contains("\u{200B}。"))
        XCTAssertFalse(s.contains("\u{200B}ょ"))
        XCTAssertTrue(s.contains("識\u{200B}し"))
        XCTAssertEqual(Sentences.wrappable("Stress the first syllable."), "Stress the first syllable.")
        XCTAssertFalse(Sentences.wrappable("「好」").contains(zw))
    }

    /// The word page keeps its own name for the splitter (the earlier test calls it).
    @MainActor
    func testWordDetailUsesTheSameSplitter() {
        XCTAssertEqual(WordDetailView.sentences("A. B."), Sentences.split("A. B."))
    }
}
