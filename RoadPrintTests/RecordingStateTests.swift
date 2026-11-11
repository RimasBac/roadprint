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

    func testStartAnywayDoesNotBypassDeniedPermission() async throws {
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
        try await recorder.record([TrackPoint(latitude: 40, longitude: -110,
                                               timestamp: originalStart.addingTimeInterval(30), horizontalAccuracy: 5)])
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

    func testDelayedFixIsRecordedWithoutClearingWaitingForGPS() async throws {
        defer { UserDefaults.standard.removeObject(forKey: "RPDebugLocationAccess") }
        UserDefaults.standard.set("precise", forKey: "RPDebugLocationAccess")
        let start = Date(timeIntervalSince1970: 1000)
        let clock = RecordingTestClock(start)
        let source = ControlledLocationSource()
        let store = InMemoryTripStore()
        let model = RecordingModel(
            environment: AppEnvironment(tripStore: store, makeLocationSource: { source }),
            now: { clock.now })
        await model.start()
        clock.advance(by: 60)
        let delayed = TrackPoint(latitude: 40, longitude: -110,
                                 timestamp: start.addingTimeInterval(10), horizontalAccuracy: 5)
        source.yield(delayed)
        let first = try await recordedPoints(count: 1, store: store)
        XCTAssertEqual(first, [delayed], "A valid delayed fix must reach persistent storage")
        XCTAssertTrue(model.waitingForGPS(at: clock.now), "Delayed route data must not clear the GPS wait")
        let recent = TrackPoint(latitude: 40, longitude: -109.99, timestamp: clock.now, horizontalAccuracy: 5)
        source.yield(recent)
        let both = try await recordedPoints(count: 2, store: store)
        XCTAssertEqual(both, [delayed, recent])
        XCTAssertFalse(model.waitingForGPS(at: clock.now))
        XCTAssertNil(model.gpsUnavailableSince)
        await model.end()
    }

    private func recordedPoints(count: Int, store: any TripStore) async throws -> [TrackPoint] {
        for _ in 0..<100 {
            let points = try await store.activeTrip()?.points ?? []
            if points.count == count { return points }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Recording consumer did not persist the expected sample count")
        return try await store.activeTrip()?.points ?? []
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

private struct ControlledLocationSource: LocationSource {
    let stream: AsyncStream<TrackPoint>
    let continuation: AsyncStream<TrackPoint>.Continuation
    init() {
        let channel = AsyncStream<TrackPoint>.makeStream()
        stream = channel.stream
        continuation = channel.continuation
    }
    func points() -> AsyncStream<TrackPoint> { stream }
    func yield(_ point: TrackPoint) { continuation.yield(point) }
    func stop() { continuation.finish() }
}

private final class RecordingTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    init(_ date: Date) { self.date = date }
    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return date
    }
    func advance(by seconds: TimeInterval) {
        lock.lock()
        date = date.addingTimeInterval(seconds)
        lock.unlock()
    }
}
