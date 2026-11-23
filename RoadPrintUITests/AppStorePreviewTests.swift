import XCTest

/// Drives the real app for the App Store preview video while CI records the simulator screen
/// (`Tools/appstore-preview/record.sh`). Every frame of the video is cut from that recording;
/// this test only paces the app and marks, in wall-clock seconds, where each scene starts.
/// `Tools/appstore-preview/scenes.json` names these marks.
final class AppStorePreviewTests: XCTestCase {
    private var marks: [String: Double] = [:]
    /// Element frames in points, so the promo video can lift real UI regions out of the screen.
    private var rects: [String: [Double]] = [:]

    @MainActor
    func testStorePreviewTake() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-RPAppStoreScreenshots", "YES", "-RPAppStorePreview", "YES", "-RPReplayRoute", "i80-slc-sac",
            "-RPDebugTheme", "night", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launchSkippingFirstLaunch()
        defer { app.terminate() }

        // Drive: record the replayed I-80 trip.
        let start = app.buttons["startTrip"]
        XCTAssertTrue(start.waitForExistence(timeout: 45))
        hold(1)
        mark("drive")
        start.tap()
        XCTAssertTrue(element("replayFinished", in: app).waitForExistence(timeout: 45))
        hold(1)
        app.buttons["endTrip"].tap()

        // Trip summary.
        waitForMap(element("tripMap", in: app))
        let share = app.buttons["shareTrip"]
        XCTAssertTrue(share.waitForExistence(timeout: 15))
        mark("summary")
        rect("tripMap", element("tripMap", in: app))
        rect("elevationChart", element("elevationChart", in: app))
        hold(5)

        // Share the trip as a video card that draws the route.
        share.tap()
        waitForShareCard("nightHighway", in: app)
        let video = app.segmentedControls.buttons["Video"]
        video.tap()
        XCTAssertTrue(video.isSelected)
        waitForShareCard("video", in: app, timeout: 180)
        mark("cardVideo")
        rect("shareCard", app.buttons["shareCardButton"])
        hold(7)
        app.navigationBars.buttons["Done"].tap()
        app.buttons["tripDone"].tap()

        // My map, all time.
        app.tabBars.buttons["Map"].tap()
        waitForMap(element("heatMap", in: app))
        app.segmentedControls["mapPeriod"].buttons["All time"].tap()
        hold(1)
        mark("myMap")
        rect("heatMap", element("heatMap", in: app))
        hold(6)

        // Filters: a year, then a road.
        mark("filters")
        hold(1)
        element("mapYearFilter", in: app).tap()
        let year = app.buttons.matching(NSPredicate(format: "label MATCHES '^20[0-9]{2}$'")).firstMatch
        XCTAssertTrue(year.waitForExistence(timeout: 5))
        hold(0.6)
        year.tap()
        hold(1.6)
        element("mapYearFilter", in: app).tap()
        let allYears = app.buttons["All years"]
        XCTAssertTrue(allYears.waitForExistence(timeout: 5))
        allYears.tap()
        hold(0.8)
        element("mapRoadFilter", in: app).tap()
        let road = app.buttons["I-80"]
        XCTAssertTrue(road.waitForExistence(timeout: 5))
        hold(0.6)
        road.tap()
        hold(2.5)

        // Back to every road for the end card.
        element("mapRoadFilter", in: app).tap()
        let allRoads = app.buttons["All roads"]
        XCTAssertTrue(allRoads.waitForExistence(timeout: 5))
        allRoads.tap()
        waitForMap(element("heatMap", in: app))
        hold(1)
        mark("end")
        hold(5)

        let window = app.windows.firstMatch.frame
        let markers: [String: Any] = ["clock": "unix", "marks": marks, "rects": rects,
                                      "window": [Double(window.width), Double(window.height)]]
        let json = try JSONSerialization.data(withJSONObject: markers, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: json, uniformTypeIdentifier: "public.json")
        attachment.name = "preview-markers"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The simulator shares the Mac's clock, so these line up with the recording's start time.
    private func mark(_ name: String) {
        marks[name] = Date().timeIntervalSince1970
    }

    private func rect(_ name: String, _ element: XCUIElement) {
        let f = element.frame
        rects[name] = [f.minX, f.minY, f.width, f.height].map(Double.init)
    }

    /// Real-time pacing: the recording keeps whatever the screen shows while the test waits.
    private func hold(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func waitForMap(_ map: XCUIElement) {
        XCTAssertTrue(map.waitForExistence(timeout: 30))
        let ready = NSPredicate(format: "value == 'ready'")
        wait(for: [XCTNSPredicateExpectation(predicate: ready, object: map)], timeout: 30)
    }

    @MainActor
    private func waitForShareCard(_ state: String, in app: XCUIApplication, timeout: TimeInterval = 40) {
        let share = app.buttons["shareCardButton"]
        let ready = NSPredicate(format: "exists == true AND value == %@", state)
        wait(for: [XCTNSPredicateExpectation(predicate: ready, object: share)], timeout: timeout)
    }
}
