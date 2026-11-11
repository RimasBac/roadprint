import XCTest
@testable import RoadPrintCore

final class PolygonLabelAnchorTests: XCTestCase {
    private func point(_ x: Double, _ y: Double) -> PlanePoint { PlanePoint(x: x, y: y) }

    func testSquareAnchorIsAtVisualCentre() throws {
        let square = [point(0, 0), point(100, 0), point(100, 100), point(0, 100)]
        let anchor = try XCTUnwrap(PolygonLabelAnchor.find(rings: [square]))
        XCTAssertEqual(anchor.x, 50, accuracy: 0.5)
        XCTAssertEqual(anchor.y, 50, accuracy: 0.5)
    }

    func testHoleIsAvoidedAndConcavePolygonHasInteriorAnchor() throws {
        let outer = [point(0, 0), point(100, 0), point(100, 100), point(0, 100)]
        let hole = [point(35, 35), point(65, 35), point(65, 65), point(35, 65)]
        let anchor = try XCTUnwrap(PolygonLabelAnchor.find(rings: [outer, hole], precision: 0.1))
        XCTAssertFalse((35...65).contains(anchor.x) && (35...65).contains(anchor.y))
        let concave = [point(0, 0), point(100, 0), point(100, 20), point(20, 20), point(20, 100), point(0, 100)]
        let corner = try XCTUnwrap(PolygonLabelAnchor.find(rings: [concave]))
        XCTAssertTrue(corner.x < 20 || corner.y < 20)
    }

    func testDegeneratePolygonHasNoAnchor() {
        XCTAssertNil(PolygonLabelAnchor.find(rings: [[point(0, 0), point(1, 0), point(2, 0)]]))
    }
}
