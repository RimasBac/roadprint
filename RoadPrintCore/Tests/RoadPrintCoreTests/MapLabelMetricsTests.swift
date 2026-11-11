import XCTest
@testable import RoadPrintCore

final class MapLabelMetricsTests: XCTestCase {
    func testRegionLabelIncludesTrackingBetweenCharacters() {
        let size = MapLabelMetrics.measure("NV", style: .region)
        XCTAssertEqual(size.width, 18.1, accuracy: 0.001)
        XCTAssertEqual(size.height, 13)
    }

    func testMapAndEmptyLabelsHaveDeterministicBounds() {
        XCTAssertEqual(MapLabelMetrics.measure("Area", style: .map).width, 26.4, accuracy: 0.001)
        let empty = MapLabelMetrics.measure("", style: .region)
        XCTAssertEqual(empty.width, 0)
        XCTAssertEqual(empty.height, 0)
    }
}
