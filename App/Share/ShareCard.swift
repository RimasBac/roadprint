import SwiftUI
import RoadPrintCore

/// The card styles a driver can pick in the share sheet (plan §4.4, mockup 2).
enum ShareCardStyle: String, CaseIterable, Identifiable, Sendable {
    case nightHighway, roadAtlas, poster

    var id: String { rawValue }

    var name: String {
        switch self {
        case .nightHighway: String(localized: "Night Highway", comment: "Share card style name.")
        case .roadAtlas: String(localized: "Road Atlas", comment: "Share card style name.")
        case .poster: String(localized: "Poster", comment: "Share card style name.")
        }
    }
}

/// Where a style draws its map, and how the core lays that map out.
struct ShareCardMapSpec {
    let top: CGFloat
    let height: CGFloat
    let insets: ViewportInsets
    let labels: MapLabelRules
    /// True when the builder places the start and end names (map style). The Night Highway card
    /// places its own small capitals, and the Poster has none.
    let namesAreas: Bool
}

/// Sizes of the share cards in points. One point is three pixels of the 1080 × 1920 export.
/// The Night Highway values come from the board reference (`Design/reference/board/night-highway`)
/// and the Designer's review of build 10 (ROA-60), divided by three.
enum ShareCardMetrics {
    static let size = CGSize(width: 360, height: 640)
    /// 1080 × 1920 px.
    static let exportScale: CGFloat = 3
    static let margin: CGFloat = 24
    static let bottomMargin: CGFloat = 22
    static let blockGap: CGFloat = 14
    static let footerHeight: CGFloat = 24
    static let markRadius: CGFloat = 5.5
    static let kickerTop: CGFloat = 80
    static let fadeTop: CGFloat = 100
    static let fadeBottom: CGFloat = 100
    static let chipHeight: CGFloat = 24
    static let nightStrip: CGFloat = 54
    static let atlasStrip: CGFloat = 70
    static let posterStrip: CGFloat = 100
    /// Room above the Poster's elevation line for the highest-point caption.
    static let posterCaption: CGFloat = 26
    static let ringRadius: CGFloat = 10

    /// The map grows when there is no elevation strip, so the card never has an empty band.
    static func map(_ style: ShareCardStyle, hasElevation: Bool) -> ShareCardMapSpec {
        switch style {
        case .nightHighway:
            let height: CGFloat = hasElevation ? 400 : 454
            var rules = MapLabelRules()
            rules.summitWidth = 84
            rules.summitHeight = 20
            rules.summitGap = 8.7
            rules.summitRise = 4
            rules.summitOffsets = [0, 3, 6, 9, 12, 16, 20, 24, -20, -24]
            rules.summitRouteClearance = 3
            // No region code inside the fades, near the route or crowding another code.
            rules.regionBand = Double(fadeTop + 13)...Double(height - fadeBottom + 20)
            rules.regionRouteClearance = 24
            rules.regionSpacing = 30
            return ShareCardMapSpec(top: 0, height: height,
                                    insets: ViewportInsets(top: 108, left: 21, bottom: hasElevation ? 68 : 72, right: 21),
                                    labels: rules, namesAreas: false)
        case .roadAtlas:
            return ShareCardMapSpec(top: 92, height: hasElevation ? 332 : 416,
                                    insets: ViewportInsets(top: 30, left: 21, bottom: 30, right: 21),
                                    labels: .map, namesAreas: true)
        case .poster:
            return ShareCardMapSpec(top: 40, height: hasElevation ? 330 : 440,
                                    insets: ViewportInsets(top: 30, left: 30, bottom: 30, right: 30),
                                    labels: .map, namesAreas: false)
        }
    }
}

/// Every text a card shows. Made only from a `TripShareSummary` (AGENTS.md §7b.3).
struct ShareCardContent: Equatable, Sendable {
    struct Stat: Equatable, Sendable {
        var value: String
        var label: String
    }

