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
    private func home(theme: String = "day", size: String = "default", locale: String = "en_US",
                      extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-RPDebugTheme", theme, "-RPDebugTypeSize", size,
                               "-AppleLocale", locale] + extra
        app.launch()
        return app
    }

    @MainActor
    func testHomeEvidenceMatrix() {
        for locale in ["en_US", "de_DE"] {
            // Create real processed content once per locale; subsequent launches keep it.
            let app = home(locale: locale, extra: ["-RPReplayRoute", "i80-slc-sac", "-RPResetStore", "YES"])
            XCTAssertTrue(app.staticTexts["homeEmpty"].waitForExistence(timeout: 15))
            shot(app, "home-day-default-\(locale)-empty")
            app.buttons["startTrip"].tap()
            XCTAssertTrue(app.staticTexts["recordingLabel"].waitForExistence(timeout: 5))
            shot(app, "home-day-default-\(locale)-recording")
            XCTAssertTrue(app.descendants(matching: .any)["replayFinished"].waitForExistence(timeout: 30))
            app.buttons["endTrip"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["tripRow"].waitForExistence(timeout: 10))
            app.terminate()
            for theme in ["night", "day"] {
                for size in ["default", "XXL", "AX3"] {
                    let content = home(theme: theme, size: size, locale: locale)
                    let row = content.descendants(matching: .any)["tripRow"].firstMatch
                    XCTAssertTrue(row.waitForExistence(timeout: 15))
                    XCTAssertTrue(row.label.contains(locale == "en_US" ? "mi" : "km"), row.label)
                    XCTAssertTrue(row.label.contains(locale == "en_US" ? "644.4" : "1.037,1"), row.label)
                    shot(content, "home-\(theme)-\(size)-\(locale)-content")
                    content.terminate()
                }
            }
        }
    }

    @MainActor
    func testHomeStorageStates() {
        let loading = home(extra: ["-RPDebugSlowStorage", "YES", "-RPResetStore", "YES"])
        XCTAssertTrue(loading.descendants(matching: .any)["homeLoading"].waitForExistence(timeout: 5))
        shot(loading, "home-day-loading")
        XCTAssertTrue(loading.staticTexts["homeEmpty"].waitForExistence(timeout: 10))
        loading.terminate()
        for size in ["default", "AX3"] {
            let error = home(size: size, extra: ["-RPDebugStorageError", "YES"])
            XCTAssertTrue(error.descendants(matching: .any)["storageUnavailable"].waitForExistence(timeout: 10))
            XCTAssertFalse(error.buttons["startTrip"].exists)
            shot(error, "home-day-\(size)-storage-error")
            error.terminate()
        }
    }
}
