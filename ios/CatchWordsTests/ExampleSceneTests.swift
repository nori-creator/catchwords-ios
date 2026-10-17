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

    /// Nothing ever fetches extra examples on its own (owner 2026-10-15): 「例文」 shows the examples the card came with,
    /// whatever its pattern count. Other empty sections are still filled.
    @MainActor
    func testExtraExamplesAreNeverFetchedOnTheirOwn() throws {
        let one = try extras(#"{"example_pattern_count":1,"examples_extra":[]}"#)
        XCTAssertTrue(one.examplesExtraComplete)
        let three = try extras(#"{"example_pattern_count":3}"#)
        let old = try extras("{}")
        for e in [one, three, old, nil] as [WordExtras?] {
            XCTAssertFalse(WordDetailView.wantsAutoFill(.examplesExtra, extras: e))
        }
        XCTAssertTrue(DexStore.retiredSections.contains("examples_extra"))
        XCTAssertTrue(WordDetailView.wantsAutoFill(.usageChunks, extras: one))
        // 発音のコツ・覚え方・ネットの画像 are off the page: never filled (owner 2026-10-15).
        XCTAssertFalse(WordDetailView.wantsAutoFill(.mnemonic, extras: one))
        XCTAssertFalse(WordDetailView.wantsAutoFill(.pronunciationTips, extras: nil))
        XCTAssertFalse(WordDetailView.wantsAutoFill(.webImages, extras: nil))
    }

    /// 語源・部首 is gone from the word page (owner 2026-10-15; the server stops writing it): never a section, never
    /// asked for, and an older card that still carries it (prose, radicals, the boxes of #183) reads as before.
    @MainActor
    func testEtymologyIsGoneButOldCardsStillRead() throws {
        for lang in ["zh-TW", "en", "ja"] {
            XCTAssertFalse(CardSection.sections(for: lang).contains(.etymology), lang)
            XCTAssertFalse(CardSection.defaultOrder(for: lang).contains(.etymology), lang)
        }
        XCTAssertTrue(CardSection.etymology.isRemoved)
        XCTAssertFalse(WordDetailView.wantsAutoFill(.etymology, extras: nil))
        for section in ["etymology", "etymology_diagram", "radicals", "pronunciation_tips", "mnemonic"] {
            XCTAssertTrue(DexStore.retiredSections.contains(section), section)
        }
        let old = try extras(#"""
        {"etymology":"どちらの字も「日」が付きます。","radicals":"日","mnemonic":"x",
         "etymology_diagram":{"kind":"compound","parts":[{"text":"曖","components":["日","愛"],"meaning":"日がかげる"}],
                              "result_meaning":"はっきり見えない"},
         "example_scene":"朝ごはんを頼むとき","example_scene_for":"我要一份鐵板麵。"}
        """#)
        XCTAssertEqual(old.etymology, "どちらの字も「日」が付きます。")
        XCTAssertEqual(old.shownExampleScene(for: "我要一份鐵板麵。"), "朝ごはんを頼むとき")
        // A saved order naming the section still reads (the case stays).
        XCTAssertEqual(CardSection(rawValue: "etymology"), .etymology)
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

    /// The card as the server writes it now (2026-10-15: `example_v` 3, `example_scene` / `example_scene_for` on the main
    /// example, `{zh, ja, scene, scene_for, chunks}` in `examples_extra`): every example shows its label (防曬乳).
    func testProductionPayloadShowsEveryLabel() throws {
        let e = try extras(#"""
        {"explain_lang":"ja","example_v":3,"example_pattern_count":2,
         "example_scene":"出かける家族に声をかけるとき","example_scene_for":"出門前記得擦防曬乳。",
         "example_chunks":[{"parts":[{"text":"擦","pos":"V"},{"text":"防曬乳","pos":"N"}],"ja":"日焼け止めを塗る"}],
         "examples_extra":[{"zh":"這瓶防曬乳擦起來很清爽。","ja":"この日焼け止めは塗り心地がさっぱりしている。",
                            "scene":"ドラッグストアで使い心地を話すとき","scene_for":"這瓶防曬乳擦起來很清爽。",
                            "chunks":[{"parts":[{"text":"擦起來","pos":"V"},{"text":"很清爽","pos":"Vs"}],"ja":"塗るとさっぱりする"}]}]}
        """#)
        XCTAssertEqual(e.exampleV, 3)
        let all = ExampleItem.all(sentence: "出門前記得擦防曬乳。", translation: "出かける前に日焼け止めを塗るのを忘れないでね。",
                                  extras: e, target: "zh-TW")
        XCTAssertEqual(all.map(\.sentence), ["出門前記得擦防曬乳。", "這瓶防曬乳擦起來很清爽。"])
        XCTAssertEqual(all.map(\.scene), ["出かける家族に声をかけるとき", "ドラッグストアで使い心地を話すとき"])
        XCTAssertEqual(ExampleItem.missingLabels(sentence: "出門前記得擦防曬乳。", extras: e, target: "zh-TW"), [])
    }

    /// `scene_for` is the very sentence, spaces and full-width / half-width punctuation aside (and full-width letters).
    func testLabelMatchIgnoresSpacesAndWidth() throws {
        let e = try extras(#"""
        {"example_scene":"店で","example_scene_for":"這瓶是 SPF50 的!",
         "examples_extra":[{"zh":"你要買哪一瓶？","scene":"店員に聞かれたとき","scene_for":"你要買 哪一瓶?"}]}
        """#)
        let all = ExampleItem.all(sentence: "這瓶是ＳＰＦ５０的！", translation: nil, extras: e, target: "zh-TW")
        XCTAssertEqual(all.map(\.scene), ["店で", "店員に聞かれたとき"])
        XCTAssertEqual(WordExtras.sceneMatchKey("你要買 哪一瓶?"), WordExtras.sceneMatchKey("你要買哪一瓶？"))
    }

    /// An example without a matching label is still shown, and why goes to the developer log.
    func testExamplesWithoutTheirLabelAreReported() throws {
        let e = try extras(#"""
        {"example_v":2,"example_scene":"友達が眼鏡をしていないことに気づいたとき","example_scene_for":"你今天沒戴眼鏡嗎？",
         "examples_extra":[{"zh":"眼鏡放在桌上。","scene":"家族に聞かれたとき"},{"zh":"我的眼鏡呢？"}]}
        """#)
        let all = ExampleItem.all(sentence: "我戴眼鏡。", translation: nil, extras: e, target: "zh-TW")
        XCTAssertEqual(all.count, 3)
        XCTAssertTrue(all.allSatisfy { $0.scene == nil })
        let lines = ExampleItem.missingLabels(sentence: "我戴眼鏡。", extras: e, target: "zh-TW")
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].contains("你今天沒戴眼鏡嗎？"))
        XCTAssertTrue(lines[1].contains("without scene_for"))
        XCTAssertTrue(lines[2].contains("no scene label"))
        XCTAssertTrue(lines[0].contains("example_v 2"))
    }

    func testOnePatternShowsOneExample() throws {
        let e = try extras(#"{"example_pattern_count":1,"examples_extra":[{"zh":"這家的鐵板麵很好吃。"}]}"#)
        let all = ExampleItem.all(sentence: "我要一份鐵板麵。", translation: nil, extras: e, target: "zh-TW")
        XCTAssertEqual(all.map(\.sentence), ["我要一份鐵板麵。"])
    }

    /// 冰淇淋 (owner 2026-10-16): the main example 「夏天吃冰淇淋。」 had no label because the card carried no
    /// `example_scene` for it. Once the server writes the label with `example_scene_for` = that sentence, it shows; until
    /// then the example shows without one (no empty label).
    func testMainExampleShowsTheLabelOnceTheServerWritesIt() throws {
        let before = try extras(#"{"example_pattern_count":1}"#)
        let shown = ExampleItem.all(sentence: "夏天吃冰淇淋。", translation: "夏にアイスを食べる。", extras: before, target: "zh-TW")
        XCTAssertEqual(shown.map(\.sentence), ["夏天吃冰淇淋。"])
        XCTAssertNil(shown[0].scene)
        let after = try extras(#"{"example_pattern_count":1,"example_scene":"暑い日にアイスを食べるとき","example_scene_for":"夏天吃冰淇淋。"}"#)
        let labelled = ExampleItem.all(sentence: "夏天吃冰淇淋。", translation: "夏にアイスを食べる。", extras: after, target: "zh-TW")
        XCTAssertEqual(labelled.map(\.scene), ["暑い日にアイスを食べるとき"])
    }
}
