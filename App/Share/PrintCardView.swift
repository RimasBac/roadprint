import SwiftUI
import RoadPrintCore

/// The Print share card (Design/cards/print/README.md, v3): a transparent overlay the driver puts on
/// their own photo. The core lays it out (`PrintCard.layout`); this view only draws the result, in the
/// README's order: the soft shadow (light ink) or halo (dark ink) of the art, the route glow, the
/// elevation fill, then the art. Lay it out at `ShareCardMetrics.size` and export at 3×.
struct PrintCardView: View {
    let layout: PrintCardLayout
    let road: MainRoad?
    /// The driver's photo, drawn full-bleed under the card; nil exports a transparent picture.
    var photo: UIImage?

    private typealias M = ShareCardMetrics

    var body: some View {
        ZStack {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: M.size.width, height: M.size.height)
                    .clipped()
            }
            canvas
        }
        .frame(width: M.size.width, height: M.size.height)
        .clipped()
        .environment(\.colorScheme, .dark)
        .dynamicTypeSize(.large)
    }

    private var canvas: some View {
        let layout = self.layout
        let scale = M.size.width / CardTokens.Print.Export.width
        return Canvas { context, _ in
            PrintCardArt.draw(layout, scale: scale, in: &context)
        } symbols: {
            if let road, let sign = layout.signRect {
                RoadSign(road: road, height: sign.height * scale, detailHeight: sign.height)
                    .tag(PrintCardArt.signSymbol)
            }
        }
        .frame(width: M.size.width, height: M.size.height)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("printCard")
    }
}

extension PrintCardLayout {
    /// The road sign's box, when the layout has one.
    var signRect: CardRect? {
        for shape in art { if case .sign(let rect, _) = shape { return rect } }
        return nil
    }
}

/// Canvas drawing for the Print card. Not a view: Canvas closures run off the main actor.
enum PrintCardArt {
    static let signSymbol = 0

    static func color(_ paint: PrintPaint, _ ink: PrintInk, opacity: Double = 1) -> Color {
        Color(cardHex: PrintCard.color(paint, ink: ink), opacity: opacity)
    }

    static func draw(_ layout: PrintCardLayout, scale: CGFloat, in context: inout GraphicsContext) {
        let ink = layout.ink
        // 1. The one soft shadow (light) or halo (dark) under the whole card: the art drawn as a shadow
        // only, a wide pass and a tight pass. GraphicsContext has no morphology filter, so the tight
        // pass's 5 px spread is approximated by drawing it twice (README "How the app draws it natively").
        let s = PrintCard.shadow(for: ink)
        let shadowColor = Color(cardHex: s.color)
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: shadowColor.opacity(s.opacity), radius: s.blur * scale * 2,
                                    x: 0, y: s.offsetY * scale, options: .shadowOnly))
            art(layout, scale: scale, in: &layer)
        }
        for _ in 0..<2 {
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: shadowColor.opacity(s.tightOpacity),
                                        radius: (s.tightBlur + s.tightSpread / 2) * scale * 2,
                                        x: 0, y: s.tightOffsetY * scale, options: .shadowOnly))
                art(layout, scale: scale, in: &layer)
            }
        }
        // 2. The route glow (light ink only).
        if !layout.glow.isEmpty {
            let glow = CardTokens.Print.Route.Glow.self
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: glow.blur * scale))
                for run in layout.glow {
                    layer.stroke(CardDraw.polyline(run, scale), with: .color(color(.route, ink, opacity: glow.opacity)),
                                 style: CardDraw.stroke(width: glow.width, dash: nil, scale))
                }
            }
        }
        // 3. The elevation fill, above the shadow so the shadow never greys it.
        if let fill = layout.elevationFill {
            let e = CardTokens.Print.Elevation.self
            for run in fill.runs where run.count > 2 {
                var path = CardDraw.polyline(run, scale)
                path.closeSubpath()
                context.fill(path, with: .linearGradient(
                    Gradient(colors: [color(.route, ink, opacity: e.fillTopOpacity), color(.route, ink, opacity: e.fillBottomOpacity)]),
                    startPoint: CGPoint(x: 0, y: fill.top * scale), endPoint: CGPoint(x: 0, y: fill.bottom * scale)))
            }
        }
        // 4. The art.
        art(layout, scale: scale, in: &context)
    }

    /// Every mark and text of the card, in the layout's order.
    static func art(_ layout: PrintCardLayout, scale: CGFloat, in context: inout GraphicsContext) {
        let ink = layout.ink
        for shape in layout.art {
            switch shape {
            case .text(let t):
                CardDraw.text(t.string, style: t.style, x: t.x, baseline: t.baseline, anchor: t.anchor,
                              color: color(t.paint, ink, opacity: t.opacity), scale: scale, in: &context)
            case .stroke(_, let runs, let width, let paint, let opacity, let dash, _):
                let style = CardDraw.stroke(width: width, dash: dash, scale)
                for run in runs where run.count > 1 {
                    context.stroke(CardDraw.polyline(run, scale), with: .color(color(paint, ink, opacity: opacity)), style: style)
                }
            case .fillCircle(_, let center, let radius, let paint, let opacity, _):
                context.fill(CardDraw.circle(center, radius: radius, scale), with: .color(color(paint, ink, opacity: opacity)))
            case .strokeCircle(_, let center, let radius, let width, let paint, let opacity, let dash, _):
                context.stroke(CardDraw.circle(center, radius: radius, scale), with: .color(color(paint, ink, opacity: opacity)),
                               style: CardDraw.stroke(width: width, dash: dash, scale))
            case .dot(_, let center, let radius, let fill, let stroke, let strokeWidth, let strokeOpacity, _):
                let path = CardDraw.circle(center, radius: radius, scale)
                context.fill(path, with: .color(color(fill, ink)))
                context.stroke(path, with: .color(color(stroke, ink, opacity: strokeOpacity)), lineWidth: strokeWidth * scale)
            case .arrow(let points, let width, let paint, _):
                context.stroke(CardDraw.polyline(points, scale), with: .color(color(paint, ink)),
                               style: CardDraw.stroke(width: width, dash: nil, scale))
            case .sign(let rect, _):
                if let sign = context.resolveSymbol(id: signSymbol) {
                    context.draw(sign, in: CGRect(x: rect.minX * scale, y: rect.minY * scale,
                                                  width: rect.width * scale, height: rect.height * scale))
                }
            }
        }
    }
}

