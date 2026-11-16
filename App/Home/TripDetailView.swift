import SwiftUI
import RoadPrintCore

/// One saved trip, laid out as mockup 1. Pushed from the lists, or shown full screen as
/// "Trip complete" right after End Trip (`presentation == .summary`).
struct TripDetailView: View {
    enum Presentation { case pushed, summary }

    let tripID: UUID
    let model: RecordingModel
    var presentation: Presentation = .pushed

    @Environment(\.appEnvironment) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .loading
    @State private var showSpinner = false
    @State private var confirmDelete = false
    @State private var showShare = false
    @State private var hapticTrigger = 0
    @State private var careerShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private var isSummary: Bool { presentation == .summary }

    private struct Detail {
        let trip: Trip
        let stats: TripStats
        let mapInput: MapSceneInput?
        let startLabel: String?
        let endLabel: String?
        let career: CareerProgress

        /// False for a trip shorter than the privacy trim: only its approximate area is stored.
        var hasRouteLine: Bool {
            trip.route?.segments.contains { !$0.points.isEmpty } ?? false
        }
    }

    private enum Phase {
        case loading
        case missing
        case loaded(Detail)
    }

    /// Mockup 1 draws the map 390 × 300 pt.
    private static let mapAspect: CGFloat = 390.0 / 300.0

