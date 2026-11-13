import XCTest

/// The tabs, the You screen, the trip screen and the temporary test-trip tool, in one pass.
final class MenuAndTestTripTests: XCTestCase {
    @MainActor
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func back(_ app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    @MainActor
    func testTabsYouTestTripDetailAndAllTrips() {
        let app = XCUIApplication()
        app.launchArguments = ["-RPResetStore", "YES", "-RPDebugTheme", "night",
                               "-RPDebugLocationAccess", "precise", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["startTrip"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["homeEmpty"].exists)

        app.tabBars.buttons["You"].tap()
        let career = app.staticTexts["careerTotal"]
        XCTAssertTrue(career.waitForExistence(timeout: 5))
        XCTAssertTrue(career.label.hasPrefix("0.0"), career.label)
        shot(app, "menu-night-you-empty")

        // Temporary test tool: an unknown city explains itself, then a real pair makes a trip.
        let link = app.buttons["testTripLink"]
        for _ in 0..<3 where !link.isHittable { app.swipeUp() }
        link.tap()
        let from = app.textFields["testTripFrom"]
        XCTAssertTrue(from.waitForExistence(timeout: 5))
        from.tap()
        from.typeText("Kaunas")
        let to = app.textFields["testTripTo"]
        to.tap()
        to.typeText("Nowhereville\n")
        XCTAssertTrue(app.staticTexts["testTripMessage"].waitForExistence(timeout: 30))
        shot(app, "menu-night-test-trip-unknown-city")
        to.tap()
        to.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12) + "Vilnius\n")

        let map = app.descendants(matching: .any).matching(identifier: "tripMap").firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 60))
        let distance = app.descendants(matching: .any).matching(identifier: "tripDistance").firstMatch
        XCTAssertTrue(distance.waitForExistence(timeout: 5))
        XCTAssertTrue(distance.label.contains("mi"), distance.label)
        sleep(2)
        shot(app, "menu-night-trip-detail")
        // The made-up trip has hills, so the elevation chart is there; then the share card.
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "elevationChart").firstMatch.exists)
        let share = app.buttons["shareTrip"]
        for _ in 0..<3 where !share.isHittable { app.swipeUp() }
        shot(app, "menu-night-trip-detail-lower")
        share.tap()
        XCTAssertTrue(app.buttons["shareCardButton"].waitForExistence(timeout: 40))
        sleep(1)
        shot(app, "menu-night-share-sheet")
        app.buttons["Done"].tap()
        XCTAssertTrue(share.waitForExistence(timeout: 5))

        back(app)
        XCTAssertTrue(app.buttons["addTestTrip"].waitForExistence(timeout: 5))
        back(app)
        XCTAssertTrue(career.waitForExistence(timeout: 5))
        XCTAssertFalse(career.label.hasPrefix("0.0"), "the test trip counts as driven: \(career.label)")
        shot(app, "menu-night-you")

        app.buttons["allTripsLink"].tap()
        let listed = app.descendants(matching: .any).matching(identifier: "allTripsRow").firstMatch
        XCTAssertTrue(listed.waitForExistence(timeout: 5))
        XCTAssertTrue(listed.label.contains("Lithuania") || listed.label.contains("mi"), listed.label)
        shot(app, "menu-night-all-trips")
        listed.tap()
        XCTAssertTrue(map.waitForExistence(timeout: 20))
        back(app)
        back(app)

        app.tabBars.buttons["Drive"].tap()
        let row = app.descendants(matching: .any).matching(identifier: "tripRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["careerLine"].exists)
        shot(app, "menu-night-drive")
        app.terminate()

        // The same content in the day theme. No reset: the trip is still there.
        let day = XCUIApplication()
        day.launchArguments = ["-RPDebugTheme", "day", "-RPDebugLocationAccess", "precise", "-AppleLocale", "en_US"]
        day.launch()
        let dayRow = day.descendants(matching: .any).matching(identifier: "tripRow").firstMatch
        XCTAssertTrue(dayRow.waitForExistence(timeout: 15))
        shot(day, "menu-day-drive")
        dayRow.tap()
        XCTAssertTrue(day.descendants(matching: .any).matching(identifier: "tripMap").firstMatch.waitForExistence(timeout: 20))
        sleep(2)
        shot(day, "menu-day-trip-detail")
        back(day)
        day.tabBars.buttons["You"].tap()
        XCTAssertTrue(day.staticTexts["careerTotal"].waitForExistence(timeout: 5))
        shot(day, "menu-day-you")
        day.terminate()
    }

    /// The Night Highway card on the hard-coded I-80 fixture, to compare with the board reference.
    @MainActor
    func testNightHighwayCardFixture() {
        let app = XCUIApplication()
        app.launchArguments = ["-RPCardFixture", "i80", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "shareCard").firstMatch.waitForExistence(timeout: 20))
        sleep(2)
        shot(app, "card-night-highway-i80")
        app.terminate()
    }
}
