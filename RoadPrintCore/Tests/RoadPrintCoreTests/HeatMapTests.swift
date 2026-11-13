import XCTest
@testable import RoadPrintCore

final class HeatMapTests: XCTestCase {
    private func line(_ from: (Double, Double), _ to: (Double, Double)) -> [RouteSegment] {
        [RouteSegment(points: [RoutePoint(latitude: from.0, longitude: from.1),
                               RoutePoint(latitude: to.0, longitude: to.1)])]
    }
    private let kaunas = (54.90, 23.90), vilnius = (54.69, 25.28), klaipeda = (55.71, 21.14)

    func testLevelsFollowTheLegend() {
        XCTAssertEqual([0, 1, 2, 3, 5, 6, 9, 10, 14, 15, 200].map(HeatMap.level(count:)),
                       [1, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5])
    }

    func testSharedStretchIsHotterThanTheRest() {
        // Three trips drive Kaunas → Vilnius. One of them comes from Klaipėda first.
        let east = line(kaunas, vilnius), west = line(klaipeda, kaunas)
        let heat = HeatMap.make(routes: [east, east, west + east])
        XCTAssertEqual(heat.maxCount, 3)
        XCTAssertEqual(Set(heat.runs.map(\.level)), [1, 2])
        XCTAssertEqual(heat.runs.map(\.level), heat.runs.map(\.level).sorted(), "coldest first")
        for run in heat.runs where run.level == 2 {
            XCTAssertTrue(run.points.allSatisfy { $0.longitude > 23.85 }, "only the eastern leg is shared")
        }
        XCTAssertTrue(heat.runs.filter { $0.level == 1 }.flatMap(\.points).contains { $0.longitude < 22 })
        // The same input gives the same runs.
        XCTAssertEqual(heat, HeatMap.make(routes: [east, east, west + east]))
    }

    func testARoadDrivenTwiceInOneTripCountsOnce() {
        let east = line(kaunas, vilnius)
        let heat = HeatMap.make(routes: [east + east])
        XCTAssertEqual(heat.maxCount, 1)
        XCTAssertEqual(Set(heat.runs.map(\.level)), [1])
    }

    func testNothingToDraw() {
        XCTAssertEqual(HeatMap.make(routes: []), HeatMap(runs: [], maxCount: 0))
        XCTAssertEqual(HeatMap.make(routes: [[RouteSegment(points: [])], []]), HeatMap(runs: [], maxCount: 0))
    }

    func testStepsAreShortEnoughToFindEveryCell() {
        let dense = HeatMap.densify(line(kaunas, vilnius)[0].points)
        XCTAssertGreaterThan(dense.count, 200)
        for (a, b) in zip(dense, dense.dropFirst()) {
            XCTAssertLessThanOrEqual(Geo.distance(from: a, to: b), HeatMap.stepMeters + 1)
        }
    }

    func testSceneDrawsOneRoutePerRunAndNoGapLines() throws {
        let heat = HeatMap.make(routes: [line(kaunas, vilnius), line(kaunas, vilnius), line(klaipeda, kaunas)])
        var input = MapSceneInput(segments: heat.runs.map { RouteSegment(points: $0.points) })
        input.connectsSegments = false
        let scene = try MapSceneBuilder.build(input: input, places: PlaceIndex.bundled(), size: (390, 360))
        XCTAssertEqual(scene.routes.count, heat.runs.count)
        XCTAssertTrue(scene.routes.allSatisfy { $0.kind == .recorded })
        // By default separate segments are joined by a dotted gap, as on a trip map.
        let joined = try MapSceneBuilder.build(input: MapSceneInput(segments: input.segments),
                                               places: PlaceIndex.bundled(), size: (390, 360))
        XCTAssertTrue(joined.routes.contains { $0.kind == .gap })
    }
}
