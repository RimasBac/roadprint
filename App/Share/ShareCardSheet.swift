import SwiftUI
import RoadPrintCore

/// Share a trip as a picture (SCREENS.md S1, first version): the Night Highway card, a switch to
/// leave the route out, and the system share sheet. More card styles and Save to Photos come with M4.
struct ShareCardSheet: View {
    let trip: Trip
    let startLabel: String?
    let endLabel: String?

    @Environment(\.appEnvironment) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var includeRoute = true
    @State private var card: Prepared?
    @State private var exported: Image?
    @Environment(\.displayScale) private var displayScale

    private struct Prepared {
        let content: NightHighwayCard.Content
        let scene: MapScene?
        let altitude: String
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: RPSpace.l) {
                preview
                Toggle("Show route", isOn: $includeRoute)
                    .font(RPType.body)
                    .tint(Color.RP.buttonPrimary)
                    .accessibilityIdentifier("shareShowRoute")
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
        .task(id: includeRoute) { await prepare() }
    }

    private var preview: some View {
        GeometryReader { proxy in
            let size = ShareCardMetrics.size
            let scale = min(proxy.size.width / size.width, proxy.size.height / size.height)
            Group {
                if let card, scale > 0 {
                    NightHighwayCard(content: card.content, scene: card.scene, summitAltitude: card.altitude)
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

    private func prepare() async {
        exported = nil
        let unit = environment.profile.distanceUnit
        guard let summary = TripShareSummary.make(from: trip, options: ShareOptions(includeRoute: includeRoute)) else {
            card = nil
            return
        }
        // The card is drawn only from the share summary, never from the trip (AGENTS.md §7b.3).
        let input = MapSceneInput(summary: summary, startLabel: startLabel, endLabel: endLabel)
        let scene = await Task.detached(priority: .userInitiated) { () -> MapScene? in
            guard let places = try? PlaceIndex.bundled() else { return nil }
            return try? MapSceneBuilder.build(
                input: input, places: places,
                size: (Double(ShareCardMetrics.size.width), Double(ShareCardMetrics.mapHeight)),
                insets: ShareCardMetrics.mapInsets)
        }.value
        guard !Task.isCancelled else { return }
        let altitude = summary.summitAltitudeMeters.map { TripMapView.altitudeText($0, unit: unit) }
        let prepared = Prepared(content: ShareCardText.content(summary: summary, unit: unit, altitude: altitude),
                                scene: scene, altitude: altitude ?? "")
        card = prepared
        let renderer = ImageRenderer(content:
            NightHighwayCard(content: prepared.content, scene: prepared.scene, summitAltitude: prepared.altitude))
        renderer.scale = ShareCardMetrics.exportScale
        if let image = renderer.uiImage { exported = Image(uiImage: image) }
    }
}

#if DEBUG
/// DEBUG-only: the card on the hard-coded I-80 fixture, for screenshots. Launch with `-RPCardFixture i80`.
struct CardDebugView: View {
    let fixture: String
    @State private var scene: MapScene?
    @State private var ready = false

    var body: some View {
        ScrollView {
            if ready {
                NightHighwayCard(content: content, scene: scene, summitAltitude: altitude)
                    .accessibilityIdentifier("shareCard")
                    .frame(maxWidth: .infinity)
            }
        }
        .background(Color.RP.Night.background.ignoresSafeArea())
        .task {
            if let input = MapDebugView.input(fixture: fixture) {
                scene = await Task.detached { () -> MapScene? in
                    guard let places = try? PlaceIndex.bundled() else { return nil }
                    return try? MapSceneBuilder.build(
                        input: input, places: places,
                        size: (Double(ShareCardMetrics.size.width), Double(ShareCardMetrics.mapHeight)),
                        insets: ShareCardMetrics.mapInsets)
                }.value
            }
            ready = true
        }
    }

    private var altitude: String { TripMapView.altitudeText(2206, unit: .miles) }

    // The fixture's known numbers (RecordAndListTests): 1,037,117.8 m and 37,336 s moving.
    private var content: NightHighwayCard.Content {
        let brag = ShareCardText.distance(meters: 1_037_117.8, unit: .miles)
        let places = TripPlaces(
            countries: [PlaceRef(code: "US", name: "United States of America")],
            regions: [PlaceRef(code: "US-UT", name: "Utah"), PlaceRef(code: "US-NV", name: "Nevada"),
                      PlaceRef(code: "US-CA", name: "California")])
        return NightHighwayCard.Content(
            distanceValue: brag.value, distanceUnit: brag.unit,
            subtitle: ShareCardText.subtitle(places: places, day: ShareDay(year: 2026, month: 11, day: 4)),
            chips: [TripFormatting.duration(seconds: 37_336), altitude])
    }
}
#endif
