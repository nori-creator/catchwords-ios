import XCTest

@MainActor
final class ChunkWheelTests: XCTestCase {
    func testOriginalWheelInWordDetail() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiPreview", "detail", "-ui.lang", "ja",
                               "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        // Warm-up, not checked: the first wheel on a freshly booted CI simulator loads the system's symbol assets and
        // Japanese line-break dictionary, and the screen stops answering long enough for the UI query to time out
        // (owner 2026-10-23: the test failed on every run). A phone in use has them loaded; the checked pass below is
        // a fresh launch with the same limits as before.
        app.launch()
        let warm = app.buttons["早餐店"].firstMatch
        if warm.waitForExistence(timeout: 120) {
            if !warm.isHittable { app.swipeUp() }
            warm.tap()
            _ = app.pickerWheels.firstMatch.waitForExistence(timeout: 120)
        }
        app.terminate()

        app.launch()
        // The 早餐店 of 在＋早餐店＋點＋鐵板麵 is the swappable block of the preview (C5 2026-10-23: a degree word no
        // longer opens the wheel, and 蘑菇＋鐵板麵 is one word by C7).
        let place = app.buttons["早餐店"].firstMatch
        XCTAssertTrue(place.waitForExistence(timeout: 30))
        if !place.isHittable { app.swipeUp() }
        place.tap()
        let wheel = app.pickerWheels.firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout: 5))
        let before = wheel.value as? String
        save(app, "chunk-original-open")
        wheel.swipeUp()
        save(app, "chunk-original-scrolled")
        XCTAssertNotEqual(wheel.value as? String, before, "Scrolling must select another original option")
    }

    private func save(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
