import Foundation
import Testing
@testable import RoadPrintCore

private func rp(_ lat: Double, _ lon: Double = 0, alt: Double? = nil) -> RoutePoint {
    RoutePoint(latitude: lat, longitude: lon, altitude: alt)
}

/// A northbound trace of `count` points, ~111 m and 10 s apart.
private func north(_ count: Int, alt: (Int) -> Double? = { _ in nil }) -> [TrackPoint] {
    (0..<count).map { i in
        TrackPoint(latitude: Double(i) * 0.001, longitude: 0, altitude: alt(i),
                   timestamp: t0.addingTimeInterval(Double(i) * 10), horizontalAccuracy: 5)
    }
}

/// Metres along `path` of a point that lies on it.
private func pathPosition(of p: RoutePoint, along path: [TrackPoint]) -> Double {
    let rps = path.map { RoutePoint(latitude: $0.latitude, longitude: $0.longitude) }
    let xy = DouglasPeucker.project(rps + [p])
    let target = xy[xy.count - 1]
    var best = (dist: Double.infinity, index: 0)
    for i in 0..<(rps.count - 1) {
        let d = DouglasPeucker.distance(target, toSegment: xy[i], xy[i + 1])
        if d < best.dist { best = (d, i) }
    }
    var position = 0.0
    for i in 0..<best.index { position += Geo.distance(from: path[i], to: path[i + 1]) }
    return position + Geo.distance(from: rps[best.index], to: p)
}

private func pathLength(_ path: [TrackPoint]) -> Double {
    zip(path, path.dropFirst()).reduce(0) { $0 + Geo.distance(from: $1.0, to: $1.1) }
}

// MARK: trim distance

@Test func trimDistanceIsDeterministicAndInRange() {
    let id = UUID(uuidString: "6C0E4F9A-1B7D-4C8E-9A52-0D3F5E7A1B22")!
    #expect(PrivacyTrim.trimDistance(for: id) == PrivacyTrim.trimDistance(for: id))
    var seen = Set<Double>()
    for _ in 0..<200 {
        let d = PrivacyTrim.trimDistance(for: UUID())
        #expect(d >= 8_000 && d < 10_000)
        seen.insert(d)
    }
    #expect(seen.count > 150)
    let other = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    #expect(PrivacyTrim.trimDistance(for: other) != PrivacyTrim.trimDistance(for: id))
}

@Test func fnv1aMatchesReferenceVector() {
    // 16 zero bytes: FNV-1a 64 = (offset basis ^ 0) * prime, sixteen times.
    var h: UInt64 = 0xcbf2_9ce4_8422_2325
    for _ in 0..<16 { h = (h ^ 0) &* 0x0000_0100_0000_01b3 }
    #expect(PrivacyTrim.fnv1a(UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))) == h)
}

// MARK: trim

@Test func trimCutsExactDistanceAndAreasCoverTheEnds() throws {
    let path = (0...200).map { rp(Double($0) * 0.001) }  // ~22.2 km
    let total = pathLength(path.map { TrackPoint(latitude: $0.latitude, longitude: 0, timestamp: t0, horizontalAccuracy: 5) })
    let r = try #require(PrivacyTrim.trim([path], trimMeters: 8_000))
    let pts = r.segments[0]
    let kept = zip(pts, pts.dropFirst()).reduce(0) { $0 + Geo.distance(from: $1.0, to: $1.1) }
    #expect(abs(kept - (total - 16_000)) < 0.5)
    #expect(r.start == ApproximateArea(centerLatitude: pts[0].latitude, centerLongitude: 0, radiusMeters: 8_000))
    #expect(abs(Geo.distance(from: path[0], to: pts[0]) - 8_000) < 0.5)
    #expect(abs(Geo.distance(from: path.last!, to: pts.last!) - 8_000) < 0.5)
}

