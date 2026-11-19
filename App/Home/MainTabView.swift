import SwiftUI
import RoadPrintCore

/// Where a tap can lead from either tab.
enum AppRoute: Hashable {
    case trip(UUID)
    case allTrips
    case credits
}

/// The app's tabs (SCREENS.md §1, board 2026-11-13): Drive, Map (the heat map of every trip) and You.
struct MainTabView: View {
    private enum MainTab: Hashable { case drive, map, you }

    @Environment(\.appEnvironment) private var environment
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: RecordingModel?
    @State private var showLoading = false
    @State private var selection: MainTab = .drive
    @State private var drivePath: [AppRoute] = []
    @State private var paywall: PaywallTrigger?

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
        .task { await model.watchSyncChanges() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refreshTrips() } }
        }
        .onChange(of: model.openTripID) { _, id in
            guard let id else { return }
            model.openTripID = nil
            selection = .drive
            drivePath = [.trip(id)]
        }
        .fullScreenCover(isPresented: Binding(
            get: { model.summaryTripID != nil },
            set: {
                guard !$0 else { return }
                model.summaryTripID = nil
                if model.paywallAfterSummary {
                    model.paywallAfterSummary = false
                    paywall = .tripEnded
                }
            }
        )) {
            if let id = model.summaryTripID {
                TripDetailView(tripID: id, model: model, presentation: .summary)
            }
        }
        .sheet(item: $paywall) { PaywallSheet(trigger: $0) }
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
        }
    }
}
