import SwiftUI
import RoadPrintCore

/// The card styles a driver can pick in the share sheet (plan §4.4, mockup 2).
enum ShareCardStyle: String, CaseIterable, Identifiable, Sendable {
    case nightHighway, roadAtlas
    /// A transparent overlay for the driver's photo (Design/cards/print), drawn by `PrintCardView`.
    case print
    /// The land in 3D (Design/cards/terrain, Pro), drawn by `TerrainCardView`.
    case terrain

    var id: String { rawValue }

    var name: String {
        switch self {
        case .nightHighway: String(localized: "Night Highway", comment: "Share card style name.")
        case .roadAtlas: String(localized: "Road Atlas", comment: "Share card style name.")
        case .print: String(localized: "Print", comment: "Share card style name: a transparent overlay for your own photo.")
        case .terrain: String(localized: "Terrain", comment: "Share card style name: the land around the trip in 3D.")
        }
    }

    /// Night Highway and Road Atlas are `ShareCard`s with a map scene and a video.
    var isMapCard: Bool { self == .nightHighway || self == .roadAtlas }
}

/// Where a style draws its map, and how the core lays that map out.
struct ShareCardMapSpec {
    let top: CGFloat
    let height: CGFloat
    let insets: ViewportInsets
    let labels: MapLabelRules
}

/// Sizes of the share cards in points. One point is three pixels of the 1080 × 1920 export.
/// The layout follows the Designer's review of build 15 (ROA-60, 2026-11-15): on a Story or a
/// TikTok the app's own bars cover the top 220 px and the bottom 320 px, so every text and the
/// mark sit between y 220 and y 1600 px (73.3 and 533.3 pt).
enum ShareCardMetrics {
    static let size = CGSize(width: 360, height: 640)
    /// 1080 × 1920 px.
    static let exportScale: CGFloat = 3
    static let margin: CGFloat = 24
    /// 1600 px: nothing but background below this line.
    static let storySafeBottom: CGFloat = 533.33
    /// The signature's centre, 1550 px.
    static let signatureCenter: CGFloat = 516.67
    static let signatureHeight: CGFloat = 22
    /// The app mark in the signature, 56 px.
    static let markSize: CGFloat = 18.67
    static let markRadius: CGFloat = 4.3
    static let kickerTop: CGFloat = 80
    static let fadeTop: CGFloat = 100
    static let fadeBottom: CGFloat = 80
    static let chipHeight: CGFloat = 24
    static let ringRadius: CGFloat = 10
    /// How much lower the text block sits when there is no elevation strip.
    static let noElevationShift: CGFloat = 52
    static let atlasNoElevationShift: CGFloat = 40

    /// Region codes: never in a fade, 95 px from the route, 170 px between codes.
    static func cardLabels(height: CGFloat, band: Bool) -> MapLabelRules {
        var rules = MapLabelRules()
        rules.summitWidth = 84
        rules.summitHeight = 20
        rules.summitGap = 8.7
        rules.summitRise = 4
        rules.summitOffsets = [0, 3, 6, 9, 12, 16, 20, 24, -20, -24]
        rules.summitRouteClearance = 3
        if band { rules.regionBand = Double(fadeTop + 13)...Double(height - fadeBottom + 20) }
        rules.regionRouteClearance = 31.7
        rules.regionSpacing = 39
        return rules
    }

