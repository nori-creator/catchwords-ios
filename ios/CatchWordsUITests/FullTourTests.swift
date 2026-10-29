import XCTest

/// Walks through every main screen of the real app against the offline demo backend (`-uiDemo`), once per
/// display language × learning language, taking a screenshot of each step and checking that no text on
/// screen is written in a language that is neither the display language nor the learning language.
///
/// Screenshots are kept as attachments (named `<display>_<learning>_<nn>_<step>`); CI exports them to the
/// ci-previews branch.
@MainActor
final class FullTourTests: XCTestCase {
    private var app: XCUIApplication!
    private var display = "ja"
    private var learning = "zh-TW"
    private var step = 0

    // The display language is the learner's native language, never the learning language.
    func test_1_ja_zh() { tour(display: "ja", learning: "zh-TW") }
    func test_2_ja_en() { tour(display: "ja", learning: "en") }
    func test_3_en_zh() { tour(display: "en", learning: "zh-TW") }
    func test_4_en_ja() { tour(display: "en", learning: "ja") }
    func test_5_zh_en() { tour(display: "zh-TW", learning: "en") }
    func test_6_zh_ja() { tour(display: "zh-TW", learning: "ja") }

    // MARK: - The tour

    private func tour(display: String, learning: String) {
        continueAfterFailure = true
        self.display = display
        self.learning = learning
        step = 0
        app = XCUIApplication()
        let appleLang = display == "zh-TW" ? "zh-Hant" : display
        app.launchArguments = [
            "-uiDemo", learning, "-uiDemoReset", "YES",
            "-ui.lang", display,
            "-onboarding.done", "YES", "-tour.pending", "NO",
            "-AppleLanguages", "(\(appleLang))", "-AppleLocale", display == "zh-TW" ? "zh_TW" : (display == "en" ? "en_US" : "ja_JP"),
        ]
        app.launch()

        aiConsent()
        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 30), "the tab bar did not appear")
        settle(2)
        snap("home")
        app.swipeUp()
        snap("home-scrolled")

        dexAndDetail()
        photoAndCatch()
        photoAndCatch(pick: 1, expectAgain: true)
        typedCatch()
        review()
        settings()
        signOutAndBackIn()
        relaunch()
    }

    /// A cold start of an account that has used the app before (nothing reset): the home album must come up with its
    /// photos. The app's trace times it (`UITestTrace.once`: the dex kept on the phone, the first photo on screen), so
    /// the time from launch to the first photo can be compared run to run.
    private func relaunch() {
        app.terminate()
        app.launchArguments = app.launchArguments.map { $0 == "-uiDemoReset" ? "-uiDemoKeep" : $0 }
        app.launch()
        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 30), "[\(display)/\(learning)] the app did not come back after a relaunch")
        XCTAssertFalse(app.buttons["aiConsent.accept"].exists, "[\(display)/\(learning)] the AI consent was asked again after a relaunch")
        settle(3)
        snap("home-relaunch")
    }

    /// The AI consent comes first, once per account (`-uiDemoReset` starts with no answer kept): photographed,
    /// then agreed to, so the camera and the word cards work for the rest of the tour.
    private func aiConsent() {
        let accept = app.buttons["aiConsent.accept"]
        guard accept.waitForExistence(timeout: 30) else {
            XCTFail("[\(display)/\(learning)] the AI consent screen did not appear")
            return
        }
        settle(1)
        snap("ai-consent")
        accept.tap()
        // On a cold simulator the first tap can land just after a stall of the main thread (the sounds being read,
        // the home's photos coming in) and UIKit cancels it (the trace's "touch cancelled", PR #5 2026-10-25): the
        // screen stayed and every later step failed behind it. Tap once more if it is still there.
        if !waitGone(accept, timeout: 5), accept.isHittable {
            accept.tap()
        }
        XCTAssertTrue(waitGone(accept, timeout: 10), "[\(display)/\(learning)] the AI consent did not close after agreeing")
        settle(1)
    }

    private func dexAndDetail() {
        tap("tab.dex")
        settle(2)
        snap("dex")
        // The 図鑑 opens on the slide dex (owner 2026-10-16); the words' squares are in the gallery.
        tap("dex.mode.grid")
        settle(1.5)
        snap("dex-gallery")
        let cell = app.buttons["dex.cell"].firstMatch
        guard cell.waitForExistence(timeout: 10) else {
            XCTFail("[\(display)/\(learning)] the dex shows no words")
            return
        }
        cell.tap()
        settle(2)
        snap("detail-top")
        for i in 1...5 {
            app.swipeUp()
            settle(0.5)
            snap("detail-\(i)")
        }
        if app.buttons["detail.sections"].exists {
            app.buttons["detail.sections"].tap()
            settle(1)
            snap("detail-sections")
            dismissPopover()
        }
        closeDetail()
        settle(1)
    }

    /// Closes the word sheet and makes sure it is gone: the sheet stayed open over the tab bar in one run
    /// (ja/en, 2026-10-10) when × was tapped while the sections popover was still going away, and every later
    /// tab (camera, settings) failed behind it — so × waits until the popover's panel is gone. × is tapped once: a
    /// second tap raced the sheet's own going away (en/zh, 2026-10-16: the first tap closed it, slower than the 3 s
    /// wait, and the second found no button — "No matches found"). A swipe, which needs no button, is the last resort.
    private func closeDetail() {
        let panel = app.descendants(matching: .any)["detail.sections.panel"]
        if panel.exists { _ = waitGone(panel, timeout: 5) }
        let close = app.buttons["detail.close"]
        guard close.waitForExistence(timeout: 2) else {
            app.swipeDown(velocity: .fast)
            return
        }
        close.tap()
        if waitGone(close, timeout: 10) { return }
        app.swipeDown(velocity: .fast)
        _ = waitGone(close, timeout: 5)
    }

    /// The GET moment (its card.catch), the same moment for a word already in the dex (its reencounter.get), or — the
    /// GET moment lasts about 3 s and then goes into the dex by itself — the mark on the square the word just landed on:
    /// the NEW badge of a new word (`dex.new`) or the re-encounter's mark (`dex.again`), shown only after a landing.
    /// Returns the first of `outcomes` seen (nil: none within `timeout`). What was seen is returned, never looked up
    /// again: the GET moment can go between two looks, a moment before the landing's mark comes (2026-10-15, en/ja: the
    /// re-encounter's GET moment was seen, gone at the second look, and the tour failed with the word landing fine).
    private func waitForCatch(_ outcomes: [XCUIElement], timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let seen = outcomes.first(where: { $0.exists }) { return seen }
            guard Date() < deadline else { return nil }
            settle(0.5)
        }
    }

    /// UTC wall-clock time, matching the app's trace (uitest-trace.txt).
    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private func waitGone(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    /// The camera only takes photos. Under `-uiDemo` the simulator has no camera: the viewfinder shows a
    /// sample photo, the shutter takes it and the demo backend names what is in it. Shutter → the words on
    /// the photo → tap the first → the celebration → 図鑑に追加 → the dex.
    /// `pick`: which object's word to tap. `expectAgain`: that word is in the dex already (the demo's photo names one
    /// word the learner owns, `candidate.1`): it must be a re-encounter — its GET moment, then its own square.
    private func photoAndCatch(pick: Int = 0, expectAgain: Bool = false) {
        let p = expectAgain ? "again-" : ""
        tap("tab.camera")
        settle(2)
        snap(p + "camera")
        let shutter = app.buttons["camera.shutter"]
        guard shutter.waitForExistence(timeout: 10), shutter.isEnabled else {
            XCTFail("[\(display)/\(learning)] the shutter is missing or disabled")
            return
        }
        shutter.tap()
        let first = app.buttons["candidate.\(pick)"].firstMatch
        guard first.waitForExistence(timeout: 30) else {
            XCTFail("[\(display)/\(learning)] the words did not appear on the photo")
            snap(p + "analysis-failed")
            return
        }
        settle(1.5)
        snap(p + "candidates")
        // What the tap aimed at, for the failure message below (CI keeps no other log of the screen).
        let aimed = first.exists ? "candidate.\(pick) hittable \(first.isHittable), frame \(first.frame)" : "candidate.\(pick) gone"
        let tappedAt = Self.clock.string(from: Date())
        first.tap()
        // A thing with several ways to say it lists them first (outside the first tour): take the everyday one once
        // the choose screen's card has come in (film v6: the rows land 0.6–1.0 s after the tap).
        // A thing with one way to say it opens the card too (2026-10-15), with that one row.
        let everyday = app.buttons["variant.0"]
        if everyday.waitForExistence(timeout: 3) {
            settle(1.2)
            snap(p + "variants")
            checkChooseScreen(several: app.buttons["variant.1"].exists)
            everyday.tap()
        }
        let catchButton = app.buttons["card.catch"]
        // A word already in the dex has the same GET moment, told apart by its identifier, and lands on its own square.
        let again = app.buttons["reencounter.get"]
        let landed = app.descendants(matching: .any)["dex.new"]
        let landedAgain = app.descendants(matching: .any)["dex.again"]
        let outcomes = [catchButton, again, landed, landedAgain]
        // 40 s, not 20: a Japanese screen's first line breaking loads the system's MeCab dictionary on the main thread,
        // which held the app ~10 s on a cold simulator right after the choice (CI 2026-10-29, ja/zh-TW, twice); the GET
        // moment passed unseen during it and the word landed in the dex a moment after a 20 s wait gave up.
        var seen = waitForCatch(outcomes, timeout: 40)
        if seen == nil {
            // The buttons the screen holds now and where (identifier @ centre), so the failure explains itself.
            let buttons = app.buttons.allElementsBoundByIndex.prefix(12).map { b in
                "\(b.identifier.isEmpty ? b.label : b.identifier)@\(Int(b.frame.midX)),\(Int(b.frame.midY))"
            }
            snap(p + "pick-failed")
            // Diagnosis only — the tour has failed either way: does a second tap on the same word open it? That tells
            // a tap the words screen never took from a screen that stopped answering. The app's own trace of both taps
            // (where each touch landed, which gestures took it) is trace.txt next to the screenshots.
            let retappedAt = Self.clock.string(from: Date())
            let second = first.exists && first.isHittable
            if second {
                first.tap()
                seen = waitForCatch(outcomes, timeout: 20)
            }
            let secondOpened = seen != nil
            let outcome = secondOpened ? "opened it" : (second ? "did not open it either" : "was not possible")
            let now = buttons.joined(separator: " ")
            XCTFail("[\(display)/\(learning)] the celebration did not open after tapping a word at \(tappedAt) UTC " +
                    "(\(aimed); now: \(now); a second tap at \(retappedAt) UTC \(outcome))")
            guard secondOpened else { return }
        }
        if seen === again || seen === landedAgain || again.exists || (landedAgain.exists && !catchButton.exists) {
            // The re-encounter's GET moment (「また会えた！」), then its sticker flies into the word's square, which is
            // already there: it gets the re-encounter's mark, never the NEW badge (the word was caught before).
            // Its GET moment may already have gone (seen a moment ago): then only its landing is waited for.
            if again.exists {
                settle(1)
                snap(p + "reencounter")
                // It goes into the dex by itself ~3 s after the choice; only a held moment (the first tour) is tapped.
                if !waitGone(again, timeout: 8), again.exists { again.tap() }
            }
            XCTAssertTrue(landedAgain.waitForExistence(timeout: 15),
                          "[\(display)/\(learning)] the re-encounter did not land on its word's square in the dex")
            XCTAssertFalse(landed.exists, "[\(display)/\(learning)] a re-encounter showed the NEW badge")
            settle(2)
            snap(p + "dex-after-reencounter")
            return
        }
        if expectAgain {
            XCTFail("[\(display)/\(learning)] a word already in the dex was caught as a new word (no re-encounter)")
        }
        if landed.exists && !catchButton.exists && !again.exists {
            // The GET moment was over (it went into the dex by itself) before the test looked: the word is in the dex.
            snap(p + "after-catch")
            settle(3)
            snap(p + "dex-after-catch")
            return
        }
        // The GET moment goes into the dex by itself 3 s after the choice (its full-screen card.catch, a skip, goes
        // with it): wait for that rather than racing it with a tap. In the first tour it holds and card.catch is its
        // 図鑑に追加 button, which stays: tap that.
        settle(1)
        snap(p + "celebration")
        if !waitGone(catchButton, timeout: 8), catchButton.exists { catchButton.tap() }
        settle(4)
        snap(p + "after-catch")
        settle(4)
        snap(p + "dex-after-catch")
    }

    /// 「違う単語を入力」 under the photo (owner 2026-10-15): what is typed never goes straight on to the catch — the words
    /// found open the choose screen (覚える単語を選ぶ), the everyday one first with its register tag, and the learner
    /// picks; then the GET moment and the dex as for a tag. The demo finds 鳳梨 / pineapple / パイナップル for "pineapple"
    /// typed in any display language (a meaning in English), a word not caught yet.
    private func typedCatch() {
        tap("tab.camera")
        settle(2)
        let shutter = app.buttons["camera.shutter"]
        guard shutter.waitForExistence(timeout: 10), shutter.isEnabled else {
            XCTFail("[\(display)/\(learning)] the shutter is missing or disabled (typed search)")
            return
        }
        shutter.tap()
        guard app.buttons["candidate.0"].firstMatch.waitForExistence(timeout: 30) else {
            XCTFail("[\(display)/\(learning)] the words did not appear on the photo (typed search)")
            snap("typed-analysis-failed")
            return
        }
        settle(1.5)
        let field = app.textFields["picker.field"]
        guard field.waitForExistence(timeout: 5) else {
            XCTFail("[\(display)/\(learning)] no field to type a word under the photo")
            return
        }
        field.tap()
        // Return on the keyboard (the field's search key) sends it, wherever the keyboard leaves the button.
        field.typeText("pineapple\n")
        let everyday = app.buttons["variant.0"]
        let catchButton = app.buttons["card.catch"]
        let landed = app.descendants(matching: .any)["dex.new"]
        guard everyday.waitForExistence(timeout: 15) else {
            let wentOn = catchButton.exists || landed.exists
            snap("typed-no-picker")
            XCTFail("[\(display)/\(learning)] the typed word " + (wentOn ? "went straight on to the catch" : "showed no choose screen"))
            return
        }
        settle(1.2)
        snap("typed-picker")
        // Never straight on: no GET moment before the choice, and the everyday name carries its register tag.
        XCTAssertFalse(catchButton.exists, "[\(display)/\(learning)] the GET moment opened before a typed word was chosen")
        let common = ["ja": "一般的な言い方", "en": "Common", "zh-TW": "常用說法"][display] ?? ""
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", common)).count > 0,
                      "[\(display)/\(learning)] the typed words have no register tag (\(common))")
        everyday.tap()
        guard waitForCatch([catchButton, landed], timeout: 20) != nil else {
            snap("typed-pick-failed")
            XCTFail("[\(display)/\(learning)] choosing a typed word did not open the GET moment")
            return
        }
        if catchButton.exists {
            settle(1)
            snap("typed-celebration")
            if !waitGone(catchButton, timeout: 8), catchButton.exists { catchButton.tap() }
        }
        XCTAssertTrue(landed.waitForExistence(timeout: 15), "[\(display)/\(learning)] the typed word did not land in the dex")
        settle(2)
        snap("typed-dex-after-catch")
    }

    /// The choose screen (owner 2026-10-15): every way to say it carries its register tag — the everyday word's
    /// 一般的な言い方 first, the demo's other name より詳しい言い方 — and a word can be typed under the card.
    /// `several`: the card lists more than one way to say it (the demo's scooter: 機車 and 速克達).
    private func checkChooseScreen(several: Bool) {
        let labels: [String: (common: String, specific: String)] = [
            "ja": ("一般的な言い方", "より詳しい言い方"), "en": ("Common", "More specific"), "zh-TW": ("常用說法", "更精確的說法"),
        ]
        guard let want = labels[display] else { return }
        func shown(_ text: String) -> Bool {
            app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).count > 0
        }
        XCTAssertTrue(shown(want.common), "[\(display)/\(learning)] the everyday name has no register tag (\(want.common))")
        if several {
            XCTAssertTrue(shown(want.specific), "[\(display)/\(learning)] the other name has no register tag (\(want.specific))")
        }
        XCTAssertTrue(app.textFields["variant.field"].exists, "[\(display)/\(learning)] no field to type a word on the choose screen")
    }

    private func review() {
        tap("tab.review")
        settle(2)
        snap("review")
        for i in 1...6 {
            let correct = app.buttons["quiz.choice.correct"].firstMatch
            let wrong = app.buttons["quiz.choice"].firstMatch
            // Answer wrong once to see the "try again" side too.
            let pick = (i == 2 && wrong.exists) ? wrong : correct
            guard pick.waitForExistence(timeout: 8) else { break }
            pick.tap()
            settle(1.2)
            snap("answer-\(i)")
            let next = app.buttons["answer.next"]
            guard next.waitForExistence(timeout: 5) else { break }
            next.tap()
            settle(1)
        }
        snap("review-end")
    }

    private func settings() {
        tap("tab.settings")
        settle(2)
        snap("settings")
        // 学習言語 shows only for an account on a language no longer offered, which can switch away from it (owner
        // 2026-10-20: the row is hidden while 繁體字（台灣） is the only choice). With 中文 as the display language
        // 繁體字（台灣） is no choice either (ProfileStore.targetChoices leaves out the display language).
        let target = learning == "zh-TW" || display == "zh-TW" ? [] : ["settings.wheel.target"]
        for wheel in ["settings.wheel.native"] + target + ["settings.wheel.current", "settings.wheel.goal"] {
            let row = app.buttons[wheel]
            guard row.waitForExistence(timeout: 4) else {
                XCTFail("[\(display)/\(learning)] \(wheel) missing")
                continue
            }
            row.tap()
            settle(1)
            snap(wheel.replacingOccurrences(of: "settings.", with: ""))
            if wheel == "settings.wheel.goal" { turnWheelAndBack() }
            // Close without changing anything (each wheel saves only when closed, and only a change).
            if app.buttons["wheel.close"].waitForExistence(timeout: 3) { app.buttons["wheel.close"].tap() }
            settle(0.8)
        }
        for i in 1...5 {
            app.swipeUp()
            settle(0.6)
            snap("settings-\(i)")
        }
    }

    /// Turns the open wheel by about a row with a finger and back (the system wheel clicks once per row: the only
    /// sound), and leaves it on the value it had, so closing changes nothing.
    private func turnWheelAndBack() {
        let wheel = app.pickerWheels.firstMatch
        guard wheel.waitForExistence(timeout: 3) else { return }
        let original = wheel.value as? String
        let centre = wheel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        for target in [0.2, 0.8] {
            centre.press(forDuration: 0.1, thenDragTo: wheel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: target)),
                         withVelocity: .slow, thenHoldForDuration: 0.3)
            settle(0.8)
        }
        if let original, (wheel.value as? String) != original { wheel.adjust(toPickerWheelValue: original) }
        settle(0.5)
    }

    private func signOutAndBackIn() {
        let out = app.buttons["settings.signOut"]
        guard out.waitForExistence(timeout: 5) else { return }
        out.tap()
        // The dialog's button is reported twice (button inside button): take the first.
        let confirm = app.buttons["settings.signOut.confirm"].firstMatch
        if confirm.waitForExistence(timeout: 3) { confirm.tap() }
        // Signed out: the welcome screen on its sign-up side; 「ログイン」 at the bottom turns it to the sign-in side, and
        // 「メールでログイン」 opens the mail fields there (owner 2026-10-29).
        let toSignIn = app.buttons["welcome.switch"]
        guard toSignIn.waitForExistence(timeout: 10) else {
            XCTFail("[\(display)/\(learning)] the welcome screen did not appear after signing out")
            return
        }
        settle(2)
        snap("welcome")
        toSignIn.tap()
        settle(1)
        let mail = app.buttons["welcome.mail"]
        guard mail.waitForExistence(timeout: 5) else {
            XCTFail("[\(display)/\(learning)] the sign-in side has no mail button")
            return
        }
        mail.tap()
        guard app.textFields["auth.email"].waitForExistence(timeout: 10) else {
            XCTFail("[\(display)/\(learning)] the mail fields did not open on the sign-in side")
            return
        }
        settle(1)
        snap("auth")
        // A wrong password first: the error must be in the display language.
        fill("auth.email", "demo@catchwords.test")
        fill("auth.password", "wrong")
        tap("auth.submit")
        settle(2)
        snap("auth-error")
        let password = app.secureTextFields["auth.password"]
        password.tap()
        // A secure field empties itself when typing starts again; the deletes cover the other case.
        password.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10) + "demo-pass-1234")
        tap("auth.submit")
        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 20), "[\(display)/\(learning)] signing in again failed")
        // The same account: its answer is kept on this device, so the consent is not asked again.
        XCTAssertFalse(app.buttons["aiConsent.accept"].exists, "[\(display)/\(learning)] the AI consent was asked again for the same account")
        settle(1)
        snap("signed-in-again")
    }

    // MARK: - Helpers

    private var closeLabels: [String] { ["閉じる", "Close", "關閉"] }

    private func tap(_ id: String) {
        let e = app.buttons[id]
        guard e.waitForExistence(timeout: 10) else {
            XCTFail("[\(display)/\(learning)] \(id) not found")
            return
        }
        // A tab under something else is never tapped blind (2026-10-15, ja/en: the tab bar was in the tree but out of
        // sight after a catch, the taps went to the dex page and the tour failed later at settings): wait for it to come
        // up, and say so when it does not.
        if id.hasPrefix("tab.") {
            let deadline = Date().addingTimeInterval(10)
            while !e.isHittable && Date() < deadline { settle(0.5) }
            guard e.isHittable else {
                snap("covered-" + id)
                XCTFail("[\(display)/\(learning)] \(id) is there but cannot be tapped (something covers it)")
                return
            }
        }
        e.tap()
    }

    private func fill(_ id: String, _ text: String) {
        let field = id == "auth.password" ? app.secureTextFields[id] : app.textFields[id]
        guard field.waitForExistence(timeout: 5) else {
            XCTFail("[\(display)/\(learning)] \(id) not found")
            return
        }
        field.tap()
        field.typeText(text)
    }

    private func dismissPopover() {
        // Tap outside the popover, near the top-left corner.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.12)).tap()
        settle(0.6)
    }

    private func settle(_ seconds: Double) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// Screenshot + the language check of everything readable on screen.
    private func snap(_ name: String) {
        step += 1
        let shot = XCTAttachment(screenshot: app.screenshot())
        let tag = display == "zh-TW" ? "zh" : display
        let learn = learning == "zh-TW" ? "zh" : learning
        shot.name = String(format: "%@_%@_%02d_%@", tag, learn, step, name)
        shot.lifetime = .keepAlways
        add(shot)
        checkLanguage(at: name)
    }

    /// One snapshot of the whole screen (a single round trip), then every label and value in it.
    private func checkLanguage(at screen: String) {
        guard let root = try? app.snapshot() else { return }
        var labels: Set<String> = []
        var stack: [XCUIElementSnapshot] = [root]
        while let e = stack.popLast() {
            let l = e.label.trimmingCharacters(in: .whitespacesAndNewlines)
            if !l.isEmpty { labels.insert(l) }
            if let v = e.value as? String {
                let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { labels.insert(t) }
            }
            stack.append(contentsOf: e.children)
        }
        for text in labels {
            if let problem = LanguageCheck.problem(text, display: display, learning: learning) {
                XCTFail("[\(display)/\(learning)] \(screen): \(problem) — 「\(text.prefix(80))」")
            }
        }
    }
}

