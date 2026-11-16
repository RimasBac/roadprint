import XCTest

/// Evidence for the "Trip complete" summary (ROA-56): night I-80, small screen at AX3 in day,
/// a trip with no altitude and no main road, and the End → summary time.
final class TripSummaryEvidenceTests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Drives Start → replay → End and returns once the summary shows its route.
    @MainActor
    private func summary(route: String, theme: String, size: String, name: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-RPReplayRoute", route, "-RPResetStore", "YES", "-AppleLocale", "en_US",
                               "-RPDebugTheme", theme]
        // The debug type size does not reach the full-screen cover; the system category does.
        if size == "AX3" {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        let start = app.buttons["startTrip"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()
        XCTAssertTrue(app.descendants(matching: .any)["replayFinished"].waitForExistence(timeout: 30))

        let tapped = ContinuousClock.now
        app.buttons["endTrip"].tap()
        let done = app.buttons["tripDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 20), "Trip complete summary appears")
        let elapsed = tapped.duration(to: .now)
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let note = XCTAttachment(string: String(format: "%.2f s from End tap to the summary (%@)", seconds, name))
        note.name = "end-to-summary-\(name)"
        note.lifetime = .keepAlways
        add(note)
        print("END_TO_SUMMARY \(name): \(seconds) s")

        let breakdown = app.descendants(matching: .any)["endBreakdown"]
        if breakdown.waitForExistence(timeout: 3) {
            let text = XCTAttachment(string: breakdown.label)
            text.name = "end-breakdown-\(name)"
            text.lifetime = .keepAlways
            add(text)
            print("END_BREAKDOWN \(name): \(breakdown.label)")
        }

        let map = app.descendants(matching: .any).matching(identifier: "tripMap").firstMatch
        let ready = NSPredicate(format: "value == 'ready'")
        wait(for: [XCTNSPredicateExpectation(predicate: ready, object: map)], timeout: 30)
        sleep(1)
        shot(app, name)
        done.tap()
        XCTAssertTrue(app.buttons["startTrip"].waitForExistence(timeout: 10))
        app.terminate()
    }

    @MainActor
    func testI80SummaryNight() {
        summary(route: "i80-slc-sac", theme: "night", size: "default", name: "summary-i80-night")
    }

    @MainActor
    func testI80SummaryDayAX3() {
        summary(route: "i80-slc-sac", theme: "day", size: "AX3", name: "summary-i80-day-AX3")
    }

    @MainActor
    func testNoAltitudeNoRoadSummary() {
        summary(route: "no-alt-no-road", theme: "day", size: "default", name: "summary-no-alt-no-road")
    }
}
