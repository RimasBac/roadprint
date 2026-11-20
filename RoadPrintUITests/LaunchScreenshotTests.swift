import XCTest

extension XCUIApplication {
    @MainActor
    func launchSkippingFirstLaunch() {
        launchArguments += ["--skip-first-launch"]
        launch()
    }
}

final class LaunchScreenshotTests: XCTestCase {
    @MainActor
    func testLaunchShowsDriveAndSavesScreenshot() {
        let app = XCUIApplication()
        app.launchSkippingFirstLaunch()
        XCTAssertTrue(app.staticTexts["Drive"].waitForExistence(timeout: 10))
        shot(app, "launch")
    }

    @MainActor
    func testFirstLaunchContinuePersistsAndEmptyTabsAreUsable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        let appearance = ["-RPDebugTheme", "night", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchArguments = appearance + ["--reset-first-launch", "-RPResetStore", "YES"]
        app.launch()
        let continueButton = app.buttons["firstLaunchContinue"]
        let startTrip = app.buttons["startTrip"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 10))
        XCTAssertFalse(startTrip.exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        shot(app, "first-launch-night")

        continueButton.tap()
        XCTAssertTrue(startTrip.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["homeEmpty"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)

        app.tabBars.buttons["Map"].tap()
        XCTAssertTrue(app.staticTexts["mapEmpty"].waitForExistence(timeout: 10))
        app.tabBars.buttons["You"].tap()
        XCTAssertTrue(app.staticTexts["careerTotal"].waitForExistence(timeout: 5))
        app.buttons["allTripsLink"].tap()
        XCTAssertTrue(app.staticTexts["allTripsEmpty"].waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = appearance
        app.launch()
        XCTAssertTrue(startTrip.waitForExistence(timeout: 15))
        XCTAssertFalse(continueButton.exists)
    }

    @MainActor
    func testFirstLaunchDayAndContinueAtAX3() {
        continueAfterFailure = false
        let app = XCUIApplication()
        let appearance = ["--reset-first-launch", "-RPDebugTheme", "day"]
        app.launchArguments = appearance
        app.launch()
        let continueButton = app.buttons["firstLaunchContinue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 10))
        shot(app, "first-launch-day")

        app.terminate()
        app.launchArguments = appearance + ["-RPDebugTypeSize", "AX3"]
        app.launch()
        XCTAssertTrue(app.staticTexts["firstLaunchTitle"].waitForExistence(timeout: 10))
        for _ in 0..<5 where !continueButton.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(continueButton.isHittable)
        continueButton.tap()
        XCTAssertTrue(app.buttons["startTrip"].waitForExistence(timeout: 15))
    }

    @MainActor
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
