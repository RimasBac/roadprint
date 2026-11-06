import SwiftUI
import RoadPrintCore

/// Dependencies injected into the view tree. Feature code sees protocols only.
struct AppEnvironment: Sendable {
    var tripStore: any TripStore

    /// Previews and the default value use the in-memory store.
    static let preview = AppEnvironment(tripStore: InMemoryTripStore())

    @MainActor
    static func live() -> AppEnvironment {
        if let container = try? SwiftDataTripStore.makeContainer() {
            return AppEnvironment(tripStore: SwiftDataTripStore(container: container))
        }
        // Last resort so the app still launches; trips would not persist.
        return .preview
    }
}

extension EnvironmentValues {
    @Entry var appEnvironment: AppEnvironment = .preview
}
