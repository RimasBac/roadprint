import XCTest
import RoadPrintCore
@testable import RoadPrint

final class ImportExportTests: XCTestCase {
    private func makeStore() throws -> SwiftDataTripStore {
        SwiftDataTripStore(container: try SwiftDataTripStore.makeContainer(inMemory: true))
    }

    private func trip(_ t: TimeInterval) -> Trip {
        let points = (0..<30).map { i in
            TrackPoint(latitude: 37 + Double(i) * 0.002, longitude: -122, altitude: 10,
                       timestamp: Date(timeIntervalSince1970: t + Double(i) * 10),
                       horizontalAccuracy: 5, verticalAccuracy: 3)
        }
        var trip = Trip(createdAt: Date(timeIntervalSince1970: t), status: .completed, points: points)
        trip.endedAt = Date(timeIntervalSince1970: t + 300)
        return trip
    }

    func testExportWipeImportRestoresTrips() async throws {
        let store = try makeStore()
        let trips = [trip(1_000), trip(5_000)]
        for t in trips { try await store.save(t) }
        let service = ImportExportService(store: store, processing: TripProcessingService(store: store))
        let profile = UserProfile(displayName: "", distanceUnit: .miles, createdAt: Date(timeIntervalSince1970: 0))

        let files = try await service.export(profile: profile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: files.json.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: files.gpx.path))
        let before = try await store.allTrips()

        for t in before { try await store.delete(id: t.id) }
        let empty = try await store.allTrips()
        XCTAssertTrue(empty.isEmpty)

        let plan = try await service.plan(fileAt: files.json, profile: profile)
        XCTAssertEqual(plan.found, 2)
        XCTAssertEqual(plan.toInsert.count, 2)
        try await service.apply(plan)
        let after = try await store.allTrips()
        XCTAssertEqual(after, before)

        // Importing the same file again finds everything already here.
        let again = try await service.plan(fileAt: files.json, profile: profile)
        XCTAssertEqual(again.alreadyHere, 2)
        XCTAssertEqual(again.importCount, 0)
    }

    func testExportWithNoTripsThrows() async throws {
        let store = try makeStore()
        let service = ImportExportService(store: store, processing: TripProcessingService(store: store))
        let profile = UserProfile(displayName: "", distanceUnit: .miles, createdAt: Date())
        do {
            _ = try await service.export(profile: profile)
            XCTFail("expected error")
        } catch let error as ImportExportService.TransferError {
            XCTAssertEqual(error, .nothingToExport)
        }
    }
}
