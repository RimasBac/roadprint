import XCTest

final class DriveStateTests: XCTestCase {
    @MainActor
    private func launch(_ access: String, theme: String = "day", size: String = "default") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-RPDebugLocationAccess", access, "-RPDebugNoGPS", "YES",
                               "-RPResetStore", "YES", "-RPDebugTheme", theme, "-RPDebugTypeSize", size]
        app.launch()
        XCTAssertTrue(app.buttons["startTrip"].waitForExistence(timeout: 15))
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
    func testLocationDeniedDoesNotStartTrip() {
        for theme in ["day", "night"] {
            let app = launch("blocked", theme: theme)
            shot(app, "drive-\(theme)-location-off")
            app.buttons["startTrip"].tap()
            XCTAssertTrue(app.alerts["Location is off for RoadPrint"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.alerts.buttons["Open Settings"].exists)
            shot(app, "drive-\(theme)-A1")
            app.alerts.buttons["Not now"].tap()
            XCTAssertTrue(app.buttons["startTrip"].exists)
            XCTAssertFalse(app.buttons["endTrip"].exists)
            app.terminate()
        }
    }

    @MainActor
    func testApproximateConsentAndDelayedGPSState() {
        let app = launch("approximate", theme: "night")
        app.buttons["startTrip"].tap()
        XCTAssertTrue(app.alerts["Precise location is off"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.buttons["Open Settings"].exists)
        shot(app, "drive-night-A2")
        app.alerts.buttons["Start anyway"].tap()
        XCTAssertTrue(app.staticTexts["recordingLabel"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["elapsedTime"].exists)
        XCTAssertFalse(app.staticTexts["waitingForGPS"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["careerLine"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["tripRow"].exists)
        shot(app, "drive-night-recording")
        XCTAssertTrue(app.staticTexts["waitingForGPS"].waitForExistence(timeout: 20))
        shot(app, "drive-night-A3")
        app.buttons["endTrip"].tap()
        XCTAssertTrue(app.buttons["startTrip"].waitForExistence(timeout: 10))
        app.terminate()
    }

    @MainActor
    func testRecordingDayAtAX3() {
        let app = launch("precise", size: "AX3")
        app.buttons["startTrip"].tap()
        XCTAssertTrue(app.staticTexts["recordingLabel"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["endTrip"].isHittable)
        shot(app, "drive-day-AX3-recording")
        app.buttons["endTrip"].tap()
        XCTAssertTrue(app.buttons["startTrip"].waitForExistence(timeout: 10))
        app.terminate()
    }
}
