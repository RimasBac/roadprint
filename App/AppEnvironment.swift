import SwiftUI
import OSLog
import RoadPrintCore

/// Dependencies injected into the view tree. Feature code sees protocols only.
struct AppEnvironment: Sendable {
    var tripStore: any TripStore
    /// A fresh source per recording.
    var makeLocationSource: @Sendable () -> any LocationSource
    /// Non-nil when the persistent store could not be opened. The UI shows a blocking state.
    var storageError: String?
    /// The local profile (no account). Persisted settings come later; the unit defaults from the locale.
    var profile: UserProfile = AppEnvironment.defaultProfile()

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
        if UserDefaults.standard.bool(forKey: "RPDebugStorageError") {
            var environment = AppEnvironment.preview
            environment.storageError = String(localized: "Your trips could not be opened.")
            return environment
        }
        #endif
        do {
            let container = try SwiftDataTripStore.makeContainer()
            return AppEnvironment(tripStore: SwiftDataTripStore(container: container), makeLocationSource: defaultSource)
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
}

extension EnvironmentValues {
    @Entry var appEnvironment: AppEnvironment = .preview
}
