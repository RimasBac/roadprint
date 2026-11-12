import XCTest
@testable import RoadPrintCore

final class SceneGeometryTests: XCTestCase {
    private func p(_ x: Double, _ y: Double) -> PlanePoint { .init(x: x, y: y) }
    func testPolylineToleranceAndEndpoints() {
        let points = [p(0,0),p(1,0.1),p(2,0.4),p(3,2),p(4,0)]
        let result = SceneGeometry.simplify(points)
        XCTAssertEqual(result.first, points.first); XCTAssertEqual(result.last, points.last)
        XCTAssertTrue(result.contains(p(3,2)))
        for point in points {
            XCTAssertLessThanOrEqual(zip(result, result.dropFirst()).map {
                SceneGeometry.distanceSquared(point, $0.0, $0.1)
            }.min()!, 0.25)
        }
    }
    func testSegmentAndPolygonClipping() {
        let view = MapRect(x: 0, y: 0, width: 10, height: 10)
        XCTAssertTrue(SceneGeometry.clipRing([], to: view).isEmpty)
        XCTAssertEqual(SceneGeometry.clip(p(-5,5), p(15,5), to: view), [p(0,5),p(10,5)])
        XCTAssertNil(SceneGeometry.clip(p(-5,-5), p(15,-5), to: view))
        let ring = SceneGeometry.clipRing([p(-5,-5),p(15,-5),p(15,15),p(-5,15)], to: view)
        XCTAssertEqual(ring.first, ring.last)
        XCTAssertTrue(ring.allSatisfy(view.contains))
        XCTAssertTrue(SceneGeometry.contains(p(5,5), rings: [ring]))
        XCTAssertFalse(SceneGeometry.contains(p(5,5), rings: [ring,[p(4,4),p(6,4),p(6,6),p(4,6)]]))
    }
    func testSharedBorderIsSimplifiedOnceInBothWindings() {
        let shared = [p(10,0),p(10.1,2),p(10.2,4),p(9.9,6),p(10,10)]
        let left = [p(0,0)] + shared + [p(0,10),p(0,0)]
        let right = Array(shared.reversed()) + [p(20,0),p(20,10),shared.last!]
        let simplified = SharedOutlineSimplifier.simplify([left,Array(right)])
        let a = simplified[0].filter { $0.x > 9 && $0.x < 11 }
        let b = simplified[1].filter { $0.x > 9 && $0.x < 11 }
        XCTAssertEqual(a.count, 2)
        // Closing duplicates are harmless and are removed for comparison.
        XCTAssertEqual(Set(a.map { "\($0.x),\($0.y)" }), Set(b.map { "\($0.x),\($0.y)" }))
    }
    func testRouteClearanceIncludesGapsAndSegmentInteriors() {
        let routes = [MapScene.Route(kind: .gap, points: [p(0,5),p(100,5)])]
        XCTAssertFalse(SceneGeometry.clear(MapRect(x: 45,y: 0,width: 10,height: 10), of: routes, by: 6))
        XCTAssertTrue(SceneGeometry.clear(MapRect(x: 45,y: 20,width: 10,height: 10), of: routes, by: 6))
    }
}
