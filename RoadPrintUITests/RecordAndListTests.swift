import XCTest

final class RecordAndListTests: XCTestCase {
    // Fixture i80-ui-test expected.json: 29836.1 m, 1074 s moving time.
    // en_US: 29836.1 m = 18.5mi; 1074 s = 17 whole minutes.
    private let expectedDistance = "18.5mi"
    private let expectedDuration = "17m"

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func rows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "tripRow")
    }

    @MainActor
    func testRecordReplayListAndRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["-RPReplayRoute", "i80-ui-test", "-RPResetStore", "YES", "-AppleLocale", "en_US"]
        app.launch()

        let start = app.buttons["startTrip"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        shot(app, "01-home")

        start.tap()
        XCTAssertTrue(app.staticTexts["recordingLabel"].waitForExistence(timeout: 5))
        shot(app, "02-recording")

        XCTAssertTrue(app.descendants(matching: .any)["replayFinished"].waitForExistence(timeout: 30))
        app.buttons["endTrip"].tap()

        let row = rows(app).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertEqual(rows(app).count, 1)
        XCTAssertTrue(row.label.contains(expectedDistance), "label: \(row.label)")
        XCTAssertTrue(row.label.contains(expectedDuration), "label: \(row.label)")
        shot(app, "03-list")

        app.terminate()

        let relaunched = XCUIApplication()
        relaunched.launchArguments = ["-AppleLocale", "en_US"]
        relaunched.launch()
        let again = rows(relaunched).firstMatch
        XCTAssertTrue(again.waitForExistence(timeout: 15))
        XCTAssertEqual(rows(relaunched).count, 1)
        XCTAssertTrue(again.label.contains(expectedDistance), "label: \(again.label)")
        XCTAssertTrue(again.label.contains(expectedDuration), "label: \(again.label)")
        shot(relaunched, "04-after-relaunch")
    }
}