/// Builds the Print card's input from a trip's share summary (AGENTS.md §7b.3): titles, date, stats.
enum PrintCardContent {
    private static var utc: TimeZone { TimeZone(identifier: "UTC") ?? .current }

    /// "Wednesday, November 4".
    static func date(_ day: ShareDay, locale: Locale = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        guard let date = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)) else { return "" }
        return date.formatted(Date.FormatStyle(locale: locale, timeZone: utc).weekday(.wide).month(.wide).day())
    }

    /// The title's two names: the first and last region (or country); one region → the two area names.
    static func title(places: TripPlaces, startLabel: String?, endLabel: String?) -> (String, String) {
        let refs = places.regions.count >= 2 ? places.regions
            : places.countries.count >= 2 ? places.countries
            : places.regions.isEmpty ? places.countries : places.regions
        if let first = refs.first?.name, let last = refs.last?.name, first != last { return (first, last) }
        let a = startLabel ?? refs.first?.name ?? "", b = endLabel ?? refs.last?.name ?? ""
        return (a, b)
    }

    @MainActor
    static func input(summary: TripShareSummary, unit: DistanceUnit, startLabel: String?, endLabel: String?,
                      careerMeters: Double?, locale: Locale = .current) -> PrintCardInput {
        let distance = ShareCardText.distance(meters: summary.distanceMeters, unit: unit, locale: locale)
        let (from, to) = title(places: summary.places, startLabel: startLabel, endLabel: endLabel)
        let altitude = summary.summitAltitudeMeters.map { TripMapView.altitudeText($0, unit: unit) }
        var stats: [(label: String, value: String)] = [
            (String(localized: "Moving time", comment: "Print card: stat label over the driving time."),
             TripFormatting.duration(seconds: summary.movingTimeSeconds)),
        ]
        if let count = ShareCardText.placeCount(summary.places) {
            stats.append((count.noun, count.count.formatted(.number.locale(locale))))
        }
        if let careerMeters {
            stats.append((unit == .miles ? String(localized: "Career miles", comment: "Print card: stat label over the career distance in miles.")
                                         : String(localized: "Career km", comment: "Print card: stat label over the career distance in kilometres."),
                          unit.displayValue(meters: careerMeters).formatted(.number.precision(.fractionLength(0)).locale(locale))))
        } else if let altitude, summary.route?.contains(where: { $0.points.contains { $0.altitude != nil } }) == true {
            stats.append((String(localized: "Highest point", comment: "Print card: stat label over the highest altitude."), altitude))
        }
        let sign = summary.mainRoad.map { road -> Double? in
            let height: CGFloat = 44
            let width = RoadSign.width(road, height: height, detailHeight: height * ShareCardMetrics.exportScale)
            return width > 0 ? Double(width / height) : nil
        } ?? nil
        return PrintCardInput(
            from: from, to: to, date: date(summary.day, locale: locale),
            wordmark: "RoadPrint",
            startLabel: startLabel ?? "", endLabel: endLabel ?? "",
            route: summary.route, hideRoute: summary.route?.isEmpty ?? true,
            placeCenters: [summary.start, summary.end].compactMap { $0.map { GeoPoint(latitude: $0.centerLatitude, longitude: $0.centerLongitude) } },
            distanceValue: distance.value, distanceUnit: distance.unit.uppercased(with: locale),
            stats: stats,
            elevationKicker: String(localized: "Elevation", comment: "Print card: kicker over the elevation strip."),
            summitLabel: String(localized: "Highest point · \(altitude ?? "")", comment: "Print card: label at the top of the elevation strip; the placeholder is the altitude, e.g. 7,102 ft."),
            signAspect: sign)
    }
}
