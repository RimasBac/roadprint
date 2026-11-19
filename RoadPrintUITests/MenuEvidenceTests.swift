import XCTest

/// The tabs, trip history and share screens, using the I-80 replay fixture.
final class MenuEvidenceTests: XCTestCase {
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
    func testTabsYouTripDetailAndAllTrips() {
        let app = XCUIApplication()
        app.launchArguments = ["-RPEntitlement", "pro", "-RPResetStore", "YES", "-RPDebugTheme", "night", "-RPReplayRoute", "i80-slc-sac",
                               "-RPDebugLocationAccess", "precise", "-AppleLocale", "en_US",
                               "-RPChartSelection", "0.5"]
        app.launch()
        XCTAssertTrue(app.buttons["startTrip"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["homeEmpty"].exists)

        app.tabBars.buttons["You"].tap()
        let career = app.staticTexts["careerTotal"]
        XCTAssertTrue(career.waitForExistence(timeout: 5))
        XCTAssertTrue(career.label.hasPrefix("0.0"), career.label)
        shot(app, "menu-night-you-empty")

        app.tabBars.buttons["Drive"].tap()
        app.buttons["startTrip"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["replayFinished"].waitForExistence(timeout: 30))
        app.buttons["endTrip"].tap()
        let done = app.buttons["tripDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 20))
        done.tap()

        app.tabBars.buttons["You"].tap()
        XCTAssertTrue(career.waitForExistence(timeout: 5))
        XCTAssertFalse(career.label.hasPrefix("0.0"), career.label)
        shot(app, "menu-night-you")

        app.buttons["allTripsLink"].tap()
        let listed = app.descendants(matching: .any).matching(identifier: "allTripsRow").firstMatch
        XCTAssertTrue(listed.waitForExistence(timeout: 5))
        XCTAssertTrue(listed.label.contains("644.4mi"), listed.label)
        shot(app, "menu-night-all-trips")
        listed.tap()

        let map = app.descendants(matching: .any).matching(identifier: "tripMap").firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 60))
        let distance = app.descendants(matching: .any).matching(identifier: "tripDistance").firstMatch
        XCTAssertTrue(distance.waitForExistence(timeout: 5))
        XCTAssertTrue(distance.label.contains("mi"), distance.label)
        let ready = NSPredicate(format: "value == 'ready'")
        wait(for: [XCTNSPredicateExpectation(predicate: ready, object: map)], timeout: 30)
        shot(app, "menu-night-trip-detail")
        let share = app.buttons["shareTrip"]
        // The Share button is pinned; scroll until the chart sits clear of it.
        let chart = app.descendants(matching: .any).matching(identifier: "elevationChart").firstMatch
        for _ in 0..<4 where !chart.isHittable || chart.frame.maxY > share.frame.minY - 20 { app.swipeUp() }
        shot(app, "menu-night-trip-detail-lower")

        // Scrub: a horizontal drag across the chart to 50 %, with the callout showing.
        XCTAssertTrue(chart.isHittable)
        let start = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: chart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
                    withVelocity: .slow, thenHoldForDuration: 1)
        // A mostly vertical swipe that starts on the chart must still scroll the trip screen.
        let before = chart.frame.minY
        chart.swipeDown()  // the screen is already scrolled down to the buttons, so up is the free direction
        XCTAssertNotEqual(chart.frame.minY, before, "a vertical drag on the chart scrolls the screen")
        // The selection is held at 50 % by the test-mode launch argument; wait for the tab bar to settle.
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        sleep(1)
        shot(app, "menu-night-trip-detail-scrub")
        for _ in 0..<3 where !share.isHittable { app.swipeUp() }
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
        // The video: the preview plays while it is made, then Share appears.
        app.segmentedControls.buttons["Night Highway"].tap()
        app.segmentedControls.buttons["Video"].tap()
        if app.descendants(matching: .any).matching(identifier: "shareVideoProgress").firstMatch.waitForExistence(timeout: 10) {
            shot(app, "menu-night-share-sheet-video-making")
        }
        XCTAssertTrue(app.buttons["shareCardButton"].waitForExistence(timeout: 180), "the video is made")
        shot(app, "menu-night-share-sheet-video")
        app.buttons["Done"].tap()
        XCTAssertTrue(share.waitForExistence(timeout: 5))

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
        day.launchArguments = ["-RPEntitlement", "pro", "-RPDebugTheme", "day", "-RPDebugLocationAccess", "precise", "-AppleLocale", "en_US"]
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