@Test func trimAcrossAnUnfilledGapAddsNoLength() throws {
    let a = (0...100).map { rp(Double($0) * 0.001) }          // ~11.1 km
    let b = (0...100).map { rp(5 + Double($0) * 0.001) }      // ~11.1 km, far away
    let r = try #require(PrivacyTrim.trim([a, b], trimMeters: 8_000))
    #expect(r.segments.count == 2)
    // 22.2 km of path total: ~3.1 km kept in each segment.
    for seg in r.segments {
        let len = zip(seg, seg.dropFirst()).reduce(0) { $0 + Geo.distance(from: $1.0, to: $1.1) }
        #expect(abs(len - 3_100) < 100)
    }
}

@Test func shortTripGetsOneCircle() throws {
    let raw = north(109)  // ~12 km
    let out = TripProcessor().process(Trip(createdAt: t0, points: raw))
    let route = try #require(out.route)
    #expect(route.segments.isEmpty)
    #expect(route.summit == nil)
    let area = try #require(route.start)
    #expect(route.end == area)
    let trim = PrivacyTrim.trimDistance(for: out.id)
    #expect(area.radiusMeters == trim)
    for p in [raw.first!, raw.last!] {
        #expect(Geo.distance(lat1: area.centerLatitude, lon1: area.centerLongitude, lat2: p.latitude, lon2: p.longitude) <= area.radiusMeters)
    }
    #expect(out.summary?.distanceMeters ?? 0 > 11_000)  // stats still use the full trace
}

@Test func shortTripRadiusGrowsWithPath() throws {
    let path = (0...153).map { rp(Double($0) * 0.001) }  // ~17 km, just above 2 × 8 km
    let r = try #require(PrivacyTrim.trim([path], trimMeters: 8_000))
    #expect(r.segments.isEmpty)
    let half = Geo.distance(from: path[0], to: path[153]) / 2
    #expect(r.start.radiusMeters > 8_000 && abs(r.start.radiusMeters - half) < 1)
}

@Test func justOverShortLimitKeepsARoute() throws {
    let path = (0...200).map { rp(Double($0) * 0.001) }  // ~22.2 km > 18 km
    #expect(try #require(PrivacyTrim.trim([path], trimMeters: 8_000)).segments.count == 1)
    #expect(PrivacyTrim.trim([], trimMeters: 8_000) == nil)
}

// MARK: processor

@Test func i80FixtureIsTrimmed() throws {
    let raw = try Fixtures.points("i80-ui-test")
    let trip = Trip(id: UUID(uuidString: "6C0E4F9A-1B7D-4C8E-9A52-0D3F5E7A1B22")!, createdAt: t0, points: raw)
    let out = TripProcessor().process(trip)
    #expect(out.schemaVersion == 2)
    let route = try #require(out.route)
    let cleaned = RouteCleaner().clean(raw).points
    let total = pathLength(cleaned)
    let trim = PrivacyTrim.trimDistance(for: trip.id)
    #expect(!route.segments.isEmpty)
    for p in route.segments.flatMap(\.points) {
        let pos = pathPosition(of: p, along: cleaned)
        #expect(pos >= trim - 1 && pos <= total - trim + 1)
    }
    let start = try #require(route.start), end = try #require(route.end)
    #expect(start.radiusMeters == trim && end.radiusMeters == trim)
    let a = cleaned.first!, b = cleaned.last!
    #expect(Geo.distance(lat1: start.centerLatitude, lon1: start.centerLongitude, lat2: a.latitude, lon2: a.longitude) <= trim)
    #expect(Geo.distance(lat1: end.centerLatitude, lon1: end.centerLongitude, lat2: b.latitude, lon2: b.longitude) <= trim)
    // Areas are centred on the first and last retained points.
    #expect(start.centerLatitude == route.segments.first?.points.first?.latitude)
    #expect(end.centerLatitude == route.segments.last?.points.last?.latitude)
}

