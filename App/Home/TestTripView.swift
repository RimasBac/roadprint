import SwiftUI
import RoadPrintCore

/// TEMPORARY (board, 2026-11-12): adds a made-up drive between two cities and stores it like a
/// recorded trip, so maps and totals can be tested without driving.
///
/// Delete this screen together with `RecordingModel.addTestTrip`, `TestRoute` and
/// `AreaNamer.place(named:)` before the public beta.
struct TestTripView: View {
    let model: RecordingModel

    private enum Field { case from, to }

    @State private var from = ""
    @State private var to = ""
    @State private var isWorking = false
    @State private var message: String?
    @State private var created: UUID?
    @State private var sampleArea = HeatFixture.Area.usa
    @State private var sample: SampleMap?
    @State private var confirmDeleteAll = false
    @FocusState private var focus: Field?
    @Environment(\.appEnvironment) private var environment

    /// A made-up set of trips to look at My map with. Nothing is stored.
    private struct SampleMap: Identifiable {
        let area: HeatFixture.Area
        let count: Int
        var id: String { "\(area.rawValue)-\(count)" }
    }

    private var canAdd: Bool {
        !isWorking && !from.trimmingCharacters(in: .whitespaces).isEmpty
            && !to.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RPSpace.xl) {
                Text("Type two cities. RoadPrint adds a drive along the road between them and counts it like a real trip. The road comes from Apple Maps, so this needs the internet. This screen is for testing and will be removed.")
                    .font(RPType.body)
                    .foregroundStyle(Color.RP.textSecondary)
                field("From", text: $from, field: .from, identifier: "testTripFrom")
                    .submitLabel(.next)
                    .onSubmit { focus = .to }
                field("To", text: $to, field: .to, identifier: "testTripTo")
                    .submitLabel(.go)
                    .onSubmit { Task { await add() } }
                if let message {
                    Text(message)
                        .font(RPType.statLabel)
                        .accessibilityIdentifier("testTripMessage")
                }
                Button {
                    Task { await add() }
                } label: {
                    Text("Add test trip")
                }
                .buttonStyle(.rpPrimary)
                .disabled(!canAdd)
                .accessibilityIdentifier("addTestTrip")
                if isWorking {
                    ProgressView("Building the trip…")
                        .font(RPType.body)
                        .frame(maxWidth: .infinity)
                }
                sampleMaps
                startOver
            }
            .padding(RPSpace.screenMargin)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.RP.background.ignoresSafeArea())
        .navigationTitle("Add a test trip")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $created) { id in
            TripDetailView(tripID: id, model: model)
        }
        .sheet(item: $sample) { sample in
            SampleMapSheet(area: sample.area, count: sample.count, unit: environment.profile.distanceUnit)
        }
        .alert("Delete all trips?", isPresented: $confirmDeleteAll) {
            Button("Delete all", role: .destructive) {
                Task { await model.deleteAllTrips() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every trip on this iPhone is removed, the real ones too. This can't be undone.")
        }
    }

    /// My map with 5 to 500 made-up trips, without storing any of them.
    private var sampleMaps: some View {
        VStack(alignment: .leading, spacing: RPSpace.m) {
            RPSectionTitle(title: "Sample maps")
                .padding(.horizontal, RPSpace.xs)
            Text("See My map with made-up trips over real cities. Pick how many. Nothing is saved.")
                .font(RPType.body)
                .foregroundStyle(Color.RP.textSecondary)
            Picker("Where", selection: $sampleArea) {
                Text("USA").tag(HeatFixture.Area.usa)
                Text("Europe").tag(HeatFixture.Area.europe)
                Text("Both").tag(HeatFixture.Area.mixed)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("sampleMapArea")
            HStack(spacing: RPSpace.s) {
                ForEach([5, 50, 250, 500], id: \.self) { count in
                    Button {
                        sample = SampleMap(area: sampleArea, count: count)
                    } label: {
                        Text(verbatim: "\(count)")
                    }
                    .buttonStyle(.rpSecondary)
                    .accessibilityIdentifier("sampleMap\(count)")
                }
            }
        }
    }

    private var startOver: some View {
        VStack(alignment: .leading, spacing: RPSpace.m) {
            RPSectionTitle(title: "Start over")
                .padding(.horizontal, RPSpace.xs)
            Button(role: .destructive) {
                confirmDeleteAll = true
            } label: {
                Text("Delete all trips")
            }
            .buttonStyle(.rpSecondary)
            .accessibilityIdentifier("deleteAllTrips")
        }
    }

    private func field(_ title: LocalizedStringKey, text: Binding<String>, field: Field, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: RPSpace.s) {
            RPSectionTitle(title: title)
                .padding(.horizontal, RPSpace.xs)
            TextField("City", text: text)
                .font(RPType.body)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($focus, equals: field)
                .padding(.horizontal, RPSpace.l)
                .frame(minHeight: RPSize.buttonHeight)
                .rpCard()
                .accessibilityIdentifier(identifier)
        }
    }

    private func add() async {
        guard canAdd else { return }
        focus = nil
        isWorking = true
        message = nil
        defer { isWorking = false }
        switch await model.addTestTrip(from: from, to: to) {
        case .success(let id):
            if !model.lastTestTripFollowedARoad {
                message = String(localized: "No road route was available, so this trip is a bent line. Check the internet connection and add it again for the real road.",
                                 comment: "Test trip screen: Apple Maps gave no driving route, so the trip is the made-up fallback line.")
            }
            created = id
        case .failure(.unknownPlace(let name)):
            message = String(localized: "Couldn't find “\(name)”. Try the English name of a larger city nearby.",
                             comment: "Test trip screen: the typed city is not in the bundled list of larger cities.")
        case .failure(.samePlace):
            message = String(localized: "Pick two different cities.",
                             comment: "Test trip screen: both fields name the same city.")
        case .failure(.failed):
            message = String(localized: "The test trip couldn't be saved. Try again.",
                             comment: "Test trip screen: building or saving the trip failed.")
        }
    }
}

/// TEMPORARY, with the test tool: My map on made-up trips, in a sheet.
private struct SampleMapSheet: View {
    let area: HeatFixture.Area
    let count: Int
    let unit: DistanceUnit

    @Environment(\.dismiss) private var dismiss
    @State private var trips: [HeatTrip]?

    var body: some View {
        MyMapScreen(trips: trips, unit: unit)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    Text("Sample: made-up trips")
                        .font(RPType.statLabel)
                        .foregroundStyle(Color.RP.textSecondary)
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(RPType.body)
                        .accessibilityIdentifier("sampleMapDone")
                }
                .padding(.horizontal, RPSpace.screenMargin)
                .padding(.vertical, RPSpace.m)
                .background(Color.RP.background)
            }
            .task { trips = HeatTrip.samples(area, count: count) }
    }
}
