import XCTest
import RoadPrintCore
@testable import RoadPrint

@MainActor
final class RecordingStateTests: XCTestCase {
    func testDeniedPermissionDoesNotCreateTrip() async throws {
        defer { UserDefaults.standard.removeObject(forKey: "RPDebugLocationAccess") }
        UserDefaults.standard.set("blocked", forKey: "RPDebugLocationAccess")
        let store = InMemoryTripStore()
        let model = RecordingModel(environment: AppEnvironment(tripStore: store, makeLocationSource: { NoFixLocationSource() }))
        await model.start()
        XCTAssertFalse(model.isRecording)
        XCTAssertEqual(model.permissionAlert, .locationOff)
        let trips = try await store.allTrips()
        XCTAssertTrue(trips.isEmpty)
    }

    func testApproximateNeedsConsentAndGPSWaitUsesSessionTime() async throws {
        defer { UserDefaults.standard.removeObject(forKey: "RPDebugLocationAccess") }
        UserDefaults.standard.set("approximate", forKey: "RPDebugLocationAccess")
        let store = InMemoryTripStore()
        let model = RecordingModel(environment: AppEnvironment(tripStore: store, makeLocationSource: { NoFixLocationSource() }))
        await model.start()
        XCTAssertEqual(model.permissionAlert, .preciseOff)
        XCTAssertFalse(model.isRecording)
        let beforeConsent = try await store.allTrips()
        XCTAssertTrue(beforeConsent.isEmpty)
        await model.startAnyway()
        XCTAssertTrue(model.isRecording)
        let since = try XCTUnwrap(model.gpsUnavailableSince)
        XCTAssertFalse(model.waitingForGPS(at: since.addingTimeInterval(14.9)))
        XCTAssertTrue(model.waitingForGPS(at: since.addingTimeInterval(15)))
        XCTAssertEqual(model.startFeedback, 1)
        await model.end()
        XCTAssertFalse(model.waitingForGPS(at: since.addingTimeInterval(60)))
        XCTAssertEqual(model.endFeedback, 1)
    }

    func testPermissionRevokedWhileConsentAlertIsOpenDoesNotStart() async throws {
        defer { UserDefaults.standard.removeObject(forKey: "RPDebugLocationAccess") }
        UserDefaults.standard.set("blocked", forKey: "RPDebugLocationAccess")
        let store = InMemoryTripStore()
        let model = RecordingModel(environment: AppEnvironment(tripStore: store, makeLocationSource: { NoFixLocationSource() }))
        await model.startAnyway()
        XCTAssertFalse(model.isRecording)
        XCTAssertEqual(model.permissionAlert, .locationOff)
        let trips = try await store.allTrips()
        XCTAssertTrue(trips.isEmpty)
    }
    func testFirstFixClearsGPSWaitAndResumeKeepsOriginalStart() async throws {
        defer { UserDefaults.standard.removeObject(forKey: "RPDebugLocationAccess") }
        UserDefaults.standard.set("precise", forKey: "RPDebugLocationAccess")
        let store = InMemoryTripStore()
        let originalStart = Date().addingTimeInterval(-3600)
        let recorder = TripRecorder(store: store, clock: { originalStart })
        _ = try await recorder.start()
        let model = RecordingModel(environment: AppEnvironment(tripStore: store, makeLocationSource: { OneFixSource() }))
        await model.bootstrap()
        XCTAssertTrue(model.isRecording)
        XCTAssertEqual(model.startedAt, originalStart)
        XCTAssertEqual(model.startFeedback, 0, "Resuming must not fire a Start haptic")
        for _ in 0..<100 where model.gpsUnavailableSince != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(model.gpsUnavailableSince)
        XCTAssertFalse(model.waitingForGPS(at: Date().addingTimeInterval(60)))
        await model.end()
    }

}

private struct OneFixSource: LocationSource {
    func points() -> AsyncStream<TrackPoint> {
        AsyncStream { continuation in
            continuation.yield(TrackPoint(latitude: 40, longitude: -110, timestamp: Date(), horizontalAccuracy: 5))
            continuation.finish()
        }
    }
    func stop() {}
}
