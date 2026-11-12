import XCTest

final class LaunchScreenshotTests: XCTestCase {
    @MainActor
    func testLaunchShowsDriveAndSavesScreenshot() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Drive"].waitForExistence(timeout: 10))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "launch"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
