import SwiftUI
import OSLog
import RoadPrintCore

/// Dependencies injected into the view tree. Feature code sees protocols only.
struct AppEnvironment: Sendable {
    var tripStore: any TripStore
    /// iCloud sync (ADR 0005). `LocalOnlySyncService` in previews and tests.
    var syncService: any SyncService = LocalOnlySyncService()
    /// Runs when the app goes to the background (writes the local safety archive while sync is on).
    var onBackground: @Sendable () async -> Void = {}
    /// A fresh source per recording.
    var makeLocationSource: @Sendable () -> any LocationSource
    /// Non-nil when the persistent store could not be opened. The UI shows a blocking state.
    var storageError: String?
    /// The local profile (no account). Persisted settings come later; the unit defaults from the locale.
    var profile: UserProfile = AppEnvironment.defaultProfile()

    static func defaultProfile(locale: Locale = .current) -> UserProfile {
        var profile = UserProfile(
            displayName: "",
            distanceUnit: .default(forRegionCode: locale.region?.identifier),
            createdAt: Date())
        #if DEBUG
        if isAppStoreScreenshotCapture {
            profile.startingCareerDistanceMeters = AppStoreScreenshotHistory.startingCareerMeters
        }
        #endif
        return profile
    }

    static let log = Logger(subsystem: "com.rimasbac.roadprint", category: "storage")

    /// Previews and the default value use the in-memory store.
    static let preview = AppEnvironment(tripStore: InMemoryTripStore(), makeLocationSource: Self.defaultSource)

    @MainActor
    static func live() -> AppEnvironment {
        #if DEBUG
        if isAppStoreScreenshotCapture {
            return AppEnvironment(tripStore: InMemoryTripStore(), makeLocationSource: defaultSource)
        }
        if UserDefaults.standard.bool(forKey: "RPDebugStorageError") {
            var environment = AppEnvironment.preview
            environment.storageError = String(localized: "Your trips could not be opened.")
            return environment
        }
        #endif
        #if DEBUG
        // Screenshot evidence: `-RPSyncStatus quotaFull` shows the A9 banner without an iCloud account.
        if let raw = UserDefaults.standard.string(forKey: "RPSyncStatus"), let status = SyncStatus(rawValue: raw) {
            var environment = AppEnvironment.preview
            environment.syncService = StubSyncService(status: status)
            return environment
        }
        #endif
        do {
            let sync = AppSettings.iCloudSyncEnabled
            let store = try SwitchableTripStore(sync: sync)
            let service = CloudKitSyncService(store: store, enabled: sync)
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            var env = AppEnvironment(tripStore: store, makeLocationSource: defaultSource)
            env.syncService = service
            env.onBackground = { await service.didEnterBackground(appVersion: version) }
            return env
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

    /// The App Store preview video records the app running, so animations must play, not freeze.
    static var isAppStorePreviewCapture: Bool {
        UserDefaults.standard.bool(forKey: "RPAppStorePreview")
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


#if DEBUG
/// A fixed status for UI tests and screenshots.
actor StubSyncService: SyncService {
    private let fixed: SyncStatus
    init(status: SyncStatus) { fixed = status }
    func status() -> SyncStatus { fixed }
    func setEnabled(_ enabled: Bool) {}
}
#endif
