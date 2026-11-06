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
    @Environment(\.appEnvironment) private var environment
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let message = environment.storageError {
                StorageUnavailableView(message: message)
            } else {
                HomeView()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { flushForBackground() }
        }
    }

    private func flushForBackground() {
        let store = environment.tripStore
        // Ask for a little time so the write finishes after the app is suspended.
        let taskID = UIApplication.shared.beginBackgroundTask(withName: "flush-trip")
        Task {
            do { try await store.flush() } catch {
                AppEnvironment.log.error("Flush on background failed: \(String(describing: error), privacy: .public)")
            }
            if taskID != .invalid { UIApplication.shared.endBackgroundTask(taskID) }
        }
    }
}

struct StorageUnavailableView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.exclamationmark").font(.largeTitle)
            Text("Storage unavailable").font(.title2.bold())
            Text("RoadPrint can't save trips right now, so recording is turned off. Restart the app or free up space on your iPhone.")
                .multilineTextAlignment(.center)
            Text(message).font(.footnote).foregroundStyle(.secondary)
        }
        .padding()
        .accessibilityIdentifier("storageUnavailable")
    }
}
