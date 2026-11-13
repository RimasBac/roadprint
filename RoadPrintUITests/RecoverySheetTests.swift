import XCTest

/// S5 and S6: an unfinished trip is seeded at launch (DEBUG only).
final class RecoverySheetTests: XCTestCase {
    @MainActor
    private func launch(_ kind: String, theme: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-RPDebugLocationAccess", "precise", "-RPDebugNoGPS", "YES",
                               "-RPResetStore", "YES", "-RPSeedUnfinished", kind, "-RPDebugTheme", theme]
        app.launch()
        return app
    }

    @MainActor
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testForgotToEndOffersEndAtStop() {
        for theme in ["day", "night"] {
            let app = launch("forgot", theme: theme)
            XCTAssertTrue(app.buttons["recoveryPrimary"].waitForExistence(timeout: 15))
            XCTAssertTrue(app.staticTexts["recoveryTitle"].label.contains("Forgot"))
            XCTAssertTrue(app.buttons["recoverySecondary"].label == "Keep recording")
            shot(app, "S5-forgot-to-end-\(theme)")
            if theme == "day" {
                app.buttons["recoveryPrimary"].tap()
                XCTAssertTrue(app.buttons["tripMenu"].waitForExistence(timeout: 15))
            } else {
                app.buttons["recoverySecondary"].tap()
                XCTAssertTrue(app.buttons["endTrip"].waitForExistence(timeout: 5))
            }
            app.terminate()
        }
    }

    @MainActor
    func testInterruptedOffersContinueOrEnd() {
        for theme in ["day", "night"] {
            let app = launch("interrupted", theme: theme)
            XCTAssertTrue(app.buttons["recoveryPrimary"].waitForExistence(timeout: 15))
            XCTAssertTrue(app.buttons["recoveryPrimary"].label == "Continue trip")
            shot(app, "S6-interrupted-\(theme)")
            if theme == "day" {
                app.buttons["recoverySecondary"].tap()
                XCTAssertFalse(app.buttons["recoveryPrimary"].waitForExistence(timeout: 3))
                XCTAssertTrue(app.buttons["tripMenu"].waitForExistence(timeout: 15))
            } else {
                app.buttons["recoveryPrimary"].tap()
                XCTAssertTrue(app.buttons["endTrip"].waitForExistence(timeout: 5))
            }
            app.terminate()
        }
    }
}
