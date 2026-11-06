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

    static let log = Logger(subsystem: "app.roadprint", category: "storage")

    /// Previews and the default value use the in-memory store.
    static let preview = AppEnvironment(tripStore: InMemoryTripStore(), makeLocationSource: Self.defaultSource)

    @MainActor
    static func live() -> AppEnvironment {
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
