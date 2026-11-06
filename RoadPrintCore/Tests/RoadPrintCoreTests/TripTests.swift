import Foundation
import Testing
@testable import RoadPrintCore

// MARK: helpers

let t0 = Date(timeIntervalSince1970: 1_780_000_000)

func pt(_ lat: Double, _ lon: Double, t: TimeInterval) -> TrackPoint {
    TrackPoint(latitude: lat, longitude: lon, timestamp: t0.addingTimeInterval(t), horizontalAccuracy: 5)
}

enum Fixtures {
    struct Missing: Error { let name: String }

    static func data(_ name: String, ext: String = "gpx") throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures") else {
            throw Missing(name: name)
        }
        return try Data(contentsOf: url)
    }

    static func points(_ name: String) throws -> [TrackPoint] {
        try GPXReader.parse(data(name))
    }

    struct Expected: Decodable {
        var pointCount: Int
        var distanceMeters: Double
        var movingTimeSeconds: Double
        var elapsedSeconds: Double
        var gapCount: Int
        var longStopCount: Int
        var expectedStatus: String
    }

    static func expected(_ name: String) throws -> Expected {
        let all = try JSONDecoder().decode([String: Expected].self, from: data("expected", ext: "json"))
        return try #require(all[name])
    }
}

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ start: Date) { current = start }
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return current }
    func advance(_ s: TimeInterval) { lock.lock(); current = current.addingTimeInterval(s); lock.unlock() }
}

// MARK: distance

@Test func distanceTwoPointsHandChecked() {
    // One degree of longitude on the equator is R·π/180 = 111,195.08 m.
    let d = TripAnalyzer().distance(of: [pt(0, 0, t: 0), pt(0, 1, t: 10)])
    // 1 degree is itself a gap leg (> 2 km), so check the haversine directly.
    #expect(abs(Geo.distance(from: pt(0, 0, t: 0), to: pt(0, 1, t: 10)) - 111_195.08) < 1)
    #expect(d == 0)
    // 0.01 degree = 1,111.95 m, below the gap threshold.
    let short = TripAnalyzer().distance(of: [pt(0, 0, t: 0), pt(0, 0.01, t: 10)])
    #expect(abs(short - 1_111.9508) < 0.01)
}

@Test func distanceEdgeCases() {
    #expect(TripAnalyzer().distance(of: []) == 0)
    #expect(TripAnalyzer().distance(of: [pt(1, 1, t: 0)]) == 0)
}

@Test func distanceExcludesGapLegs() {
    let points = [pt(0, 0, t: 0), pt(0, 0.001, t: 10), pt(0, 0.1, t: 400), pt(0, 0.101, t: 410)]
    let d = TripAnalyzer().distance(of: points)
    #expect(abs(d - 2 * 111.1951) < 0.01)
}

// MARK: moving time

@Test func movingTimeCountsOnlyShortIntervals() {
    let points = [pt(0, 0, t: 0), pt(0, 0.001, t: 10), pt(0, 0.002, t: 130), pt(0, 0.003, t: 251)]
    // 10 + 120 counted; 121 is a stop.
    #expect(TripAnalyzer().movingTime(of: points) == 130)
}

// MARK: long stops

@Test func longStopDetected() {
    let nineHours: TimeInterval = 9 * 3600
    let points = [pt(0, 0, t: 0), pt(0, 0.001, t: 10), pt(0, 0.002, t: 10 + nineHours), pt(0, 0.003, t: 20 + nineHours)]
    let stops = TripAnalyzer().longStops(in: points)
    #expect(stops == [LongStop(startIndex: 1, endIndex: 2, duration: nineHours)])
}

@Test func longIntervalWithBigDisplacementIsNotAStop() {
    let points = [pt(0, 0, t: 0), pt(0, 0.05, t: 3 * 3600)]
    #expect(TripAnalyzer().longStops(in: points).isEmpty)
}

@Test func trailingStop() {
    let points = [pt(0, 0, t: 0), pt(0, 0.001, t: 10)]
    let recording = Trip(createdAt: t0, status: .recording, points: points)
    let analyzer = TripAnalyzer()
    let stop = analyzer.trailingStop(of: recording, now: t0.addingTimeInterval(10 + 3 * 3600))
    #expect(stop == LongStop(startIndex: 1, endIndex: 1, duration: 3 * 3600))
    #expect(analyzer.trailingStop(of: recording, now: t0.addingTimeInterval(10 + 3600)) == nil)
    var done = recording
    done.status = .completed
    #expect(analyzer.trailingStop(of: done, now: t0.addingTimeInterval(10 + 9 * 3600)) == nil)
    #expect(analyzer.trailingStop(of: Trip(createdAt: t0), now: t0.addingTimeInterval(9 * 3600)) == nil)
}

// MARK: gaps

