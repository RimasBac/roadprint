import Foundation
import Testing
@testable import RoadPrintCore

private func ms(_ s: Double) -> Date { Date(timeIntervalSince1970: (s * 1000).rounded() / 1000) }
private let base = 1_780_000_000.0
private let now = ms(1_790_000_000)

private func trip(_ i: Int, updated: Double? = nil, status: TripStatus = .completed) -> Trip {
    let start = base + Double(i) * 86_400
    return Trip(id: UUID(), createdAt: ms(start), updatedAt: ms(updated ?? start + 1000), schemaVersion: 1,
                status: status,
                points: (0..<3).map { TrackPoint(latitude: 40 + Double($0) * 0.01, longitude: -111, timestamp: ms(start + Double($0) * 60), horizontalAccuracy: 5) },
                endedAt: ms(start + 120))
}

private func archive(_ trips: [Trip], profile: UserProfile? = nil) throws -> Data {
    try TripArchive(exportedAt: now, appVersion: "1.0 (1)", profile: profile, trips: trips).encoded()
}

private let blank = UserProfile(displayName: "", distanceUnit: .miles, createdAt: ms(base))
private func plan(_ d: Data, _ name: String = "f.json", existing: [Trip] = [], profile: UserProfile = blank) throws -> ImportPlan {
    try TripImporter.plan(data: d, fileName: name, existing: existing, localProfile: profile, now: now)
}

private func gpx(_ tracks: [String]) -> Data {
    Data("<?xml version=\"1.0\"?><gpx version=\"1.1\" xmlns=\"http://www.topografix.com/GPX/1/1\">\(tracks.joined())</gpx>".utf8)
}
private func trk(name: String = "Drive", timed: Bool, count: Int = 4, start: String = "2026-06-01T14:00:") -> String {
    let pts = (0..<count).map { i in
        "<trkpt lat=\"\(40 + Double(i) * 0.01)\" lon=\"-111\"><ele>1300</ele>\(timed ? "<time>\(start)\(String(format: "%02d", i * 10))Z</time>" : "")</trkpt>"
    }.joined()
    return "<trk><name>\(name)</name><trkseg>\(pts)</trkseg></trk>"
}

@Suite struct ImportTests {
    @Test func archiveIntoEmptyStore() throws {
        let trips = [trip(1), trip(2), trip(3)]
        let p = try plan(try archive(trips))
        #expect(p.found == 3 && p.toInsert.count == 3 && p.alreadyHere == 0 && p.toReplace.isEmpty && !p.needsProcessing)
    }

    @Test func mergeRules() throws {
        let a = trip(1), b = trip(2), c = trip(3), d = trip(4)
        var bNewer = b; bNewer.updatedAt = b.updatedAt.addingTimeInterval(500)
        var cOlder = c; cOlder.updatedAt = c.updatedAt.addingTimeInterval(-500)
        // local: a same, b older than the file, c newer than the file
        let p = try plan(try archive([a, bNewer, cOlder, d]), existing: [a, b, c])
        #expect(p.found == 4 && p.alreadyHere == 2 && p.toReplace.map(\.id) == [b.id] && p.toInsert.map(\.id) == [d.id])
    }

    @Test func idempotent() throws {
        let data = try archive([trip(1), trip(2)])
        let first = try plan(data)
        let second = try plan(data, existing: first.toInsert)
        #expect(second.toInsert.isEmpty && second.toReplace.isEmpty && second.alreadyHere == 2)
    }

    @Test func archiveDuplicatesUseSharedRuleAndPreserveTripOrder() throws {
        let original = trip(1)
        let other = trip(2)
        var richer = original
        richer.points.append(original.points[0])
        var older = richer
        older.updatedAt = original.updatedAt.addingTimeInterval(-1)
        older.points.append(original.points[0])

        var file = TripArchive(exportedAt: now, appVersion: "1.0 (1)", trips: [])
        file.trips = [original, other, older, richer]
        let p = try plan(try file.encoded())
        #expect(p.found == 2 && p.toInsert == [richer, other])

        let repeatImport = try plan(try archive([richer]), existing: [original])
        #expect(repeatImport.alreadyHere == 1 && repeatImport.toReplace.isEmpty)
    }

    @Test func recordingTripsSkipped() throws {
        let p = try plan(try archive([trip(1, status: .recording), trip(2)]))
        #expect(p.skipped.map(\.reason) == [.recording] && p.toInsert.count == 1 && p.found == 2)
        // A local recording is never replaced.
        var inc = trip(3); inc.updatedAt = ms(base * 2)
        var mine = inc; mine.status = .recording; mine.updatedAt = ms(base)
        #expect(try plan(try archive([inc]), existing: [mine]).alreadyHere == 1)
        var finished = mine; finished.status = .completed
        let duplicateLocal = try plan(try archive([inc]), existing: [finished, mine])
        #expect(duplicateLocal.alreadyHere == 1 && duplicateLocal.toReplace.isEmpty)
    }