/// Which scripts may appear: those of the display language and of the learning language only.
enum LanguageCheck {
    /// Latin words allowed on any screen (names, exam scales, units).
    static let latinAllowed: Set<String> = [
        "catchwords", "pro", "tocfl", "cefr", "jlpt", "ipa", "toefl", "ielts", "band", "level", "apple", "google",
        "app", "store", "ai", "gre", "cet", "iphone", "ipad", "ok", "lv", "unsplash", "wikimedia", "youtube",
        "youglish", "dcard", "threads", "reddit", "instagram", "merriam", "webster", "weblio", "kotobank", "jisho",
        "chiebukuro", "yahoo", "photographer", "moe", "abc", "zhuyin", "pinyin", "demo", "catchwords.test",
    ]

    static func problem(_ text: String, display: String, learning: String) -> String? {
        var kana = 0, han = 0, hangul = 0, bopomofo = 0
        for u in text.unicodeScalars {
            let v = u.value
            if (0x3041...0x30FF).contains(v) || (0x31F0...0x31FF).contains(v) { kana += 1 }
            if (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) { han += 1 }
            if (0xAC00...0xD7AF).contains(v) { hangul += 1 }
            if (0x3100...0x312F).contains(v) || (0x31A0...0x31BF).contains(v) { bopomofo += 1 }
        }
        let uses = Set([display, learning])
        if hangul > 0 { return "Korean text" }
        if kana > 0 && !uses.contains("ja") { return "Japanese kana on a screen without Japanese" }
        if bopomofo > 0 && learning != "zh-TW" { return "zhuyin while not learning Mandarin" }
        if han > 0 && !uses.contains("ja") && !uses.contains("zh-TW") { return "Chinese characters on an English-only screen" }
        if !uses.contains("en") {
            // Latin words (not pinyin, romaji or names) on a Japanese / Chinese screen.
            let words = text.split { !$0.isLetter && $0 != "'" }.map(String.init)
            for w in words where w.count >= 3 {
                let plainAscii = w.unicodeScalars.allSatisfy { $0.isASCII && CharacterSet.letters.contains($0) }
                guard plainAscii else { continue }  // pinyin with tone marks, romaji with macrons
                if latinAllowed.contains(w.lowercased()) { continue }
                if learning == "ja" || learning == "zh-TW" {
                    // Romaji / toneless pinyin may appear as readings: only flag Capitalised English-looking words.
                    guard w.first?.isUppercase == true, w.count >= 4 else { continue }
                }
                return "English word \"\(w)\" on a screen without English"
            }
        }
        return nil
    }
}
