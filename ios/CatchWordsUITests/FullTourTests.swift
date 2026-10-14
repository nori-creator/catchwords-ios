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
        review()
        settings()
        signOutAndBackIn()
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
        settle(1)
    }

    private func dexAndDetail() {
        tap("tab.dex")
        settle(2)
        snap("dex")
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
    /// tab (camera, settings) failed behind it. × again once, then a swipe as the last resort.
    private func closeDetail() {
        let close = app.buttons["detail.close"]
        guard close.exists else {
            app.swipeDown(velocity: .fast)
            return
        }
        for _ in 0..<2 where close.exists {
            close.tap()
            if waitGone(close, timeout: 3) { return }
        }
        if close.exists { app.swipeDown(velocity: .fast) }
    }

    /// The celebration's 図鑑に追加, or the re-encounter card for a word already in the dex.
    private func waitForCatch(_ catchButton: XCUIElement, _ again: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !catchButton.exists && !again.exists && Date() < deadline { settle(0.5) }
        return catchButton.exists || again.exists
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
    private func photoAndCatch() {
        tap("tab.camera")
        settle(2)
        snap("camera")
        let shutter = app.buttons["camera.shutter"]
        guard shutter.waitForExistence(timeout: 10), shutter.isEnabled else {
            XCTFail("[\(display)/\(learning)] the shutter is missing or disabled")
            return
        }
        shutter.tap()
        let first = app.buttons["candidate.0"].firstMatch
        guard first.waitForExistence(timeout: 30) else {
            XCTFail("[\(display)/\(learning)] the words did not appear on the photo")
            snap("analysis-failed")
            return
        }
        settle(1.5)
        snap("candidates")
        // What the tap aimed at, for the failure message below (CI keeps no other log of the screen).
        let aimed = first.exists ? "candidate.0 hittable \(first.isHittable), frame \(first.frame)" : "candidate.0 gone"
        let tappedAt = Self.clock.string(from: Date())
        first.tap()
        // A thing with several ways to say it lists them first (outside the first tour): take the everyday one.
        let everyday = app.buttons["variant.0"]
        if everyday.waitForExistence(timeout: 3) { everyday.tap() }
        let catchButton = app.buttons["card.catch"]
        let again = app.buttons["reencounter.dex"]
        // A word already in the dex opens the re-encounter card instead of the celebration.
        if !waitForCatch(catchButton, again, timeout: 20) {
            // The buttons the screen holds now and where (identifier @ centre), so the failure explains itself.
            let buttons = app.buttons.allElementsBoundByIndex.prefix(12).map { b in
                "\(b.identifier.isEmpty ? b.label : b.identifier)@\(Int(b.frame.midX)),\(Int(b.frame.midY))"
            }
            snap("pick-failed")
            // Diagnosis only — the tour has failed either way: does a second tap on the same word open it? That tells
            // a tap the words screen never took from a screen that stopped answering. The app's own trace of both taps
            // (where each touch landed, which gestures took it) is trace.txt next to the screenshots.
            let retappedAt = Self.clock.string(from: Date())
            let second = first.exists && first.isHittable
            if second { first.tap() }
            let secondOpened = second && waitForCatch(catchButton, again, timeout: 20)
            let outcome = secondOpened ? "opened it" : (second ? "did not open it either" : "was not possible")
            let now = buttons.joined(separator: " ")
            XCTFail("[\(display)/\(learning)] the celebration did not open after tapping a word at \(tappedAt) UTC " +
                    "(\(aimed); now: \(now); a second tap at \(retappedAt) UTC \(outcome))")
            guard secondOpened else { return }
        }
        if again.exists && !catchButton.exists {
            settle(1)
            snap("reencounter")
            again.tap()
            settle(3)
            snap("dex-after-reencounter")
            return
        }
        settle(2)
        snap("celebration")
        catchButton.tap()
        settle(4)
        snap("after-catch")
        settle(4)
        snap("dex-after-catch")
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
        for wheel in ["settings.wheel.native", "settings.wheel.target", "settings.wheel.current", "settings.wheel.goal"] {
            let row = app.buttons[wheel]
            guard row.waitForExistence(timeout: 4) else {
                XCTFail("[\(display)/\(learning)] \(wheel) missing")
                continue
            }
            row.tap()
            settle(1)
            snap(wheel.replacingOccurrences(of: "settings.", with: ""))
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

    private func signOutAndBackIn() {
        let out = app.buttons["settings.signOut"]
        guard out.waitForExistence(timeout: 5) else { return }
        out.tap()
        // The dialog's button is reported twice (button inside button): take the first.
        let confirm = app.buttons["settings.signOut.confirm"].firstMatch
        if confirm.waitForExistence(timeout: 3) { confirm.tap() }
        // Signed out: the welcome screen first, then 「メールでログイン」 opens the sign-in screen with the mail form.
        let signIn = app.buttons["welcome.signin"]
        guard signIn.waitForExistence(timeout: 10) else {
            XCTFail("[\(display)/\(learning)] the welcome screen did not appear after signing out")
            return
        }
        settle(2)
        snap("welcome")
        signIn.tap()
        guard app.textFields["auth.email"].waitForExistence(timeout: 10) else {
            XCTFail("[\(display)/\(learning)] the mail form did not open from the welcome screen")
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
        if e.waitForExistence(timeout: 10) {
            e.tap()
        } else {
            XCTFail("[\(display)/\(learning)] \(id) not found")
        }
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
