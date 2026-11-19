import XCTest

final class YourDataTests: XCTestCase {
    @MainActor
    func testDeleteAllDataEmptiesTripHistory() {
        continueAfterFailure = false
        let app = XCUIApplication()
        let appearance = ["-RPDebugTheme", "night", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchArguments = appearance + ["-RPResetStore", "YES", "-RPImportFixture", "archive-v1"]
        app.launchSkippingFirstLaunch()
        XCTAssertTrue(app.buttons["startTrip"].waitForExistence(timeout: 15))
        app.tabBars.buttons["You"].tap()

        let fixture = app.buttons["importFixtureRow"]
        for _ in 0..<5 where !fixture.isHittable { app.swipeUp() }
        fixture.tap()
        XCTAssertTrue(app.staticTexts["importFoundText"].waitForExistence(timeout: 10))
        app.buttons["importConfirmButton"].tap()

        let allTrips = app.buttons["allTripsLink"]
        for _ in 0..<5 where !allTrips.isHittable { app.swipeDown() }
        let populated = NSPredicate(format: "label CONTAINS '2'")
        wait(for: [XCTNSPredicateExpectation(predicate: populated, object: allTrips)], timeout: 15)

        app.swipeUp()
        app.swipeUp()
        let delete = app.buttons["deleteAllDataRow"]
        for _ in 0..<3 where !delete.isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["privacyPolicyRow"].isHittable)
        XCTAssertTrue(app.buttons["supportRow"].isHittable)
        XCTAssertTrue(delete.isHittable)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "you-about-night"
        attachment.lifetime = .keepAlways
        add(attachment)

        let alert = app.alerts["Delete all data?"]
        delete.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Cancel"].tap()
        for _ in 0..<5 where !allTrips.isHittable { app.swipeDown() }
        XCTAssertTrue(populated.evaluate(with: allTrips))

        for _ in 0..<5 where !delete.isHittable { app.swipeUp() }
        delete.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Delete all data"].tap()
        assertEmptyHistory(in: app)

        app.terminate()
        app.launchArguments = appearance
        app.launchSkippingFirstLaunch()
        XCTAssertTrue(app.buttons["startTrip"].waitForExistence(timeout: 15))
        app.tabBars.buttons["You"].tap()
        assertEmptyHistory(in: app)
    }

    @MainActor
    private func assertEmptyHistory(in app: XCUIApplication) {
        let allTrips = app.buttons["allTripsLink"]
        for _ in 0..<5 where !allTrips.isHittable { app.swipeDown() }
        allTrips.tap()
        XCTAssertTrue(app.staticTexts["allTripsEmpty"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "allTripsRow").firstMatch.exists)
    }
}
