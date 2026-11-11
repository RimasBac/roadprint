import CoreLocation
import Observation

/// Permission checks happen before a trip is created. This manager never collects locations.
@MainActor
@Observable
final class LocationAccess: NSObject, @preconcurrency CLLocationManagerDelegate {
    enum State { case unknown, blocked, approximate, precise }
    private(set) var state: State = .unknown
    private let manager = CLLocationManager()
    private var pendingRequest: CheckedContinuation<State, Never>?
    private var stateOverride: State?

    override init() {
        super.init()
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "RPDebugLocationAccess") {
        case "blocked": stateOverride = .blocked
        case "approximate": stateOverride = .approximate
        case "precise": stateOverride = .precise
        default: if AppEnvironment.isReplay { stateOverride = .precise }
        }
        #endif
        manager.delegate = self
        refresh()
    }

    func refresh() {
        if let stateOverride { state = stateOverride; return }
        switch manager.authorizationStatus {
        case .denied, .restricted: state = .blocked
        case .authorizedAlways, .authorizedWhenInUse:
            state = manager.accuracyAuthorization == .fullAccuracy ? .precise : .approximate
        case .notDetermined: state = .unknown
        @unknown default: state = .blocked
        }
    }

    func request() async -> State {
        refresh()
        guard state == .unknown else { return state }
        return await withCheckedContinuation { continuation in
            pendingRequest = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refresh()
        guard state != .unknown else { return }
        pendingRequest?.resume(returning: state)
        pendingRequest = nil
    }
}
