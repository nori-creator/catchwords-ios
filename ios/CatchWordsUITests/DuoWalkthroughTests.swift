import XCTest

/// iPhone Duo の見て回る試し（オーナー 2026-10-31「iPhone duo のすべての画面と、すべての機能、ボタンを押したときの画面や
/// アニメーションがどのように映るのかすべて目で確認したい」）。
///
/// 合否を決める試しではない: 本物のアプリ（`-uiDemo`、本番に触れないデモ）を、人が使う速さでゆっくり操作し、CI がその間の
/// 画面を録画する（ios-duo-walkthrough.yml）。1 画面ごとに写真も残す（`<持ち方>_<nn>_<場面>`）。
/// 持ち方は CI が Duo を開く・閉じる道具で決め、ここには `DUO_POSTURE`（outer / landscape / portrait）で伝わる。
@MainActor
final class DuoWalkthroughTests: XCTestCase {
    private var app: XCUIApplication!
    private var posture = "outer"
    private var step = 0

    func test_walkthrough() {
        continueAfterFailure = true
        posture = ProcessInfo.processInfo.environment["DUO_POSTURE"] ?? "outer"
        app = XCUIApplication()
        app.launchArguments = [
            "-uiDemo", "zh-TW", "-uiDemoReset", "YES",
            "-ui.lang", "ja",
            "-onboarding.done", "YES", "-tour.pending", "NO",
            "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP",
        ]
        app.launch()
        turn()

        consent()
        guard app.buttons["tab.home"].waitForExistence(timeout: 30) else {
            snap("no-tab-bar")
            XCTFail("[\(posture)] the tab bar did not appear")
            return
        }
        pause(2.5)
        snap("home")
        home()
        dex()
        wordPage()
        camera()
        typedWord()
        review()
        settings()
        signOutAndIn()
    }

    // MARK: - 持ち方

    /// 横長・縦長はシミュレーターの向きで決める（Duo の内側だけが向きを変えられる）。
    private func turn() {
        switch posture {
        case "landscape": XCUIDevice.shared.orientation = .landscapeLeft
        case "portrait", "outer": XCUIDevice.shared.orientation = .portrait
        default: break
        }
        pause(2)
    }

    // MARK: - 場面

    private func consent() {
        let accept = app.buttons["aiConsent.accept"]
        guard accept.waitForExistence(timeout: 30) else { return }
        pause(2)
        snap("ai-consent")
        swipe(.up); pause(1)
        accept.tap()
        if !gone(accept, 5), accept.exists, accept.isHittable { accept.tap() }
        pause(1.5)
    }

    private func home() {
        swipe(.up); pause(1.5); snap("home-scrolled")
        swipe(.down); pause(1.5)
        if tapIf("home.calendar") {
            pause(2); snap("home-calendar")
            closeSheet()
        }
        // 写真を1枚押す（単語の頁が開く）。
        let photo = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'home.photo'")).firstMatch
        if photo.exists { photo.tap(); pause(2.5); snap("home-photo-open"); closeDetail() }
    }

    private func dex() {
        guard tapIf("tab.dex") else { return }
        pause(2.5); snap("dex-cards")
        // カードを左右に送る。
        for _ in 0..<2 { swipe(.left); pause(1.2) }
        snap("dex-cards-swiped")
        swipe(.right); pause(1.2)
        for mode in ["map", "grid", "list"] {
            if tapIf("dex.mode.\(mode)") {
                pause(2.5); snap("dex-\(mode)")
                swipe(.up); pause(1.5); snap("dex-\(mode)-scrolled")
                swipe(.down); pause(1)
            }
        }
        tapIf("dex.mode.grid"); pause(1.5)
    }