    static func map(_ style: ShareCardStyle, hasElevation: Bool) -> ShareCardMapSpec {
        switch style {
        case .nightHighway, .print, .terrain:
            // 0–1000 px; the route in the box (130, 350)–(950, 680) px.
            let height: CGFloat = 333.33 + (hasElevation ? 0 : noElevationShift)
            return ShareCardMapSpec(top: 0, height: height,
                                    insets: ViewportInsets(top: 94.7, left: 21.3, bottom: 84.6, right: 21.3),
                                    labels: cardLabels(height: height, band: true))
        case .roadAtlas:
            // 400–1180 px.
            let height: CGFloat = 260 + (hasElevation ? 0 : atlasNoElevationShift)
            return ShareCardMapSpec(top: 133.33, height: height,
                                    insets: ViewportInsets(top: 30, left: 21, bottom: 30, right: 21),
                                    labels: cardLabels(height: height, band: false))
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
    /// The same distance as a number in the display unit, for counting up in the video.
    var distanceAmount: Double = 0
    /// "Utah → California · Nov 4".
    var subtitle: String
    var chips: [String]
    /// "Utah → California": the Road Atlas header.
    var title: String
    /// "Wednesday, November 4, 2026".
    var longDate: String
    /// The Road Atlas strip: distance, hours, places, summit.
    var stats: [Stat]
    /// Codes of the regions and countries the trip crosses: their map labels are brighter.
    var crossedCodes: Set<String>
    var startLabel: String?
    var endLabel: String?
    var summitAltitude: String?
    /// Drawn as its road sign.
    var mainRoad: MainRoad?
    /// "Donner Summit" when the highest point is a known pass (`NamedSummit`).
    var summitName: String?

    /// The big number while the card animates: counting up in whole units to the final value.
    func distanceText(progress: Double) -> String {
        guard progress < 1, distanceAmount > 0 else { return distanceValue }
        return (distanceAmount * max(progress, 0)).formatted(.number.precision(.fractionLength(0)))
    }

    var summitLabel: String { summitName ?? String(localized: "Highest point") }
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

/// Where a card is in its video. A picture is `.still`: everything drawn, nothing fading.
struct CardMotion: Equatable, Sendable {
    /// Seconds into the video; nil for the picture.
    var time: Double?
    var timing = CardVideo.Timing.standard

    static let still = CardMotion(time: nil)

    /// How much of the route is drawn.
    var progress: Double { time.map(timing.progress(at:)) ?? 1 }

    /// 0 → 1 over `CardVideo.fadeSeconds` once the route's tip passes `mark` (a share of the route).
    func appear(at mark: Double) -> Double {
        guard let time else { return 1 }
        return min(max((time - timing.time(atProgress: mark)) / CardVideo.fadeSeconds, 0), 1)
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

        var longDate = ""
        if let date = date(summary.day) {
            longDate = date.formatted(Date.FormatStyle(locale: locale, timeZone: utc).weekday(.wide).month(.wide).day().year())
        }

        return ShareCardContent(
            distanceValue: brag.value, distanceUnit: brag.unit,
            distanceAmount: unit.displayValue(meters: summary.distanceMeters),
            subtitle: subtitle(places: summary.places, day: summary.day, locale: locale), chips: chips,
            title: title(places: summary.places), longDate: longDate, stats: stats,
            crossedCodes: Set((summary.places.regions + summary.places.countries).map(\.code)),
            startLabel: startLabel, endLabel: endLabel, summitAltitude: altitude, mainRoad: summary.mainRoad,
            summitName: summary.summit.flatMap(NamedSummit.name(at:)))
    }
}

/// Puts card text at exact heights: by its first baseline, or by its top.
@MainActor
enum CardPlace {
    /// `content`'s first text baseline at `y`, its leading edge at `x`.
    static func baseline<Content: View>(_ y: CGFloat, x: CGFloat = ShareCardMetrics.margin,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        Color.clear
            .frame(width: ShareCardMetrics.size.width, height: ShareCardMetrics.size.height)
            .alignmentGuide(.firstTextBaseline) { _ in y }
            .overlay(alignment: Alignment(horizontal: .leading, vertical: .firstTextBaseline)) {
                content().padding(.leading, x)
            }
            .allowsHitTesting(false)
    }

    /// `content`'s top edge at `y`, its leading edge at `x`.
    static func top<Content: View>(_ y: CGFloat, x: CGFloat = ShareCardMetrics.margin,
                                   @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.leading, x)
            .padding(.top, y)
            .frame(width: ShareCardMetrics.size.width, height: ShareCardMetrics.size.height, alignment: .topLeading)
            .allowsHitTesting(false)
    }

    /// The signature, centred on the card at `ShareCardMetrics.signatureCenter`.
    static func signature(word: Color, caption: Color) -> some View {
        top(ShareCardMetrics.signatureCenter - ShareCardMetrics.signatureHeight / 2, x: 0) {
            ShareCardSignature(word: word, caption: caption)
                .frame(width: ShareCardMetrics.size.width)
        }
    }
}

/// A share card (plan §4.4, mockup 2, FEEL_STANDARD §9). Lay it out at `ShareCardMetrics.size`
/// and scale it; never resize its frame. Each style keeps its own palette whatever the phone's theme.
struct ShareCard: View {
    let style: ShareCardStyle
    let content: ShareCardContent
    let scene: MapScene?
    let elevation: ShareCardElevation?
    /// Where the card is in its video; the picture is `.still`.
    var motion: CardMotion = .still

    private typealias M = ShareCardMetrics
    private typealias Night = Color.RP.Night
    private typealias Day = Color.RP.Day

    var body: some View {
        Group {
            switch style {
            case .nightHighway: nightHighway
            case .roadAtlas: roadAtlas
            // Drawn by PrintCardView and TerrainCardView; never a map card.
            case .print, .terrain: Color.clear
            }
        }
        .frame(width: M.size.width, height: M.size.height, alignment: .topLeading)
        .clipped()
        .environment(\.colorScheme, style == .roadAtlas ? .light : .dark)
        .dynamicTypeSize(.large)
    }

    private func display(_ size: CGFloat) -> Font { .custom(RPFont.number, fixedSize: size) }

    private var labels: ShareCardArt.Labels {
        ShareCardArt.Labels(crossed: content.crossedCodes, start: content.startLabel, end: content.endLabel,
                            summitName: content.summitLabel, summitAltitude: content.summitAltitude)
    }

    /// The big number and its unit word. The unit stays where the final number puts it, so it
    /// doesn't slide while the number counts up.
    private func bigNumber(size: CGFloat, unitSize: CGFloat, tracking: CGFloat, color: Color, unitColor: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            ZStack(alignment: Alignment(horizontal: .leading, vertical: .firstTextBaseline)) {
                Text(content.distanceValue).hidden()
                Text(content.distanceText(progress: motion.progress))
            }
            .font(display(size))
            .tracking(tracking)
            .foregroundStyle(color)
            Text(content.distanceUnit)
                .font(display(unitSize))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(unitColor)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }

    // MARK: Night Highway

    private var nightHighway: some View {
        let spec = M.map(.nightHighway, hasElevation: elevation != nil)
        let shift = elevation == nil ? M.noElevationShift : 0
        let labels = self.labels, motion = self.motion
        return ZStack(alignment: .topLeading) {
            Night.background
            if let scene {
                Canvas { context, _ in
                    ShareCardArt.nightHighway(scene, labels: labels, motion: motion, in: &context)
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
            // The number at 1150 px, the places at 1222 px, the chips from 1262 px.
            CardPlace.baseline(383.33 + shift, x: M.margin - 3) {
                bigNumber(size: 100, unitSize: 26, tracking: -0.67, color: Night.text, unitColor: Night.accentText)
            }
            CardPlace.baseline(407.33 + shift) {
                Text(content.subtitle)
                    .font(.rpText(size: 14, weight: .semibold))
                    .foregroundStyle(Night.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: M.size.width - 2 * M.margin, alignment: .leading)
            }
            CardPlace.top(418 + shift) {
                HStack(spacing: 5.3) {
                    // The sign 88 px tall, the first chip 22 px to its right.
                    if let road = content.mainRoad {
                        RoadSign(road: road, height: 29.33, detailHeight: 88)
                            .padding(.trailing, 2)
                    }
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
                .frame(height: 29.33)
            }
            if let elevation {
                // The strip 1370–1490 px; its amber carries on, fading, to the bottom edge, and grows
                // with the strip in the video. 0.12 rather than the review's 0.20: at 0.20 it read as
                // a slab under the card.
                CardPlace.top(496.67) {
                    LinearGradient(colors: [Night.route.opacity(0.12), Night.route.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(width: (M.size.width - 2 * M.margin) * min(max(motion.progress, 0), 1),
                               height: M.size.height - 496.67)
                }
                CardPlace.top(456.67) {
                    strip(elevation, line: Night.route, fillTop: 0.45, bottomFill: 0.12, dot: Night.text)
                        .frame(width: M.size.width - 2 * M.margin, height: 40)
                }
            }
            CardPlace.signature(word: Night.accentText, caption: Night.textSecondary)
        }
    }

    // MARK: Road Atlas

    private var roadAtlas: some View {
        let spec = M.map(.roadAtlas, hasElevation: elevation != nil)
        let shift = elevation == nil ? M.atlasNoElevationShift : 0
        let labels = self.labels, motion = self.motion
        return ZStack(alignment: .topLeading) {
            Day.background
            // The header below the top 220 px: title at 300 px, date at 356 px, sign from 226 px.
            CardPlace.baseline(100) {
                Text(content.title)
                    .font(display(30))
                    .textCase(.uppercase)
                    .foregroundStyle(Day.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: M.size.width - 2 * M.margin - (content.mainRoad == nil ? 0 : 60), alignment: .leading)
            }
            CardPlace.baseline(118.67) {
                Text(content.longDate)
                    .font(.rpText(size: 11.5))
                    .foregroundStyle(Day.textSecondary)
                    .lineLimit(1)
            }
            if let road = content.mainRoad {
                CardPlace.top(75.33, x: 0) {
                    RoadSign(road: road, height: 40, detailHeight: 120)
                        .frame(width: M.size.width - M.margin, alignment: .trailing)
                }
            }
            if let scene {
                Canvas { context, _ in
                    ShareCardArt.roadAtlas(scene, labels: labels, motion: motion, in: &context)
                }
                .frame(width: M.size.width, height: spec.height)
                .clipped()
                .overlay(alignment: .top) { Rectangle().fill(Day.border).frame(height: 0.67) }
                .overlay(alignment: .bottom) { Rectangle().fill(Day.border).frame(height: 0.67) }
                .padding(.top, spec.top)
            }
            // The rule at 1212 px, the numbers at 1312 px, their labels at 1352 px.
            CardPlace.top(404 + shift) {
                Rectangle().fill(Day.text).frame(width: M.size.width - 2 * M.margin, height: 1)
            }
            CardPlace.baseline(437.33 + shift) {
                statRow { stat in
                    Text(stat.value).font(display(26)).foregroundStyle(Day.text)
                }
            }
            CardPlace.baseline(450.67 + shift) {
                statRow { stat in
                    Text(stat.label)
                        .font(.rpText(size: 7.5, weight: .semibold))
                        .tracking(1.5)
                        .textCase(.uppercase)
                        .foregroundStyle(Day.textSecondary)
                }
            }
            if let elevation {
                CardPlace.top(464) {
                    strip(elevation, line: Day.route, fillTop: 0.4, bottomFill: 0, dot: nil)
                        .frame(width: M.size.width - 2 * M.margin, height: 36.67)
                }
            }
            CardPlace.signature(word: Day.text, caption: Day.textSecondary)
        }
    }

    /// The Road Atlas stats in four equal columns, one line of each.
    private func statRow<Cell: View>(@ViewBuilder _ cell: @escaping (ShareCardContent.Stat) -> Cell) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            ForEach(content.stats, id: \.label) { stat in
                cell(stat)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: (M.size.width - 2 * M.margin) / CGFloat(max(content.stats.count, 1)), alignment: .leading)
            }
        }
    }

    // MARK: Shared parts

    private func strip(_ elevation: ShareCardElevation, line: Color, fillTop: Double, bottomFill: Double,
                       dot: Color?) -> some View {
        let progress = motion.progress
        return Canvas { context, size in
            ShareCardArt.elevation(elevation, size: size, line: line, fillTop: fillTop, fillBottom: bottomFill,
                                   lineWidth: 1.5, topInset: 4, summitDot: dot, progress: progress, in: &context)
        }
    }
}

/// The signature on every share card: the app's mark and its name.
struct ShareCardSignature: View {
    let word: Color
    let caption: Color

    private typealias M = ShareCardMetrics

    var body: some View {
        HStack(spacing: 7) {
            Image("BrandMark")
                .resizable()
                .interpolation(.high)
                .frame(width: M.markSize, height: M.markSize)
                .clipShape(RoundedRectangle(cornerRadius: M.markRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: M.markRadius, style: .continuous)
                    .strokeBorder(caption.opacity(0.35), lineWidth: 0.5))
            VStack(alignment: .leading, spacing: 1.5) {
                Text("Made with")
                    .font(.rpText(size: 6, weight: .semibold))
                    .tracking(1.5)
                    .textCase(.uppercase)
                    .foregroundStyle(caption)
                Text(verbatim: "ROADPRINT")
                    .font(.rpText(size: 10, weight: .bold))
                    .tracking(3)
                    .foregroundStyle(word)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: M.signatureHeight)
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

    /// The colours of one card's map marks and labels.
    struct Ink: Sendable {
        var text: Color
        var secondary: Color
        var route: Color
        var ground: Color
        /// Start and end names, as a share of `text`.
        var areaOpacity: Double
        /// Region codes: crossed, and the others.
        var crossedOpacity: Double
        var otherOpacity: Double

        static let night = Ink(text: Color.RP.Night.text, secondary: Color.RP.Night.textSecondary,
                               route: Color.RP.Night.route, ground: Color.RP.Night.background,
                               areaOpacity: 0.85, crossedOpacity: 0.42, otherOpacity: 0.22)
        static let paper = Ink(text: Color.RP.Day.text, secondary: Color.RP.Day.textSecondary,
                               route: Color.RP.Day.route, ground: Color.RP.Day.background,
                               areaOpacity: 0.75, crossedOpacity: 0.5, otherOpacity: 0.28)
    }

    private typealias Night = Color.RP.Night
    private typealias Day = Color.RP.Day
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

    private static func base(_ scene: MapScene, scheme: ColorScheme, in context: inout GraphicsContext) {
        var base = MapSceneRenderer(scene: scene, scheme: scheme, displayScale: ShareCardMetrics.exportScale,
                                    summitName: "", summitAltitude: "")
        base.only = [.landFill, .regionBorders, .countryBorders]
        base.draw(&context)
    }

    /// The Night Highway map: the dark land, then light spilled on the ground, a soft halo, a tight
    /// halo, the amber core and a pale centre line (the reference's five strokes), then the marks
    /// and, last, the labels, so the glow never covers one.
    static func nightHighway(_ scene: MapScene, labels: Labels, motion: CardMotion = .still,
                             in context: inout GraphicsContext) {
        base(scene, scheme: .dark, in: &context)
        let progress = motion.progress
        if progress >= 1 { drawGaps(scene, color: Night.textSecondary, in: &context) }

        let recorded = scene.routes.filter { $0.kind == .recorded }
        let drawn = trimmed(recorded, progress: progress)
        let paths = drawn.paths
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
        // While drawing: a headlight at the tip (core r 7 px white, halo r 40 px at 0.45, blur 16 px).
        if progress > 0, progress < 1, let tip = drawn.tip {
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 5.33))
                layer.fill(Path(ellipseIn: CGRect(x: tip.x - 13.33, y: tip.y - 13.33, width: 26.67, height: 26.67)),
                           with: .color(Night.heat5.opacity(0.45)))
            }
            context.fill(Path(ellipseIn: CGRect(x: tip.x - 2.33, y: tip.y - 2.33, width: 4.67, height: 4.67)),
                         with: .color(.white))
        }
        marks(scene, recorded: recorded, labels: labels, ink: .night, motion: motion, in: &context)
    }

    /// The Road Atlas map: paper land, the route printed in amber with a fine dark edge (1 px each
    /// side), then the same marks and labels as Night Highway in the paper colours.
    static func roadAtlas(_ scene: MapScene, labels: Labels, motion: CardMotion = .still,
                          in context: inout GraphicsContext) {
        base(scene, scheme: .light, in: &context)
        let progress = motion.progress
        if progress >= 1 { drawGaps(scene, color: Day.textSecondary, in: &context) }
        let recorded = scene.routes.filter { $0.kind == .recorded }
        let drawn = trimmed(recorded, progress: progress)
        for path in drawn.paths {
            context.stroke(path, with: .color(Day.routeEdge),
                           style: StrokeStyle(lineWidth: 3.33 + 0.67, lineCap: .round, lineJoin: .round))
        }
        for path in drawn.paths {
            context.stroke(path, with: .color(Day.route),
                           style: StrokeStyle(lineWidth: 3.33, lineCap: .round, lineJoin: .round))
        }
        if progress > 0, progress < 1, let tip = drawn.tip {
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 4))
                layer.fill(Path(ellipseIn: CGRect(x: tip.x - 9, y: tip.y - 9, width: 18, height: 18)),
                           with: .color(Day.route.opacity(0.45)))
            }
            context.fill(Path(ellipseIn: CGRect(x: tip.x - 2.33, y: tip.y - 2.33, width: 4.67, height: 4.67)),
                         with: .color(Day.routeEdge))
        }
        marks(scene, recorded: recorded, labels: labels, ink: .paper, motion: motion, in: &context)
    }

