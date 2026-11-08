import Foundation
import Testing
@testable import RoadPrintCore

private func processedI80() throws -> (Trip, [TrackPoint]) {
    let raw = try Fixtures.points("i80-ui-test")
    let trip = Trip(id: UUID(uuidString: "6C0E4F9A-1B7D-4C8E-9A52-0D3F5E7A1B22")!, createdAt: t0, points: raw)
    return (TripProcessor().process(trip), RouteCleaner().clean(raw).points)
}

private let utc = TimeZone(identifier: "UTC")!

@Test func shareSummaryIsNilForUnprocessedTrip() {
    #expect(TripShareSummary.make(from: Trip(createdAt: t0, points: [pt(0, 0, t: 0)]), options: ShareOptions(includeRoute: true, timeZone: utc)) == nil)
}

@Test func shareSummaryWithoutRouteHasNoCoordinatesOrTimes() throws {
    let (trip, _) = try processedI80()
    let s = try #require(TripShareSummary.make(from: trip, options: ShareOptions(includeRoute: false, timeZone: utc)))
    #expect(s.route == nil && s.start == nil && s.end == nil && s.summit == nil)
    let json = String(decoding: try JSONEncoder().encode(s), as: UTF8.self)
    for bad in ["timestamp", "speed", "accuracy", "latitude", "longitude", "Latitude", "Longitude", "route"] {
        #expect(!json.contains(bad), "\(bad)")
    }
    #expect(json.range(of: #"\d{2}:\d{2}"#, options: .regularExpression) == nil)
}

@Test func shareSummaryRouteIsCoarseAndKeepsTheTrim() throws {
    let (trip, cleaned) = try processedI80()
    let s = try #require(TripShareSummary.make(from: trip, options: ShareOptions(includeRoute: true, timeZone: utc)))
    let json = String(decoding: try JSONEncoder().encode(s), as: UTF8.self)
    for bad in ["timestamp", "speed", "Accuracy", "accuracy"] { #expect(!json.contains(bad), "\(bad)") }
    #expect(json.range(of: #"\d{2}:\d{2}"#, options: .regularExpression) == nil)
    let pts = try #require(s.route).flatMap(\.points)
    #expect(!pts.isEmpty)
    #expect(pts.count <= trip.route!.segments.flatMap(\.points).count)
    let total = pathLength(cleaned), trim = PrivacyTrim.trimDistance(for: trip.id)
    for p in pts {
        #expect(abs(p.latitude * 1e4 - (p.latitude * 1e4).rounded()) < 1e-6)
        #expect(abs(p.longitude * 1e4 - (p.longitude * 1e4).rounded()) < 1e-6)
        if let a = p.altitude { #expect(a == a.rounded()) }
        let pos = pathPosition(of: p, along: cleaned)
        #expect(pos >= trim - 50 && pos <= total - trim + 50)
    }
    #expect(s.start != nil && s.end != nil)
    #expect(s.tripID == trip.id)
    #expect(s.distanceMeters == trip.summary?.distanceMeters)
    #expect(s.badgeIDs.isEmpty)
    let back = try JSONDecoder().decode(TripShareSummary.self, from: JSONEncoder().encode(s))
    #expect(back == s)
    #expect(back.schemaVersion == 1)
}

@Test func shareDayUsesTheTimeZone() throws {
    var (trip, _) = try processedI80()
    trip.storedStartedAt = Date(timeIntervalSince1970: 1_780_000_000)  // late on the day in UTC
    let utcDay = try #require(TripShareSummary.make(from: trip, options: ShareOptions(includeRoute: false, timeZone: utc))).day
    let tokyo = try #require(TripShareSummary.make(from: trip, options: ShareOptions(includeRoute: false, timeZone: TimeZone(identifier: "Pacific/Kiritimati")!))).day
    #expect(utcDay == ShareDay(year: 2026, month: 5, day: 28))
    #expect(tokyo == ShareDay(year: 2026, month: 5, day: 29))
}
