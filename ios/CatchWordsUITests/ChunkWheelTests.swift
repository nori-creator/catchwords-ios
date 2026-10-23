import XCTest

@MainActor
final class ChunkWheelTests: XCTestCase {
    func testOriginalWheelInWordDetail() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiPreview", "detail", "-ui.lang", "ja",
                               "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        // The sauce of 蘑菇＋鐵板麵 is the swappable block of the preview (C5 2026-10-23: a degree word no longer opens it).
        let sauce = app.buttons["蘑菇"].firstMatch
        XCTAssertTrue(sauce.waitForExistence(timeout: 30))
        if !sauce.isHittable { app.swipeUp() }
        sauce.tap()
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