@Test func gapsDetected() {
    let points = [pt(0, 0, t: 0), pt(0, 0.001, t: 10), pt(0, 0.1, t: 500)]
    let gaps = TripAnalyzer().gaps(in: points)
    #expect(gaps.count == 1)
    #expect(gaps[0].startIndex == 1 && gaps[0].endIndex == 2)
    #expect(gaps[0].duration == 490)
    #expect(TripAnalyzer().gaps(in: [pt(0, 0, t: 0), pt(0, 0.001, t: 10)]).isEmpty)
}

// MARK: fixtures

@Test(arguments: ["i80-ui-test", "i80-long-stop", "i80-gap"])
func fixtureMatchesExpected(name: String) throws {
    let points = try Fixtures.points(name)
    let expected = try Fixtures.expected(name)
    let analyzer = TripAnalyzer()
    #expect(points.count == expected.pointCount)
    let distance = analyzer.distance(of: points)
    #expect(abs(distance - expected.distanceMeters) / expected.distanceMeters < 0.005)
    #expect(analyzer.movingTime(of: points) == expected.movingTimeSeconds)
    #expect(analyzer.gaps(in: points).count == expected.gapCount)
    #expect(analyzer.longStops(in: points).count == expected.longStopCount)
    let trip = Trip(createdAt: points[0].timestamp, status: .completed, points: points, endedAt: points.last?.timestamp)
    let stats = analyzer.stats(for: trip)
    #expect(stats.elapsedSeconds == expected.elapsedSeconds)
    #expect(stats.gapCount == expected.gapCount)
}

@Test func longStopFixtureIsNineHours() throws {
    let stops = TripAnalyzer().longStops(in: try Fixtures.points("i80-long-stop"))
    #expect(stops.count == 1)
    #expect(stops[0].duration >= 9 * 3600)
}

// MARK: recorder

@Test func recorderStartRecordEnd() async throws {
    let store = InMemoryTripStore()
    let clock = TestClock(t0)
    let recorder = TripRecorder(store: store, clock: { clock.now() })
    let trip = try await recorder.start()
    #expect(trip.status == .recording)
    #expect(try await store.activeTrip()?.id == trip.id)

    clock.advance(60)
    try await recorder.record([pt(0, 0, t: 0), pt(0, 0.001, t: 10)])
    let mid = try #require(try await store.trip(id: trip.id))
    #expect(mid.points.count == 2)
    #expect(mid.updatedAt == t0.addingTimeInterval(60))

    clock.advance(60)
    let ended = try await recorder.end(at: t0.addingTimeInterval(100))
    #expect(ended.status == .completed)
    #expect(ended.endedAt == t0.addingTimeInterval(100))
    #expect(ended.updatedAt == t0.addingTimeInterval(120))
    #expect(try await store.activeTrip() == nil)
}

@Test func recorderGapMakesPartial() async throws {
    let store = InMemoryTripStore()
    let recorder = TripRecorder(store: store, clock: { t0 })
    _ = try await recorder.start()
    try await recorder.record(try Fixtures.points("i80-gap"))
    let ended = try await recorder.end(at: t0)
    #expect(ended.status == .partial)
}

@Test func recorderResumesAfterRelaunch() async throws {
    let store = InMemoryTripStore()
    let first = TripRecorder(store: store, clock: { t0 })
    let trip = try await first.start()
    try await first.record([pt(0, 0, t: 0)])

    let second = TripRecorder(store: store, clock: { t0 })
    let resumed = try await second.resumeIfNeeded()
    #expect(resumed?.id == trip.id)
    try await second.record([pt(0, 0.001, t: 10)])
    let ended = try await second.end(at: t0)
    #expect(ended.points.count == 2)
    #expect(try await second.resumeIfNeeded() == nil)
}

@Test func recorderErrors() async throws {
    let store = InMemoryTripStore()
    let recorder = TripRecorder(store: store, clock: { t0 })
    await #expect(throws: TripRecorderError.notRecording) { try await recorder.record([pt(0, 0, t: 0)]) }
    _ = try await recorder.start()
    await #expect(throws: TripRecorderError.alreadyRecording) { _ = try await recorder.start() }
    await #expect(throws: TripRecorderError.invalidStop) {
        _ = try await recorder.endAtStop(LongStop(startIndex: 5, endIndex: 6, duration: 1))
    }
}

@Test func recorderEndAtStopTruncates() async throws {
    let store = InMemoryTripStore()
    let recorder = TripRecorder(store: store, clock: { t0 })
    _ = try await recorder.start()
    let points = try Fixtures.points("i80-long-stop")
    try await recorder.record(points)
    let stop = try #require(TripAnalyzer().longStops(in: points).first)
    let ended = try await recorder.endAtStop(stop)
    #expect(ended.status == .completed)
    #expect(ended.points.count == stop.startIndex + 1)
    #expect(ended.endedAt == points[stop.startIndex].timestamp)
}