@Test func sameUUIDSameOutputDifferentUUIDDifferentTrim() throws {
    let raw = try Fixtures.points("i80-ui-test")
    let id1 = UUID(uuidString: "6C0E4F9A-1B7D-4C8E-9A52-0D3F5E7A1B22")!
    let id2 = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    let one = TripProcessor().process(Trip(id: id1, createdAt: t0, points: raw))
    #expect(TripProcessor().process(Trip(id: id1, createdAt: t0, points: raw)) == one)
    let two = TripProcessor().process(Trip(id: id2, createdAt: t0, points: raw))
    #expect(one.route?.start?.radiusMeters != two.route?.start?.radiusMeters)
    for r in [one.route?.start?.radiusMeters, two.route?.start?.radiusMeters] {
        #expect((8_000...10_000).contains(r ?? 0))
    }
}

@Test func summitIsKeptAndIgnoresTheTrimmedEnds() throws {
    // 44 km straight road: DP would drop a mid-road peak. Index 5 is trimmed away.
    let raw = north(400) { i in i == 5 ? 9_000 : (i == 200 ? 3_000 : 100) }
    let out = TripProcessor().process(Trip(createdAt: t0, points: raw))
    let route = try #require(out.route)
    let summit = try #require(route.summit)
    #expect(summit.altitude == 3_000)
    #expect(abs(summit.latitude - 0.2) < 1e-9)
    #expect(route.segments.flatMap(\.points).contains(summit))
}

@Test func encodedRouteHasNoTimeSpeedOrAccuracy() throws {
    let raw = try Fixtures.points("i80-ui-test")
    let out = TripProcessor().process(Trip(createdAt: t0, points: raw))
    let data = try ExportJSON.encoder().encode(out)
    let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let route = try #require(root["route"])
    func keys(_ any: Any) -> Set<String> {
        if let d = any as? [String: Any] { return Set(d.keys).union(d.values.flatMap { keys($0) }) }
        if let a = any as? [Any] { return a.reduce(into: Set<String>()) { $0.formUnion(keys($1)) } }
        return []
    }
    let found = keys(route)
    #expect(found.isDisjoint(with: ["timestamp", "speed", "horizontalAccuracy", "verticalAccuracy", "course"]))
    #expect(found.isSuperset(of: ["start", "end", "centerLatitude", "centerLongitude", "radiusMeters"]))
}

// MARK: schema versions

@Test func readsV1FixtureAndProcessedV2() throws {
    let v1 = try ExportJSON.decoder().decode(Trip.self, from: Fixtures.data("trip-v1", ext: "json"))
    #expect(v1.schemaVersion == 1 && v1.points.count == 2 && v1.route == nil)
    // v1 → process → v2 → encode → decode round trip.
    let v2 = TripProcessor().process(v1)
    #expect(v2.schemaVersion == 2 && v2.route != nil)
    #expect(try ExportJSON.decoder().decode(Trip.self, from: ExportJSON.encoder().encode(v2)) == v2)
    // v1 re-encodes as v1.
    let again = try ExportJSON.decoder().decode(Trip.self, from: ExportJSON.encoder().encode(v1))
    #expect(again == v1)
}

@Test func processedLongTripRoundTrips() throws {
    let raw = try Fixtures.points("i80-ui-test")
    let out = TripProcessor().process(Trip(createdAt: t0, points: raw))
    #expect(out.route?.segments.isEmpty == false)
    #expect(try ExportJSON.decoder().decode(Trip.self, from: ExportJSON.encoder().encode(out)) == out)
}

@Test func rejectsNewerSchema() throws {
    let text = String(decoding: try Fixtures.data("trip-v1", ext: "json"), as: UTF8.self)
        .replacingOccurrences(of: "\"schemaVersion\" : 1", with: "\"schemaVersion\" : 3")
    #expect(throws: DecodingError.self) {
        try ExportJSON.decoder().decode(Trip.self, from: Data(text.utf8))
    }
}
