import XCTest

final class RecordAndListTests: XCTestCase {
    // Fixture i80-slc-sac expected.json: 1037117.8 m, 37336 s moving time, Utah, Nevada, California.
    // en_US: 1037117.8 m = 644.4mi; 37336 s = 10 h 22 min.
    private let expectedDistance = "644.4mi"
    private let expectedDuration = "10h 22m"
    private let expectedRegions = ["Utah", "Nevada", "California"]

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
        app.launchArguments = ["-RPReplayRoute", "i80-slc-sac", "-RPResetStore", "YES", "-AppleLocale", "en_US"]
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
        let timing = app.staticTexts["flushTiming"]
        if timing.waitForExistence(timeout: 3) {
            let note = XCTAttachment(string: timing.label)
            note.name = "flush-timing"
            note.lifetime = .keepAlways
            add(note)
            print("FLUSH_TIMING: \(timing.label)")
        }
        XCTAssertTrue(row.label.contains(expectedDistance), "label: \(row.label)")
        XCTAssertTrue(row.label.contains(expectedDuration), "label: \(row.label)")
        for region in expectedRegions { XCTAssertTrue(row.label.contains(region), "label: \(row.label)") }
        XCTAssertLessThan(
            row.label.range(of: "Utah")?.lowerBound ?? row.label.endIndex,
            row.label.range(of: "Nevada")?.lowerBound ?? row.label.startIndex, "regions in travel order")
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
        for region in expectedRegions { XCTAssertTrue(again.label.contains(region), "label: \(again.label)") }
        shot(relaunched, "04-after-relaunch")
    }
}
