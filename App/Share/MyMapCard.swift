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
    /// The road most trips were on, shown with its sign.
    var topRoad: MyMapLogic.TopRoad?
    /// Every region and country the trips cross: only these and their neighbours are labelled.
    var crossedCodes: Set<String>

    static func make(trips: [HeatTrip], caption: String, unit: DistanceUnit) -> MyMapCardContent {
        let distance = ShareCardText.distance(meters: trips.reduce(0) { $0 + $1.distanceMeters }, unit: unit)
        return MyMapCardContent(distanceValue: distance.value, distanceUnit: distance.unit,
                                tripsLine: MyMapLogic.tripsLine(trips), caption: caption,
                                topRoad: MyMapLogic.topRoads(trips, limit: 1).first,
                                crossedCodes: Set(trips.flatMap { ($0.regions + $0.countries).map(\.code) }))
    }

    /// "Most driven: I-80 · 244 trips".
    func topRoadLine(_ road: MyMapLogic.TopRoad) -> String {
        String(localized: "Most driven: \(road.name) · \(MyMapLogic.tripCount(road.trips))",
               comment: "My map share card, beside the road sign: the road most trips were on and how many trips.")
    }
}

/// The heat map as a picture to share (1080 × 1920): the driver's whole road network glowing on
/// the night map, the total distance, the most driven road and the signature. Always the night
/// palette. Everything sits above 1600 px (Designer, ROA-60). Lay it out at
/// `ShareCardMetrics.size` and scale it; never resize its frame.
struct MyMapCard: View {
    let content: MyMapCardContent
    let scene: HeatScene?

    private typealias M = ShareCardMetrics
    private typealias Night = Color.RP.Night

    /// 0–1100 px; the network in the box (72, 340)–(1008, 840) px.
    static let mapHeight: CGFloat = 366.67
    static let mapInsets = ViewportInsets(top: 91.3, left: 2, bottom: 64.7, right: 2)
    static var mapLabels: MapLabelRules { ShareCardMetrics.cardLabels(height: mapHeight, band: true) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Night.background
            if let scene {
                let base = HeatMapArt.base(scene, scheme: .dark, displayScale: M.exportScale, labels: false)
                let crossed = content.crossedCodes
                Canvas { context, _ in
                    base.draw(&context)
                    HeatMapArt.draw(scene.lines, palette: HeatMapArt.nightPalette, glow: true, softHalo: 4, in: &context)
                    MyMapCardArt.labels(scene.map, crossed: crossed, in: &context)
                }
                .frame(width: M.size.width, height: Self.mapHeight)
                .overlay(alignment: .top) {
                    LinearGradient(colors: [Night.background, Night.background.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: M.fadeTop)
                }
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [Night.background.opacity(0), Night.background], startPoint: .top, endPoint: .bottom)
                        .frame(height: M.fadeBottom)
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
            // The number at 1240 px, the trips at 1310 px, the caption at 1360 px, the road from 1388 px.
            CardPlace.baseline(413.33, x: M.margin - 2) {
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
            }
            CardPlace.baseline(436.67) {
                Text(content.tripsLine)
                    .font(.rpText(size: 14, weight: .semibold))
                    .foregroundStyle(Night.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            CardPlace.baseline(453.33) {
                Text(content.caption)
                    .font(.rpText(size: 10.5, weight: .medium))
                    .foregroundStyle(Night.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            if let road = content.topRoad {
                CardPlace.top(462.67) {
                    HStack(spacing: 8) {
                        RoadSign(road: road.road, height: 21.33, detailHeight: 64)
                        Text(verbatim: content.topRoadLine(road))
                            .font(.rpText(size: 10, weight: .medium))
                            .foregroundStyle(Night.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(height: 21.33)
                }
            }
            CardPlace.signature(word: Night.accentText, caption: Night.textSecondary)
        }
        .frame(width: M.size.width, height: M.size.height, alignment: .topLeading)
        .clipped()
        .environment(\.colorScheme, .dark)
        .dynamicTypeSize(.large)
    }
}

/// Canvas drawing for the My map card. Not a view: Canvas closures run off the main actor.
enum MyMapCardArt {
    /// Only the places the driver has been (0.42) and the places next to them (0.22); every other
    /// label is dropped. "Next to" means their outlines' boxes touch.
    static func labels(_ scene: MapScene, crossed: Set<String>, in context: inout GraphicsContext) {
        var boxes: [String: CGRect] = [:]
        for outline in scene.outlines {
            var box = boxes[outline.place.code] ?? .null
            for ring in outline.rings {
                for point in ring { box = box.union(CGRect(x: point.x, y: point.y, width: 0, height: 0)) }
            }
            boxes[outline.place.code] = box
        }
        let driven = crossed.compactMap { boxes[$0]?.insetBy(dx: -2, dy: -2) }
        for label in scene.regionLabels {
            guard let code = label.placeCode else { continue }
            let opacity: Double
            if crossed.contains(code) {
                opacity = 0.42
            } else if let box = boxes[code], driven.contains(where: { $0.intersects(box) }) {
                opacity = 0.22
            } else {
                continue
            }
            let text = Text(label.text.uppercased()).font(.rpText(size: 12.67, weight: .semibold)).tracking(3)
                .foregroundColor(Color.RP.Night.textSecondary.opacity(opacity))
            context.draw(context.resolve(text), at: CGPoint(x: label.anchor.x, y: label.anchor.y), anchor: .center)
        }
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
            size: CGSize(width: ShareCardMetrics.size.width, height: MyMapCard.mapHeight), insets: MyMapCard.mapInsets,
            labels: MyMapCard.mapLabels)
        guard !Task.isCancelled else { return }
        let content = MyMapCardContent.make(trips: trips, caption: caption, unit: unit)
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
                size: CGSize(width: ShareCardMetrics.size.width, height: MyMapCard.mapHeight), insets: MyMapCard.mapInsets,
            labels: MyMapCard.mapLabels)
            let first = trips.map(\.date).min() ?? Date()
            card = (MyMapCardContent.make(
                trips: trips, caption: "Every recorded trip since \(first.formatted(.dateTime.month(.abbreviated).year()))",
                unit: .miles), scene)
        }
    }
}
#endif
