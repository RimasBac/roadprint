import XCTest
import RoadPrintCore
@testable import RoadPrint

final class SwiftDataTripStoreTests: XCTestCase {
    private func makeStore(now: @escaping @Sendable () -> Date = { Date() }) throws -> SwiftDataTripStore {
        SwiftDataTripStore(container: try SwiftDataTripStore.makeContainer(inMemory: true), now: now)
    }

    private func point(_ i: Int) -> TrackPoint {
        TrackPoint(latitude: 37 + Double(i) * 0.001, longitude: -122, altitude: 10,
                   timestamp: Date(timeIntervalSince1970: 1_000 + Double(i)),
                   horizontalAccuracy: 5, verticalAccuracy: 3)
    }

    private func trip(at t: TimeInterval, status: TripStatus = .completed, points: Int = 0) -> Trip {
        Trip(createdAt: Date(timeIntervalSince1970: t), status: status,
             points: (0..<points).map(point))
    }

    func testSaveFetchRoundTrip() async throws {
        let store = try makeStore()
        var t = trip(at: 100, points: 5)
        t.endedAt = Date(timeIntervalSince1970: 2_000)
        try await store.save(t)
        let fetched = try await store.trip(id: t.id)
        XCTAssertEqual(fetched, t)
    }

    func testSaveTwiceUpdatesInsteadOfDuplicating() async throws {
        let store = try makeStore()
        var t = trip(at: 100)
        try await store.save(t)
        t.status = .partial
        try await store.save(t)
        let all = try await store.allTrips()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.status, .partial)
    }

    func testAppendIsVisibleToReads() async throws {
        let store = try makeStore()
        let t = trip(at: 100, status: .recording)
        try await store.save(t)
        try await store.append([point(0), point(1)], toTripWithID: t.id, updatedAt: Date(timeIntervalSince1970: 500))
        try await store.append([point(2)], toTripWithID: t.id, updatedAt: Date(timeIntervalSince1970: 600))
        let fetched = try await store.trip(id: t.id)
        XCTAssertEqual(fetched?.points, [point(0), point(1), point(2)])
        XCTAssertEqual(fetched?.updatedAt, Date(timeIntervalSince1970: 600))
    }

    func testAppendToMissingTripThrows() async throws {
        let store = try makeStore()
        let id = UUID()
        do {
            try await store.append([point(0)], toTripWithID: id, updatedAt: Date())
            XCTFail("expected error")
        } catch let error as TripStoreError {
            XCTAssertEqual(error, .tripNotFound(id))
        }
    }

    func testActiveTrip() async throws {
        let store = try makeStore()
        let none = try await store.activeTrip()
        XCTAssertNil(none)
        try await store.save(trip(at: 100))
        let rec = trip(at: 200, status: .recording)
        try await store.save(rec)
        let active = try await store.activeTrip()
        XCTAssertEqual(active?.id, rec.id)
    }

    func testDelete() async throws {
        let store = try makeStore()
        let t = trip(at: 100)
        try await store.save(t)
        try await store.delete(id: t.id)
        let fetched = try await store.trip(id: t.id)
        XCTAssertNil(fetched)
        let all = try await store.allTrips()
        XCTAssertTrue(all.isEmpty)
    }

    func testSortNewestFirst() async throws {
        let store = try makeStore()
        let a = trip(at: 100), b = trip(at: 300), c = trip(at: 200)
        for t in [a, b, c] { try await store.save(t) }
        let ids = try await store.allTrips().map(\.id)
        XCTAssertEqual(ids, [b.id, c.id, a.id])
    }

    func testBatchedAppendFlushesAtThreshold() async throws {
        let store = try makeStore()
        let t = trip(at: 100, status: .recording)
        try await store.save(t)
        for i in 0..<45 {
            try await store.append([point(i)], toTripWithID: t.id, updatedAt: Date(timeIntervalSince1970: 1_000 + Double(i)))
        }
        try await store.flush()
        let fetched = try await store.trip(id: t.id)
        XCTAssertEqual(fetched?.points.count, 45)
        XCTAssertEqual(fetched?.points.last, point(44))
    }
}
