import Foundation
import XCTest
@testable import RoadPrintCore

/// The temporary test-trip tool: place lookup by name and the made-up route.
final class TestRouteTests: XCTestCase {
    private let kaunas = GeoCoordinate(latitude: 54.90, longitude: 23.90)
    private let vilnius = GeoCoordinate(latitude: 54.69, longitude: 25.28)
    private let end = Date(timeIntervalSince1970: 1_800_000_000)

    func testPlaceLookupIgnoresCaseSpacesAndDiacritics() throws {
        let namer = try AreaNamer.bundled()
        let found = try XCTUnwrap(namer.place(named: "  kaunas "))
        XCTAssertEqual(found.name, "Kaunas")
        XCTAssertEqual(found.coordinate.latitude, 54.9, accuracy: 0.2)
        XCTAssertEqual(found.coordinate.longitude, 23.9, accuracy: 0.2)
        XCTAssertEqual(namer.place(named: "VILNIUS")?.name, "Vilnius")
        // A prefix finds the largest place that starts with it.
        XCTAssertEqual(namer.place(named: "Salt Lake")?.name, "Salt Lake City")
        // Diacritics are optional when typing.
        XCTAssertNotNil(namer.place(named: "Zurich"))
        XCTAssertNil(namer.place(named: "zzzzqq"))
        XCTAssertNil(namer.place(named: "   "))
    }

    func testRouteStartsAndEndsAtThePlacesAndLooksRecorded() throws {
        let points = TestRoute.points(from: kaunas, to: vilnius, endingAt: end, seed: 7)
        let first = try XCTUnwrap(points.first), last = try XCTUnwrap(points.last)
        XCTAssertLessThan(Geo.distance(lat1: first.latitude, lon1: first.longitude, lat2: 54.90, lon2: 23.90), 50)
        XCTAssertLessThan(Geo.distance(lat1: last.latitude, lon1: last.longitude, lat2: 54.69, lon2: 25.28), 50)
        XCTAssertEqual(last.timestamp, end)

        let direct = Geo.distance(lat1: 54.90, lon1: 23.90, lat2: 54.69, lon2: 25.28)
        var path = 0.0
        for (a, b) in zip(points, points.dropFirst()) {
            let step = Geo.distance(from: a, to: b), dt = b.timestamp.timeIntervalSince(a.timestamp)
            path += step
            XCTAssertLessThan(step, RecordingHeuristics.default.gapMinDisplacement / 2) // never a gap
            XCTAssertGreaterThan(dt, 0)
            XCTAssertLessThanOrEqual(dt, RecordingHeuristics.default.movingMaxInterval) // all moving time
            XCTAssertEqual(step / dt, TestRoute.speedMetersPerSecond, accuracy: 0.01)
        }
        // Curved like a road, but not a detour.
        XCTAssertGreaterThan(path, direct)
        XCTAssertLessThan(path, direct * 1.2)
        XCTAssertEqual(points, TestRoute.points(from: kaunas, to: vilnius, endingAt: end, seed: 7))
        XCTAssertNotEqual(points, TestRoute.points(from: kaunas, to: vilnius, endingAt: end, seed: 8))
    }

    func testRouteProcessesLikeARealTrip() throws {
        let points = TestRoute.points(from: kaunas, to: vilnius, endingAt: end)
        let trip = Trip(createdAt: points[0].timestamp, status: .completed, points: points, endedAt: end)
        let processed = TripProcessor(placeIndex: try PlaceIndex.bundled()).process(trip)
        XCTAssertEqual(processed.status, .completed)
        XCTAssertTrue(processed.points.isEmpty)
        let summary = try XCTUnwrap(processed.summary)
        XCTAssertEqual(summary.gapCount, 0)
        XCTAssertEqual(summary.distanceMeters, 92_000, accuracy: 12_000)
        XCTAssertEqual(summary.movingTimeSeconds, summary.distanceMeters / TestRoute.speedMetersPerSecond, accuracy: 60)
        // Long enough to keep a route line after the privacy trim.
        let route = try XCTUnwrap(processed.route)
        XCTAssertEqual(route.segments.count, 1)
        XCTAssertGreaterThan(route.segments[0].points.count, 2)
        XCTAssertEqual(processed.places?.countries.first?.name, "Lithuania")
    }

    func testLongDriveStaysUnderTheGapThresholdAndSamePlaceIsEmpty() {
        let lisbon = GeoCoordinate(latitude: 38.72, longitude: -9.14)
        let vladivostok = GeoCoordinate(latitude: 43.12, longitude: 131.89)
        let long = TestRoute.points(from: lisbon, to: vladivostok, endingAt: end)
        XCTAssertLessThanOrEqual(long.count, Int(TestRoute.targetPointCount) + 2)
        for (a, b) in zip(long, long.dropFirst()) {
            XCTAssertLessThan(Geo.distance(from: a, to: b), RecordingHeuristics.default.gapMinDisplacement)
        }
        XCTAssertTrue(TestRoute.points(from: kaunas, to: kaunas, endingAt: end).isEmpty)
    }
}
