import SwiftUI
import RoadPrintCore

@main
struct RoadPrintApp: App {
    private let environment = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.appEnvironment, environment)
        }
    }
}

struct RootView: View {
    var body: some View {
        HomeView()
    }
}
