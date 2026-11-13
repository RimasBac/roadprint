import SwiftUI
import RoadPrintCore

/// Where a tap can lead from either tab.
enum AppRoute: Hashable {
    case trip(UUID)
    case allTrips
    case credits
    /// TEMPORARY: the test-trip tool (see `TestTripView`).
    case testTrip
}

/// The app's tabs (SCREENS.md §1, board 2026-11-12): Drive and You. Map joins them with the heatmap in M4.
struct MainTabView: View {
    private enum MainTab: Hashable { case drive, you }

    @Environment(\.appEnvironment) private var environment
    @State private var model: RecordingModel?
    @State private var showLoading = false
    @State private var selection: MainTab = .drive
    @State private var drivePath: [AppRoute] = []

    var body: some View {
        Group {
            if let model {
                tabs(model)
            } else if showLoading {
                ProgressView("Loading trips…")
                    .font(RPType.body)
                    .accessibilityIdentifier("homeLoading")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.clear
            }
        }
        .task {
            let model = model ?? RecordingModel(environment: environment)
            let loading = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                if !Task.isCancelled { showLoading = true }
            }
            await model.bootstrap()
            loading.cancel()
            showLoading = false
            self.model = model
        }
    }

    private func tabs(_ model: RecordingModel) -> some View {
        TabView(selection: $selection) {
            NavigationStack(path: $drivePath) {
                HomeView(model: model)
                    .navigationDestination(for: AppRoute.self) { destination($0, model: model) }
            }
            .tabItem { Label("Drive", systemImage: "steeringwheel") }
            .tag(MainTab.drive)

            NavigationStack {
                YouView(model: model)
                    .navigationDestination(for: AppRoute.self) { destination($0, model: model) }
            }
            .tabItem { Label("You", systemImage: "person.crop.circle") }
            .tag(MainTab.you)
        }
        .onChange(of: model.openTripID) { _, id in
            guard let id else { return }
            model.openTripID = nil
            selection = .drive
            drivePath = [.trip(id)]
        }
        .sheet(item: Binding(get: { model.recovery }, set: { model.recovery = $0 })) { recovery in
            RecoverySheet(recovery: recovery, model: model)
                .presentationDetents([.medium])
                .interactiveDismissDisabled()
        }
    }

    @ViewBuilder
    private func destination(_ route: AppRoute, model: RecordingModel) -> some View {
        switch route {
        case .trip(let id): TripDetailView(tripID: id, model: model)
        case .allTrips: AllTripsView(model: model)
        case .credits: CreditsView()
        case .testTrip: TestTripView(model: model)
        }
    }
}
