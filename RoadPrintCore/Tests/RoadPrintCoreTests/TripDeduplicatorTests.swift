import Foundation
import Testing
@testable import RoadPrintCore

@Suite struct TripDeduplicatorTests {
    private let date = Date(timeIntervalSince1970: 1_780_000_000)

    private func trip() -> Trip {
        Trip(createdAt: date, status: .completed)
    }

    @Test func newestWinsEvenWithLessData() {
        var older = trip()
        older.route = ProcessedRoute(segments: [])
        var newer = older
        newer.updatedAt = date.addingTimeInterval(1)
        newer.route = nil

        #expect(TripDeduplicator.plan([newer, older]).keep == [0])
        #expect(TripDeduplicator.plan([older, newer]).keep == [1])
    }

    @Test func routePresenceWinsBeforePointCount() {
        var raw = trip()
        raw.points = [TrackPoint(latitude: 40, longitude: -111, timestamp: date, horizontalAccuracy: 5)]
        var processed = raw
        processed.points = []
        processed.route = ProcessedRoute(segments: [])

        #expect(TripDeduplicator.plan([raw, processed]).keep == [1])
    }

    @Test func morePointsWinInBothTripFormats() {
        let raw = trip()
        var moreRaw = raw
        moreRaw.points = [TrackPoint(latitude: 40, longitude: -111, timestamp: date, horizontalAccuracy: 5)]
        #expect(TripDeduplicator.plan([raw, moreRaw]).keep == [1])

        let segment = RouteSegment(points: [RoutePoint(latitude: 40, longitude: -111)])
        var processed = raw
        processed.route = ProcessedRoute(segments: [segment])
        var moreProcessed = processed
        moreProcessed.route?.segments.append(segment)
        #expect(TripDeduplicator.plan([processed, moreProcessed]).keep == [1])
    }

    @Test func fullTieSelectsSameContentsAcrossPermutations() throws {
        let a = trip()
        var b = a
        b.endedAt = date.addingTimeInterval(0.0001)
        var c = a
        c.endedAt = date.addingTimeInterval(0.0002)
        let permutations = [[a, b, c], [a, c, b], [b, a, c], [b, c, a], [c, a, b], [c, b, a]]
        let expectedIndex = try #require(TripDeduplicator.plan(permutations[0]).keep.first)
        let expected = permutations[0][expectedIndex]
        for trips in permutations {
            let index = try #require(TripDeduplicator.plan(trips).keep.first)
            #expect(trips[index] == expected)
        }
    }

    @Test func localRecordingSurvivesNewerFinishedCopy() {
        var recording = trip()
        recording.status = .recording
        var finished = recording
        finished.status = .partial
        finished.updatedAt = date.addingTimeInterval(1)

        #expect(TripDeduplicator.plan([finished, recording]).keep == [1])
        #expect(TripDeduplicator.plan([recording, finished]).delete == [1])
        #expect(TripDeduplicator.plan([recording, finished], protectRecordings: false).keep == [1])
    }

    @Test func snapshotPlanKeepsOneIndexPerIDAndDeletesOnlyOtherCopies() {
        let original = trip()
        let other = trip()
        var middle = original
        middle.updatedAt = date.addingTimeInterval(1)
        var newest = original
        newest.updatedAt = date.addingTimeInterval(2)

        let plan = TripDeduplicator.plan([middle, other, original, newest, other])
        #expect(plan.keep == [3, 1])
        #expect(plan.delete == [0, 2])  // the identical copy of `other` (4) is left for the store to hide

        let empty = TripDeduplicator.plan([])
        #expect(empty.keep.isEmpty && empty.delete.isEmpty)
    }

    @Test func identicalCopiesAreNotDeletedWithoutStableKeys() {
        let a = trip()
        let plan = TripDeduplicator.plan([a, a, a])
        #expect(plan.delete.isEmpty)
        #expect(plan.keep.count == 1)
    }

    @Test func identicalCopiesKeepTheSameSurvivorInAnyOrder() {
        let a = trip()
        let keys = ["rec-c", "rec-a", "rec-b"]
        for order in [[0, 1, 2], [2, 1, 0], [1, 2, 0], [1, 0, 2]] {
            let plan = TripDeduplicator.plan(order.map { _ in a }, tieBreakers: order.map { keys[$0] })
            #expect(plan.keep.count == 1)
            #expect(plan.delete.count == 2)
            #expect(order[plan.keep[0]] == 1)  // "rec-a" survives everywhere
        }
    }

    @Test func differentContentStillDeletedWithoutKeys() {
        let a = trip()
        var b = a
        b.updatedAt = a.updatedAt.addingTimeInterval(5)
        #expect(TripDeduplicator.plan([a, b]).delete == [0])
    }
}
