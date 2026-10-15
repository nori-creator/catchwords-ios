import XCTest
@testable import CatchWords

/// Examples written by usage pattern (server PR nori-creator/Lovable-catch-words-app#182): the scene label shows only
/// over the sentence it was written for, and a word with one usage pattern has no 「追加の例文」 to fill.
/// Run on its own by .github/workflows/ios-check.yml.
final class ExampleSceneTests: XCTestCase {
    private func extras(_ json: String) throws -> WordExtras {
        try JSONDecoder().decode(WordExtras.self, from: Data(json.utf8))
    }

    func testLabelShownOverItsOwnSentence() throws {
        let e = try extras(#"{"example_scene":"家族に眼鏡をどこに置いたか聞かれたとき","example_scene_for":"我 戴眼鏡！"}"#)
        // Spaces and punctuation do not count.
        XCTAssertEqual(e.shownExampleScene(for: "我戴眼鏡。"), "家族に眼鏡をどこに置いたか聞かれたとき")
    }

    func testLabelHiddenOverAnotherSentence() throws {
        let e = try extras(#"{"example_scene":"友達が眼鏡をしていないことに気づいたとき","example_scene_for":"你今天沒戴眼鏡嗎？"}"#)
        XCTAssertNil(e.shownExampleScene(for: "我戴眼鏡。"))
    }

    func testOldLabelWithoutMarkIsHidden() throws {
        let e = try extras(#"{"example_scene":"友達が眼鏡をしていないことに気づいたとき"}"#)
        XCTAssertNil(e.shownExampleScene(for: "我戴眼鏡。"))
        let blank = try extras(#"{"example_scene":"友達が眼鏡をしていないことに気づいたとき","example_scene_for":"  "}"#)
        XCTAssertNil(blank.shownExampleScene(for: "我戴眼鏡。"))
        let noScene = try extras(#"{"example_scene":"","example_scene_for":"我戴眼鏡。"}"#)
        XCTAssertNil(noScene.shownExampleScene(for: "我戴眼鏡。"))
    }

    func testNewFieldsDecodeLeniently() throws {
        let e = try extras(#"{"example_v":2,"example_pattern_count":"1","example_scene_for":"我戴眼鏡。"}"#)
        XCTAssertEqual(e.exampleV, 2)
        XCTAssertEqual(e.examplePatternCount, 1)
        XCTAssertEqual(e.exampleSceneFor, "我戴眼鏡。")
        let nulls = try extras(#"{"example_v":null,"example_pattern_count":null,"example_scene_for":null}"#)
        XCTAssertNil(nulls.exampleV)
        XCTAssertNil(nulls.examplePatternCount)
        XCTAssertNil(nulls.exampleSceneFor)
        let old = try extras(#"{"mnemonic":"x"}"#)
        XCTAssertNil(old.examplePatternCount)
        XCTAssertEqual(try extras(#"{"example_pattern_count":3.0}"#).examplePatternCount, 3)
        XCTAssertNil(try extras(#"{"example_pattern_count":"many"}"#).examplePatternCount)
    }

    /// One usage pattern: the empty 「追加の例文」 is complete, so the word page never asks the server to fill it.
    @MainActor
    func testOnePatternSkipsTheExamplesFill() throws {
        let one = try extras(#"{"example_pattern_count":1,"examples_extra":[]}"#)
        XCTAssertTrue(one.examplesExtraComplete)
        XCTAssertFalse(WordDetailView.wantsAutoFill(.examplesExtra, extras: one))
        // Other sections are still filled, and more patterns (or an older card) still fill the examples.
        XCTAssertTrue(WordDetailView.wantsAutoFill(.usageChunks, extras: one))
        // 発音のコツ and 覚え方 are off the page: never filled (owner 2026-10-15).
        XCTAssertFalse(WordDetailView.wantsAutoFill(.mnemonic, extras: one))
        XCTAssertFalse(WordDetailView.wantsAutoFill(.pronunciationTips, extras: nil))
        XCTAssertFalse(WordDetailView.wantsAutoFill(.webImages, extras: nil))
        let three = try extras(#"{"example_pattern_count":3}"#)
        XCTAssertTrue(WordDetailView.wantsAutoFill(.examplesExtra, extras: three))
        XCTAssertTrue(WordDetailView.wantsAutoFill(.examplesExtra, extras: try extras("{}")))
        XCTAssertTrue(WordDetailView.wantsAutoFill(.examplesExtra, extras: nil))
    }

    /// 「例文」 lists every usage pattern's example (owner 2026-10-15): the main one, then examples_extra, each with
    /// its own label only when that label was written for it.
    func testAllPatternsInOneSection() throws {
        let e = try extras(#"""
        {"example_scene":"朝ごはんを頼むとき","example_scene_for":"我要一份鐵板麵。","example_pattern_count":3,
         "examples_extra":[{"zh":"這家的鐵板麵很好吃。","ja":"この店の鉄板麺はおいしい。","scene":"友達にすすめるとき","scene_for":"這家的鐵板麵很好吃！"},
                           {"zh":"鐵板麵要加蛋嗎？","ja":"卵をのせますか？","scene":"店員に聞かれたとき"},
                           {"zh":"我要一份鐵板麵","ja":"同じ文"},
                           {"zh":"Teppan noodles","ja":"英語"}]}
        """#)
        let all = ExampleItem.all(sentence: "我要一份鐵板麵。", translation: "鉄板麺をひとつください。", extras: e, target: "zh-TW")
        XCTAssertEqual(all.map(\.sentence), ["我要一份鐵板麵。", "這家的鐵板麵很好吃。", "鐵板麵要加蛋嗎？"])
        XCTAssertEqual(all.map(\.scene), ["朝ごはんを頼むとき", "友達にすすめるとき", nil])
        XCTAssertEqual(all[1].translation, "この店の鉄板麺はおいしい。")
    }

    func testExtraLabelForAnotherSentenceIsHidden() throws {
        let e = try extras(#"{"examples_extra":[{"zh":"鐵板麵要加蛋嗎？","scene":"友達にすすめるとき","scene_for":"這家的鐵板麵很好吃。"}]}"#)
        let all = ExampleItem.all(sentence: nil, translation: nil, extras: e, target: "zh-TW")
        XCTAssertEqual(all.map(\.sentence), ["鐵板麵要加蛋嗎？"])
        XCTAssertNil(all[0].scene)
    }

    func testOnePatternShowsOneExample() throws {
        let e = try extras(#"{"example_pattern_count":1,"examples_extra":[{"zh":"這家的鐵板麵很好吃。"}]}"#)
        let all = ExampleItem.all(sentence: "我要一份鐵板麵。", translation: nil, extras: e, target: "zh-TW")
        XCTAssertEqual(all.map(\.sentence), ["我要一份鐵板麵。"])
    }
}
