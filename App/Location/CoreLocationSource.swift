import CoreLocation
import CoreMotion
import Foundation
import RoadPrintCore

/// CoreLocation implementation of `LocationSource`. Background updates are on only between
/// `points()` and `stop()`. Speed and course are never read.
final class CoreLocationSource: LocationSource, @unchecked Sendable {
    private let lock = NSLock()
    private var session: Session?
    private var signalHandler: (@Sendable (Bool) -> Void)?

    func setSignalHandler(_ handler: @escaping @Sendable (Bool) -> Void) {
        lock.lock()
        signalHandler = handler
        lock.unlock()
    }

    func points() -> AsyncStream<TrackPoint> {
        let (stream, continuation) = AsyncStream<TrackPoint>.makeStream()
        lock.lock()
        let session = Session(continuation: continuation, signalHandler: signalHandler)
        self.session?.stop()
        self.session = session
        lock.unlock()
        DispatchQueue.main.async { session.start() }
        continuation.onTermination = { _ in session.stop() }
        return stream
    }

    func stop() {
        lock.lock()
        let session = self.session
        self.session = nil
        lock.unlock()
        session?.stop()
    }

    /// Created and driven on the main thread, so delegate callbacks arrive there too.
    private final class Session: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
        private let continuation: AsyncStream<TrackPoint>.Continuation
        private let lock = NSLock()
        private let signalHandler: (@Sendable (Bool) -> Void)?
        private var manager: CLLocationManager?
        private var altimeter: CMAltimeter?
        private var stopped = false
        // Fusion state, guarded by `lock`.
        private var relativeAltitude: Double?
        private var fusedAltitude: Double?
        private var relativeAtFused: Double?

        init(continuation: AsyncStream<TrackPoint>.Continuation, signalHandler: (@Sendable (Bool) -> Void)?) {
            self.signalHandler = signalHandler
            self.continuation = continuation
        }

        func start() {
            lock.lock()
            let alreadyStopped = stopped
            lock.unlock()
            if alreadyStopped { return }
            let manager = CLLocationManager()
            manager.delegate = self
            manager.desiredAccuracy = kCLLocationAccuracyBest
            manager.distanceFilter = 100
            manager.activityType = .automotiveNavigation
            manager.pausesLocationUpdatesAutomatically = false
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
            self.manager = manager
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            }
            manager.startUpdatingLocation()
            if CMAltimeter.isRelativeAltitudeAvailable() {
                let altimeter = CMAltimeter()
                self.altimeter = altimeter
                altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
                    guard let self, let meters = data?.relativeAltitude.doubleValue else { return }
                    self.lock.lock()
                    self.relativeAltitude = meters
                    self.lock.unlock()
                }
            }
        }

        func stop() {
            lock.lock()
            let wasStopped = stopped
            stopped = true
            lock.unlock()
            if wasStopped { return }
            continuation.finish()
            DispatchQueue.main.async {
                self.manager?.stopUpdatingLocation()
                self.manager?.allowsBackgroundLocationUpdates = false
                self.manager?.delegate = nil
                self.manager = nil
                self.altimeter?.stopRelativeAltitudeUpdates()
                self.altimeter = nil
            }
        }

        /// Complementary filter: barometer deltas smooth GPS altitude between fixes.
        private func fuse(gps: Double, verticalAccuracy: Double) -> Double? {
            guard verticalAccuracy >= 0 else { return nil }
            lock.lock()
            defer { lock.unlock() }
            guard let rel = relativeAltitude else {
                fusedAltitude = gps
                relativeAtFused = nil
                return gps
            }
            if let previous = fusedAltitude, let relBefore = relativeAtFused {
                let predicted = previous + (rel - relBefore)
                fusedAltitude = 0.3 * gps + 0.7 * predicted
            } else {
                fusedAltitude = gps
            }
            relativeAtFused = rel
            return fusedAltitude
        }

        nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            for location in locations where location.horizontalAccuracy >= 0 {
                // Ignore stale cached fixes when determining whether GPS is ready.
                guard abs(location.timestamp.timeIntervalSinceNow) < 15 else { continue }
                signalHandler?(true)
                let altitude = fuse(gps: location.altitude, verticalAccuracy: location.verticalAccuracy)
                continuation.yield(TrackPoint(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    altitude: altitude,
                    timestamp: location.timestamp,
                    horizontalAccuracy: location.horizontalAccuracy,
                    verticalAccuracy: location.verticalAccuracy >= 0 ? location.verticalAccuracy : nil
                ))
            }
        }

        nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
            // Keep recording through a lost signal; the screen shows a delayed inline state.
            signalHandler?(false)
        }
    }
}
