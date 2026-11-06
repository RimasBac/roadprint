import XCTest
import RoadPrintCore

final class CoreLinkTests: XCTestCase {
    func testCoreIsLinked() {
        XCTAssertGreaterThanOrEqual(RoadPrintCore.schemaVersion, 1)
    }
}
