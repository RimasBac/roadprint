import XCTest
import SwiftData
import CloudKit
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

    // MARK: processing (ROA-43)

    /// 60 km straight north, a point every 100 m, 3 s apart: long enough to survive the privacy trim.
    private func longTrip() -> Trip {
        let points = (0..<600).map { i in
            TrackPoint(latitude: 40.5 + Double(i) * 0.0009, longitude: -111.9, altitude: 1_300,
                       timestamp: Date(timeIntervalSince1970: 1_000_000 + Double(i) * 3),
                       horizontalAccuracy: 5, verticalAccuracy: 3)
        }
        return Trip(createdAt: Date(timeIntervalSince1970: 1_000_000), status: .completed,
                    points: points, endedAt: points.last?.timestamp)
    }

    func testRemoveDuplicatesKeepsNewestUpdate() async throws {
        let container = try SwiftDataTripStore.makeContainer(inMemory: true)
        let store = SwiftDataTripStore(container: container)
        let old = trip(at: 100, points: 2)
        var newer = old
        newer.updatedAt = old.updatedAt.addingTimeInterval(60)
        try await store.save(old)
        // A second record with the same id, as a second device would sync it.
        let context = ModelContext(container)
        let copy = TripRecord()
        context.insert(copy)
        copy.id = newer.id
        copy.createdAt = newer.createdAt
        copy.updatedAt = newer.updatedAt
        copy.statusRaw = newer.status.rawValue
        try context.save()

        let removed = try await store.removeDuplicates()
        XCTAssertEqual(removed, 1)
        let all = try await store.allTrips()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.updatedAt, newer.updatedAt)
    }

    func testDeleteRemovesEveryIdenticalCopyAndRemoveDuplicatesKeepsOne() async throws {
        let container = try SwiftDataTripStore.makeContainer(inMemory: true)
        let store = SwiftDataTripStore(container: container)
        let t = trip(at: 100)
        try await store.save(t)
        let context = ModelContext(container)
        let copy = TripRecord()
        context.insert(copy)
        copy.id = t.id
        copy.createdAt = t.createdAt
        copy.updatedAt = t.updatedAt
        copy.statusRaw = t.status.rawValue
        try context.save()

        XCTAssertEqual(try store.removeDuplicates(), 0)
        let listed = try await store.allTrips()
        XCTAssertEqual(listed.map(\.id), [t.id])

        try await store.delete(id: t.id)
        let after = try await store.allTrips()
        XCTAssertTrue(after.isEmpty)
        let gone = try await store.trip(id: t.id)
        XCTAssertNil(gone)
    }

    func testProcessingDeletesRawPointsAndStoresDecodableRoute() async throws {
        let container = try SwiftDataTripStore.makeContainer(inMemory: true)
        let store = SwiftDataTripStore(container: container)
        let raw = longTrip()
        try await store.save(raw)
        let service = TripProcessingService(store: store)

        let pending = try await store.allTrips().filter(TripProcessingService.needsProcessing)
        XCTAssertEqual(pending.count, 1)
        await service.processPending()

        // The stored record: no raw points, route decodes, summary and places present.
        let context = ModelContext(container)
        let records = try context.fetch(FetchDescriptor<TripRecord>())
        XCTAssertEqual(records.count, 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertNil(record.pointsData)
        let route = try JSONDecoder().decode(ProcessedRoute.self, from: try XCTUnwrap(record.routeData))
        XCTAssertFalse(route.segments.isEmpty)
        XCTAssertNotNil(record.summaryData)

        let fetched = try await store.trip(id: raw.id)
        XCTAssertEqual(fetched?.points, [])
        XCTAssertEqual(fetched?.route, route)
        XCTAssertGreaterThan(fetched?.summary?.distanceMeters ?? 0, 50_000)
        XCTAssertEqual(fetched?.schemaVersion, Trip.processedSchemaVersion)
        XCTAssertFalse(TripProcessingService.needsProcessing(try XCTUnwrap(fetched)))
    }

    func testRecordingTripIsNotProcessed() {
        var t = longTrip()
        t.status = .recording
        XCTAssertFalse(TripProcessingService.needsProcessing(t))
    }

    // MARK: ROA-108 sync

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("roa108-\(UUID().uuidString).store")
    }

    func testTwoStoresOnOneFileDedupeIdempotentlyAndDeletedStaysDeleted() async throws {
        let url = tempURL()
        let a = SwiftDataTripStore(container: try SwiftDataTripStore.makeContainer(url: url))
        let b = SwiftDataTripStore(container: try SwiftDataTripStore.makeContainer(url: url))
        let t = trip(at: 100)
        try await a.save(t)
        // Same id from a second context; fetch in `b` sees the record, so insert a duplicate by hand.
        var older = t
        older.updatedAt = t.updatedAt.addingTimeInterval(-10)
        let context = ModelContext(try SwiftDataTripStore.makeContainer(url: url))
        let copy = TripRecord()
        context.insert(copy)
        copy.id = older.id
        copy.createdAt = older.createdAt
        copy.updatedAt = older.updatedAt
        copy.statusRaw = older.status.rawValue
        try context.save()

        _ = try await a.removeDuplicates()
        let second = try await b.removeDuplicates()
        XCTAssertEqual(second, 0)
        let again = try await a.removeDuplicates()
        XCTAssertEqual(again, 0)
        let all = try await b.allTrips()
        XCTAssertEqual(all.map(\.id), [t.id])

        try await a.delete(id: t.id)
        _ = try await b.removeDuplicates()
        let afterDelete = try await b.allTrips()
        XCTAssertTrue(afterDelete.isEmpty)
    }

    func testSwitchableStoreRebuildKeepsEveryTrip() async throws {
        // Uses the default store file name inside a clean Application Support is not possible here,
        // so exercise the container swap on a temp URL through two stores with sync off.
        let url = tempURL()
        let first = SwiftDataTripStore(container: try SwiftDataTripStore.makeContainer(url: url, sync: false))
        let trips = (0..<3).map { trip(at: Double($0) * 10) }
        for t in trips { try await first.save(t) }
        try await first.flush()
        // "on" with inMemory false would need iCloud; reopen the file with sync:false twice (off→off→off).
        for _ in 0..<2 {
            let reopened = SwiftDataTripStore(container: try SwiftDataTripStore.makeContainer(url: url, sync: false))
            let all = try await reopened.allTrips()
            XCTAssertEqual(Set(all.map(\.id)), Set(trips.map(\.id)))
        }
    }

    func testPartialFailureQuotaExceededMapsToQuotaFull() {
        let inner = CKError(.quotaExceeded)
        let error = CKError(.partialFailure, userInfo: [
            CKPartialErrorsByItemIDKey: [CKRecord.ID(recordName: "x"): inner]
        ])
        XCTAssertEqual(CloudKitSyncService.issue(for: error), .quotaFull)
        XCTAssertEqual(CloudKitSyncService.issue(for: CKError(.notAuthenticated)), .noAccount)
        XCTAssertEqual(CloudKitSyncService.issue(for: CKError(.networkFailure)), .error)
    }

    @MainActor
    func testRemoteChangeSignalReloadsModel() async throws {
        let store = InMemoryTripStore()
        let hub = SyncChangeHub()
        var env = AppEnvironment.preview
        env.tripStore = store
        env.syncService = HubSyncService(hub: hub)
        let model = RecordingModel(environment: env, syncDebounce: .milliseconds(20))
        await model.bootstrap()
        XCTAssertTrue(model.rows.isEmpty)
        let watcher = Task { await model.watchSyncChanges() }
        defer { watcher.cancel() }

        var done = Trip(createdAt: Date(timeIntervalSince1970: 100), status: .completed)
        done.endedAt = Date(timeIntervalSince1970: 200)
        try await store.save(done)
        for _ in 0..<5 { hub.send() }  // a burst
        for _ in 0..<50 where model.rows.isEmpty { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(model.rows.map(\.id), [done.id])
    }
}

private actor HubSyncService: SyncService {
    private let hub: SyncChangeHub
    init(hub: SyncChangeHub) { self.hub = hub }
    func status() -> SyncStatus { .available }
    func setEnabled(_ enabled: Bool) {}
    nonisolated func changes() -> AsyncStream<Void> { hub.stream() }
}