    private func wordPage() {
        let cell = app.buttons["dex.cell"].firstMatch
        guard cell.waitForExistence(timeout: 10) else { return }
        cell.tap()
        pause(3); snap("word-top")
        for i in 1...6 { swipe(.up); pause(1.2); snap("word-\(i)") }
        if tapIf("detail.sections") {
            pause(1.5); snap("word-sections")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.12)).tap(); pause(1)
        }
        if tapIf("detail.reviewCount") { pause(2); snap("word-memory"); closeSheet() }
        closeDetail()
        pause(1.5)
    }

    private func camera() {
        guard tapIf("tab.camera") else { return }
        pause(3); snap("camera")
        let shutter = app.buttons["camera.shutter"]
        guard shutter.waitForExistence(timeout: 10) else { return }
        shutter.tap()
        pause(1); snap("camera-shot")
        let first = app.buttons["candidate.0"].firstMatch
        guard first.waitForExistence(timeout: 30) else { snap("camera-no-words"); return }
        pause(2); snap("candidates")
        first.tap()
        let everyday = app.buttons["variant.0"]
        if everyday.waitForExistence(timeout: 4) {
            pause(1.5); snap("variants")
            everyday.tap()
        }
        // GET の演出 → 図鑑へ飛ぶ所まで、間を空けずに写真を数枚。
        for i in 1...6 { pause(1); snap("catch-\(i)") }
        let get = app.buttons["card.catch"]
        if get.exists { get.tap() }
        pause(4); snap("after-catch")
    }

    private func typedWord() {
        guard tapIf("tab.camera") else { return }
        pause(2)
        let shutter = app.buttons["camera.shutter"]
        guard shutter.waitForExistence(timeout: 10) else { return }
        shutter.tap()
        guard app.buttons["candidate.0"].firstMatch.waitForExistence(timeout: 30) else { return }
        pause(1.5)
        let field = app.textFields["picker.field"]
        guard field.waitForExistence(timeout: 5) else { return }
        field.tap(); pause(1); snap("typed-keyboard")
        field.typeText("pineapple\n")
        let everyday = app.buttons["variant.0"]
        if everyday.waitForExistence(timeout: 15) {
            pause(1.5); snap("typed-choose")
            everyday.tap()
        }
        for i in 1...4 { pause(1); snap("typed-catch-\(i)") }
        pause(3)
    }

    private func review() {
        guard tapIf("tab.review") else { return }
        pause(2.5); snap("review")
        for i in 1...4 {
            let correct = app.buttons["quiz.choice.correct"].firstMatch
            let wrong = app.buttons["quiz.choice"].firstMatch
            let pick = (i == 2 && wrong.exists) ? wrong : correct
            guard pick.waitForExistence(timeout: 8) else { break }
            pick.tap()
            pause(2); snap("answer-\(i)")
            guard tapIf("answer.next") else { break }
            pause(1.5)
        }
        pause(1.5); snap("review-end")
        // 記憶の状態（ボタンの文字で探す）。
        let memory = app.buttons.matching(NSPredicate(format: "label CONTAINS '記憶'")).firstMatch
        if memory.exists, memory.isHittable {
            memory.tap(); pause(2.5); snap("memory")
            let row = app.buttons.matching(NSPredicate(format: "label CONTAINS '%'")).firstMatch
            if row.exists, row.isHittable { row.tap(); pause(2.5); snap("memory-curve") }
            closeSheet()
        }
    }

    private func settings() {
        guard tapIf("tab.settings") else { return }
        pause(2.5); snap("settings")
        for wheel in ["settings.wheel.native", "settings.wheel.current", "settings.wheel.goal"] {
            if tapIf(wheel) {
                pause(1.5); snap(wheel.replacingOccurrences(of: "settings.", with: ""))
                tapIf("wheel.close"); pause(1)
            }
        }
        for i in 1...5 { swipe(.up); pause(1.2); snap("settings-\(i)") }
        if tapIf("settings.aiConsent.review") { pause(2); snap("settings-ai-consent"); closeSheet() }
    }

    private func signOutAndIn() {
        guard tapIf("settings.signOut") else { return }
        pause(1); snap("sign-out-confirm")
        let confirm = app.buttons["settings.signOut.confirm"].firstMatch
        if confirm.waitForExistence(timeout: 3) { confirm.tap() }
        guard app.buttons["welcome.switch"].waitForExistence(timeout: 10) else { return }
        pause(2.5); snap("welcome-signup")
        tapIf("welcome.mail"); pause(1.5); snap("welcome-signup-mail")
        tapIf("welcome.switch"); pause(2); snap("welcome-login")
        if !app.textFields["auth.email"].exists { tapIf("welcome.mail"); pause(1.5) }
        snap("welcome-login-mail")
        fill(app.textFields["auth.email"], "demo@catchwords.test")
        fill(app.secureTextFields["auth.password"], "demo-pass-1234")
        tapIf("auth.submit")
        if app.buttons["tab.home"].waitForExistence(timeout: 20) { pause(3); snap("signed-in") }
    }

    // MARK: - 道具

    @discardableResult
    private func tapIf(_ id: String) -> Bool {
        let e = app.buttons[id].firstMatch
        guard e.waitForExistence(timeout: 6) else { return false }
        let deadline = Date().addingTimeInterval(6)
        while !e.isHittable && Date() < deadline { pause(0.5) }
        guard e.isHittable else { return false }
        e.tap()
        return true
    }

    private func fill(_ field: XCUIElement, _ text: String) {
        guard field.waitForExistence(timeout: 5) else { return }
        field.tap(); field.typeText(text)
    }

    private func closeDetail() {
        let close = app.buttons["detail.close"]
        if close.waitForExistence(timeout: 2) { close.tap() } else { app.swipeDown(velocity: .fast) }
        _ = gone(close, 6)
    }

    /// シートを閉じる: 閉じるボタンがあれば押す、無ければ下へ払う。
    private func closeSheet() {
        let close = app.buttons.matching(NSPredicate(format: "label IN %@", ["閉じる", "完了", "Close", "Done"])).firstMatch
        if close.exists, close.isHittable { close.tap() } else { app.swipeDown(velocity: .fast) }
        pause(1.2)
    }

    private func gone(_ element: XCUIElement, _ timeout: TimeInterval) -> Bool {
        let e = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [e], timeout: timeout) == .completed
    }

    private enum Direction { case up, down, left, right }

    /// A swipe on the screen's scrolling list or map when there is one: on the Duo's inner screen a swipe on the whole
    /// app landed nowhere (taps on elements worked, the app's own swipes did not move anything).
    private func swipe(_ d: Direction) {
        let candidates = [app.scrollViews.firstMatch, app.maps.firstMatch, app.collectionViews.firstMatch]
        let target = candidates.first { $0.exists && $0.isHittable } ?? app
        switch d {
        case .up: target.swipeUp()
        case .down: target.swipeDown()
        case .left: target.swipeLeft()
        case .right: target.swipeRight()
        }
    }

    private func pause(_ seconds: Double) { Thread.sleep(forTimeInterval: seconds) }

    private func snap(_ name: String) {
        step += 1
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = String(format: "%@_%02d_%@", posture, step, name)
        shot.lifetime = .keepAlways
        add(shot)
    }
}
