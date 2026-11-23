import SwiftUI
import SafariServices
import RoadPrintCore

/// The You tab (SCREENS.md P15 and P16, first version): career so far, the trip list and settings.
/// Badges, the yearly goal and the rest of Settings arrive with M7.
struct YouView: View {
    let model: RecordingModel

    @Environment(\.appEnvironment) private var environment
    @Environment(\.openURL) private var openURL
    @AppStorage(AppSettings.distanceUnitKey) private var storedUnit = ""
    @Environment(\.scenePhase) private var scenePhase
    @State private var transfer = DataTransferModel()
    @State private var helpPage: HelpPage?
    @State private var confirmDeleteAll = false
    @State private var deletionFailed = false
    @State private var syncOn = AppSettings.iCloudSyncEnabled
    @State private var syncStatus: SyncStatus = .off
    @State private var confirmSyncOff = false
    @State private var switchingSync = false
    @State private var paywall: PaywallTrigger?

    private var unit: DistanceUnit { environment.profile.distanceUnit }

    private var careerMeters: Double {
        environment.profile.startingCareerDistanceMeters + model.rows.reduce(0) { $0 + $1.distanceMeters }
    }

    private var movingSeconds: TimeInterval {
        model.rows.reduce(0) { $0 + $1.movingTimeSeconds }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RPSpace.xl) {
                Text("You").font(RPType.screenTitle)
                if let banner = syncStatus.banner { syncBanner(banner) }
                career
                section("Trips") {
                    NavigationLink(value: AppRoute.allTrips) {
                        row("All trips") {
                            value(model.rows.count.formatted())
                            chevron
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("allTripsLink")
                }
                section("RoadPrint Pro") { proRows }
                section("Your data") {
                    Button {
                        Task { await transfer.export(model: model, profile: environment.profile) }
                    } label: {
                        row("Export all trips") { chevron }
                    }
                    .buttonStyle(.plain)
                    .disabled(model.rows.isEmpty)
                    .opacity(model.rows.isEmpty ? 0.4 : 1)
                    .accessibilityIdentifier("exportAllTripsRow")
                    divider
                    Button {
                        transfer.pickingFile = true
                    } label: {
                        row("Import trips") { chevron }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("importTripsRow")
                    #if DEBUG
                    if let fixture = UserDefaults.standard.string(forKey: "RPImportFixture") {
                        divider
                        Button {
                            Task {
                                if transfer.exportedFixture != nil {
                                    await transfer.restoreExportedFixture(model: model, profile: environment.profile)
                                } else {
                                    await transfer.importFixture(named: fixture, model: model, profile: environment.profile)
                                }
                            }
                        } label: {
                            row("Import test file") { chevron }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(transfer.exportedFixture == nil ? "importFixtureRow" : "restoreExportedFixtureRow")
                    }
                    #endif
                }
                .disabled(model.isBusy)
                section("Settings") {
                    row("Units") {
                        Picker("Units", selection: unitBinding) {
                            Text("Miles").tag(DistanceUnit.miles)
                            Text("Kilometres").tag(DistanceUnit.kilometers)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .accessibilityIdentifier("unitsPicker")
                    }
                    divider
                    row("iCloud sync") {
                        Toggle("iCloud sync", isOn: syncBinding)
                            .labelsHidden()
                            .disabled(switchingSync)
                            .accessibilityIdentifier("iCloudSyncToggle")
                    }
                    divider
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    } label: {
                        row("Location access") {
                            value(locationText)
                            chevron
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Opens Settings"))
                    .accessibilityIdentifier("locationAccessRow")
                }
                section("About and privacy") {
                    Button {
                        helpPage = .privacy
                    } label: {
                        row("Privacy policy") { chevron }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("privacyPolicyRow")
                    divider
                    Button {
                        helpPage = .support
                    } label: {
                        row("Support") { chevron }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("supportRow")
                    divider
                    Button(role: .destructive) {
                        confirmDeleteAll = true
                    } label: {
                        row("Delete all data") { chevron }
                            .foregroundStyle(Color.RP.accentText)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isRecording || model.isBusy || transfer.isWorking)
                    .accessibilityIdentifier("deleteAllDataRow")
                    divider
                    row("Version") { value(versionText) }
                    divider
                    NavigationLink(value: AppRoute.credits) {
                        row("Credits") { chevron }
                    }
                    .buttonStyle(.plain)
                    divider
                    Text("Start before rolling. End after parking. Never use your phone while driving.")
                        .font(RPType.body)
                        .foregroundStyle(Color.RP.textSecondary)
                        .padding(RPSpace.l)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(RPSpace.screenMargin)
            .padding(.bottom, RPSpace.s)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.RP.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { model.locationAccess.refresh() }
        .sheet(item: $helpPage) { page in
            HelpBrowser(url: page.url).ignoresSafeArea()
        }
        .alert("Delete all data?", isPresented: $confirmDeleteAll) {
            Button("Delete all data", role: .destructive) {
                Task {
                    do { try await model.deleteAllTrips() }
                    catch { deletionFailed = true }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All trips will be deleted from this iPhone. This can’t be undone.")
        }
        .alert("Something went wrong", isPresented: $deletionFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("RoadPrint couldn’t delete all trips. Try again.")
        }
        .task { await refreshSyncStatus() }
        .task {
            for await _ in environment.syncService.changes() { await refreshSyncStatus() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshSyncStatus() } }
        }
        .alert("Turn off iCloud sync?", isPresented: $confirmSyncOff) {
            Button("Turn off", role: .destructive) { Task { await setSync(false) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Trips will stay only on this phone.")
        }
        .dataTransferPresentations(transfer, model: model, profile: environment.profile)
        .sheet(item: $paywall) { PaywallSheet(trigger: $0) }
    }

    @ViewBuilder
    private var proRows: some View {
        let pro = environment.pro
        row("Status") {
            value(pro.isPro ? String(localized: "Pro", comment: "Pro status row: the driver has Pro.")
                            : String(localized: "Free", comment: "Pro status row: the driver is on the free plan."))
                .accessibilityIdentifier("proStatus")
        }
        divider
        if !pro.isPro {
            Button {
                paywall = .tappedAllTime
            } label: {
                row("Get Pro") { chevron }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("getProRow")
            divider
        }
        Button {
            Task { await pro.restore() }
        } label: {
            row("Restore purchases") {
                if pro.isWorking { ProgressView() } else { chevron }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("restorePurchasesRow")
        if let message = pro.errorMessage {
            Text(message)
                .font(RPType.statLabel)
                .foregroundStyle(Color.RP.textSecondary)
                .padding(.horizontal, RPSpace.l)
                .padding(.bottom, RPSpace.s)
        }
        divider
        Button {
            if let url = pro.manageSubscriptionsURL { openURL(url) }
        } label: {
            row("Manage subscription") { chevron }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("manageSubscriptionRow")
    }

    private var career: some View {
        VStack(alignment: .leading, spacing: RPSpace.l) {
            VStack(alignment: .leading, spacing: RPSpace.xs) {
                Text("Career distance")
                    .font(RPType.statLabel)
                    .foregroundStyle(Color.RP.textSecondary)
                Text(TripFormatting.distance(meters: careerMeters, unit: unit))
                    .font(RPType.statNumber)
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("careerTotal")
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: RPSpace.xxl) { careerStats }
                VStack(alignment: .leading, spacing: RPSpace.m) { careerStats }
            }
        }
        .padding(RPSpace.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rpCard()
    }

    @ViewBuilder
    private var careerStats: some View {
        RPStat(label: "Trips", value: model.rows.count.formatted())
        RPStat(label: "Time driving", value: TripFormatting.duration(seconds: movingSeconds))
    }

    private var syncBinding: Binding<Bool> {
        Binding(get: { syncOn }, set: { wanted in
            if wanted { Task { await setSync(true) } } else { confirmSyncOff = true }
        })
    }

    private func setSync(_ enabled: Bool) async {
        switchingSync = true
        defer { switchingSync = false }
        do {
            try await environment.syncService.setEnabled(enabled)
            syncOn = enabled
        } catch {
            AppEnvironment.log.error("Changing iCloud sync failed: \(String(describing: error), privacy: .public)")
        }
        await refreshSyncStatus()
    }

    private func refreshSyncStatus() async {
        syncStatus = await environment.syncService.status()
    }

    private func syncBanner(_ banner: SyncBanner) -> some View {
        VStack(alignment: .leading, spacing: RPSpace.s) {
            switch banner {
            case .iCloudUnavailable:
                Text("iCloud is not available").font(RPType.body.weight(.semibold))
                Text("Sign in to iCloud to back up your trips. They stay on this phone until then.")
                    .font(RPType.body).foregroundStyle(Color.RP.textSecondary)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .font(RPType.body.weight(.semibold))
                .frame(minHeight: RPSize.minTouch, alignment: .leading)
            case .storageFull:
                Text("iCloud storage is full").font(RPType.body.weight(.semibold))
                Text("Your trips are safe on this phone.")
                    .font(RPType.body).foregroundStyle(Color.RP.textSecondary)
            }
        }
        .padding(RPSpace.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rpCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("iCloudBanner")
    }

    private var unitBinding: Binding<DistanceUnit> {
        Binding(get: { unit }, set: { storedUnit = $0.rawValue })
    }

    private var locationText: String {
        switch model.locationAccess.state {
        case .precise: String(localized: "On", comment: "Location access status: allowed with precise location.")
        case .approximate: String(localized: "Approximate", comment: "Location access status: allowed, but Precise Location is off.")
        case .blocked: String(localized: "Off", comment: "Location access status: denied or restricted.")
        case .unknown: String(localized: "Not asked yet", comment: "Location access status: iOS has not asked the driver yet.")
        }
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? version : "\(version) (\(build))"
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: RPSpace.s) {
            RPSectionTitle(title: title)
                .padding(.horizontal, RPSpace.xs)
            VStack(spacing: 0) { content() }
                .rpCard()
        }
    }

    private func row<Trailing: View>(_ title: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: RPSpace.m) {
            Text(title).font(RPType.body)
            Spacer(minLength: RPSpace.m)
            trailing()
        }
        .padding(.horizontal, RPSpace.l)
        .padding(.vertical, RPSpace.s)
        .frame(minHeight: RPSize.minTouch)
        .contentShape(Rectangle())
    }

    private func value(_ text: String) -> some View {
        Text(text)
            .font(RPType.body)
            .foregroundStyle(Color.RP.textSecondary)
            .multilineTextAlignment(.trailing)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(RPType.statLabel)
            .foregroundStyle(Color.RP.textSecondary)
            .accessibilityHidden(true)
    }

    private var divider: some View {
        Divider()
            .overlay(Color.RP.border)
            .padding(.leading, RPSpace.l)
    }
}

private enum HelpPage: Hashable, Identifiable {
    case privacy, support

    var id: Self { self }

    var url: URL {
        switch self {
        case .privacy: AppSettings.helpURLs.privacy
        case .support: AppSettings.helpURLs.support
        }
    }
}

private struct HelpBrowser: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

/// Map data and font credits (SCREENS.md P17).
struct CreditsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RPSpace.xl) {
                block("Map data", "Made with Natural Earth. Free vector and raster map data at naturalearthdata.com.")
                block("Fonts", "Inter by the Inter Project Authors and Barlow Condensed by Jeremy Tribby, under the SIL Open Font License 1.1.")
            }
            .padding(RPSpace.screenMargin)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.RP.background.ignoresSafeArea())
        .navigationTitle("Credits")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func block(_ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: RPSpace.s) {
            RPSectionTitle(title: title)
            Text(text).font(RPType.body)
        }
    }
}
