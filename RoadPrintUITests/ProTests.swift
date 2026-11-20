import XCTest

/// Pro with the DEBUG fake store (`-RPFakeStore`, the `RoadPrint.storekit` offers): `xcodebuild
/// test` doesn't apply the scheme's StoreKit configuration. A purchase persists across launches,
/// so the tests run in name order: the free checks first (A, A2, B), then the purchase (C) and
/// Restore (D). The real StoreKit and RevenueCat paths are checked with a sandbox account.
final class ProTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func mapApp(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-RPHeatFixture", "usa-500", "-RPFakeStore", "YES", "-RPDebugTheme", "night",
                               "-AppleLocale", "en_US"] + extra
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "heatMap").firstMatch.waitForExistence(timeout: 30))
        return app
    }

    @MainActor
    private func allTime(_ app: XCUIApplication) -> XCUIElement {
        app.segmentedControls["mapPeriod"].buttons.matching(NSPredicate(format: "label CONTAINS 'All time'")).firstMatch
    }

    @MainActor
    func testA_LockedMapOpensPaywall() {
        let app = mapApp()
        sleep(3)
        shot(app, "my-map-locked-night")
        XCTAssertTrue(app.buttons["mapYearFilter"].exists, "filters show, locked")
        allTime(app).tap()
        let paywall = app.descendants(matching: .any).matching(identifier: "paywall").firstMatch
        XCTAssertTrue(paywall.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["paywallYearly"].waitForExistence(timeout: 15), "prices load from the store")
        XCTAssertTrue(app.buttons["paywallMonthly"].exists)
        XCTAssertTrue(app.buttons["paywallRestore"].exists)
        XCTAssertTrue(app.staticTexts["paywallLegal"].exists)
        sleep(2)
        shot(app, "paywall-night")
        app.buttons["paywallClose"].tap()
        XCTAssertTrue(app.segmentedControls["mapPeriod"].waitForExistence(timeout: 5))
        // A locked filter opens it too.
        app.buttons["mapRoadFilter"].tap()
        XCTAssertTrue(paywall.waitForExistence(timeout: 10))
    }

    /// Free: both picture styles share, Video opens the paywall and the picker stays on Picture.
    @MainActor
    func testA2_VideoCardIsPro() {
        let app = XCUIApplication()
        app.launchArguments = ["-RPReplayRoute", "i80-slc-sac", "-RPResetStore", "YES", "-RPFakeStore", "YES", "-RPDebugTheme", "night",
                               "-RPDebugLocationAccess", "precise", "-AppleLocale", "en_US"]
        app.launch()
        let start = app.buttons["startTrip"]
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        start.tap()
        XCTAssertTrue(app.descendants(matching: .any)["replayFinished"].waitForExistence(timeout: 40))
        app.buttons["endTrip"].tap()
        let share = app.buttons["shareTrip"]
        XCTAssertTrue(share.waitForExistence(timeout: 30))
        share.tap()
        let styles = app.segmentedControls["shareStylePicker"]
        XCTAssertTrue(styles.waitForExistence(timeout: 15))
        styles.buttons["Road Atlas"].tap()
        let paywall = app.descendants(matching: .any).matching(identifier: "paywall").firstMatch
        XCTAssertFalse(paywall.waitForExistence(timeout: 3), "Road Atlas pictures are free")
        let formats = app.segmentedControls["shareFormatPicker"]
        formats.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Video'")).firstMatch.tap()
        XCTAssertTrue(paywall.waitForExistence(timeout: 10), "Video opens the paywall")
        XCTAssertTrue(app.staticTexts["paywallPriceTerms"].waitForExistence(timeout: 15), "price terms by the buy button")
        sleep(2)
        shot(app, "paywall-video-night")
        app.buttons["paywallClose"].tap()
        XCTAssertTrue(formats.buttons["Picture"].waitForExistence(timeout: 5))
        XCTAssertTrue(formats.buttons["Picture"].isSelected, "back on Picture")
        app.terminate()
    }

    @MainActor
    func testB_ThirdTripPaywallShowsOnce() {
        let app = XCUIApplication()
        app.launchArguments = ["-RPReplayRoute", "i80-slc-sac", "-RPResetStore", "YES", "-RPFakeStore", "YES", "-RPDebugTheme", "night",
                               "-RPDebugLocationAccess", "precise", "-AppleLocale", "en_US"]
        app.launch()
        let paywall = app.descendants(matching: .any).matching(identifier: "paywall").firstMatch
        for trip in 1...3 {
            let start = app.buttons["startTrip"]
            XCTAssertTrue(start.waitForExistence(timeout: 20))
            start.tap()
            XCTAssertTrue(app.descendants(matching: .any)["replayFinished"].waitForExistence(timeout: 40))
            app.buttons["endTrip"].tap()
            let done = app.buttons["tripDone"]
            XCTAssertTrue(done.waitForExistence(timeout: 30))
            done.tap()
            if trip < 3 {
                XCTAssertFalse(paywall.waitForExistence(timeout: 3), "no paywall after trip \(trip)")
            } else {
                XCTAssertTrue(paywall.waitForExistence(timeout: 10), "paywall after the 3rd trip")
                app.buttons["paywallClose"].tap()
            }
        }
        app.terminate()
        // Once only: a new launch and a new trip show nothing.
        app.launchArguments = ["-RPReplayRoute", "i80-slc-sac", "-RPFakeStore", "YES", "-RPDebugTheme", "night",
                               "-RPDebugLocationAccess", "precise", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["startTrip"].waitForExistence(timeout: 20))
        XCTAssertFalse(paywall.waitForExistence(timeout: 3))
        app.terminate()
    }

    @MainActor
    func testC_YearlyPurchaseUnlocksAllTime() {
        let app = mapApp()
        allTime(app).tap()
        XCTAssertTrue(app.buttons["paywallYearly"].waitForExistence(timeout: 15))
        app.buttons["paywallYearly"].tap()
        app.buttons["paywallBuy"].tap()
        let paywall = app.descendants(matching: .any).matching(identifier: "paywall").firstMatch
        let gone = NSPredicate(format: "exists == false")
        wait(for: [XCTNSPredicateExpectation(predicate: gone, object: paywall)], timeout: 30)
        let period = app.segmentedControls["mapPeriod"]
        period.buttons["All time"].tap()
        XCTAssertTrue(app.buttons["mapYearFilter"].waitForExistence(timeout: 10))
        XCTAssertFalse(paywall.exists, "All time opens the map now")
        sleep(3)
        shot(app, "my-map-pro-night")
    }

    @MainActor
    func testD_RestoreAndStatus() {
        let app = XCUIApplication()
        app.launchArguments = ["-RPResetStore", "YES", "-RPFakeStore", "YES", "-RPDebugTheme", "night", "-AppleLocale", "en_US"]
        // No replay route, so the first-launch screen would show first.
        app.launchSkippingFirstLaunch()
        XCTAssertTrue(app.buttons["startTrip"].waitForExistence(timeout: 20))
        app.tabBars.buttons["You"].tap()
        let restore = app.buttons["restorePurchasesRow"]
        for _ in 0..<5 where !restore.isHittable { app.swipeUp() }
        restore.tap()
        let status = app.staticTexts["proStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 20))
        XCTAssertEqual(status.label, "Pro", "the purchase from test C is restored")
        XCTAssertTrue(app.buttons["manageSubscriptionRow"].exists)
        XCTAssertFalse(app.buttons["getProRow"].exists)
    }
}
