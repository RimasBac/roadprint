import Foundation
import Testing
@testable import RoadPrintCore

// MARK: helpers

/// A northbound trace: ~111 m and 10 s per step, starting at (0, lon).
private func line(_ range: Range<Int>, lon: Double = 0, tOffset: TimeInterval = 0) -> [TrackPoint] {
    range.map { pt(Double($0) * 0.001, lon, t: Double($0) * 10 + tOffset) }
}

private func rp(_ lat: Double, _ lon: Double) -> RoutePoint { RoutePoint(latitude: lat, longitude: lon) }

// MARK: cleaning

@Test func cleanerDropsBadAccuracy() {
    var pts = line(0..<6)
    pts[2].horizontalAccuracy = -1
    pts[3].horizontalAccuracy = 100.5
    pts[4].horizontalAccuracy = 100
    let out = RouteCleaner().clean(pts)
    #expect(out.points.count == 4)
    #expect(out.status == .completed)
}

@Test func cleanerDropsSpike() {
    var pts = line(0..<10)
    pts[5] = pt(0.005, 0.5, t: 50)  // 55 km away, 10 s after its neighbour
    let out = RouteCleaner().clean(pts)
    #expect(out.segments.count == 1)
    #expect(out.points.count == 9)
    #expect(!out.points.contains { $0.longitude == 0.5 })
    #expect(out.status == .completed)
}

@Test func cleanerKeepsSustainedRelocationAsGap() {
    let pts = line(0..<5) + line(5..<10, lon: 0.5)
    let out = RouteCleaner().clean(pts)
    #expect(out.points.count == 10)
    #expect(out.segments.map(\.count) == [5, 5])
    #expect(out.unfilledGapCount == 1)
    #expect(out.status == .partial)
}

@Test func cleanerTrailingJumpIsASpike() {
    let pts = line(0..<5) + [pt(0.005, 0.5, t: 50)]
    #expect(RouteCleaner().clean(pts).points.count == 5)
}

@Test func cleanerFillsTunnelGap() {
    // 5 km in 300 s = 16.7 m/s.
    let pts = line(0..<5) + (5..<10).map { pt(Double($0) * 0.001 + 0.045, 0, t: Double($0) * 10 + 290) }
    let out = RouteCleaner().clean(pts)
    #expect(out.segments.count == 1)
    #expect(out.points.count == 10)
    #expect(out.filledGapCount == 1)
    #expect(out.unfilledGapCount == 0)
    #expect(out.status == .completed)
}

@Test(arguments: [
    (0.045, 3600.0),   // too long (> 15 min)
    (0.27, 800.0),     // too far (> 25 km), 33 m/s
    (0.20, 400.0),     // too fast (> 45 m/s), 55 m/s: not a spike either
])
func cleanerLongGapSplitsSegments(jumpLat: Double, jumpSeconds: Double) {
    let pts = line(0..<5) + (5..<10).map { pt(Double($0) * 0.001 + jumpLat, 0, t: Double($0) * 10 + jumpSeconds - 50) }
    let out = RouteCleaner().clean(pts)
    #expect(out.segments.map(\.count) == [5, 5])
    #expect(out.filledGapCount == 0)
    #expect(out.unfilledGapCount == 1)
    #expect(out.status == .partial)
}

// MARK: Douglas–Peucker

@Test func douglasPeuckerStraightLineCollapses() {
    let pts = (0...100).map { rp(Double($0) * 0.001, 10) }
    #expect(DouglasPeucker.simplifiedIndices(pts) == [0, 100])
}

@Test func douglasPeuckerKeepsCornerAndClampsTolerance() {
    // An L-shape: the corner is ~790 m from the chord, so it stays.
    let pts = (0...10).map { rp(Double($0) * 0.001, 0) } + (1...10).map { rp(0.01, Double($0) * 0.001) }
    #expect(DouglasPeucker.simplifiedIndices(pts) == [0, 10, 20])
    #expect(DouglasPeucker.clampedTolerance(1) == 10)
    #expect(DouglasPeucker.clampedTolerance(500) == 30)
    #expect(DouglasPeucker.clampedTolerance(15) == 15)
}

@Test func douglasPeuckerForceKeep() {
    let pts = (0...100).map { rp(Double($0) * 0.001, 10) }
    #expect(DouglasPeucker.simplifiedIndices(pts, forceKeep: [40, 77]) == [0, 40, 77, 100])
}

@Test func douglasPeuckerClosedLoop() {
    // Start == end: the chord is degenerate; the far side must still be kept.
    let pts = [rp(0, 0), rp(0.01, 0), rp(0.01, 0.01), rp(0, 0.01), rp(0, 0)]
    #expect(DouglasPeucker.simplifiedIndices(pts).count >= 3)
}

