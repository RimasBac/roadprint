import UIKit
import XCTest

final class AppStoreScreenshotTests: XCTestCase {
    @MainActor
    func testStoreScreenshots() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-RPAppStoreScreenshots", "YES", "-RPReplayRoute", "i80-slc-sac",
            "-RPDebugTheme", "night", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launchSkippingFirstLaunch()
        defer { app.terminate() }

        let start = app.buttons["startTrip"]
        XCTAssertTrue(start.waitForExistence(timeout: 45))
        start.tap()
        XCTAssertTrue(element("replayFinished", in: app).waitForExistence(timeout: 45))
        app.buttons["endTrip"].tap()

        let tripMap = element("tripMap", in: app)
        waitForMap(tripMap)
        let chart = element("elevationChart", in: app)
        XCTAssertTrue(chart.waitForExistence(timeout: 15))
        let share = app.buttons["shareTrip"]
        XCTAssertTrue(share.waitForExistence(timeout: 15))
        let heading = app.staticTexts["Trip complete"]
        let close = app.buttons["tripClose"]
        // The iPhone 16 Pro Max status bar occupies the top 62 points.
        XCTAssertTrue(heading.isHittable && close.isHittable)
        XCTAssertGreaterThanOrEqual(heading.frame.minY, 62)
        XCTAssertGreaterThanOrEqual(close.frame.minY, 62)
        XCTAssertTrue(tripMap.isHittable, "tripMap \(tripMap.frame)")
        // Swift Charts can answer the hit test at the chart's centre with a mark (the Donner climb
        // does), so check the layout by geometry: fully on screen, below the map.
        XCTAssertTrue(app.windows.firstMatch.frame.contains(chart.frame), "chart \(chart.frame)")
        XCTAssertGreaterThanOrEqual(chart.frame.minY, tripMap.frame.maxY, "chart \(chart.frame)")
        XCTAssertLessThanOrEqual(chart.frame.maxY, share.frame.minY - 12)
        try capture("01-trip-summary")

        share.tap()
        waitForShareCard("nightHighway", in: app)
        try capture("02-night-highway")
        app.navigationBars.buttons["Done"].tap()
        app.buttons["tripDone"].tap()

        app.tabBars.buttons["Map"].tap()
        waitForMap(element("heatMap", in: app))
        revealAboveTabBar(element("topRoad", in: app), in: app)
        try capture("03-my-map")

        app.tabBars.buttons["Drive"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        let latestTrip = element("tripRow", in: app)
        XCTAssertTrue(latestTrip.isHittable)
        XCTAssertFalse(element("replayFinished", in: app).exists)
        XCTAssertFalse(element("flushTiming", in: app).exists)
        try capture("04-drive")

        latestTrip.tap()
        XCTAssertTrue(share.waitForExistence(timeout: 20))
        share.tap()
        waitForShareCard("nightHighway", in: app)
        let video = app.segmentedControls.buttons["Video"]
        video.tap()
        XCTAssertTrue(video.isSelected)
        waitForShareCard("video", in: app, timeout: 180)
        try capture("05-trip-card-video")
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// The floating tab bar covers the bottom of a scroll view. Scroll just far enough that `row`
    /// sits fully above it, so the store shot shows no content behind the bar.
    @MainActor
    private func revealAboveTabBar(_ row: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.exists)
        let overlap = row.frame.maxY - (bar.frame.minY - 16)
        if overlap > 0 {
            // Start on the stats, below the map, so the drag scrolls the page instead of the map.
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.82))
            let end = start.withOffset(CGVector(dx: 0, dy: -(overlap + 12)))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.5)
        }
        XCTAssertLessThanOrEqual(row.frame.maxY, bar.frame.minY)
        XCTAssertTrue(element("heatMap", in: app).isHittable)
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

    @MainActor
    private func capture(_ name: String) throws {
        // The whole display includes the simulator status bar. App Store PNGs must be opaque.
        let image = try XCTUnwrap(UIImage(data: XCUIScreen.main.screenshot().pngRepresentation))
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        let png = renderer.pngData { _ in image.draw(at: .zero) }
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
