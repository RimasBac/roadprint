import SwiftUI
import RoadPrintCore

/// Share a trip as a picture (SCREENS.md S1): pick a card style, then the system share sheet.
struct ShareCardSheet: View {
    let trip: Trip
    let startLabel: String?
    let endLabel: String?

    @Environment(\.appEnvironment) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var style: ShareCardStyle = .nightHighway
    @State private var card: Prepared?
    @State private var exported: Image?

    private struct Prepared {
        let style: ShareCardStyle
        let content: ShareCardContent
        let scene: MapScene?
        let elevation: ShareCardElevation?
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: RPSpace.l) {
                preview
                Picker("Card style", selection: $style) {
                    ForEach(ShareCardStyle.allCases) { style in
                        Text(style.name).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .sensoryFeedback(.selection, trigger: style)
                .accessibilityIdentifier("shareStylePicker")
                if let exported {
                    ShareLink(item: exported, preview: SharePreview("RoadPrint trip card", image: exported)) {
                        Text("Share")
                    }
                    .buttonStyle(.rpPrimary)
                    .accessibilityIdentifier("shareCardButton")
                } else {
                    ProgressView()
                        .frame(height: RPSize.buttonHeight)
                }
            }
            .padding(RPSpace.screenMargin)
            .background(Color.RP.background.ignoresSafeArea())
            .navigationTitle("Share trip card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task(id: style) { await prepare(style) }
    }

    private var preview: some View {
        GeometryReader { proxy in
            let size = ShareCardMetrics.size
            let scale = min(proxy.size.width / size.width, proxy.size.height / size.height)
            Group {
                if let card, scale > 0 {
                    ShareCard(style: card.style, content: card.content, scene: card.scene, elevation: card.elevation)
                        .scaleEffect(scale)
                        .frame(width: size.width * scale, height: size.height * scale)
                        .clipShape(RoundedRectangle(cornerRadius: RPRadius.card))
                        .overlay {
                            RoundedRectangle(cornerRadius: RPRadius.card)
                                .strokeBorder(Color.RP.border, lineWidth: RPSize.hairline(displayScale: displayScale))
                        }
                        .accessibilityIdentifier("shareCardPreview")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func prepare(_ style: ShareCardStyle) async {
        exported = nil
        let unit = environment.profile.distanceUnit
        // The card is drawn only from the share summary, never from the trip (AGENTS.md §7b.3).
        guard let summary = TripShareSummary.make(from: trip, options: ShareOptions(includeRoute: true)) else {
            card = nil
            return
        }
        let elevation = summary.route
            .flatMap { ElevationProfile.make(segments: $0, summit: summary.summit, unit: unit,
                                             tripDistanceMeters: summary.distanceMeters) }
            .flatMap(ShareCardElevation.make)
        let hasElevation = elevation != nil
        let start = startLabel, end = endLabel
        let scene = await Task.detached(priority: .userInitiated) { () -> MapScene? in
            guard let places = try? PlaceIndex.bundled() else { return nil }
            let spec = ShareCardMetrics.map(style, hasElevation: hasElevation)
            let input = MapSceneInput(summary: summary, startLabel: spec.namesAreas ? start : nil,
                                      endLabel: spec.namesAreas ? end : nil)
            return try? MapSceneBuilder.build(
                input: input, places: places,
                size: (Double(ShareCardMetrics.size.width), Double(spec.height)),
                insets: spec.insets, labels: spec.labels)
        }.value
        guard !Task.isCancelled else { return }
        let altitude = summary.summitAltitudeMeters.map { TripMapView.altitudeText($0, unit: unit) }
        let content = ShareCardText.content(summary: summary, unit: unit, altitude: altitude,
                                            startLabel: start, endLabel: end)
        card = Prepared(style: style, content: content, scene: scene, elevation: elevation)
        let renderer = ImageRenderer(content: ShareCard(style: style, content: content, scene: scene, elevation: elevation))
        renderer.scale = ShareCardMetrics.exportScale
        if let image = renderer.uiImage { exported = Image(uiImage: image) }
    }
}

#if DEBUG
/// DEBUG-only: a card on the hard-coded I-80 fixture, for screenshots.
/// Launch with `-RPCardFixture i80` and, for the other style, `-RPCardStyle roadAtlas`.
struct CardDebugView: View {
    let fixture: String
    @State private var scene: MapScene?
    @State private var ready = false

    private var style: ShareCardStyle {
        UserDefaults.standard.string(forKey: "RPCardStyle").flatMap(ShareCardStyle.init(rawValue:)) ?? .nightHighway
    }

    var body: some View {
        ScrollView {
            if ready {
                ShareCard(style: style, content: content, scene: scene, elevation: Self.elevation)
                    .accessibilityIdentifier("shareCard")
                    .frame(maxWidth: .infinity)
            }
        }
        .background(Color.RP.Night.background.ignoresSafeArea())
        .task {
            let chosen = style
            if let fixtureInput = MapDebugView.input(fixture: fixture) {
                scene = await Task.detached { () -> MapScene? in
                    guard let places = try? PlaceIndex.bundled() else { return nil }
                    let spec = ShareCardMetrics.map(chosen, hasElevation: true)
                    var input = fixtureInput
                    if !spec.namesAreas {
                        input.startLabel = nil
                        input.endLabel = nil
                    }
                    return try? MapSceneBuilder.build(
                        input: input, places: places,
                        size: (Double(ShareCardMetrics.size.width), Double(spec.height)),
                        insets: spec.insets, labels: spec.labels)
                }.value
            }
            ready = true
        }
    }

    /// A made-up profile shaped like I-80 westbound: the basin, Donner Summit, the drop to Sacramento.
    private static let elevation: ShareCardElevation = {
        let points = (0...140).map { index -> CGPoint in
            let t = Double(index) / 140
            let basin = 0.42 + 0.09 * sin(t * 19) + 0.05 * sin(t * 47 + 1)
            let peak = 0.55 * exp(-pow((t - 0.86) / 0.035, 2))
            let drop = t > 0.9 ? (t - 0.9) / 0.1 : 0
            return CGPoint(x: t, y: min(1, max(0.02, basin * (1 - drop) + peak)))
        }
        return ShareCardElevation(series: [points], summit: points.max { $0.y < $1.y } ?? .zero)
    }()

    // The fixture's known numbers (RecordAndListTests): 1,037,117.8 m and 37,336 s moving.
    private var content: ShareCardContent {
        let altitude = TripMapView.altitudeText(2206, unit: .miles)
        var trip = Trip(
            createdAt: Date(timeIntervalSince1970: 1_793_750_400), status: .completed,
            endedAt: Date(timeIntervalSince1970: 1_793_790_000),
            summary: TripStats(distanceMeters: 1_037_117.8, movingTimeSeconds: 37_336, elapsedSeconds: 39_000, gapCount: 0),
            route: ProcessedRoute(segments: [RouteSegment(points: [
                RoutePoint(latitude: 40.76, longitude: -111.89, altitude: 1300),
                RoutePoint(latitude: 39.33, longitude: -120.34, altitude: 2206),
                RoutePoint(latitude: 38.58, longitude: -121.49, altitude: 10)])],
                                  summit: RoutePoint(latitude: 39.33, longitude: -120.34, altitude: 2206)),
            places: TripPlaces(
                countries: [PlaceRef(code: "US", name: "United States of America")],
                regions: [PlaceRef(code: "US-UT", name: "Utah"), PlaceRef(code: "US-NV", name: "Nevada"),
                          PlaceRef(code: "US-CA", name: "California")]))
        trip.mainRoad = MainRoad(network: .usInterstate, ref: "80", countryCode: "US")
        let utc = TimeZone(identifier: "UTC") ?? .current
        guard let summary = TripShareSummary.make(from: trip, options: ShareOptions(includeRoute: true, timeZone: utc)) else {
            return ShareCardContent(distanceValue: "", distanceUnit: "", subtitle: "", chips: [], title: "", longDate: "",
                                    stats: [], crossedCodes: [])
        }
        return ShareCardText.content(summary: summary, unit: .miles, altitude: altitude,
                                     startLabel: "Salt Lake City area", endLabel: "Sacramento area")
    }
}
#endif
