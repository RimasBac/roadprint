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
        ZStack {
            Color("Background").ignoresSafeArea()
            Text("RoadPrint")
                .font(.largeTitle.bold())
                .foregroundStyle(Color("Ink"))
                // Placeholder use of the core package (proves the link).
                .accessibilityHint("Schema \(RoadPrintCore.schemaVersion)")
        }
    }
}
