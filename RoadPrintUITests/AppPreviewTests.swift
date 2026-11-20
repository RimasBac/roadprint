import XCTest

/// The App Store app preview (board, 2026-11-20). CI records the simulator screen while this test
/// plays a short tour; each `keep` block prints its start and end time, and
/// `Tools/ci/make-app-preview.py` cuts the recording to those blocks, so waits for the replay,
/// processing and video export never reach the preview. Run with `evidence=apppreview`.
final class AppPreviewTests: XCTestCase {
    @MainActor
    func testAppPreviewTour() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-RPEntitlement", "pro", "-RPAppStoreScreenshots", "YES", "-RPAppPreview", "YES",
            "-RPReplayRoute", "i80-slc-sac", "-RPDebugTheme", "night", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launchSkippingFirstLaunch()
        defer { app.terminate() }

        // 1. Drive: a seasoned driver's career, then Start Trip.
        let start = app.buttons["startTrip"]
        XCTAssertTrue(start.waitForExistence(timeout: 45))
        sleep(2)
        keep {
            pause(2.5)
            start.tap()
            pause(1.5)
        }
        XCTAssertTrue(element("replayFinished", in: app).waitForExistence(timeout: 60))

        // 2. End Trip: the summary with the route, Donner Summit and the elevation profile.
        let share = app.buttons["shareTrip"]
        keep {
            app.buttons["endTrip"].tap()
            XCTAssertTrue(element("elevationChart", in: app).waitForExistence(timeout: 30))
            XCTAssertTrue(share.waitForExistence(timeout: 15))
            pause(4.5)
            share.tap()
            pause(0.6)
        }

        // 3. The share card: Night Highway, Road Atlas, then the video drawing itself.
        waitForShareCard("nightHighway", in: app)
        keep {
            pause(2.5)
            app.segmentedControls.buttons["Road Atlas"].tap()
            waitForShareCard("roadAtlas", in: app)
            pause(2)
            app.segmentedControls.buttons["Night Highway"].tap()
            pause(0.4)
            app.segmentedControls.buttons["Video"].tap()
            pause(5)
        }
        // Let the export finish: CI also keeps the card video itself (1080 × 1920) for social posts.
        waitForShareCard("video", in: app, timeout: 240)
        app.navigationBars.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["tripDone"].waitForExistence(timeout: 10))
        app.buttons["tripDone"].tap()

        // 4. My map, all time.
        let mapTab = app.tabBars.buttons["Map"]
        XCTAssertTrue(mapTab.waitForExistence(timeout: 10))
        keep {
            mapTab.tap()
            pause(0.6)
        }
        let map = element("heatMap", in: app)
        XCTAssertTrue(map.waitForExistence(timeout: 30))
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'ready'"), object: map)], timeout: 30)
        keep {
            pause(4.5)
        }
    }

    /// Marks a block of the screen recording that goes into the preview.
    @MainActor
    private func keep(_ body: () -> Void) {
        print(String(format: "RP_PREVIEW_KEEP_BEGIN %.3f", Date().timeIntervalSince1970))
        body()
        print(String(format: "RP_PREVIEW_KEEP_END %.3f", Date().timeIntervalSince1970))
    }

    private func pause(_ seconds: Double) {
        Thread.sleep(forTimeInterval: seconds)
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func waitForShareCard(_ state: String, in app: XCUIApplication, timeout: TimeInterval = 40) {
        let button = app.buttons["shareCardButton"]
        let ready = NSPredicate(format: "exists == true AND value == %@", state)
        wait(for: [XCTNSPredicateExpectation(predicate: ready, object: button)], timeout: timeout)
    }
}
