import SwiftUI
import OSLog
import RoadPrintCore

/// Dependencies injected into the view tree. Feature code sees protocols only.
struct AppEnvironment: Sendable {
    var tripStore: any TripStore
    /// iCloud sync (ADR 0005). Off until the enable-sync PR swaps in the CloudKit implementation.
    var syncService: any SyncService = LocalOnlySyncService()
    /// A fresh source per recording.
    var makeLocationSource: @Sendable () -> any LocationSource
    /// Non-nil when the persistent store could not be opened. The UI shows a blocking state.
    var storageError: String?
    /// The local profile (no account). Persisted settings come later; the unit defaults from the locale.
    var profile: UserProfile = AppEnvironment.defaultProfile()
    /// The Pro entitlement and the offers (ROA-101). Views check `pro.entitlement` through `ProPolicy`.
    var pro: ProStore = ProStore(service: OfflinePurchaseService())

    static func defaultProfile(locale: Locale = .current) -> UserProfile {
        UserProfile(
            displayName: "",
            distanceUnit: .default(forRegionCode: locale.region?.identifier),
            createdAt: Date())
    }

    static let log = Logger(subsystem: "com.rimasbac.roadprint", category: "storage")

    /// Previews and the default value use the in-memory store.
    static let preview = AppEnvironment(tripStore: InMemoryTripStore(), makeLocationSource: Self.defaultSource)

    @MainActor
    static func live() -> AppEnvironment {
        #if DEBUG
        if isAppStoreScreenshotCapture {
            return AppEnvironment(tripStore: InMemoryTripStore(), makeLocationSource: defaultSource, pro: ProStore.live())
        }
        if UserDefaults.standard.bool(forKey: "RPDebugStorageError") {
            var environment = AppEnvironment.preview
            environment.pro = ProStore.live()
            environment.storageError = String(localized: "Your trips could not be opened.")
            return environment
        }
        #endif
        do {
            let container = try SwiftDataTripStore.makeContainer()
            return AppEnvironment(tripStore: SwiftDataTripStore(container: container), makeLocationSource: defaultSource,
                                  pro: ProStore.live())
        } catch {
            // Never fall back to a store that loses trips silently.
            log.error("Storage unavailable: \(String(describing: error), privacy: .public)")
            var env = AppEnvironment.preview
            env.storageError = error.localizedDescription
            return env
        }
    }

    @Sendable
    static func defaultSource() -> any LocationSource {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "RPDebugNoGPS") { return NoFixLocationSource() }
        if let route = UserDefaults.standard.string(forKey: "RPReplayRoute"),
           let replay = ReplayLocationSource(routeName: route) {
            return replay
        }
        #endif
        return CoreLocationSource()
    }

    static var isReplay: Bool {
        #if DEBUG
        UserDefaults.standard.string(forKey: "RPReplayRoute") != nil
        #else
        false
        #endif
    }

    #if DEBUG
    static var isAppStoreScreenshotCapture: Bool {
        UserDefaults.standard.bool(forKey: "RPAppStoreScreenshots")
    }
    #endif
}

extension EnvironmentValues {
    @Entry var appEnvironment: AppEnvironment = .preview
}

#if DEBUG
/// Exercises the real 15-second GPS wait without depending on simulator location services.
final class NoFixLocationSource: LocationSource, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<TrackPoint>.Continuation?
    func points() -> AsyncStream<TrackPoint> {
        let (stream, continuation) = AsyncStream<TrackPoint>.makeStream()
        lock.lock()
        self.continuation = continuation
        lock.unlock()
        return stream
    }
    func stop() {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.finish()
    }
}
#endif
