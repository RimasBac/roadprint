import SwiftUI
import RoadPrintCore

/// Dependencies injected into the view tree. Feature code sees protocols only.
struct AppEnvironment: Sendable {
    var tripStore: any TripStore
    /// A fresh source per recording.
    var makeLocationSource: @Sendable () -> any LocationSource

    /// Previews and the default value use the in-memory store.
    static let preview = AppEnvironment(tripStore: InMemoryTripStore(), makeLocationSource: Self.defaultSource)

    @MainActor
    static func live() -> AppEnvironment {
        if let container = try? SwiftDataTripStore.makeContainer() {
            return AppEnvironment(tripStore: SwiftDataTripStore(container: container), makeLocationSource: defaultSource)
        }
        // Last resort so the app still launches; trips would not persist.
        return .preview
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
