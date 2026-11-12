import XCTest

final class TripMapTests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
    }

    @MainActor
    func testI80MapLabelAndScreenshots() {
        for (theme, fixture) in [("night", "i80"), ("day", "i80-gap")] {
            let app = XCUIApplication()
            app.launchArguments = ["-RPMapFixture", fixture, "-RPDebugTheme", theme, "-AppleLocale", "en_US"]
            app.launch()
            let map = app.descendants(matching: .any).matching(identifier: "tripMap").firstMatch
            XCTAssertTrue(map.waitForExistence(timeout: 10))
            let predicate = NSPredicate(format: "label BEGINSWITH 'Route map. Salt Lake City area to Sacramento area, through Utah'")
            expectation(for: predicate, evaluatedWith: map)
            waitForExpectations(timeout: 10)
            XCTAssertTrue(map.label.contains("Highest point"), "label: \(map.label)")
            sleep(1)
            shot(app, "map-\(fixture)-\(theme)")
            app.terminate()
        }
    }

    /// Flips the simulator appearance while the map is visible; the cached image must be re-rendered.
    @MainActor
    func testMapRedrawsWhenAppearanceSwitches() {
        let app = XCUIApplication()
        app.launchArguments = ["-RPMapFixture", "i80", "-AppleLocale", "en_US"]
        XCUIDevice.shared.appearance = .dark
        app.launch()
        let map = app.descendants(matching: .any).matching(identifier: "tripMap").firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        sleep(2)
        shot(app, "map-appearance-before-dark")
        XCUIDevice.shared.appearance = .light
        sleep(3)
        XCTAssertTrue(map.exists)
        XCTAssertTrue(map.label.hasPrefix("Route map."), "label: \(map.label)")
        shot(app, "map-appearance-after-light")
        app.terminate()
    }
}