    /// The one big number and its unit word: "649", "miles".
    var distanceValue: String
    var distanceUnit: String
    /// "Utah → California · Nov 4".
    var subtitle: String
    var chips: [String]
    /// "Utah → California": the Road Atlas header.
    var title: String
    /// "Wednesday, November 4, 2026".
    var longDate: String
    /// The Road Atlas strip: distance, hours, places, summit.
    var stats: [Stat]
    /// "I-80 West", or the title when the main road isn't known.
    var posterTitle: String
    /// "649 mi · 3 states · 11/04/2026".
    var posterLine: String
    /// Codes of the regions and countries the trip crosses: their map labels are brighter.
    var crossedCodes: Set<String>
    var startLabel: String?
    var endLabel: String?
    var summitAltitude: String?
}

/// The trip's elevation as a shape: x is the share of the distance, y the share of the height.
struct ShareCardElevation: Equatable, Sendable {
    var series: [[CGPoint]]
    var summit: CGPoint

    /// A nearly flat trip keeps a low line: the height is never stretched over less than this
    /// many feet or metres.
    static let minimumSpan = 60.0

    static func make(_ profile: ElevationProfile) -> ShareCardElevation? {
        let altitudes = profile.series.flatMap { $0.map(\.altitude) } + [profile.summit.altitude]
        guard let low = altitudes.min(), let high = altitudes.max(), profile.totalDistance > 0,
              profile.series.contains(where: { $0.count > 1 }) else { return nil }
        let span = max(high - low, minimumSpan), total = profile.totalDistance
        func point(_ sample: ElevationProfile.Sample) -> CGPoint {
            CGPoint(x: min(max(sample.distance / total, 0), 1), y: min(max((sample.altitude - low) / span, 0), 1))
        }
        return ShareCardElevation(series: profile.series.map { $0.map(point) }, summit: point(profile.summit))
    }
}

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

    private static var utc: TimeZone { TimeZone(identifier: "UTC") ?? .current }

    private static func date(_ day: ShareDay) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12))
    }

    /// "Utah → California": the first and last region (or country) of the trip.
    static func title(places: TripPlaces) -> String {
        let refs = places.regions.count >= 2 ? places.regions
            : places.countries.count >= 2 ? places.countries
            : places.regions.isEmpty ? places.countries : places.regions
        guard let first = refs.first?.name, let last = refs.last?.name else { return "" }
        return first == last ? first : "\(first) → \(last)"
    }

    /// "Utah → California · Nov 4".
    static func subtitle(places: TripPlaces, day: ShareDay, locale: Locale = .current) -> String {
        var parts: [String] = []
        let names = title(places: places)
        if !names.isEmpty { parts.append(names) }
        if let date = date(day) {
            parts.append(date.formatted(Date.FormatStyle(locale: locale, timeZone: utc).month(.abbreviated).day()))
        }
        return parts.joined(separator: " · ")
    }

    /// (3, "states"): how many regions or countries the trip crosses, with the right word.
    static func placeCount(_ places: TripPlaces) -> (count: Int, noun: String)? {
        if places.countries.count > 1 {
            return (places.countries.count, String(localized: "countries", comment: "Share card: after a number, e.g. 3 countries."))
        }
        guard let first = places.regions.first else { return nil }
        let count = places.regions.count, one = count == 1
        switch first.code.split(separator: "-").first.map(String.init) ?? "" {
        case "US", "AU":
            return (count, one ? String(localized: "state", comment: "Share card: after the number 1.")
                               : String(localized: "states", comment: "Share card: after a number, e.g. 3 states."))
        case "CA":
            return (count, one ? String(localized: "province", comment: "Share card: after the number 1.")
                               : String(localized: "provinces", comment: "Share card: after a number, e.g. 3 provinces."))
        default:
            return (count, one ? String(localized: "region", comment: "Share card: after the number 1.")
                               : String(localized: "regions", comment: "Share card: after a number, e.g. 3 regions."))
        }
    }

    /// "I-80", "US-50", "E40".
    static func roadName(_ road: MainRoad) -> String {
        switch road.network {
        case .usInterstate: "I-\(road.ref)"
        case .usHighway: "US-\(road.ref)"
        default: road.ref
        }
    }

    /// "West": the compass side the trip ends on, seen from its start.
    static func heading(_ summary: TripShareSummary) -> String? {
        let from = summary.start.map { ($0.centerLatitude, $0.centerLongitude) }
            ?? summary.route?.first?.points.first.map { ($0.latitude, $0.longitude) }
        let to = summary.end.map { ($0.centerLatitude, $0.centerLongitude) }
            ?? summary.route?.last?.points.last.map { ($0.latitude, $0.longitude) }
        guard let from, let to else { return nil }
        let north = to.0 - from.0
        let east = (to.1 - from.1) * cos((from.0 + to.0) / 2 * .pi / 180)
        guard abs(north) + abs(east) > 0.01 else { return nil }
        if abs(east) >= abs(north) {
            return east > 0 ? String(localized: "East", comment: "Share card: direction of travel, after a road name.")
                            : String(localized: "West", comment: "Share card: direction of travel, after a road name.")
        }
        return north > 0 ? String(localized: "North", comment: "Share card: direction of travel, after a road name.")
                         : String(localized: "South", comment: "Share card: direction of travel, after a road name.")
    }

    /// "10:22": hours and minutes of driving.
    static func clock(seconds: Double) -> String {
        let minutes = Int(max(0, seconds) / 60)
        return "\(minutes / 60):" + (minutes % 60 < 10 ? "0" : "") + "\(minutes % 60)"
    }

    static func content(summary: TripShareSummary, unit: DistanceUnit, altitude: String?,
                        startLabel: String? = nil, endLabel: String? = nil,
                        locale: Locale = .current) -> ShareCardContent {
        let brag = distance(meters: summary.distanceMeters, unit: unit, locale: locale)
        let count = placeCount(summary.places)
        let countText = count.map { "\($0.count.formatted(.number.locale(locale))) \($0.noun)" }
        let duration = TripFormatting.duration(seconds: summary.movingTimeSeconds)

        // The altitude chip would repeat the highest-point label on the map, so it only
        // stands in when there is no second chip or no marker.
        var chips = [duration]
        if let count, count.count >= 2, let countText { chips.append(countText) }
        if let altitude, chips.count < 2 || summary.summit == nil { chips.append(altitude) }

        var stats = [ShareCardContent.Stat(value: brag.value, label: brag.unit),
                     ShareCardContent.Stat(value: clock(seconds: summary.movingTimeSeconds),
                                           label: String(localized: "hours", comment: "Share card: under the driving time, e.g. 10:22."))]
        if let count {
            stats.append(.init(value: count.count.formatted(.number.locale(locale)), label: count.noun))
        }
        if let altitude {
            let parts = altitude.split(separator: " ")
            if parts.count >= 2, let symbol = parts.last {
                stats.append(.init(value: parts.dropLast().joined(separator: " "),
                                   label: String(localized: "\(String(symbol)) summit",
                                                 comment: "Share card: under the highest altitude; the placeholder is the unit, e.g. ft summit.")))
            }
        }

        let names = title(places: summary.places)
        let road = summary.mainRoad.map { [roadName($0), heading(summary)].compactMap { $0 }.joined(separator: " ") }
        let symbol = unit == .miles ? UnitLength.miles.symbol : UnitLength.kilometers.symbol
        var line = ["\(brag.value) \(symbol)"]
        if let countText { line.append(countText) }
        var longDate = ""
        if let date = date(summary.day) {
            let style = Date.FormatStyle(locale: locale, timeZone: utc)
            line.append(date.formatted(style.day(.twoDigits).month(.twoDigits).year()))
            longDate = date.formatted(style.weekday(.wide).month(.wide).day().year())
        }

        return ShareCardContent(
            distanceValue: brag.value, distanceUnit: brag.unit,
            subtitle: subtitle(places: summary.places, day: summary.day, locale: locale), chips: chips,
            title: names, longDate: longDate, stats: stats,
            posterTitle: road ?? (names.isEmpty ? "\(brag.value) \(symbol)" : names),
            posterLine: line.joined(separator: " · "),
            crossedCodes: Set((summary.places.regions + summary.places.countries).map(\.code)),
            startLabel: startLabel, endLabel: endLabel, summitAltitude: altitude)
    }
}

