import CoreLocation
import Foundation
import XCTest
import RoadPrintCore
@testable import RoadPrint

@MainActor
final class CoreLocationSourceTests: XCTestCase {
    func testDelayedRouteFixIsKeptWhilePreSessionCacheIsExcluded() async {
        let start = Date(timeIntervalSince1970: 1000)
        let received = start.addingTimeInterval(60)
        let delayed = start.addingTimeInterval(10)
        let recent = received.addingTimeInterval(-1)
        let (stream, continuation) = AsyncStream<TrackPoint>.makeStream()
        let signals = SignalLog()
        let session = CoreLocationSource.Session(
            continuation: continuation, signalHandler: { signals.append($0) },
            sessionStartedAt: start, now: { received })
        let manager = CLLocationManager()

        session.locationManager(manager, didUpdateLocations: [location(at: start.addingTimeInterval(-1)), location(at: delayed)])
        XCTAssertEqual(signals.values, [false], "Delayed delivery must not report live GPS readiness")
        session.locationManager(manager, didUpdateLocations: [location(at: recent)])
        XCTAssertEqual(signals.values, [false, true])
        session.locationManager(manager, didUpdateLocations: [location(at: start.addingTimeInterval(-1))])
        XCTAssertEqual(signals.values, [false, true], "Obsolete cache must not affect this session")
        session.stop()
        var points: [TrackPoint] = []
        for await point in stream { points.append(point) }
        XCTAssertEqual(points.map(\.timestamp), [delayed, recent])
    }

    func testBatchReadinessDoesNotDependOnTimestampOrder() async {
        let start = Date(timeIntervalSince1970: 1000)
        let received = start.addingTimeInterval(60)
        let (stream, continuation) = AsyncStream<TrackPoint>.makeStream()
        let signals = SignalLog()
        let session = CoreLocationSource.Session(
            continuation: continuation, signalHandler: { signals.append($0) },
            sessionStartedAt: start, now: { received })
        session.locationManager(CLLocationManager(), didUpdateLocations: [
            location(at: received.addingTimeInterval(-1)), location(at: start.addingTimeInterval(10))
        ])
        session.stop()
        var count = 0
        for await _ in stream { count += 1 }
        XCTAssertEqual(count, 2)
        XCTAssertEqual(signals.values, [true], "An older sample after a recent one must still be saved")
    }

    private func location(at timestamp: Date) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: 40, longitude: -110), altitude: 0,
                   horizontalAccuracy: 5, verticalAccuracy: -1, timestamp: timestamp)
    }
}

private final class SignalLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Bool] = []
    func append(_ value: Bool) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
    var values: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
