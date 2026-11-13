import XCTest
@testable import RoadPrintCore

final class HeatMapTests: XCTestCase {
    private func line(_ from: (Double, Double), _ to: (Double, Double)) -> [RouteSegment] {
        [RouteSegment(points: [RoutePoint(latitude: from.0, longitude: from.1),
                               RoutePoint(latitude: to.0, longitude: to.1)])]
    }
    private let kaunas = (54.90, 23.90), vilnius = (54.69, 25.28), klaipeda = (55.71, 21.14)

    func testHeatScaleIsLogarithmicAndNeverOverstatesAFewRepeats() {
        XCTAssertEqual(HeatMap.heat(count: 1, maxCount: 500), 0)
        XCTAssertEqual(HeatMap.heat(count: 500, maxCount: 500), 1, accuracy: 1e-9)
        XCTAssertEqual(HeatMap.heat(count: 8, maxCount: 3), 1, accuracy: 1e-9)
        // Driven twice out of a best of two: warm, not the hottest colour.
        XCTAssertEqual(HeatMap.heat(count: 2, maxCount: 2), 1.0 / 3, accuracy: 1e-9)
        let scale = [1, 2, 4, 8, 16, 64, 250].map { HeatMap.heat(count: $0, maxCount: 250) }
        XCTAssertEqual(scale, scale.sorted())
        XCTAssertLessThan(scale[3], 0.5)
    }

    func testOneRoadDrivenManyTimesIsOneLine() {
        let heat = HeatMap.make(routes: [[RouteSegment]](repeating: line(kaunas, vilnius), count: 20))
        XCTAssertEqual(heat.tripCount, 20)
        XCTAssertEqual(heat.maxCount, 20)
        XCTAssertEqual(heat.lines.count, 1, "20 drives over one road must not be 20 lines")
        XCTAssertEqual(heat.lines.first?.count, 20)
        XCTAssertEqual(heat.lines.first?.heat ?? 0, 1, accuracy: 1e-9)
        // The line still runs from one town to the other.
        let longitudes = heat.lines.flatMap(\.points).map(\.longitude)
        XCTAssertEqual(longitudes.min() ?? 0, 23.90, accuracy: 0.02)
        XCTAssertEqual(longitudes.max() ?? 0, 25.28, accuracy: 0.02)
    }

    func testGPSNoiseDoesNotSplitOrCoolARoad() {
        var random = HeatFixture.Generator(state: 42)
        let road = (0...60).map { RoutePoint(latitude: 54.90 - 0.0035 * Double($0), longitude: 23.90 + 0.023 * Double($0)) }
        let trips = (0..<30).map { _ in
            [RouteSegment(points: road.map {
                RoutePoint(latitude: $0.latitude + (random.unit() - 0.5) * 0.000_2,
                           longitude: $0.longitude + (random.unit() - 0.5) * 0.000_3)
            })]
        }
        let heat = HeatMap.make(routes: trips)
        XCTAssertEqual(heat.maxCount, 30)
        XCTAssertTrue(heat.lines.allSatisfy { $0.count == 30 }, "every stretch counts all 30 trips")
        XCTAssertTrue(heat.lines.allSatisfy { $0.heat == 1 })
    }

    func testSharedStretchIsHotterThanTheRest() {
        // Three trips drive Kaunas → Vilnius. One of them comes from Klaipėda first.
        let east = line(kaunas, vilnius), west = line(klaipeda, kaunas)
        let heat = HeatMap.make(routes: [east, east, west + east])
        XCTAssertEqual(heat.maxCount, 3)
        XCTAssertEqual(heat.lines.map(\.heat), heat.lines.map(\.heat).sorted(), "coldest first")
        let hot = heat.lines.filter { $0.heat > 0 }, cold = heat.lines.filter { $0.heat == 0 }
        XCTAssertFalse(hot.isEmpty)
        XCTAssertFalse(cold.isEmpty)
        XCTAssertTrue(hot.flatMap(\.points).allSatisfy { $0.longitude > 23.8 }, "only the eastern leg is shared")
        XCTAssertTrue(cold.flatMap(\.points).contains { $0.longitude < 22 })
        XCTAssertEqual(heat, HeatMap.make(routes: [east, east, west + east]), "same trips, same lines")
    }

