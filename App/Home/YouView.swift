import SwiftUI
import RoadPrintCore

/// The You tab (SCREENS.md P15 and P16, first version): career so far, the trip list and settings.
/// Badges, the yearly goal and the rest of Settings arrive with M7.
struct YouView: View {
    let model: RecordingModel

    @Environment(\.appEnvironment) private var environment
    @Environment(\.openURL) private var openURL
    @AppStorage(AppSettings.distanceUnitKey) private var storedUnit = ""

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
                // TEMPORARY: remove with `TestTripView`.
                section("Testing") {
                    NavigationLink(value: AppRoute.testTrip) {
                        row("Add a test trip") { chevron }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("testTripLink")
                }
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
                section("Before you drive") {
                    Text("Start before rolling. End after parking. Never use your phone while driving.")
                        .font(RPType.body)
                        .padding(RPSpace.l)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                section("About") {
                    row("Version") { value(versionText) }
                    divider
                    NavigationLink(value: AppRoute.credits) {
                        row("Credits") { chevron }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(RPSpace.screenMargin)
            .padding(.bottom, RPSpace.s)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.RP.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { model.locationAccess.refresh() }
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
