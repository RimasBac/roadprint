import XCTest

final class ImportExportTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func scrollTo(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<5 where !element.isHittable { app.swipeUp() }
    }

    /// Import (plan, then apply, no system picker) → export → delete all → import again → the trip opens.
    @MainActor
    func testImportExportRoundTrip() {
        let app = XCUIApplication()
        app.launchArguments = ["-RPResetStore", "YES", "-RPImportFixture", "archive-v1", "-RPDebugTheme", "night",
                               "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["startTrip"].waitForExistence(timeout: 15))
        app.tabBars.buttons["You"].tap()

        importFixture(app, rowIdentifier: "importFixtureRow", screenshotName: "import-preview-night")
        let count = tripCount(app)
        XCTAssertGreaterThan(count, 0)

        // The restore row appears only after both export files are readable and the archive is staged.
        let export = app.buttons["exportAllTripsRow"]
        scrollTo(export, app)
        export.tap()
        let restoreRow = "restoreExportedFixtureRow"
        XCTAssertTrue(app.buttons[restoreRow].waitForExistence(timeout: 15), "Expected readable JSON and GPX exports")

        // Delete all trips, then restore the exported archive.
        let link = app.buttons["testTripLink"]
        scrollTo(link, app)
        link.tap()
        let delete = app.buttons["deleteAllTrips"]
        scrollTo(delete, app)
        delete.tap()
        app.alerts.buttons["Delete all"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let exportDisabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == false"), object: export)
        XCTAssertEqual(XCTWaiter.wait(for: [exportDisabled], timeout: 10), .completed)
        XCTAssertEqual(tripCount(app), 0)

        importFixture(app, rowIdentifier: restoreRow)
        XCTAssertEqual(tripCount(app), count)

        app.buttons["allTripsLink"].tap()
        let row = app.descendants(matching: .any).matching(identifier: "allTripsRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "tripDistance").firstMatch
            .waitForExistence(timeout: 15))
    }

    @MainActor
    private func importFixture(_ app: XCUIApplication, rowIdentifier: String, screenshotName: String? = nil) {
        let row = app.buttons[rowIdentifier]
        scrollTo(row, app)
        row.tap()
        let found = app.staticTexts["importFoundText"]
        XCTAssertTrue(found.waitForExistence(timeout: 10))
        if let screenshotName { shot(app, screenshotName) }
        app.buttons["importConfirmButton"].tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: found)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 10), .completed)
    }

    /// The "All trips" row on You shows the number of trips.
    @MainActor
    private func tripCount(_ app: XCUIApplication) -> Int {
        let link = app.buttons["allTripsLink"]
        for _ in 0..<5 where !link.isHittable { app.swipeDown() }
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        let digits = link.label.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        return Int(digits) ?? -1
    }
}
