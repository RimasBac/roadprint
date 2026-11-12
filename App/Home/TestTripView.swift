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
    @FocusState private var focus: Field?

    private var canAdd: Bool {
        !isWorking && !from.trimmingCharacters(in: .whitespaces).isEmpty
            && !to.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RPSpace.xl) {
                Text("Type two cities. RoadPrint adds a made-up drive between them and counts it like a real trip. This screen is for testing and will be removed.")
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
