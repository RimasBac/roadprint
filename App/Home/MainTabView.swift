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

/// The app's tabs (SCREENS.md §1, board 2026-11-13): Drive, Map (the heat map of every trip) and You.
struct MainTabView: View {
    private enum MainTab: Hashable { case drive, map, you }

    @Environment(\.appEnvironment) private var environment
    @State private var model: RecordingModel?
    @State private var showLoading = false
    @State private var selection: MainTab = .drive

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
            NavigationStack {
                HomeView(model: model)
                    .navigationDestination(for: AppRoute.self) { destination($0, model: model) }
            }
            .tabItem { Label("Drive", systemImage: "steeringwheel") }
            .tag(MainTab.drive)

            NavigationStack {
                MyMapView(model: model)
            }
            .tabItem { Label("Map", systemImage: "map") }
            .tag(MainTab.map)

            NavigationStack {
                YouView(model: model)
                    .navigationDestination(for: AppRoute.self) { destination($0, model: model) }
            }
            .tabItem { Label("You", systemImage: "person.crop.circle") }
            .tag(MainTab.you)
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