/// A share card (plan §4.4, mockup 2, FEEL_STANDARD §9). Lay it out at `ShareCardMetrics.size`
/// and scale it; never resize its frame. Each style keeps its own palette whatever the phone's theme.
struct ShareCard: View {
    let style: ShareCardStyle
    let content: ShareCardContent
    let scene: MapScene?
    let elevation: ShareCardElevation?

    private typealias M = ShareCardMetrics
    private typealias Night = Color.RP.Night

    var body: some View {
        Group {
            switch style {
            case .nightHighway: nightHighway
            case .roadAtlas: roadAtlas
            case .poster: poster
            }
        }
        .frame(width: M.size.width, height: M.size.height, alignment: .topLeading)
        .clipped()
        .environment(\.colorScheme, style == .roadAtlas ? .light : .dark)
        .dynamicTypeSize(.large)
    }

    private func display(_ size: CGFloat) -> Font { .custom(RPFont.number, fixedSize: size) }

    // MARK: Night Highway

    private var nightHighway: some View {
        let spec = M.map(.nightHighway, hasElevation: elevation != nil)
        let labels = ShareCardArt.Labels(
            crossed: content.crossedCodes, start: content.startLabel, end: content.endLabel,
            summitName: String(localized: "Highest point"), summitAltitude: content.summitAltitude)
        return ZStack(alignment: .topLeading) {
            Night.background
            if let scene {
                Canvas { context, _ in
                    ShareCardArt.nightHighway(scene, labels: labels, in: &context)
                }
                .frame(width: M.size.width, height: spec.height)
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
            Text(verbatim: "ROADPRINT")
                .font(.rpText(size: 9, weight: .bold))
                .tracking(3.7)
                .foregroundStyle(Night.accentText)
                .padding(.leading, M.margin)
                .padding(.top, M.kickerTop)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    // Proportional digits: tabular ones leave holes in a number this big.
                    Text(content.distanceValue)
                        .font(display(100))
                        .tracking(-0.67)
                        .foregroundStyle(Night.text)
                    Text(content.distanceUnit)
                        .font(display(26))
                        .tracking(1)
                        .textCase(.uppercase)
                        .foregroundStyle(Night.accentText)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                // The digit's ink starts a little inside its box: line it up with the text below.
                .padding(.leading, -3)
                .padding(.bottom, -12)
                Text(content.subtitle)
                    .font(.rpText(size: 14, weight: .semibold))
                    .foregroundStyle(Night.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 2.7)
                HStack(spacing: 5.3) {
                    ForEach(content.chips, id: \.self) { chip in
                        Text(chip)
                            .font(.rpText(size: 11.5, weight: .medium))
                            .foregroundStyle(Night.text)
                            .padding(.horizontal, 11.3)
                            .frame(height: M.chipHeight)
                            .background(Night.land, in: Capsule())
                            .overlay(Capsule().strokeBorder(Night.border, lineWidth: 0.67))
                    }
                }
                .padding(.top, 10)
                if let elevation {
                    strip(elevation, line: Night.route, fillTop: 0.45, dot: Night.text)
                        .frame(height: M.nightStrip)
                        .padding(.top, M.blockGap)
                }
                footer(word: Night.accentText, caption: Night.textSecondary)
                    .padding(.top, M.blockGap)
            }
            .padding(.horizontal, M.margin)
            .padding(.bottom, M.bottomMargin)
            .frame(width: M.size.width, height: M.size.height, alignment: .bottomLeading)
        }
    }

