import XCTest

/// Evidence for the iCloud toggle (Settings on You) and the A9 "iCloud storage is full" banner.
/// Skips the first-launch screen: whether it shows depends on what earlier tests left in the simulator.
final class SyncBannerTests: XCTestCase {
    @MainActor
    func testToggleAndQuotaBanner() {
        for theme in ["night", "day"] {
            let app = XCUIApplication()
            app.launchArguments = ["-RPDebugTheme", theme, "-RPSyncStatus", "quotaFull", "-AppleLocale", "en_US"]
            app.launchSkippingFirstLaunch()
            app.tabBars.buttons["You"].tap()
            let banner = app.descendants(matching: .any)["iCloudBanner"]
            XCTAssertTrue(banner.waitForExistence(timeout: 15))
            attach(app, "sync-\(theme)-banner")
            let toggle = app.descendants(matching: .any)["iCloudSyncToggle"]
            for _ in 0..<4 where !toggle.isHittable { app.swipeUp() }
            XCTAssertTrue(toggle.exists)
            attach(app, "sync-\(theme)-toggle")
            app.terminate()
        }
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
