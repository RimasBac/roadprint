import SwiftUI
import RoadPrintCore

/// Sizes of the Night Highway card in points. One point is three pixels of the 1080 × 1920 export;
/// the values are the board reference (`Design/reference/board/night-highway`) divided by three.
enum ShareCardMetrics {
    static let size = CGSize(width: 360, height: 640)
    /// 1080 × 1920 px.
    static let exportScale: CGFloat = 3
    /// The map fills the top of the card and fades out below this height.
    static let mapHeight: CGFloat = 360
    /// With the 22 pt the builder reserves for the area circles, the route lands in the
    /// reference's route box (x 43...317, y 127...283).
    static let mapInsets = ViewportInsets(top: 105, left: 21, bottom: 55, right: 21)
    static let margin: CGFloat = 24
    static let kickerTop: CGFloat = 80
    static let bragTop: CGFloat = 322
    static let fadeTop: CGFloat = 100
    static let fadeBottom: CGFloat = 80
    static let watermarkTop: CGFloat = 524
    static let chipHeight: CGFloat = 24
}

/// Text for a share card, made only from a `TripShareSummary` (AGENTS.md §7b.3).
enum ShareCardText {
    /// The one big number and its unit word: ("649", "miles").
    static func distance(meters: Double, unit: DistanceUnit, locale: Locale = .current) -> (value: String, unit: String) {
        let value = unit.displayValue(meters: meters)
            .formatted(.number.precision(.fractionLength(0...1)).locale(locale))
        switch unit {
        case .miles: return (value, String(localized: "miles", comment: "Share card: unit word next to the big distance number."))
        case .kilometers: return (value, String(localized: "km", comment: "Share card: unit next to the big distance number."))
        }
    }

    /// "Utah → California · Nov 4": first and last region (or country), then the day.
    static func subtitle(places: TripPlaces, day: ShareDay, locale: Locale = .current) -> String {
        let refs = places.regions.count >= 2 ? places.regions
            : places.countries.count >= 2 ? places.countries
            : places.regions.isEmpty ? places.countries : places.regions
        var parts: [String] = []
        if let first = refs.first?.name, let last = refs.last?.name {
            parts.append(first == last ? first : "\(first) → \(last)")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        if let date = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)) {
            var style = Date.FormatStyle(locale: locale, timeZone: calendar.timeZone)
            style = style.month(.abbreviated).day()
            parts.append(date.formatted(style))
        }
        return parts.joined(separator: " · ")
    }

    static func content(summary: TripShareSummary, unit: DistanceUnit, altitude: String?,
                        locale: Locale = .current) -> NightHighwayCard.Content {
        let brag = distance(meters: summary.distanceMeters, unit: unit, locale: locale)
        var chips = [TripFormatting.duration(seconds: summary.movingTimeSeconds)]
        if let altitude { chips.append(altitude) }
        return NightHighwayCard.Content(
            distanceValue: brag.value, distanceUnit: brag.unit,
            subtitle: subtitle(places: summary.places, day: summary.day, locale: locale), chips: chips)
    }
}

/// The free default share card (plan §4.4, mockup 2, FEEL_STANDARD §9): the route glowing on the
/// night map, one big number, at most two more stats. Always the night palette, whatever the
/// phone's theme. Lay it out at `ShareCardMetrics.size` and scale it; never resize its frame.
struct NightHighwayCard: View {
    struct Content: Equatable {
        var distanceValue: String
        var distanceUnit: String
        var subtitle: String
        var chips: [String]
    }

    let content: Content
    /// Nil when the driver hides the route: the card keeps its numbers and loses the map.
    let scene: MapScene?
    let summitAltitude: String

