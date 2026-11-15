import Foundation
import Testing
#if canImport(FoundationXML)
import FoundationXML
#endif
@testable import RoadPrintCore

// Whole-millisecond dates, so a round trip is exact.
private func ms(_ seconds: Double) -> Date { Date(timeIntervalSince1970: (seconds * 1000).rounded() / 1000) }
private let base = 1_780_000_000.0

private func rawPoints(_ n: Int, start: Double) -> [TrackPoint] {
    (0..<n).map {
        TrackPoint(latitude: 40.76 + Double($0) * 0.001, longitude: -111.89, altitude: $0 % 2 == 0 ? 1288.4 : nil,
                   timestamp: ms(start + Double($0) * 10.25), horizontalAccuracy: 5, verticalAccuracy: 3)
    }
}

private func processed(_ i: Int, status: TripStatus = .completed, segments: [[RoutePoint]]) -> Trip {
    let start = base + Double(i) * 86_400
    let area = ApproximateArea(centerLatitude: 40.8, centerLongitude: -111.7, radiusMeters: 8421.7)
    return Trip(
        id: UUID(), createdAt: ms(start), updatedAt: ms(start + 1080), schemaVersion: 2, status: status,
        points: [], endedAt: ms(start + 1080), storedStartedAt: ms(start),
        summary: TripStats(distanceMeters: 29836.1, movingTimeSeconds: 1074, elapsedSeconds: 1080, gapCount: status == .partial ? 1 : 0),
        route: ProcessedRoute(segments: segments.map { RouteSegment(points: $0) }, start: area, end: area,
                              summit: segments.first?.first),
        places: TripPlaces(countries: [PlaceRef(code: "US", name: "United States")], regions: [PlaceRef(code: "US-UT", name: "Utah")]),
        mainRoad: MainRoad(network: .usInterstate, ref: "80", countryCode: "US"))
}

private func mixedTrips() -> [Trip] {
    let line = [RoutePoint(latitude: 40.8214, longitude: -111.7142, altitude: 1620),
                RoutePoint(latitude: 40.912, longitude: -111.21, altitude: 1795)]
    let more = [RoutePoint(latitude: 41.0, longitude: -111.0)]
    var recording = Trip(createdAt: ms(base + 10), schemaVersion: 1, status: .recording, points: rawPoints(3, start: base + 10))
    recording.updatedAt = ms(base + 40)
    let unprocessed = Trip(createdAt: ms(base + 5), schemaVersion: 1, status: .completed,
                           points: rawPoints(4, start: base + 5), endedAt: ms(base + 60))
    var short = processed(3, segments: [])
    short.route?.summit = nil
    return [
        recording, unprocessed,
        processed(1, segments: [line]),
        processed(2, status: .partial, segments: [line, more]),
        short,
        processed(4, segments: [line]),
    ]
}

private func scrubbedText(_ data: Data) -> String { String(decoding: data, as: UTF8.self).lowercased() }

// MARK: JSON archive

@Test func archiveRoundTripsMixedTrips() throws {
    let profile = UserProfile(displayName: "A & B", distanceUnit: .miles, startingCareerDistanceMeters: 1234.5,
                              createdAt: ms(base), updatedAt: ms(base + 1))
    let archive = TripArchive(exportedAt: ms(base + 99), appVersion: "1.0 (15)", profile: profile, trips: mixedTrips())
    let decoded = try TripArchive.decode(try archive.encoded())
    #expect(decoded == archive)
    #expect(decoded.trips.count == 6)
    #expect(Set(decoded.trips.map(\.status)) == Set(TripStatus.allCases))
}

@Test func archiveIsNewestFirst() {
    let archive = TripArchive(exportedAt: ms(base), appVersion: "1", trips: mixedTrips())
    let starts = archive.trips.map { $0.startedAt ?? $0.createdAt }
    #expect(starts == starts.sorted(by: >))
}

@Test func archiveWithoutProfileRoundTrips() throws {
    let archive = TripArchive(exportedAt: ms(base), appVersion: "1", trips: [])
    #expect(try TripArchive.decode(archive.encoded()) == archive)
}

