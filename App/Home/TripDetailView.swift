import SwiftUI
import RoadPrintCore

/// One saved trip (SCREENS.md P9, first version): its map, the main stats and Delete.
/// ROA-56 brings this up to mockup 1 with the elevation chart and the road sign.
struct TripDetailView: View {
    let tripID: UUID
    let model: RecordingModel

    @Environment(\.appEnvironment) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .loading
    @State private var showSpinner = false
    @State private var confirmDelete = false
    @State private var showShare = false

    private struct Detail {
        let trip: Trip
        let stats: TripStats
        let mapInput: MapSceneInput?
        let startLabel: String?
        let endLabel: String?

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
                Text("This trip is no longer on this iPhone.")
                    .font(RPType.body)
                    .foregroundStyle(Color.RP.textSecondary)
                    .padding(RPSpace.screenMargin)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("tripMissing")
            case .loaded(let detail):
                loaded(detail)
            }
        }
        .background(Color.RP.background.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
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
        guard case .loaded(let detail) = phase else { return "" }
        return (detail.trip.startedAt ?? detail.trip.createdAt).formatted(date: .abbreviated, time: .shortened)
    }

    @ViewBuilder
    private func loaded(_ detail: Detail) -> some View {
        let unit = environment.profile.distanceUnit
        VStack(alignment: .leading, spacing: RPSpace.xl) {
            if let input = detail.mapInput {
                TripMapView(input: input, unit: unit)
                    .aspectRatio(Self.mapAspect, contentMode: .fit)
            }
            VStack(alignment: .leading, spacing: RPSpace.xl) {
                if detail.mapInput != nil, !detail.hasRouteLine {
                    note("This trip was too short to draw as a route. RoadPrint hides the start and end of every trip, so only the area is shown.")
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: RPSpace.xxl) { stats(detail, unit: unit) }
                    VStack(alignment: .leading, spacing: RPSpace.l) { stats(detail, unit: unit) }
                }
                if let places = TripFormatting.placesLine(detail.trip.places) {
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
                if detail.trip.route != nil {
                    Button {
                        showShare = true
                    } label: {
                        Text("Share trip card")
                    }
                    .buttonStyle(.rpPrimary)
                    .accessibilityIdentifier("shareTrip")
                }
            }
            .padding(.horizontal, RPSpace.screenMargin)
        }
        .padding(.bottom, RPSpace.xl)
    }

    @ViewBuilder
    private func stats(_ detail: Detail, unit: DistanceUnit) -> some View {
        RPStat(label: "Distance", value: TripFormatting.distance(meters: detail.stats.distanceMeters, unit: unit))
            .accessibilityIdentifier("tripDistance")
        RPStat(label: "Moving time", value: TripFormatting.duration(seconds: detail.stats.movingTimeSeconds))
        if let altitude = detail.trip.route?.summit?.altitude {
            RPStat(label: "Highest point", value: TripMapView.altitudeText(altitude, unit: unit))
        }
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
        phase = .loaded(Detail(trip: trip, stats: stats, mapInput: input, startLabel: startLabel, endLabel: endLabel))
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