@Test func storeOrdersNewestFirstAndDeletes() async throws {
    let store = InMemoryTripStore()
    let old = Trip(createdAt: t0, status: .completed)
    let new = Trip(createdAt: t0.addingTimeInterval(100), status: .completed)
    try await store.save(old)
    try await store.save(new)
    #expect(try await store.allTrips().map(\.id) == [new.id, old.id])
    try await store.delete(id: new.id)
    #expect(try await store.trip(id: new.id) == nil)
    await #expect(throws: TripStoreError.tripNotFound(new.id)) {
        try await store.append([pt(0, 0, t: 0)], toTripWithID: new.id)
    }
}

// MARK: GPX

@Test func gpxParsesInlineDocument() throws {
    let xml = """
    <?xml version="1.0"?>
    <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1"><trk><trkseg>
    <trkpt lat="40.5" lon="-111.25"><ele>1300.5</ele><time>2026-06-01T14:00:00Z</time></trkpt>
    <trkpt lat="40.6" lon="-111.35"><time>2026-06-01T14:00:03.500Z</time></trkpt>
    </trkseg></trk></gpx>
    """
    let points = try GPXReader.parse(Data(xml.utf8))
    #expect(points.count == 2)
    #expect(points[0].latitude == 40.5 && points[0].longitude == -111.25)
    #expect(points[0].altitude == 1300.5)
    #expect(points[1].altitude == nil)
    #expect(points[0].timestamp == Date(timeIntervalSince1970: 1_780_322_400))
    #expect(abs(points[1].timestamp.timeIntervalSince(points[0].timestamp) - 3.5) < 0.001)
}

@Test func gpxRejectsBadInput() {
    #expect(throws: (any Error).self) { try GPXReader.parse(Data("<gpx><trkpt".utf8)) }
    let noTime = #"<gpx><trk><trkseg><trkpt lat="1" lon="2"></trkpt></trkseg></trk></gpx>"#
    #expect(throws: GPXReader.ParseError.missingOrInvalidTime) { try GPXReader.parse(Data(noTime.utf8)) }
    let badLat = #"<gpx><trk><trkseg><trkpt lat="95" lon="2"><time>2026-06-01T14:00:00Z</time></trkpt></trkseg></trk></gpx>"#
    #expect(throws: GPXReader.ParseError.invalidCoordinate) { try GPXReader.parse(Data(badLat.utf8)) }
}

@Test func gpxFixtureParses() throws {
    let points = try Fixtures.points("i80-ui-test")
    #expect(points.count == 300)
    #expect(points[0].altitude != nil)
}

// MARK: Codable and model

@Test func tripCodableRoundTrip() throws {
    let trip = Trip(
        createdAt: Date(timeIntervalSince1970: 1_780_000_000),
        status: .partial,
        points: [TrackPoint(latitude: 40.5, longitude: -111.25, altitude: 1300, timestamp: Date(timeIntervalSince1970: 1_780_000_010), horizontalAccuracy: 5, verticalAccuracy: 3)],
        endedAt: Date(timeIntervalSince1970: 1_780_000_020)
    )
    let data = try ExportJSON.encoder().encode(trip)
    let json = String(decoding: data, as: UTF8.self)
    #expect(json.contains("\"schemaVersion\" : 1"))
    #expect(json.contains("\"visibility\" : \"private\""))
    #expect(!json.lowercased().contains("speed"))
    #expect(!json.lowercased().contains("course"))
    #expect(try ExportJSON.decoder().decode(Trip.self, from: data) == trip)
}

@Test func profileCodableRoundTrip() throws {
    let profile = UserProfile(displayName: "Rimas", distanceUnit: .miles, startingCareerDistanceMeters: 160_934, createdAt: Date(timeIntervalSince1970: 1_780_000_000))
    let data = try ExportJSON.encoder().encode(profile)
    #expect(try ExportJSON.decoder().decode(UserProfile.self, from: data) == profile)
}

@Test func tripDerivedTimes() {
    let points = [pt(0, 0, t: 5), pt(0, 0.001, t: 15)]
    var trip = Trip(createdAt: t0, points: points)
    #expect(trip.startedAt == t0.addingTimeInterval(5))
    #expect(trip.effectiveEndedAt == t0.addingTimeInterval(15))
    trip.endedAt = t0.addingTimeInterval(99)
    #expect(trip.effectiveEndedAt == t0.addingTimeInterval(99))
    #expect(Trip(createdAt: t0).startedAt == nil)
    #expect(Trip.currentSchemaVersion == 1)
    #expect(Visibility.private.rawValue == "private")
}

@Test func distanceUnitDefault() {
    #expect(DistanceUnit.default(forUsesMetricSystem: true) == .kilometers)
    #expect(DistanceUnit.default(forUsesMetricSystem: false) == .miles)
}