    /// Start and end rings, the highest point, the start and end names, the highest point's name
    /// and the region codes. In the video the highest point and the end fade in over a quarter of a
    /// second as the route reaches them, the triangle growing from 0.6 to full size.
    private static func marks(_ scene: MapScene, recorded: [MapScene.Route], labels: Labels, ink: Ink,
                              motion: CardMotion, in context: inout GraphicsContext) {
        let endAlpha = motion.appear(at: 1)
        let summitAlpha = scene.summit.map { motion.appear(at: fraction(of: $0.position, along: recorded)) } ?? 0

        // Start and end: a fine dashed ring with a dot.
        let radius = ShareCardMetrics.ringRadius
        let oneArea = scene.startArea == scene.endArea
        let areas: [(MapScene.Area, Double)] = [
            scene.startArea.map { ($0, 1.0) }, oneArea ? nil : scene.endArea.map { ($0, endAlpha) },
        ].compactMap { $0 }
        for (area, alpha) in areas where alpha > 0 {
            var context = context
            context.opacity = alpha
            let centre = CGPoint(x: area.center.x, y: area.center.y)
            let ring = Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
            context.fill(ring, with: .color(ink.route.opacity(0.13)))
            context.stroke(ring, with: .color(ink.route),
                           style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [1.67, 2.33]))
            context.fill(Path(ellipseIn: CGRect(x: centre.x - 3, y: centre.y - 3, width: 6, height: 6)),
                         with: .color(ink.ground))
            context.fill(Path(ellipseIn: CGRect(x: centre.x - 2, y: centre.y - 2, width: 4, height: 4)),
                         with: .color(ink.route))
        }