    private typealias M = ShareCardMetrics

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.RP.Night.background
            if let scene { map(scene) }
            Text(verbatim: "ROADPRINT")
                .font(.rpText(size: 9, weight: .bold))
                .tracking(3.7)
                .foregroundStyle(Color.RP.Night.accentText)
                .padding(.leading, M.margin)
                .padding(.top, M.kickerTop)
            brag
                .padding(.horizontal, M.margin)
                .padding(.top, M.bragTop)
            Text("Made with RoadPrint")
                .font(.rpText(size: 7.3, weight: .semibold))
                .tracking(1.7)
                .textCase(.uppercase)
                .foregroundStyle(Color.RP.Night.textSecondary.opacity(0.75))
                .frame(width: M.size.width)
                .padding(.top, M.watermarkTop)
        }
        .frame(width: M.size.width, height: M.size.height, alignment: .topLeading)
        .clipped()
        .environment(\.colorScheme, .dark)
        .dynamicTypeSize(.large)
    }

    private var brag: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(content.distanceValue)
                    .font(.rpNumber(size: 100))
                    .foregroundStyle(Color.RP.Night.text)
                Text(content.distanceUnit)
                    .font(.rpNumber(size: 26))
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.RP.Night.accentText)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.bottom, -12)
            Text(content.subtitle)
                .font(.rpText(size: 14, weight: .semibold))
                .foregroundStyle(Color.RP.Night.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            HStack(spacing: 6) {
                ForEach(content.chips, id: \.self) { chip in
                    Text(chip)
                        .font(.rpText(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.RP.Night.text)
                        .padding(.horizontal, 10)
                        .frame(height: M.chipHeight)
                        .background(Color.RP.Night.land, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.RP.Night.border, lineWidth: 0.67))
                }
            }
            .padding(.top, 6)
        }
    }

    private func map(_ scene: MapScene) -> some View {
        let renderer = MapSceneRenderer(scene: scene, scheme: .dark, displayScale: M.exportScale,
                                        summitName: String(localized: "Highest point"), summitAltitude: summitAltitude)
        return Canvas { context, _ in
            renderer.draw(&context)
            Self.drawHeadlights(scene, in: &context)
        }
        .frame(width: M.size.width, height: M.mapHeight)
        .overlay(alignment: .top) {
            LinearGradient(colors: [Color.RP.Night.background, Color.RP.Night.background.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: M.fadeTop)
        }
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [Color.RP.Night.background.opacity(0), Color.RP.Night.background],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: M.fadeBottom)
        }
    }

    /// The card's signature: light spilled on the ground, a soft halo, a tight halo, the amber
    /// core and a pale centre line (the reference's five strokes), over the standard map.
    private nonisolated static func drawHeadlights(_ scene: MapScene, in context: inout GraphicsContext) {
        let paths: [Path] = scene.routes.filter { $0.kind == .recorded }.map { route in
            var path = Path()
            guard let first = route.points.first else { return path }
            path.move(to: CGPoint(x: first.x, y: first.y))
            for point in route.points.dropFirst() { path.addLine(to: CGPoint(x: point.x, y: point.y)) }
            return path
        }
        guard !paths.isEmpty else { return }
        func halo(width: CGFloat, blur: CGFloat, opacity: Double) {
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: blur))
                layer.opacity = opacity
                for path in paths {
                    layer.stroke(path, with: .color(Color.RP.Night.route),
                                 style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                }
            }
        }
        halo(width: 30, blur: 15, opacity: 0.16)
        halo(width: 13, blur: 7, opacity: 0.38)
        halo(width: 7, blur: 2.5, opacity: 0.7)
        for path in paths {
            context.stroke(path, with: .color(Color.RP.Night.route),
                           style: StrokeStyle(lineWidth: 3.3, lineCap: .round, lineJoin: .round))
            context.stroke(path, with: .color(Color.RP.Night.heat5.opacity(0.85)),
                           style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
        }
        // The halos soften the end dots: put them back on top.
        for area in [scene.startArea, scene.endArea].compactMap({ $0 }) {
            let centre = CGPoint(x: area.center.x, y: area.center.y)
            context.fill(Path(ellipseIn: CGRect(x: centre.x - 3, y: centre.y - 3, width: 6, height: 6)),
                         with: .color(Color.RP.Night.background))
            context.fill(Path(ellipseIn: CGRect(x: centre.x - 2, y: centre.y - 2, width: 4, height: 4)),
                         with: .color(Color.RP.Night.route))
        }
    }
}
