import SwiftUI
import RoadPrintCore

/// Every text of the "My map" share card.
struct MyMapCardContent: Equatable, Sendable {
    /// The total distance and its unit word: "87,412", "km".
    var distanceValue: String
    var distanceUnit: String
    /// "198 trips · 38 states".
    var tripsLine: String
    /// What the map shows: "Every recorded trip since Jan 2025", or the filters.
    var caption: String
    /// The busiest road's count, for the legend.
    var maxCount: Int

    static func make(trips: [HeatTrip], caption: String, unit: DistanceUnit, maxCount: Int) -> MyMapCardContent {
        let distance = ShareCardText.distance(meters: trips.reduce(0) { $0 + $1.distanceMeters }, unit: unit)
        return MyMapCardContent(distanceValue: distance.value, distanceUnit: distance.unit,
                                tripsLine: MyMapLogic.tripsLine(trips), caption: caption, maxCount: maxCount)
    }
}

/// The heat map as a picture to share (1080 × 1920): the driver's whole road network glowing on
/// the night map, the total distance, and the signature. Always the night palette.
/// Lay it out at `ShareCardMetrics.size` and scale it; never resize its frame.
struct MyMapCard: View {
    let content: MyMapCardContent
    let scene: HeatScene?

    private typealias M = ShareCardMetrics
    private typealias Night = Color.RP.Night

    static let mapHeight: CGFloat = 440
    static let mapInsets = ViewportInsets(top: 100, left: 20, bottom: 86, right: 20)

    var body: some View {
        ZStack(alignment: .topLeading) {
            Night.background
            if let scene {
                let base = HeatMapArt.base(scene, scheme: .dark, displayScale: M.exportScale)
                Canvas { context, _ in
                    base.draw(&context)
                    HeatMapArt.draw(scene.lines, palette: HeatMapArt.nightPalette, glow: true, in: &context)
                }
                .frame(width: M.size.width, height: Self.mapHeight)
                .overlay(alignment: .top) {
                    LinearGradient(colors: [Night.background, Night.background.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 90)
                }
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [Night.background.opacity(0), Night.background], startPoint: .top, endPoint: .bottom)
                        .frame(height: 110)
                }
                .clipped()
            }
            Text("My map")
                .font(.rpText(size: 9, weight: .bold))
                .tracking(3.7)
                .textCase(.uppercase)
                .foregroundStyle(Night.accentText)
                .padding(.leading, M.margin)
                .padding(.top, M.kickerTop)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(content.distanceValue)
                        .font(.custom(RPFont.number, fixedSize: 84))
                        .tracking(-0.5)
                        .foregroundStyle(Night.text)
                    Text(content.distanceUnit)
                        .font(.custom(RPFont.number, fixedSize: 24))
                        .tracking(1)
                        .textCase(.uppercase)
                        .foregroundStyle(Night.accentText)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.leading, -2)
                .padding(.bottom, -10)
                Text(content.tripsLine)
                    .font(.rpText(size: 14, weight: .semibold))
                    .foregroundStyle(Night.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 2.7)
                Text(content.caption)
                    .font(.rpText(size: 10.5, weight: .medium))
                    .foregroundStyle(Night.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 3)
                HeatLegend(maxCount: content.maxCount, palette: HeatMapArt.nightPalette, text: Night.textSecondary,
                           font: .rpText(size: 8.5, weight: .semibold))
                    .frame(width: 150)
                    .padding(.top, 12)
                ShareCardSignature(word: Night.accentText, caption: Night.textSecondary)
                    .padding(.top, M.blockGap + 2)
            }
            .padding(.horizontal, M.margin)
            .padding(.bottom, M.bottomMargin)
            .frame(width: M.size.width, height: M.size.height, alignment: .bottomLeading)
        }
        .frame(width: M.size.width, height: M.size.height, alignment: .topLeading)
        .clipped()
        .environment(\.colorScheme, .dark)
        .dynamicTypeSize(.large)
    }
}

/// Share the heat map as a picture: a preview and the system share sheet.
struct MyMapShareSheet: View {
    let trips: [HeatTrip]
    let caption: String
    let unit: DistanceUnit

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var card: Prepared?
    @State private var exported: Image?

    private struct Prepared {
        let content: MyMapCardContent
        let scene: HeatScene?
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: RPSpace.l) {
                GeometryReader { proxy in
                    let size = ShareCardMetrics.size
                    let scale = min(proxy.size.width / size.width, proxy.size.height / size.height)
                    Group {
                        if let card, scale > 0 {
                            MyMapCard(content: card.content, scene: card.scene)
                                .scaleEffect(scale)
                                .frame(width: size.width * scale, height: size.height * scale)
                                .clipShape(RoundedRectangle(cornerRadius: RPRadius.card))
                                .overlay {
                                    RoundedRectangle(cornerRadius: RPRadius.card)
                                        .strokeBorder(Color.RP.border, lineWidth: RPSize.hairline(displayScale: displayScale))
                                }
                                .accessibilityIdentifier("myMapCardPreview")
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if let exported {
                    ShareLink(item: exported, preview: SharePreview("RoadPrint map", image: exported)) {
                        Text("Share")
                    }
                    .buttonStyle(.rpPrimary)
                    .accessibilityIdentifier("shareMapButton")
                } else {
                    ProgressView()
                        .frame(height: RPSize.buttonHeight)
                }
            }
            .padding(RPSpace.screenMargin)
            .background(Color.RP.background.ignoresSafeArea())
            .navigationTitle("Share my map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await prepare() }
    }

    private func prepare() async {
        let scene = await HeatMapArt.layout(
            routes: trips.map(\.segments),
            size: CGSize(width: ShareCardMetrics.size.width, height: MyMapCard.mapHeight), insets: MyMapCard.mapInsets)
        guard !Task.isCancelled else { return }
        let content = MyMapCardContent.make(trips: trips, caption: caption, unit: unit, maxCount: scene?.maxCount ?? 0)
        card = Prepared(content: content, scene: scene)
        let renderer = ImageRenderer(content: MyMapCard(content: content, scene: scene))
        renderer.scale = ShareCardMetrics.exportScale
        if let image = renderer.uiImage { exported = Image(uiImage: image) }
    }
}

#if DEBUG
/// DEBUG-only: the "My map" card on made-up trips. Launch with `-RPHeatCardFixture usa-500`.
struct MyMapCardDebugView: View {
    let fixture: String
    @State private var card: (content: MyMapCardContent, scene: HeatScene?)?

    var body: some View {
        ScrollView {
            if let card {
                MyMapCard(content: card.content, scene: card.scene)
                    .accessibilityIdentifier("myMapCard")
                    .frame(maxWidth: .infinity)
            }
        }
        .background(Color.RP.Night.background.ignoresSafeArea())
        .task {
            let trips = MyMapLogic.filtered(HeatDebugView.trips(fixture: fixture), by: MapFilter(), now: Date())
            let scene = await HeatMapArt.layout(
                routes: trips.map(\.segments),
                size: CGSize(width: ShareCardMetrics.size.width, height: MyMapCard.mapHeight), insets: MyMapCard.mapInsets)
            let first = trips.map(\.date).min() ?? Date()
            card = (MyMapCardContent.make(
                trips: trips, caption: "Every recorded trip since \(first.formatted(.dateTime.month(.abbreviated).year()))",
                unit: .miles, maxCount: scene?.maxCount ?? 0), scene)
        }
    }
}
#endif