@Test func readsFrozenArchiveV1() throws {
    let archive = try TripArchive.decode(Fixtures.data("archive-v1", ext: "json"))
    #expect(archive.archiveVersion == 1)
    #expect(archive.appVersion == "1.0 (15)")
    #expect(archive.profile?.displayName == "Test Driver")
    #expect(archive.trips.count == 2)
    #expect(archive.trips[0].schemaVersion == 1)
    #expect(archive.trips[0].points.count == 2)
    #expect(archive.trips[1].route?.segments.first?.points.count == 2)
    #expect(archive.trips[1].mainRoad?.ref == "80")
}

@Test func archiveContainsTheTripV1Fixture() throws {
    let tripJSON = try Fixtures.data("trip-v1", ext: "json")
    let trip = try ExportJSON.decoder().decode(Trip.self, from: tripJSON)
    let frozen = try TripArchive.decode(Fixtures.data("archive-v1", ext: "json"))
    #expect(frozen.trips.contains(trip))
}

private func jsonData(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object) }

@Test func rejectsNewerArchiveVersion() throws {
    let data = try jsonData(["format": "roadprint-archive", "archiveVersion": 2, "trips": []])
    #expect(throws: ArchiveError.newerVersion(2)) { try TripArchive.decode(data) }
}

@Test func rejectsTripWithNewerSchema() throws {
    var object = try #require(JSONSerialization.jsonObject(with: Fixtures.data("archive-v1", ext: "json")) as? [String: Any])
    var trips = try #require(object["trips"] as? [[String: Any]])
    trips[0]["schemaVersion"] = 3
    object["trips"] = trips
    let data = try jsonData(object)
    #expect(throws: ArchiveError.newerVersion(3)) { try TripArchive.decode(data) }
}

@Test func rejectsOtherJSON() throws {
    let tripOnly = try Fixtures.data("trip-v1", ext: "json")
    #expect(throws: ArchiveError.notARoadPrintFile) { try TripArchive.decode(tripOnly) }
    let other = try jsonData(["format": "something-else", "archiveVersion": 1])
    #expect(throws: ArchiveError.notARoadPrintFile) { try TripArchive.decode(other) }
    let array = Data("[1,2]".utf8)
    #expect(throws: ArchiveError.notARoadPrintFile) { try TripArchive.decode(array) }
}

@Test func rejectsCorruptData() throws {
    #expect(throws: ArchiveError.corrupt) { try TripArchive.decode(Data("not json {".utf8)) }
    let damaged = try jsonData(["format": "roadprint-archive", "archiveVersion": 1, "trips": [["id": "x", "schemaVersion": 1]]])
    #expect(throws: ArchiveError.corrupt) { try TripArchive.decode(damaged) }
}

@Test func fivehundredTripsRoundTrip() throws {
    let trips: [Trip] = HeatFixture.trips(.mixed, count: 500).enumerated().map { i, f in
        var trip = processed(i, segments: [])
        trip.route = ProcessedRoute(segments: f.segments)
        trip.places = TripPlaces(countries: f.countries, regions: f.regions)
        trip.mainRoad = f.mainRoad
        trip.summary?.distanceMeters = f.distanceMeters
        return trip
    }
    let archive = TripArchive(exportedAt: ms(base), appVersion: "1", trips: trips)
    let data = try archive.encoded()
    #expect(try TripArchive.decode(data) == archive)
    #expect(archive.trips.count == 500)
    #expect(GPXWriter.document(trips: trips).count > 0)
}

@Test func noSpeedOrCourseInOutput() throws {
    let archive = TripArchive(exportedAt: ms(base), appVersion: "1", trips: mixedTrips())
    let json = scrubbedText(try archive.encoded())
    let gpx = scrubbedText(GPXWriter.document(trips: archive.trips))
    for word in ["speed", "course"] {
        #expect(!json.contains(word))
        #expect(!gpx.contains(word))
    }
}

// MARK: GPX