    var body: some View {
        ScrollView {
            switch phase {
            case .loading:
                if showSpinner {
                    ProgressView("Loading trip…")
                        .font(RPType.body)
                        .padding(.top, RPSpace.xxl)
                        .frame(maxWidth: .infinity)
                }
            case .missing:
                if isSummary {
                    failure
                } else {
                    Text("This trip is no longer on this iPhone.")
                        .font(RPType.body)
                        .foregroundStyle(Color.RP.textSecondary)
                        .padding(RPSpace.screenMargin)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("tripMissing")
                }
            case .loaded(let detail):
                loaded(detail)
            }
        }
        .background(Color.RP.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { pinnedButtons }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(isSummary ? .hidden : .automatic, for: .navigationBar)
        .sensoryFeedback(.success, trigger: hapticTrigger)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Delete trip", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .accessibilityIdentifier("tripMenu")
            }
        }
        .alert("Delete this trip?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                Task {
                    await model.deleteTrip(id: tripID)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It will be removed from this iPhone. This can't be undone.")
        }
        .sheet(isPresented: $showShare) {
            if case .loaded(let detail) = phase {
                ShareCardSheet(trip: detail.trip, startLabel: detail.startLabel, endLabel: detail.endLabel)
            }
        }
        .task(id: tripID) { await load() }
    }

    private var title: String {
        guard !isSummary, case .loaded(let detail) = phase else { return "" }
        return (detail.trip.startedAt ?? detail.trip.createdAt).formatted(date: .abbreviated, time: .shortened)
    }

    @ViewBuilder
    private func loaded(_ detail: Detail) -> some View {
        let unit = environment.profile.distanceUnit
        VStack(alignment: .leading, spacing: 0) {
            if isSummary { header(detail) }
            if let input = detail.mapInput {
                TripMapView(input: input, unit: unit)
                    .frame(height: mapHeight)
                    .padding(.top, isSummary ? RPSpace.m : 0)
            }
            VStack(alignment: .leading, spacing: RPSpace.xl) {
                if detail.mapInput != nil, !detail.hasRouteLine {
                    note("This trip was too short to draw as a route. RoadPrint hides the start and end of every trip, so only the area is shown.")
                }
                statsRow(detail, unit: unit)
                if !isSummary, let places = TripFormatting.placesLine(detail.trip.places) {
                    Text(places)
                        .font(RPType.subtitle)
                        .foregroundStyle(Color.RP.textSecondary)
                }
                if detail.trip.status == .partial {
                    note("Partially recorded. Part of this trip is missing because recording was interrupted.")
                }
                if let profile = detail.trip.route.flatMap({
                    ElevationProfile.make(route: $0, unit: unit, tripDistanceMeters: detail.stats.distanceMeters)
                }) {
                    ElevationChartView(profile: profile)
                }
                career(detail.career, tripMeters: detail.stats.distanceMeters, unit: unit)
            }
            .padding(.top, RPSpace.l)
            .padding(.horizontal, RPSpace.screenMargin)
        }
        .padding(.bottom, RPSpace.xl)
    }

    /// Mockup 1: 0.47 of the screen height, between 300 and 460 pt.
    private var mapHeight: CGFloat {
        min(460, max(300, UIScreen.main.bounds.height * 0.47))
    }

    private func header(_ detail: Detail) -> some View {
        HStack(alignment: .center, spacing: RPSpace.m) {
            VStack(alignment: .leading, spacing: RPSpace.xs) {
                Text("Trip complete")
                    .font(RPType.screenTitle)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle(detail.trip))
                    .font(RPType.subtitle)
                    .foregroundStyle(Color.RP.textSecondary)
            }
            Spacer(minLength: 0)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.RP.text)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.RP.land))
                    .frame(width: RPSize.minTouch, height: RPSize.minTouch)
            }
            .accessibilityLabel("Close")
            .accessibilityIdentifier("tripClose")
        }
        .padding(.top, RPSpace.l)
        .padding(.horizontal, RPSpace.screenMargin)
    }

    private func subtitle(_ trip: Trip) -> String {
        let date = trip.startedAt ?? trip.createdAt
        var style = Date.FormatStyle().weekday(.abbreviated).month(.abbreviated).day()
        if !Calendar.current.isDate(date, equalTo: .now, toGranularity: .year) { style = style.year() }
        let names = TripPlaceSummary.headerNames(TripPlaceSummary.names(trip.places))
        let day = date.formatted(style)
        return names.isEmpty ? day : day + " · " + names.joined(separator: " → ")
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(RPType.statLabel)
            .foregroundStyle(Color.RP.textSecondary)
    }

    private func load() async {
        let spinner = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            if !Task.isCancelled { showSpinner = true }
        }
        defer {
            spinner.cancel()
            showSpinner = false
        }
        guard let trip = try? await environment.tripStore.trip(id: tripID) else {
            phase = .missing
            return
        }
        let stats = trip.summary ?? TripAnalyzer().stats(for: trip)
        var input: MapSceneInput?
        var startLabel: String?, endLabel: String?
        if let route = trip.route, route.start != nil || route.segments.contains(where: { !$0.points.isEmpty }) {
            let names = await Self.areaNames(start: route.start, end: route.end)
            // A trip shorter than the trim stores one circle as both ends: label it once.
            let oneArea = route.start == route.end
            startLabel = names.start.map { Self.areaLabel($0) }
            endLabel = oneArea ? nil : names.end.map { Self.areaLabel($0) }
            input = MapSceneInput(trip: trip, startLabel: startLabel, endLabel: endLabel)
        }
        let others = ((try? await environment.tripStore.allTrips()) ?? [])
            .filter { $0.id != trip.id && $0.status != .recording }
            .reduce(0.0) { $0 + ($1.summary ?? TripAnalyzer().stats(for: $1)).distanceMeters }
        let career = CareerProgress(
            otherTripsMeters: others, thisTripMeters: stats.distanceMeters,
            startingMeters: environment.profile.startingCareerDistanceMeters, unit: environment.profile.distanceUnit)
        phase = .loaded(Detail(trip: trip, stats: stats, mapInput: input, startLabel: startLabel, endLabel: endLabel, career: career))
        if isSummary {
            hapticTrigger += 1
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(reduceMotion ? nil : RPMotion.slow) { careerShown = true }
        }
    }

    /// Only the already approximate areas go in, never route points (see `AreaNamer`).
    private nonisolated static func areaNames(start: ApproximateArea?, end: ApproximateArea?) async
        -> (start: String?, end: String?) {
        await Task.detached(priority: .userInitiated) { () -> (start: String?, end: String?) in
            guard let namer = try? AreaNamer.bundled() else { return (nil, nil) }
            return (start.flatMap { namer.name(for: $0) }, end.flatMap { namer.name(for: $0) })
        }.value
    }

    private nonisolated static func areaLabel(_ name: String) -> String {
        String(localized: "\(name) area", comment: "Map label for an approximate start or end, for example \"Salt Lake City area\".")
    }
}
