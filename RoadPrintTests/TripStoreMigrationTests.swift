import XCTest
import SwiftData
import RoadPrintCore
@testable import RoadPrint

/// Frozen copy of `TripRecord` as shipped up to TestFlight build 16 (before ADR 0005 encrypted
/// the dates, summary, places and main road). Never edit it: it is the store an updating user has.
/// The class name must stay `TripRecord` so SwiftData sees the same entity.
enum TripSchemaV1 {
    @Model
    final class TripRecord {
        var id: UUID = UUID()
        var createdAt: Date = Date(timeIntervalSince1970: 0)
        var updatedAt: Date = Date(timeIntervalSince1970: 0)
        var schemaVersion: Int = 1
        var statusRaw: String = TripStatus.recording.rawValue
        var visibilityRaw: String = Visibility.private.rawValue
        var endedAt: Date?
        @Attribute(.externalStorage, .allowsCloudEncryption)
        var pointsData: Data?
        var storedStartedAt: Date?
        @Attribute(.externalStorage, .allowsCloudEncryption)
        var routeData: Data?
        var summaryData: Data?
        var placesData: Data?
        var mainRoadData: Data?

        init() {}
    }
}

final class TripStoreMigrationTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rp-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// One trip still recording (raw points) and one processed trip with every blob filled.
    private func fixtureTrips() -> [Trip] {
        let points = (0..<30).map { i in
            TrackPoint(latitude: 54.9 + Double(i) * 0.001, longitude: 23.9, altitude: 60 + Double(i),
                       timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double(i)),
                       horizontalAccuracy: 5, verticalAccuracy: 3)
        }
        let recording = Trip(createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                             updatedAt: Date(timeIntervalSince1970: 1_700_000_030),
                             schemaVersion: 1, status: .recording, points: points)
        let route = ProcessedRoute(
            segments: [RouteSegment(points: [RoutePoint(latitude: 54.9, longitude: 23.9, altitude: 60),
                                             RoutePoint(latitude: 54.7, longitude: 25.3, altitude: 120)])],
            start: ApproximateArea(centerLatitude: 54.9, centerLongitude: 23.9, radiusMeters: 800),
            end: ApproximateArea(centerLatitude: 54.7, centerLongitude: 25.3, radiusMeters: 800),
            summit: RoutePoint(latitude: 54.8, longitude: 24.6, altitude: 180))
        let processed = Trip(createdAt: Date(timeIntervalSince1970: 1_690_000_000),
                             updatedAt: Date(timeIntervalSince1970: 1_690_010_000),
                             status: .completed,
                             endedAt: Date(timeIntervalSince1970: 1_690_009_000),
                             storedStartedAt: Date(timeIntervalSince1970: 1_690_000_100),
                             summary: TripSummaryStats(distanceMeters: 102_400, movingTimeSeconds: 4_000,
                                                       elapsedSeconds: 4_300, gapCount: 1),
                             route: route,
                             places: TripPlaces(countries: [PlaceRef(code: "LT", name: "Lithuania")],
                                                regions: [PlaceRef(code: "LT-VL", name: "Vilnius County")]),
                             mainRoad: MainRoad(network: .eRoad, ref: "E85", countryCode: "LT"))
        return [recording, processed]
    }

    /// Writes the trips exactly as the V1 `SwiftDataTripStore.apply` did.
    private func writeV1Store(at url: URL, trips: [Trip]) throws {
        let schema = Schema([TripSchemaV1.TripRecord.self])
        let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let encoder = JSONEncoder()
        for trip in trips {
            let r = TripSchemaV1.TripRecord()
            r.id = trip.id
            r.createdAt = trip.createdAt
            r.updatedAt = trip.updatedAt
            r.schemaVersion = trip.schemaVersion
            r.statusRaw = trip.status.rawValue
            r.visibilityRaw = trip.visibility.rawValue
            r.endedAt = trip.endedAt
            r.pointsData = trip.points.isEmpty ? nil : try encoder.encode(trip.points)
            r.storedStartedAt = trip.storedStartedAt
            r.routeData = try trip.route.map { try encoder.encode($0) }
            r.summaryData = try trip.summary.map { try encoder.encode($0) }
            r.placesData = try trip.places.map { try encoder.encode($0) }
            r.mainRoadData = try trip.mainRoad.map { try encoder.encode($0) }
            context.insert(r)
        }
        try context.save()
    }

    func testV1StoreOpensWithCurrentSchemaAndKeepsEveryTrip() async throws {
        let url = directory.appendingPathComponent("trips.store")
        let trips = fixtureTrips()
        try writeV1Store(at: url, trips: trips)

        let store = SwiftDataTripStore(container: try SwiftDataTripStore.makeContainer(url: url))
        let read = try await store.allTrips()

        XCTAssertEqual(read.count, trips.count)
        for trip in trips {
            let migrated = try await store.trip(id: trip.id)
            XCTAssertEqual(migrated, trip, "trip \(trip.id) changed during migration")
        }
        let active = try await store.activeTrip()
        XCTAssertEqual(active?.id, trips[0].id)
    }

    func testMigratedStoreStaysWritable() async throws {
        let url = directory.appendingPathComponent("trips.store")
        let trips = fixtureTrips()
        try writeV1Store(at: url, trips: trips)

        let store = SwiftDataTripStore(container: try SwiftDataTripStore.makeContainer(url: url))
        let fetched = try await store.trip(id: trips[1].id)
        var edited = try XCTUnwrap(fetched)
        edited.updatedAt = Date(timeIntervalSince1970: 1_690_020_000)
        try await store.save(edited)
        let fresh = SwiftDataTripStore(container: try SwiftDataTripStore.makeContainer(url: url))
        let reread = try await fresh.trip(id: edited.id)
        XCTAssertEqual(reread, edited)
        let count = try await fresh.allTrips().count
        XCTAssertEqual(count, trips.count)
    }
}