    func testARoadDrivenTwiceInOneTripCountsOnce() {
        let east = line(kaunas, vilnius)
        let heat = HeatMap.make(routes: [east + east])
        XCTAssertEqual(heat.maxCount, 1)
        XCTAssertTrue(heat.lines.allSatisfy { $0.heat == 0 })
    }

    func testNothingToDraw() {
        XCTAssertEqual(HeatMap.make(routes: []), .empty)
        XCTAssertEqual(HeatMap.make(routes: [[RouteSegment(points: [])], []]), .empty)
        XCTAssertThrowsError(try MapSceneBuilder.buildHeat(.empty, places: PlaceIndex.bundled(), size: (390, 410)))
    }

    /// 5, 50, 250 and 500 trips over the USA and over Europe (board, 2026-11-13).
    func testFromFiveToFiveHundredTrips() throws {
        let places = try PlaceIndex.bundled()
        for area in [HeatFixture.Area.usa, .europe, .mixed] {
            var previousMax = 0
            for count in [5, 50, 250, 500] {
                let trips = HeatFixture.trips(area, count: count)
                XCTAssertEqual(trips.count, count)
                let started = Date()
                let heat = HeatMap.make(routes: trips.map(\.segments))
                let made = Date().timeIntervalSince(started)
                let scene = try MapSceneBuilder.buildHeat(heat, places: places, size: (390, 410))
                let laidOut = Date().timeIntervalSince(started) - made
                let points = scene.lines.reduce(0) { $0 + $1.points.count }
                print("heat \(area.rawValue) \(count): \(heat.lines.count) lines, \(points) points in view, max \(heat.maxCount)×, "
                      + "cell \(Int(heat.cellMeters)) m, make \(Int(made * 1000)) ms, layout \(Int(laidOut * 1000)) ms")

                // For looking at the result: CI keeps these with the map previews.
                if let directory = ProcessInfo.processInfo.environment["MAP_SCENE_OUTPUT_DIR"] {
                    let folder = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent("heat", isDirectory: true)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try JSONEncoder().encode(scene).write(to: folder.appendingPathComponent("\(area.rawValue)-\(count).json"))
                }

                XCTAssertEqual(heat.tripCount, count)
                XCTAssertGreaterThanOrEqual(heat.maxCount, previousMax, "more trips never cool the hottest road")
                previousMax = heat.maxCount
                XCTAssertFalse(scene.lines.isEmpty)
                // Merged roads: the drawing does not grow with the number of trips.
                XCTAssertLessThan(points, 60_000, "\(area) \(count)")
                let view = MapRect(x: -1, y: -1, width: 392, height: 412)
                XCTAssertTrue(scene.lines.allSatisfy { $0.points.allSatisfy(view.contains) }, "\(area) \(count): a line leaves the view")
                XCTAssertLessThan(made + laidOut, 30, "\(area) \(count) took too long")
                if count == 500 {
                    XCTAssertGreaterThan(heat.maxCount, 30, "busy roads are driven dozens of times")
                    XCTAssertEqual(scene.lines.last?.heat ?? 0, 1, accuracy: 1e-9)
                    XCTAssertLessThan(scene.lines.first?.heat ?? 1, 0.6, "quiet roads stay cooler")
                }
            }
        }
    }

    func testFixtureTripsFollowTheSameRoads() {
        XCTAssertEqual(HeatFixture.trips(.usa, count: 50), HeatFixture.trips(.usa, count: 50))
        let mixed = HeatFixture.trips(.mixed, count: 50)
        XCTAssertTrue(mixed.contains { $0.countries.contains { $0.code == "US" } })
        XCTAssertTrue(mixed.contains { $0.countries.contains { $0.code == "LT" } })
        XCTAssertTrue(mixed.allSatisfy { $0.distanceMeters > 10_000 && $0.segments[0].points.count > 4 })
    }

    func testSeparateSegmentsDrawNoGapLines() throws {
        var input = MapSceneInput(segments: line(kaunas, vilnius) + line(klaipeda, kaunas))
        let places = try PlaceIndex.bundled()
        XCTAssertTrue(try MapSceneBuilder.build(input: input, places: places, size: (390, 360))
            .routes.contains { $0.kind == .gap }, "one trip: a break is a recording gap")
        input.connectsSegments = false
        XCTAssertTrue(try MapSceneBuilder.build(input: input, places: places, size: (390, 360))
            .routes.allSatisfy { $0.kind == .recorded })
    }
}