@Test func douglasPeuckerSegmentsKeepEndpoints() {
    let route = ProcessedRoute(segments: [
        RouteSegment(points: (0...20).map { rp(Double($0) * 0.001, 0) }),
        RouteSegment(points: (0...20).map { rp(1 + Double($0) * 0.001, 0) }),
    ])
    let out = DouglasPeucker.simplify(route)
    #expect(out.segments.map(\.points.count) == [2, 2])
    #expect(out.segments[1].points.first == rp(1, 0))
}

@Test func i80FixtureSimplifiesWithinTolerance() throws {
    let raw = try Fixtures.points("i80-ui-test")
    let pts = raw.map { RoutePoint(latitude: $0.latitude, longitude: $0.longitude, altitude: $0.altitude) }
    let tolerance = 15.0
    let kept = DouglasPeucker.simplifiedIndices(pts, tolerance: tolerance)
    #expect(kept.count * 5 <= pts.count)
    #expect(kept.first == 0 && kept.last == pts.count - 1)

    let xy = DouglasPeucker.project(pts)
    for (a, b) in zip(kept, kept.dropFirst()) {
        for i in (a + 1)..<max(a + 1, b) {
            #expect(DouglasPeucker.distance(xy[i], toSegment: xy[a], xy[b]) <= tolerance + 1e-6)
        }
    }
}

@Test func douglasPeucker20kPointsIsFast() {
    // A winding road: 20,000 points on a sine wave.
    let pts = (0..<20_000).map { rp(Double($0) * 0.0005, 5 + 0.01 * sin(Double($0) / 200)) }
    let clock = ContinuousClock()
    var kept: [Int] = []
    let elapsed = clock.measure { kept = DouglasPeucker.simplifiedIndices(pts) }
    #expect(elapsed < .seconds(1))
    #expect(kept.count < pts.count / 5)
}

// MARK: processor

@Test func processorProducesProcessedTrip() throws {
    let raw = try Fixtures.points("i80-ui-test")
    let trip = Trip(createdAt: t0, points: raw, endedAt: raw.last?.timestamp)
    let out = TripProcessor().process(trip)
    #expect(out.points.isEmpty)
    #expect(out.startedAt == raw.first?.timestamp)
    #expect(out.status == .completed)
    let summary = try #require(out.summary)
    let expected = try Fixtures.expected("i80-ui-test")
    #expect(abs(summary.distanceMeters - expected.distanceMeters) < 1)
    #expect(summary.elapsedSeconds == expected.elapsedSeconds)
    #expect(summary.gapCount == 0)
    let route = try #require(out.route)
    #expect(route.segments.count == 1)
    #expect(route.segments[0].points.count * 5 <= raw.count)
}

@Test func processorFillsTheI80FixtureGap() throws {
    // The fixture's gap is ~15 km in ~8.5 min (~29 m/s): a filled gap under ADR 0003.
    let raw = try Fixtures.points("i80-gap")
    let out = TripProcessor().process(Trip(createdAt: t0, points: raw))
    #expect(out.status == .completed)
    #expect(out.summary?.gapCount == 0)
    #expect(out.route?.segments.count == 1)
    // The straight line over the gap counts as driven distance.
    #expect((out.summary?.distanceMeters ?? 0) > 29_736 + 5_000)
}

@Test func processorSplitsOnUnfilledGap() {
    let raw = line(0..<5) + line(5..<10, lon: 0.5)
    let out = TripProcessor().process(Trip(createdAt: t0, points: raw))
    #expect(out.status == .partial)
    #expect(out.summary?.gapCount == 1)
    #expect(out.route?.segments.count == 2)
}

@Test func processedTripRoundTripsAndOldJSONStillDecodes() throws {
    let raw = try Fixtures.points("i80-ui-test")
    let out = TripProcessor().process(Trip(createdAt: t0, points: raw))
    let data = try ExportJSON.encoder().encode(out)
    #expect(try ExportJSON.decoder().decode(Trip.self, from: data) == out)

    let old = Trip(createdAt: t0, points: Array(raw.prefix(3)))
    let oldData = try ExportJSON.encoder().encode(old)
    let text = String(decoding: oldData, as: UTF8.self)
    #expect(!text.contains("route") && !text.contains("summary") && !text.contains("startedAt"))
    #expect(try ExportJSON.decoder().decode(Trip.self, from: oldData) == old)
}

@Test func routePointHasNoTimeOrAccuracy() throws {
    let data = try ExportJSON.encoder().encode(RoutePoint(latitude: 1, longitude: 2, altitude: 3))
    let keys = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys
    #expect(Set(keys) == ["latitude", "longitude", "altitude"])
}
