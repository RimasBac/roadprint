import XCTest
import RoadPrintCore
@testable import RoadPrint

@MainActor
final class MenuTests: XCTestCase {
    private func environment(_ store: InMemoryTripStore) -> AppEnvironment {
        AppEnvironment(tripStore: store, makeLocationSource: { NoFixLocationSource() })
    }

    func testStoredUnitWinsAndBadValuesFallBack() {
        XCTAssertEqual(AppSettings.distanceUnit(stored: "miles", fallback: .kilometers), .miles)
        XCTAssertEqual(AppSettings.distanceUnit(stored: "kilometers", fallback: .miles), .kilometers)
        XCTAssertEqual(AppSettings.distanceUnit(stored: "", fallback: .miles), .miles)
        XCTAssertEqual(AppSettings.distanceUnit(stored: "furlongs", fallback: .kilometers), .kilometers)

        var base = environment(InMemoryTripStore())
        base.profile.distanceUnit = .miles
        XCTAssertEqual(base.withDistanceUnit(stored: "kilometers").profile.distanceUnit, .kilometers)
        XCTAssertEqual(base.withDistanceUnit(stored: "").profile.distanceUnit, .miles)
    }

    func testTripsGroupByMonthKeepingOrder() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let formatter = ISO8601DateFormatter()
        func row(_ iso: String) throws -> TripRowData {
            TripRowData(id: UUID(), date: try XCTUnwrap(formatter.date(from: iso)),
                        distanceMeters: 1, movingTimeSeconds: 1, placesLine: nil)
        }
        let rows = [try row("2026-11-12T10:00:00Z"), try row("2026-11-02T10:00:00Z"), try row("2026-10-30T10:00:00Z")]
        let months = TripRowData.byMonth(rows, calendar: calendar)
        XCTAssertEqual(months.map(\.rows.count), [2, 1])
        XCTAssertEqual(months[0].rows.map(\.id), [rows[0].id, rows[1].id])
        XCTAssertGreaterThan(months[0].id, months[1].id)
        XCTAssertTrue(TripRowData.byMonth([], calendar: calendar).isEmpty)
    }

    func testDeleteTripRemovesItFromStoreAndList() async throws {
        let store = InMemoryTripStore()
        let trip = Trip(createdAt: Date(timeIntervalSince1970: 1_000), status: .completed,
                        endedAt: Date(timeIntervalSince1970: 2_000),
                        summary: TripStats(distanceMeters: 5_000, movingTimeSeconds: 600, elapsedSeconds: 700, gapCount: 0))
        await store.save(trip)
        let model = RecordingModel(environment: environment(store))
        await model.bootstrap()
        XCTAssertEqual(model.rows.map(\.id), [trip.id])
        await model.deleteTrip(id: trip.id)
        XCTAssertTrue(model.rows.isEmpty)
        let gone = await store.trip(id: trip.id)
        XCTAssertNil(gone)
    }

    /// TEMPORARY test tool: a made-up drive is stored and counted like a recorded trip.
    func testAddTestTripStoresAProcessedTripAndRejectsBadInput() async throws {
        // The offline line, so the test doesn't depend on a map service (the real road is longer).
        UserDefaults.standard.set(true, forKey: "RPTestTripStraight")
        defer { UserDefaults.standard.removeObject(forKey: "RPTestTripStraight") }
        let store = InMemoryTripStore()
        let model = RecordingModel(environment: environment(store))
        await model.bootstrap()

        let unknown = await model.addTestTrip(from: "Kaunas", to: "Nowhereville")
        XCTAssertEqual(unknown, .failure(.unknownPlace("Nowhereville")))
        let same = await model.addTestTrip(from: "Kaunas", to: "kaunas")
        XCTAssertEqual(same, .failure(.samePlace))
        XCTAssertTrue(model.rows.isEmpty)

        let added = await model.addTestTrip(from: "kaunas", to: " Vilnius ")
        guard case .success(let id) = added else { return XCTFail("expected a trip, got \(added)") }
        XCTAssertEqual(model.rows.map(\.id), [id])
        XCTAssertEqual(model.rows[0].distanceMeters, 92_000, accuracy: 12_000)
        let fetched = await store.trip(id: id)
        let stored = try XCTUnwrap(fetched)
        XCTAssertEqual(stored.status, .completed)
        XCTAssertTrue(stored.points.isEmpty, "processed like a recorded trip: raw points are gone")
        XCTAssertEqual(stored.route?.segments.count, 1)
        XCTAssertNotNil(stored.summary)
    }
}
