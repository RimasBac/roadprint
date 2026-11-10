import XCTest

final class TokensGalleryScreenshotTests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testGalleryInBothThemesAtDefaultAndAX3() {
        for theme in ["night", "day"] {
            for ax3 in [false, true] {
                let app = XCUIApplication()
                app.launchArguments = ["-RPTokensGallery", "YES", "-RPDebugTheme", theme,
                                       "-RPDebugAX3", ax3 ? "YES" : "NO"]
                app.launch()
                XCTAssertTrue(app.staticTexts["tokensGallery"].waitForExistence(timeout: 10))
                let prefix = "tokens-\(theme)-\(ax3 ? "AX3" : "default")"
                var reachedEnd = false
                for page in 0..<24 {
                    shot(app, "\(prefix)-\(page)")
                    if app.staticTexts["tokensGalleryEnd"].isHittable { reachedEnd = true; break }
                    // Overlapping pages preserve evidence for every style and all six button states.
                    app.scrollViews.firstMatch.swipeUp(velocity: .slow)
                }
                XCTAssertTrue(reachedEnd, "Gallery did not reach its end: \(prefix)")
                app.terminate()
            }
        }
    }

    @MainActor
    func testHomeDayShowsBundledDigits() {
        let app = XCUIApplication()
        app.launchArguments = ["-RPDebugTheme", "day", "-RPReplayRoute", "i80-slc-sac",
                               "-RPResetStore", "YES", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["startTrip"].waitForExistence(timeout: 15))
        shot(app, "home-day-empty")
        app.buttons["startTrip"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["replayFinished"].waitForExistence(timeout: 30))
        app.buttons["endTrip"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["tripRow"].waitForExistence(timeout: 10))
        shot(app, "home-day-Barlow-digits")
    }
}