    @Test func singleTripJSON() throws {
        let t = trip(1)
        let data = try ExportJSON.encoder().encode(t)
        #expect(try plan(data).toInsert.map(\.id) == [t.id])
    }

    @Test func gpxWithTimes() throws {
        let p = try plan(gpx([trk(timed: true), trk(name: "", timed: true, start: "2026-06-02T14:00:")]), "a.gpx")
        #expect(p.found == 2 && p.toInsert.count == 2 && p.needsProcessing)
        let t = p.toInsert[0]
        #expect(t.schemaVersion == 1 && t.status == .completed && t.createdAt == now && t.updatedAt == now)
        #expect(t.points.count == 4 && t.endedAt == t.points.last?.timestamp)
        #expect(t.id != p.toInsert[1].id)
    }

    @Test func gpxWithoutTimesPointsToJSON() throws {
        let p = try plan(gpx([trk(timed: false)]), "RoadPrint.gpx")
        #expect(p.toInsert.isEmpty && p.skipped.map(\.reason) == [.noTimes] && p.suggestsJSON)
    }

    @Test func gpxMixedAndTooShort() throws {
        let short = "<trk><name>Hop</name><trkseg><trkpt lat=\"40\" lon=\"-111\"><time>2026-06-03T10:00:00Z</time></trkpt><trkpt lat=\"40.0001\" lon=\"-111\"><time>2026-06-03T10:00:10Z</time></trkpt></trkseg></trk>"
        let p = try plan(gpx([trk(timed: true), trk(name: "Flat", timed: false), short]))
        #expect(p.found == 3 && p.toInsert.count == 1)
        #expect(p.skipped == [ImportSkip(name: "Flat", reason: .noTimes), ImportSkip(name: "Hop", reason: .tooShort)])
        #expect(!p.suggestsJSON)
    }

    @Test func gpxTwiceInsertsNothing() throws {
        let data = gpx([trk(timed: true)])
        let first = try plan(data)
        let second = try plan(data, existing: first.toInsert)
        #expect(second.toInsert.isEmpty && second.alreadyHere == 1)
    }

    @Test func errors() throws {
        #expect(throws: ImportError.empty) { try plan(Data()) }
        #expect(throws: ImportError.empty) { try plan(try archive([])) }
        #expect(throws: ImportError.empty) { try plan(gpx([])) }
        #expect(throws: ImportError.notARoadPrintFile) { try plan(Data("{\"hello\":1}".utf8)) }
        #expect(throws: ImportError.notARoadPrintFile) { try plan(Data("PK\u{3}\u{4}".utf8)) }
        #expect(throws: ImportError.notARoadPrintFile) { try plan(Data("<html></html>".utf8)) }
        let data = try archive([trip(1), trip(2)])
        #expect(throws: ImportError.corrupt) { try plan(data.prefix(data.count / 2)) }
        #expect(throws: ImportError.corrupt) { try plan(Data("{not json".utf8)) }
        let g = gpx([trk(timed: true)])
        #expect(throws: ImportError.corrupt) { try plan(g.prefix(g.count - 30)) }
    }

    @Test func newerVersions() throws {
        let s = String(decoding: try archive([trip(1)]), as: UTF8.self)
        let newerArchive = s.replacingOccurrences(of: "\"archiveVersion\" : 1", with: "\"archiveVersion\" : 9")
        #expect(throws: ImportError.newerVersion(9)) { try plan(Data(newerArchive.utf8)) }
        let newerTrip = s.replacingOccurrences(of: "\"schemaVersion\" : 1", with: "\"schemaVersion\" : 7")
        #expect(throws: ImportError.newerVersion(7)) { try plan(Data(newerTrip.utf8)) }
        #expect(!ImportError.newerVersion(2).message.isEmpty)
    }

    @Test func profileAdoption() throws {
        let theirs = UserProfile(displayName: "Rimas", distanceUnit: .kilometers, startingCareerDistanceMeters: 5000, createdAt: ms(base))
        let data = try archive([trip(1)], profile: theirs)
        #expect(try plan(data).profile == theirs)
        let filledIn = UserProfile(displayName: "Me", distanceUnit: .miles, createdAt: ms(base))
        #expect(try plan(data, profile: filledIn).profile == nil)
        let withMiles = UserProfile(displayName: "", distanceUnit: .miles, startingCareerDistanceMeters: 1, createdAt: ms(base))
        #expect(try plan(data, profile: withMiles).profile == nil)
        #expect(try plan(try archive([trip(1)])).profile == nil)
    }

    @Test func frozenFixtureImports() throws {
        let p = try plan(try Fixtures.data("archive-v1", ext: "json"))
        #expect(p.found == p.toInsert.count + p.skipped.count)
        #expect(p.found > 0)
    }
}