        // The highest point: a small solid triangle on the route, 26 × 22 px.
        if let summit = scene.summit, summitAlpha > 0 {
            let x = summit.position.x, y = summit.position.y
            let grow = 0.6 + 0.4 * summitAlpha, w = 8.67 * grow, h = 7.33 * grow
            var triangle = Path()
            triangle.move(to: CGPoint(x: x, y: y - h / 2))
            triangle.addLine(to: CGPoint(x: x + w / 2, y: y + h / 2))
            triangle.addLine(to: CGPoint(x: x - w / 2, y: y + h / 2))
            triangle.closeSubpath()
            context.fill(triangle, with: .color(ink.text.opacity(summitAlpha)))
        }

        // Labels. `taken` keeps the region codes off the other texts.
        var taken: [CGRect] = []
        let routePoints = recorded.flatMap(\.points)
        func areaLabel(_ area: MapScene.Area?, _ text: String?, alpha: Double = 1) {
            guard let area, let text, !text.isEmpty, alpha > 0 else { return }
            let resolved = context.resolve(
                Text(text.uppercased()).font(.rpText(size: 7.33, weight: .semibold)).tracking(0.83)
                    .foregroundColor(ink.text.opacity(ink.areaOpacity * alpha)))
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
        if !oneArea { areaLabel(scene.endArea, labels.end, alpha: endAlpha) }

        if let summit = scene.summit, let box = summit.labelBounds, summitAlpha > 0 {
            let right = box.x > summit.position.x
            func line(_ text: Text, baseline: Double) {
                let resolved = context.resolve(text)
                let size = resolved.measure(in: measure)
                let x = right ? box.x : box.x + box.width - Double(size.width)
                let top = baseline - Double(resolved.firstBaseline(in: size))
                context.draw(resolved, at: CGPoint(x: x, y: top), anchor: .topLeading)
            }
            // The name's baseline is level with the triangle's base when the box sits beside it.
            line(Text(labels.summitName).font(.rpText(size: 9.33, weight: .bold)).foregroundColor(ink.text.opacity(summitAlpha)),
                 baseline: box.y + 7.67)
            if let altitude = labels.summitAltitude {
                line(Text(altitude).font(.rpText(size: 8, weight: .medium)).foregroundColor(ink.secondary.opacity(summitAlpha)),
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
                .foregroundColor(ink.secondary.opacity(crossed ? ink.crossedOpacity : ink.otherOpacity))
            context.draw(context.resolve(text), at: CGPoint(x: label.anchor.x, y: label.anchor.y), anchor: .center)
        }
    }

    private static func point(_ p: CGPoint, size: CGSize, topInset: CGFloat, lineWidth: CGFloat) -> CGPoint {
        CGPoint(x: p.x * size.width, y: topInset + (1 - p.y) * (size.height - topInset - lineWidth))
    }

    /// The elevation line over a fill that fades from `fillTop` at the line to `fillBottom` at the
    /// strip's bottom edge.
    static func elevation(_ elevation: ShareCardElevation, size: CGSize, line: Color, fillTop: Double,
                          fillBottom: Double = 0, lineWidth: CGFloat, topInset: CGFloat, summitDot: Color?,
                          progress: Double = 1, in context: inout GraphicsContext) {
        guard progress > 0 else { return }
        let finished = progress >= 1
        var context = context
        if !finished {
            context.clip(to: Path(CGRect(x: 0, y: 0, width: size.width * progress, height: size.height)))
        }
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
                Gradient(colors: [line.opacity(fillTop), line.opacity(fillBottom)]),
                startPoint: CGPoint(x: 0, y: topInset), endPoint: CGPoint(x: 0, y: size.height)))
            context.stroke(linePath, with: .color(line),
                           style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        if let summitDot, finished || elevation.summit.x <= progress {
            let p = point(elevation.summit, size: size, topInset: topInset, lineWidth: lineWidth)
            context.fill(Path(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)), with: .color(summitDot))
        }
        // While drawing: a dot at the front, level with the route's headlight.
        if !finished, let front = elevation.series.lazy.compactMap({ value(in: $0, at: progress) }).first {
            let p = point(front, size: size, topInset: topInset, lineWidth: lineWidth)
            context.fill(Path(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)), with: .color(line))
        }
    }

    /// The point of `series` at share `x` of the distance, if the series covers it.
    private static func value(in series: [CGPoint], at x: Double) -> CGPoint? {
        guard let first = series.first, let last = series.last, x >= first.x, x <= last.x else { return nil }
        for (a, b) in zip(series, series.dropFirst()) where x >= a.x && x <= b.x {
            let t = b.x > a.x ? (x - a.x) / (b.x - a.x) : 0
            return CGPoint(x: x, y: a.y + (b.y - a.y) * t)
        }
        return last
    }

    /// The recorded lines cut at `progress` of their total length, in order, and the cut's point.
    static func trimmed(_ routes: [MapScene.Route], progress: Double) -> (paths: [Path], tip: CGPoint?) {
        let lengths = routes.map(length)
        let total = lengths.reduce(0, +)
        guard progress < 1, total > 0 else { return (routes.map { path($0.points) }, nil) }
        var left = total * max(progress, 0)
        var paths: [Path] = []
        for (route, routeLength) in zip(routes, lengths) {
            if left >= routeLength {
                paths.append(path(route.points))
                left -= routeLength
                continue
            }
            var points = [route.points[0]]
            for (a, b) in zip(route.points, route.points.dropFirst()) {
                let step = hypot(b.x - a.x, b.y - a.y)
                if left >= step {
                    points.append(b)
                    left -= step
                } else {
                    let t = step > 0 ? left / step : 0
                    points.append(PlanePoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                    break
                }
            }
            paths.append(path(points))
            return (paths, points.last.map { CGPoint(x: $0.x, y: $0.y) })
        }
        return (paths, nil)
    }

    /// How far along the recorded lines `point` is (its nearest vertex), as a share of their length.
    static func fraction(of point: PlanePoint, along routes: [MapScene.Route]) -> Double {
        let total = routes.map(length).reduce(0, +)
        guard total > 0 else { return 0 }
        var walked = 0.0, best = (distance: Double.infinity, at: 0.0)
        for route in routes {
            for (index, vertex) in route.points.enumerated() {
                if index > 0 {
                    let a = route.points[index - 1]
                    walked += hypot(vertex.x - a.x, vertex.y - a.y)
                }
                let d = hypot(vertex.x - point.x, vertex.y - point.y)
                if d < best.distance { best = (d, walked) }
            }
        }
        return best.at / total
    }

    private static func length(_ route: MapScene.Route) -> Double {
        zip(route.points, route.points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }
}