    /// My map with made-up trips in the USA and in Europe, and with trips in both (board,
    /// 2026-11-13). The core tests run every size (5, 50, 250, 500) in each; here a few are shot,
    /// to keep the macOS job short.
    @MainActor
    func testMyMapFromFiveToFiveHundredTrips() {
        func open(_ fixture: String, theme: String) -> XCUIApplication {
            let app = XCUIApplication()
            app.launchArguments = ["-RPEntitlement", "pro", "-RPHeatFixture", fixture, "-RPDebugTheme", theme, "-AppleLocale", "en_US"]
            app.launch()
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "heatMap").firstMatch
                .waitForExistence(timeout: 30), fixture)
            // The totals appear with the trips; the map itself is laid out a moment later.
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "mapTrips").firstMatch
                .waitForExistence(timeout: 30), fixture)
            return app
        }
        for fixture in ["usa-5", "usa-500", "europe-50", "europe-250", "mixed-500"] {
            let app = open(fixture, theme: "night")
            // The first launch also loads the bundled places.
            sleep(fixture == "usa-5" ? 8 : 4)
            shot(app, "map-night-\(fixture)")
            if fixture == "mixed-500" {
                // Europe has more trips, so it shows first. North America is one tap away.
                app.segmentedControls.buttons["North America"].tap()
                sleep(4)
                shot(app, "map-night-mixed-500-north-america")
            }
            if fixture == "usa-500" {
                // Top roads, under the totals.
                let top = app.buttons["topRoad"].firstMatch
                for _ in 0..<4 where !top.isHittable { app.swipeUp() }
                XCTAssertTrue(top.exists, "the sample trips have roads")
                shot(app, "map-night-usa-500-top-roads")
                top.tap()
                sleep(4)
                shot(app, "map-night-usa-500-one-road")
                top.tap()
                app.swipeDown()
                app.swipeDown()
                app.swipeDown()
                app.segmentedControls.buttons["Last 30 days"].tap()
                sleep(4)
                shot(app, "map-night-usa-500-last-30-days")
            }
            app.terminate()
        }
        for fixture in ["usa-500"] {
            let app = open(fixture, theme: "day")
            sleep(4)
            shot(app, "map-day-\(fixture)")
            app.terminate()
        }
    }

    /// The "My map" share card on made-up trips.
    @MainActor
    func testMyMapCardFixtures() {
        for fixture in ["usa-500", "europe-250"] {
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

    /// Every road-sign template with its sample refs, to compare with Design/road-signs.
    @MainActor
    func testRoadSignGallery() {
        let app = XCUIApplication()
        app.launchArguments = ["-RPSignGallery", "YES", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "roadSign").firstMatch.waitForExistence(timeout: 20))
        sleep(1)
        shot(app, "road-signs-gallery")
        app.terminate()
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
        // A frame of the video, mid-route.
        let frame = XCUIApplication()
        frame.launchArguments = ["-RPCardFixture", "i80", "-RPCardProgress", "0.45", "-AppleLocale", "en_US"]
        frame.launch()
        XCTAssertTrue(frame.descendants(matching: .any).matching(identifier: "shareCard").firstMatch.waitForExistence(timeout: 20))
        sleep(2)
        shot(frame, "card-night-highway-i80-drawing")
        frame.terminate()
    }
}

/// "Your data" on You: Export all trips is off with no trips, and Import trips opens the file picker.
final class YourDataTests: XCTestCase {
    @MainActor
    func testYourDataRows() {
        let app = XCUIApplication()
        app.launchArguments = ["-RPResetStore", "YES", "-RPDebugTheme", "night",
                               "-RPDebugLocationAccess", "precise", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["startTrip"].waitForExistence(timeout: 15))
        app.tabBars.buttons["You"].tap()
        let export = app.buttons["exportAllTripsRow"]
        XCTAssertTrue(export.waitForExistence(timeout: 5))
        XCTAssertFalse(export.isEnabled)
        XCTAssertTrue(app.buttons["importTripsRow"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "you-your-data"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
