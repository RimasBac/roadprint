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
        // The other card styles.
        for (name, file) in [("Road Atlas", "atlas")] {
            app.segmentedControls.buttons[name].tap()
            sleep(1)
            XCTAssertTrue(app.buttons["shareCardButton"].waitForExistence(timeout: 40))
            sleep(1)
            shot(app, "menu-night-share-sheet-\(file)")
        }
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

        // My map: the one trip so far, drawn on the heat map.
        app.tabBars.buttons["Map"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "heatMap").firstMatch.waitForExistence(timeout: 30))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "mapTrips").firstMatch.exists)
        sleep(3)
        shot(app, "menu-night-map")
        // The map can be shared as a picture.
        XCTAssertTrue(app.buttons["shareMapIcon"].exists)
        let shareMap = app.buttons["shareMap"]
        for _ in 0..<3 where !shareMap.isHittable { app.swipeUp() }
        shareMap.tap()
        XCTAssertTrue(app.buttons["shareMapButton"].waitForExistence(timeout: 40))
        sleep(1)
        shot(app, "menu-night-map-share")
        app.buttons["Done"].tap()
        XCTAssertTrue(shareMap.waitForExistence(timeout: 5))

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

    /// My map with 5, 50, 250 and 500 made-up trips in the USA and in Europe, and with trips in
    /// both (board, 2026-11-13).
    @MainActor
    func testMyMapFromFiveToFiveHundredTrips() {
        func open(_ fixture: String, theme: String) -> XCUIApplication {
            let app = XCUIApplication()
            app.launchArguments = ["-RPHeatFixture", fixture, "-RPDebugTheme", theme, "-AppleLocale", "en_US"]
            app.launch()
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "heatMap").firstMatch
                .waitForExistence(timeout: 30), fixture)
            // The totals appear with the trips; the map itself is laid out a moment later.
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "mapTrips").firstMatch
                .waitForExistence(timeout: 30), fixture)
            return app
        }
        for fixture in ["usa-5", "usa-50", "usa-250", "usa-500", "europe-5", "europe-50", "europe-250", "europe-500", "mixed-500"] {
            let app = open(fixture, theme: "night")
            // The first launch also loads the bundled places.
            sleep(fixture == "usa-5" ? 9 : 5)
            shot(app, "map-night-\(fixture)")
            if fixture == "mixed-500" {
                // Europe has more trips, so it shows first. North America is one tap away.
                app.segmentedControls.buttons["North America"].tap()
                sleep(5)
                shot(app, "map-night-mixed-500-north-america")
            }
            if fixture == "usa-500" {
                app.segmentedControls.buttons["Last 30 days"].tap()
                sleep(5)
                shot(app, "map-night-usa-500-last-30-days")
            }
            app.terminate()
        }
        for fixture in ["usa-500", "europe-50"] {
            let app = open(fixture, theme: "day")
            sleep(5)
            shot(app, "map-day-\(fixture)")
            app.terminate()
        }
    }

    /// The sample maps of the temporary test tool, the way the board sees them on the phone.
    @MainActor
    func testSampleMapFromTheTestTool() {
        let app = XCUIApplication()
        app.launchArguments = ["-RPResetStore", "YES", "-RPDebugTheme", "night",
                               "-RPDebugLocationAccess", "precise", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["startTrip"].waitForExistence(timeout: 15))
        app.tabBars.buttons["You"].tap()
        let link = app.buttons["testTripLink"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        for _ in 0..<3 where !link.isHittable { app.swipeUp() }
        link.tap()
        let sample = app.buttons["sampleMap250"]
        XCTAssertTrue(sample.waitForExistence(timeout: 5))
        for _ in 0..<3 where !sample.isHittable { app.swipeUp() }
        sample.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "heatMap").firstMatch.waitForExistence(timeout: 30))
        sleep(9)
        shot(app, "sample-map-usa-250")
        app.buttons["sampleMapDone"].tap()
        XCTAssertTrue(sample.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["deleteAllTrips"].exists)
    }

    /// The "My map" share card on made-up trips.
    @MainActor
    func testMyMapCardFixtures() {
        for fixture in ["usa-500", "europe-250", "europe-5"] {
            let app = XCUIApplication()
            app.launchArguments = ["-RPHeatCardFixture", fixture, "-AppleLocale", "en_US"]
            app.launch()
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "myMapCard").firstMatch
                .waitForExistence(timeout: 40), fixture)
            sleep(3)
            shot(app, "card-my-map-\(fixture)")
            app.terminate()
        }
    }

    /// Each card style on the hard-coded I-80 fixture, to compare with the board reference and mockup 2.
    @MainActor
    func testShareCardFixtures() {
        for (style, file) in [("nightHighway", "night-highway"), ("roadAtlas", "road-atlas")] {
            let app = XCUIApplication()
            app.launchArguments = ["-RPCardFixture", "i80", "-RPCardStyle", style, "-AppleLocale", "en_US"]
            app.launch()
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "shareCard").firstMatch.waitForExistence(timeout: 20))
            sleep(2)
            shot(app, "card-\(file)-i80")
            app.terminate()
        }
    }
}