private final class TrackCounter: NSObject, XMLParserDelegate {
    var tracks = 0, segments = 0
    var points: [[Double]] = []
    var times = 0
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes a: [String: String]) {
        switch name {
        case "trk": tracks += 1
        case "trkseg": segments += 1
        case "trkpt": points.append([Double(a["lat"]!)!, Double(a["lon"]!)!])
        case "time": times += 1
        default: break
        }
    }
}

private func count(_ data: Data) -> TrackCounter {
    let counter = TrackCounter()
    let parser = XMLParser(data: data)
    parser.delegate = counter
    #expect(parser.parse())
    return counter
}

@Test func gpxMatchesGoldenFile() throws {
    // Build both trips with fixed dates that match the golden file.
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let start = try #require(iso.date(from: "2026-06-01T15:00:00.250Z"))
    let raw = Trip(createdAt: start, schemaVersion: 1, status: .completed, points: [
        TrackPoint(latitude: 40.760157, longitude: -111.889808, altitude: 1288.4, timestamp: start, horizontalAccuracy: 5),
        TrackPoint(latitude: 40.760457, longitude: -111.889808, timestamp: start.addingTimeInterval(9.75), horizontalAccuracy: 5),
    ])
    var done = processed(0, segments: [
        [RoutePoint(latitude: 40.8214, longitude: -111.7142, altitude: 1620), RoutePoint(latitude: 40.912, longitude: -111.21, altitude: 1795)],
        [RoutePoint(latitude: 41.0, longitude: -111.0)],
    ])
    done.storedStartedAt = try #require(iso.date(from: "2026-06-01T14:00:00.000Z"))
    let output = String(decoding: GPXWriter.document(trips: [raw, done]), as: UTF8.self)
    let golden = String(decoding: try Fixtures.data("export-golden", ext: "gpx"), as: UTF8.self)
    #expect(output == golden)
}

@Test func gpxRawTripReadsBackWithGPXReader() throws {
    let trip = Trip(createdAt: ms(base), schemaVersion: 1, status: .completed, points: rawPoints(5, start: base))
    let back = try GPXReader.parse(GPXWriter.document(trips: [trip]))
    #expect(back.count == 5)
    for (a, b) in zip(back, trip.points) {
        #expect(abs(a.latitude - b.latitude) < 1e-7)
        #expect(abs(a.longitude - b.longitude) < 1e-7)
        #expect(abs(a.timestamp.timeIntervalSince(b.timestamp)) < 0.001)
        #expect((a.altitude == nil) == (b.altitude == nil))
    }
}

@Test func gpxProcessedTripKeepsSegmentsAndCoordinates() {
    let a = [RoutePoint(latitude: 40.8214, longitude: -111.7142, altitude: 1620), RoutePoint(latitude: 40.912, longitude: -111.21)]
    let b = [RoutePoint(latitude: 41.0, longitude: -111.0)]
    let counter = count(GPXWriter.document(trips: [processed(1, segments: [a, b])]))
    #expect(counter.tracks == 1)
    #expect(counter.segments == 2)
    #expect(counter.times == 0)
    #expect(counter.points == [[40.8214, -111.7142], [40.912, -111.21], [41.0, -111.0]])
}

@Test func gpxShortTripWritesNoTrack() {
    let counter = count(GPXWriter.document(trips: [processed(1, segments: [])]))
    #expect(counter.tracks == 0)
    let empty = count(GPXWriter.document(trips: []))
    #expect(empty.tracks == 0)
}

@Test func gpxEscapesText() {
    #expect(GPXWriter.escape("a<b>&\"c'") == "a&lt;b&gt;&amp;&quot;c&apos;")
}

@Test func exportFileNamesUseUTCDate() throws {
    let iso = ISO8601DateFormatter()
    let late = try #require(iso.date(from: "2026-11-15T23:59:59Z"))
    #expect(ExportFileNames.json(on: late) == "RoadPrint-2026-11-15.json")
    #expect(ExportFileNames.gpx(on: late.addingTimeInterval(2)) == "RoadPrint-2026-11-16.gpx")
}