    // MARK: Road Atlas

    private var roadAtlas: some View {
        let spec = M.map(.roadAtlas, hasElevation: elevation != nil)
        let summitName = String(localized: "Highest point")
        let altitude = content.summitAltitude ?? ""
        return ZStack(alignment: .topLeading) {
            Color.RP.background
            VStack(alignment: .leading, spacing: 3) {
                Text(content.title)
                    .font(display(30))
                    .textCase(.uppercase)
                    .foregroundStyle(Color.RP.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(content.longDate)
                    .font(.rpText(size: 11.5))
                    .foregroundStyle(Color.RP.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, M.margin)
            .padding(.top, 30)
            if let scene {
                let renderer = MapSceneRenderer(scene: scene, scheme: .light, displayScale: M.exportScale,
                                                summitName: summitName, summitAltitude: altitude)
                Canvas { context, _ in
                    renderer.draw(&context)
                }
                .frame(width: M.size.width, height: spec.height)
                .clipped()
                .overlay(alignment: .top) { Rectangle().fill(Color.RP.border).frame(height: 0.67) }
                .overlay(alignment: .bottom) { Rectangle().fill(Color.RP.border).frame(height: 0.67) }
                .padding(.top, spec.top)
            }
            VStack(alignment: .leading, spacing: 0) {
                Rectangle().fill(Color.RP.text).frame(height: 1)
                HStack(alignment: .top, spacing: 0) {
                    ForEach(content.stats, id: \.label) { stat in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stat.value)
                                .font(display(26))
                                .foregroundStyle(Color.RP.text)
                            Text(stat.label)
                                .font(.rpText(size: 7.5, weight: .semibold))
                                .tracking(1.5)
                                .textCase(.uppercase)
                                .foregroundStyle(Color.RP.textSecondary)
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, M.blockGap)
                if let elevation {
                    strip(elevation, line: Color.RP.route, fillTop: 0.4, dot: nil)
                        .frame(height: M.atlasStrip)
                        .padding(.top, M.blockGap)
                }
                footer(word: Color.RP.text, caption: Color.RP.textSecondary)
                    .padding(.top, M.blockGap)
            }
            .padding(.horizontal, M.margin)
            .padding(.bottom, M.bottomMargin)
            .frame(width: M.size.width, height: M.size.height, alignment: .bottomLeading)
        }
    }

    // MARK: Poster

    private var poster: some View {
        let spec = M.map(.poster, hasElevation: elevation != nil)
        let summitName = String(localized: "Highest point")
        let altitude = content.summitAltitude
        return ZStack(alignment: .topLeading) {
            Night.background
            if let scene {
                Canvas { context, _ in
                    ShareCardArt.posterRoute(scene, in: &context)
                }
                .frame(width: M.size.width, height: spec.height)
                .padding(.top, spec.top)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(content.posterTitle)
                    .font(display(54))
                    .textCase(.uppercase)
                    .foregroundStyle(Night.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                Text(content.posterLine)
                    .font(.rpText(size: 10.5, weight: .semibold))
                    .tracking(2)
                    .textCase(.uppercase)
                    .foregroundStyle(Night.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 2)
                if let elevation {
                    Canvas { context, size in
                        ShareCardArt.elevation(elevation, size: size, line: Night.route, fillTop: 0.55, lineWidth: 1.5,
                                               topInset: M.posterCaption, summitDot: nil, in: &context)
                        ShareCardArt.posterCaption(elevation, size: size, name: summitName, altitude: altitude, in: &context)
                    }
                    .frame(height: M.posterStrip)
                    // The profile runs edge to edge.
                    .padding(.horizontal, -M.margin)
                    .padding(.top, 12)
                }
                footer(word: Night.text, caption: Night.textSecondary)
                    .padding(.top, M.blockGap)
            }
            .padding(.horizontal, M.margin)
            .padding(.bottom, M.bottomMargin)
            .frame(width: M.size.width, height: M.size.height, alignment: .bottomLeading)
        }
    }

    // MARK: Shared parts

    private func strip(_ elevation: ShareCardElevation, line: Color, fillTop: Double, dot: Color?) -> some View {
        Canvas { context, size in
            ShareCardArt.elevation(elevation, size: size, line: line, fillTop: fillTop, lineWidth: 1.5,
                                   topInset: 4, summitDot: dot, in: &context)
        }
    }

    /// The signature: the app's mark and its name.
    private func footer(word: Color, caption: Color) -> some View {
        HStack(spacing: 8) {
            Image("BrandMark")
                .resizable()
                .interpolation(.high)
                .frame(width: M.footerHeight, height: M.footerHeight)
                .clipShape(RoundedRectangle(cornerRadius: M.markRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: M.markRadius, style: .continuous)
                    .strokeBorder(caption.opacity(0.35), lineWidth: 0.5))
            VStack(alignment: .leading, spacing: 2) {
                Text("Made with")
                    .font(.rpText(size: 6.5, weight: .semibold))
                    .tracking(1.6)
                    .textCase(.uppercase)
                    .foregroundStyle(caption)
                Text(verbatim: "ROADPRINT")
                    .font(.rpText(size: 11, weight: .bold))
                    .tracking(3.2)
                    .foregroundStyle(word)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: M.footerHeight)
    }
}

/// Canvas drawing for the cards. Not a view: Canvas closures run off the main actor.
enum ShareCardArt {
    struct Labels: Sendable {
        var crossed: Set<String>
        var start: String?
        var end: String?
        var summitName: String
        var summitAltitude: String?
    }

    private typealias Night = Color.RP.Night
    private static let measure = CGSize(width: 1_000, height: 200)

    static func path(_ points: [PlanePoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: first.x, y: first.y))
        for point in points.dropFirst() { path.addLine(to: CGPoint(x: point.x, y: point.y)) }
        return path
    }

    private static func drawGaps(_ scene: MapScene, color: Color, in context: inout GraphicsContext) {
        for route in scene.routes where route.kind == .gap {
            context.stroke(path(route.points), with: .color(color),
                           style: StrokeStyle(lineWidth: RPStroke.gap, lineCap: .round, lineJoin: .round,
                                              dash: [0.01, RPSize.gapDotSpacing]))
        }
    }

    /// The Night Highway map: the dark land, then light spilled on the ground, a soft halo, a tight
    /// halo, the amber core and a pale centre line (the reference's five strokes), then the marks
    /// and, last, the labels, so the glow never covers one.
    static func nightHighway(_ scene: MapScene, labels: Labels, in context: inout GraphicsContext) {
        var base = MapSceneRenderer(scene: scene, scheme: .dark, displayScale: ShareCardMetrics.exportScale,
                                    summitName: "", summitAltitude: "")
        base.only = [.landFill, .regionBorders, .countryBorders]
        base.draw(&context)
        drawGaps(scene, color: Night.textSecondary, in: &context)

        let recorded = scene.routes.filter { $0.kind == .recorded }
        let paths = recorded.map { path($0.points) }
        func halo(width: CGFloat, blur: CGFloat, opacity: Double) {
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: blur))
                layer.opacity = opacity
                for path in paths {
                    layer.stroke(path, with: .color(Night.route),
                                 style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                }
            }
        }
        if !paths.isEmpty {
            halo(width: 30, blur: 15, opacity: 0.16)
            halo(width: 13, blur: 7, opacity: 0.38)
            halo(width: 7, blur: 2.5, opacity: 0.7)
            for path in paths {
                context.stroke(path, with: .color(Night.route),
                               style: StrokeStyle(lineWidth: 3.3, lineCap: .round, lineJoin: .round))
                context.stroke(path, with: .color(Night.heat5.opacity(0.85)),
                               style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
            }
        }

        // Start and end: a fine dashed ring with a dot.
        let radius = ShareCardMetrics.ringRadius
        let areas = [scene.startArea, scene.endArea].compactMap { $0 }
        for area in areas {
            let centre = CGPoint(x: area.center.x, y: area.center.y)
            let ring = Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
            context.fill(ring, with: .color(Night.route.opacity(0.13)))
            context.stroke(ring, with: .color(Night.route),
                           style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [1.67, 2.33]))
            context.fill(Path(ellipseIn: CGRect(x: centre.x - 3, y: centre.y - 3, width: 6, height: 6)),
                         with: .color(Night.background))
            context.fill(Path(ellipseIn: CGRect(x: centre.x - 2, y: centre.y - 2, width: 4, height: 4)),
                         with: .color(Night.route))
        }

        // The highest point: a small solid triangle on the route.
        if let summit = scene.summit {
            let x = summit.position.x, y = summit.position.y, w = 8.67, h = 7.33
            var triangle = Path()
            triangle.move(to: CGPoint(x: x, y: y - h / 2))
            triangle.addLine(to: CGPoint(x: x + w / 2, y: y + h / 2))
            triangle.addLine(to: CGPoint(x: x - w / 2, y: y + h / 2))
            triangle.closeSubpath()
            context.fill(triangle, with: .color(Night.text))
        }

        // Labels. `taken` keeps the region codes off the other texts.
        var taken: [CGRect] = []
        let routePoints = recorded.flatMap(\.points)
        func areaLabel(_ area: MapScene.Area?, _ text: String?) {
            guard let area, let text, !text.isEmpty else { return }
            let resolved = context.resolve(
                Text(text.uppercased()).font(.rpText(size: 7.33, weight: .semibold)).tracking(0.83)
                    .foregroundColor(Night.text.opacity(0.85)))
            let size = resolved.measure(in: measure)
            let width = Double(size.width), cx = area.center.x, cy = area.center.y
            let ring = Double(radius), margin = Double(ShareCardMetrics.margin)
            // The label goes on the side of the ring the route does not leave from.
            let near = routePoints.filter {
                let distance = hypot($0.x - cx, $0.y - cy)
                return distance > 12 && distance < 70
            }
            let pool = near.isEmpty ? routePoints : near
            let routeY = pool.isEmpty ? cy : pool.map(\.y).reduce(0, +) / Double(pool.count)
            let baseline = routeY > cy ? cy - 16.7 : cy + 24
            // Aligned with the ring's outer edge, towards the middle of the card.
            let aligned = cx < scene.width / 2 ? cx - ring : cx + ring - width
            let x = Swift.min(Swift.max(aligned, margin), scene.width - margin - width)
            let top = baseline - Double(resolved.firstBaseline(in: size))
            context.draw(resolved, at: CGPoint(x: x, y: top), anchor: .topLeading)
            taken.append(CGRect(x: x, y: top, width: width, height: Double(size.height)))
        }
        areaLabel(scene.startArea, labels.start)
        if scene.endArea != scene.startArea { areaLabel(scene.endArea, labels.end) }

        if let summit = scene.summit, let box = summit.labelBounds {
            let right = box.x > summit.position.x
            func line(_ text: Text, baseline: Double) {
                let resolved = context.resolve(text)
                let size = resolved.measure(in: measure)
                let x = right ? box.x : box.x + box.width - Double(size.width)
                let top = baseline - Double(resolved.firstBaseline(in: size))
                context.draw(resolved, at: CGPoint(x: x, y: top), anchor: .topLeading)
            }
            // The name's baseline is level with the triangle's base when the box sits beside it.
            line(Text(labels.summitName).font(.rpText(size: 9.33, weight: .bold)).foregroundColor(Night.text),
                 baseline: box.y + 7.67)
            if let altitude = labels.summitAltitude {
                line(Text(altitude).font(.rpText(size: 8, weight: .medium)).foregroundColor(Night.textSecondary),
                     baseline: box.y + 18.33)
            }
            taken.append(CGRect(x: box.x, y: box.y, width: box.width, height: box.height))
        }

        for label in scene.regionLabels {
            let box = CGRect(x: label.bounds.x, y: label.bounds.y, width: label.bounds.width, height: label.bounds.height)
                .insetBy(dx: -6, dy: -6)
            guard !taken.contains(where: { $0.intersects(box) }) else { continue }
            let crossed = label.placeCode.map { labels.crossed.contains($0) } ?? false
            let text = Text(label.text.uppercased()).font(.rpText(size: 12.67, weight: .semibold)).tracking(3)
                .foregroundColor(Night.textSecondary.opacity(crossed ? 0.42 : 0.22))
            context.draw(context.resolve(text), at: CGPoint(x: label.anchor.x, y: label.anchor.y), anchor: .center)
        }
    }

    /// The Poster: nothing but the shape of the road.
    static func posterRoute(_ scene: MapScene, in context: inout GraphicsContext) {
        drawGaps(scene, color: Night.textSecondary, in: &context)
        for route in scene.routes where route.kind == .recorded {
            context.stroke(path(route.points), with: .color(Night.text),
                           style: StrokeStyle(lineWidth: 3.3, lineCap: .round, lineJoin: .round))
        }
        if scene.routes.allSatisfy({ $0.kind != .recorded }) {
            // A trip too short to draw: its area, so the card is not empty.
            for area in [scene.startArea, scene.endArea].compactMap({ $0 }) {
                let r = Swift.max(area.radius, Double(ShareCardMetrics.ringRadius))
                context.stroke(Path(ellipseIn: CGRect(x: area.center.x - r, y: area.center.y - r, width: r * 2, height: r * 2)),
                               with: .color(Night.text), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 4]))
            }
        }
    }

    private static func point(_ p: CGPoint, size: CGSize, topInset: CGFloat, lineWidth: CGFloat) -> CGPoint {
        CGPoint(x: p.x * size.width, y: topInset + (1 - p.y) * (size.height - topInset - lineWidth))
    }

    /// The elevation line over a fill that fades down to nothing.
    static func elevation(_ elevation: ShareCardElevation, size: CGSize, line: Color, fillTop: Double,
                          lineWidth: CGFloat, topInset: CGFloat, summitDot: Color?, in context: inout GraphicsContext) {
        for series in elevation.series where series.count > 1 {
            let points = series.map { point($0, size: size, topInset: topInset, lineWidth: lineWidth) }
            var linePath = Path()
            linePath.move(to: points[0])
            for p in points.dropFirst() { linePath.addLine(to: p) }
            var area = linePath
            area.addLine(to: CGPoint(x: points[points.count - 1].x, y: size.height))
            area.addLine(to: CGPoint(x: points[0].x, y: size.height))
            area.closeSubpath()
            context.fill(area, with: .linearGradient(
                Gradient(colors: [line.opacity(fillTop), line.opacity(0)]),
                startPoint: CGPoint(x: 0, y: topInset), endPoint: CGPoint(x: 0, y: size.height)))
            context.stroke(linePath, with: .color(line),
                           style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        if let summitDot {
            let p = point(elevation.summit, size: size, topInset: topInset, lineWidth: lineWidth)
            context.fill(Path(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)), with: .color(summitDot))
        }
    }

    /// The Poster names the highest point beside the peak of its profile.
    static func posterCaption(_ elevation: ShareCardElevation, size: CGSize, name: String, altitude: String?,
                              in context: inout GraphicsContext) {
        guard let altitude else { return }
        let peak = point(elevation.summit, size: size, topInset: ShareCardMetrics.posterCaption, lineWidth: 1.5)
        let font = Font.rpText(size: 8.5, weight: .bold)
        let lines = [context.resolve(Text(name.uppercased()).font(font).tracking(0.6).foregroundColor(Night.accentText)),
                     context.resolve(Text(altitude.uppercased()).font(font).tracking(0.6).foregroundColor(Night.text))]
        var top: CGFloat = Swift.max(0, peak.y - 14)
        let margin = ShareCardMetrics.margin
        for line in lines {
            let width: CGFloat = line.measure(in: measure).width
            let beside: CGFloat = peak.x > size.width / 2 ? peak.x - 9 - width : peak.x + 9
            let x: CGFloat = Swift.min(Swift.max(beside, margin), size.width - margin - width)
            context.draw(line, at: CGPoint(x: x, y: top), anchor: .topLeading)
            top += 11
        }
    }
}
