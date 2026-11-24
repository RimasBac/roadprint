import SwiftUI
import RoadPrintCore

/// Everything the Terrain card writes, from the share summary (AGENTS.md §7b.3).
struct TerrainCardContent: Sendable, Equatable {
    /// "Wednesday, November 4, 2026" (upper-cased by its style).
    var date: String
    /// One line "A → B", or two: "A", "→ B".
    var titleLines: [String]
    var number: String
    var unit: String
    var chips: [String]
    var road: MainRoad?
    var summitKicker: String
    var summitValue: String?
    var summitName: String?
}

/// A rendered Terrain card: the relief image and the geometry its overlays need.
struct TerrainPrepared: @unchecked Sendable {
    // CGImage is immutable; it is shared read-only between the render task and the view.
    let relief: CGImage
    let ribbon: [TerrainRibbonPoint]
    let places: [CardPoint]
    let placeNames: [String]
    let summit: TerrainSummitLabel?
    let content: TerrainCardContent
    let zoom: Int
}

enum TerrainCardPipeline {
    enum Failure: Error {
        case noRoute
        case offline
        case renderFailed
    }

    @MainActor
    static func content(summary: TripShareSummary, unit: DistanceUnit, startLabel: String?, endLabel: String?,
                        flat: Bool, locale: Locale = .current) -> TerrainCardContent {
        let T = CardTokens.Terrain.self
        let (from, to) = PrintCardContent.title(places: summary.places, startLabel: startLabel, endLabel: endLabel)
        let one = "\(from) → \(to)"
        let title = CardTextStyle(T.Typography.title)
        let width = CardTokens.Terrain.Export.width - 2 * T.SafeArea.side
        let lines = CoreTextMeasurer.shared.ink(CardText.uppercased(one), style: title).width <= width ? [one] : [from, "→ \(to)"]
        let distance = ShareCardText.distance(meters: summary.distanceMeters, unit: unit, locale: locale)
        var chips = [TripFormatting.duration(seconds: summary.movingTimeSeconds)]
        if let count = ShareCardText.placeCount(summary.places), count.count >= 2 {
            chips.append("\(count.count.formatted(.number.locale(locale))) \(count.noun)")
        }
        if flat { chips.append(String(localized: "Elevation unavailable", comment: "Terrain card: chip when the trip has no usable altitude.")) }
        var calendar = Calendar(identifier: .gregorian)
        let utc = TimeZone(identifier: "UTC") ?? .current
        calendar.timeZone = utc
        let day = calendar.date(from: DateComponents(year: summary.day.year, month: summary.day.month, day: summary.day.day, hour: 12))
        return TerrainCardContent(
            date: day.map { $0.formatted(Date.FormatStyle(locale: locale, timeZone: utc).weekday(.wide).month(.wide).day().year()) } ?? "",
            titleLines: lines, number: distance.value, unit: distance.unit, chips: chips, road: summary.mainRoad,
            summitKicker: String(localized: "Highest recorded point", comment: "Terrain card: kicker over the summit altitude."),
            summitValue: summary.summitAltitudeMeters.map { TripMapView.altitudeText($0, unit: unit) },
            summitName: summary.summit.flatMap(NamedSummit.name(at:)))
    }

    /// Plans the card, fetches its tiles, renders the relief and places the summit label.
    @MainActor
    static func prepare(summary: TripShareSummary, unit: DistanceUnit, startLabel: String?, endLabel: String?,
                        progress: @Sendable @escaping (Double) -> Void) async throws -> TerrainPrepared {
        let route = summary.route ?? []
        let hasAltitude = route.contains { $0.points.contains { $0.altitude != nil } }
        let request = TerrainRequest(mode: hasAltitude ? .route : .flat, route: route, places: [])
        guard let plan = TerrainCard.plan(request) else { throw Failure.noRoute }
        let content = content(summary: summary, unit: unit, startLabel: startLabel, endLabel: endLabel, flat: !hasAltitude)
        let tiles: [TerrainTileID: TerrainTile]
        do {
            tiles = try await TerrainTileStore.shared.tiles(plan.tiles, progress: progress)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Failure.offline
        }
        let render = await Task.detached(priority: .userInitiated) { () -> TerrainRender? in
            guard let land = TerrainPNG.landCover() else { return nil }
            return TerrainCard.render(request, plan: plan, tiles: tiles, landCover: land)
        }.value
        try Task.checkCancellation()
        guard let render, let relief = TerrainPNG.image(render) else { throw Failure.renderFailed }
        var summit: TerrainSummitLabel?
        if request.mode == .route, let value = content.summitValue {
            summit = TerrainCard.summitLabel(render: render, kicker: CardText.uppercased(content.summitKicker), value: value,
                                             name: content.summitName, measurer: CoreTextMeasurer.shared)
        }
        return TerrainPrepared(relief: relief, ribbon: render.ribbon, places: render.places, placeNames: [],
                               summit: summit, content: content, zoom: render.zoom)
    }
}

/// The Terrain share card, style 5 (Design/cards/terrain/README.md): the core's relief, then the
/// scrims, the lifted ribbon with its ground shadow, the summit label and the type, all with one soft
/// text shadow. Lay it out at `ShareCardMetrics.size` and export at 3×.
struct TerrainCardView: View {
    let card: TerrainPrepared

    private typealias M = ShareCardMetrics

    var body: some View {
        let card = self.card
        let scale = M.size.width / CardTokens.Terrain.Export.width
        Canvas { context, _ in
            TerrainCardArt.draw(card, scale: scale, in: &context)
        } symbols: {
            if let road = card.content.road {
                let size = CardTokens.Terrain.Layout.roadSignSize
                RoadSign(road: road, height: size * scale, detailHeight: size).tag(TerrainCardArt.signSymbol)
            }
        }
        .frame(width: M.size.width, height: M.size.height)
        .environment(\.colorScheme, .dark)
        .dynamicTypeSize(.large)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("terrainCard")
    }
}

/// Canvas drawing for the Terrain card (port of Tools/design/terrain-previews.mjs).
enum TerrainCardArt {
    static let signSymbol = 0
    private typealias T = CardTokens.Terrain

    static func draw(_ card: TerrainPrepared, scale: CGFloat, in context: inout GraphicsContext) {
        let W = T.Export.width, H = T.Export.height
        context.draw(Image(decorative: card.relief, scale: 1), in: CGRect(x: 0, y: 0, width: W * scale, height: H * scale))
        scrims(scale: scale, in: &context)
        if !card.ribbon.isEmpty { ribbon(card.ribbon, scale: scale, in: &context) }
        shaded(scale: scale, in: &context) { layer in
            places(card, scale: scale, in: &layer)
            if let summit = card.summit { self.summit(summit, card: card, scale: scale, in: &layer) }
            type(card.content, scale: scale, in: &layer)
        }
    }

    /// One soft ink shadow under the type and labels (`terrain.textShadow`), drawn with the content.
    private static func shaded(scale: CGFloat, in context: inout GraphicsContext, _ body: (inout GraphicsContext) -> Void) {
        let s = T.TextShadow.self
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: Color(cardHex: s.color, opacity: s.opacity),
                                    radius: (s.blur + s.spread) * scale * 2, x: 0, y: 0))
            body(&layer)
        }
    }

    private static func scrims(scale: CGFloat, in context: inout GraphicsContext) {
        let bg = CardTokens.Color.background, sc = T.Scrim.self
        let top = CGRect(x: 0, y: 0, width: T.Export.width * scale, height: sc.Top.to * scale)
        context.fill(Path(top), with: .linearGradient(Gradient(colors: [Color(cardHex: bg, opacity: sc.Top.opacity), Color(cardHex: bg, opacity: 0)]),
                                                      startPoint: CGPoint(x: 0, y: top.minY), endPoint: CGPoint(x: 0, y: top.maxY)))
        let bottom = CGRect(x: 0, y: sc.Bottom.from * scale, width: T.Export.width * scale, height: (T.Export.height - sc.Bottom.from) * scale)
        context.fill(Path(bottom), with: .linearGradient(Gradient(colors: [Color(cardHex: bg, opacity: 0), Color(cardHex: bg, opacity: sc.Bottom.opacity)]),
                                                         startPoint: CGPoint(x: 0, y: bottom.minY), endPoint: CGPoint(x: 0, y: bottom.maxY)))
    }

    /// The ribbon's runs from the core's points (`TerrainRibbonPoint`): a point is on the ribbon unless it
    /// is a gap with no altitude. Two consecutive on-ribbon points are joined by a solid line (or the
    /// x-ray dash when the second is hidden), unless the second starts a gap or points were skipped
    /// between them: then a straight dotted link joins them.
    static func runs(_ points: [TerrainRibbonPoint]) -> (visible: [[CardPoint]], hidden: [[CardPoint]], gaps: [[CardPoint]]) {
        var visible: [[CardPoint]] = [], hidden: [[CardPoint]] = [], gaps: [[CardPoint]] = []
        var current: [CardPoint] = [], currentHidden = false
        func flush() {
            if current.count > 1 { if currentHidden { hidden.append(current) } else { visible.append(current) } }
            current = []
        }
        var previous: (index: Int, point: TerrainRibbonPoint)?
        for (index, point) in points.enumerated() where !(point.gap && point.elevation == nil) {
            defer { previous = (index, point) }
            guard let prev = previous else { continue }
            let (pi, a) = prev
            if pi == index - 1, !point.gap {
                if current.isEmpty || currentHidden != point.hidden {
                    flush()
                    current = [a.position]
                    currentHidden = point.hidden
                }
                current.append(point.position)
            } else {
                flush()
                gaps.append([a.position, point.position])
            }
        }
        flush()
        return (visible, hidden, gaps)
    }

    private static func ribbon(_ points: [TerrainRibbonPoint], scale: CGFloat, in context: inout GraphicsContext) {
        let R = T.Ribbon.self, (visible, hidden, gaps) = runs(points)
        let color = Color(cardHex: R.color)
        func strokes(_ runs: [[CardPoint]], _ shading: GraphicsContext.Shading, _ style: StrokeStyle, in ctx: inout GraphicsContext) {
            for run in runs { ctx.stroke(CardDraw.polyline(run, scale), with: shading, style: style) }
        }
        strokes(hidden, .color(Color(cardHex: R.Occluded.color, opacity: R.Occluded.opacity)),
                StrokeStyle(lineWidth: R.Occluded.width * scale, lineCap: .butt, lineJoin: .round,
                            dash: R.Occluded.dash.dashArray.map { $0 * scale }), in: &context)
        strokes(gaps, .color(Color(cardHex: R.Gap.color, opacity: R.Gap.opacity)),
                StrokeStyle(lineWidth: R.Gap.width * scale, lineCap: .round, lineJoin: .round,
                            dash: R.Gap.dash.dashArray.map { max($0, 0.01) * scale }), in: &context)
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: R.Shadow.blur * scale))
            strokes(visible, .color(Color(cardHex: R.Shadow.color, opacity: R.Shadow.opacity)),
                    CardDraw.stroke(width: R.Shadow.width, dash: nil, scale), in: &layer)
        }
        var lifted = context
        lifted.translateBy(x: 0, y: -R.lift * scale)
        for glow in R.glow {
            lifted.drawLayer { layer in
                layer.addFilter(.blur(radius: glow.radius * scale))
                strokes(visible, .color(Color(cardHex: glow.color, opacity: glow.opacity)), CardDraw.stroke(width: glow.width, dash: nil, scale), in: &layer)
            }
        }
        strokes(visible, .color(Color(cardHex: R.Casing.color, opacity: R.Casing.opacity)), CardDraw.stroke(width: R.Casing.width, dash: nil, scale), in: &lifted)
        strokes(visible, .color(color), CardDraw.stroke(width: R.width, dash: nil, scale), in: &lifted)
        // The approximate start and end circles.
        let valid = points.filter { !($0.gap && $0.elevation == nil) }
        let E = R.Endpoint.self
        for p in [valid.first, valid.last].compactMap({ $0 }) {
            let circle = CardDraw.circle(p.position, radius: E.radius, scale)
            lifted.fill(circle, with: .color(Color(cardHex: E.color, opacity: E.fillOpacity)))
            lifted.stroke(circle, with: .color(Color(cardHex: E.color)), lineWidth: E.stroke * scale)
        }
    }

    private static func marker(_ at: CardPoint, scale: CGFloat, in context: inout GraphicsContext) {
        let S = T.Summit.Marker.self
        context.fill(CardDraw.circle(at, radius: S.radius + S.ring, scale), with: .color(Color(cardHex: CardTokens.Color.background)))
        context.fill(CardDraw.circle(at, radius: S.radius, scale), with: .color(Color(cardHex: S.fill)))
    }

    private static func summit(_ label: TerrainSummitLabel, card: TerrainPrepared, scale: CGFloat, in context: inout GraphicsContext) {
        let S = T.Summit.self
        var leader = Path()
        leader.move(to: CardDraw.point(label.marker, scale))
        leader.addLine(to: CardDraw.point(label.leaderEnd, scale))
        context.stroke(leader, with: .color(Color(cardHex: S.Leader.color, opacity: S.Leader.opacity)), lineWidth: S.Leader.width * scale)
        marker(label.marker, scale: scale, in: &context)
        let content = card.content
        let lines: [(CardTypeToken, String, Double?)] = [
            (T.Typography.summitKicker, CardText.uppercased(content.summitKicker), nil),
            (T.Typography.summitValue, content.summitValue ?? "", nil),
        ] + (content.summitName.map { [(T.Typography.summitName, $0, nil)] } ?? [])
        for (index, (token, string, size)) in lines.enumerated() where index < label.baselines.count {
            CardDraw.text(string, style: CardTextStyle(token, size: size), x: label.x, baseline: label.baselines[index], anchor: .start,
                          color: Color(cardHex: token.color), scale: scale, in: &context)
        }
    }

    private static func places(_ card: TerrainPrepared, scale: CGFloat, in context: inout GraphicsContext) {
        for (index, p) in card.places.enumerated() {
            marker(p, scale: scale, in: &context)
            guard index < card.placeNames.count else { continue }
            let token = T.Typography.summitName
            CardDraw.text(card.placeNames[index], style: CardTextStyle(token), x: p.x, baseline: p.y - T.Summit.Marker.radius - 16,
                          anchor: .middle, color: Color(cardHex: token.color), scale: scale, in: &context)
        }
    }

    private static func type(_ content: TerrainCardContent, scale: CGFloat, in context: inout GraphicsContext) {
        let L = T.Layout.self, Y = T.Typography.self, side = T.SafeArea.side
        func style(_ token: CardTypeToken) -> (CardTextStyle, Color) { (CardTextStyle(token), Color(cardHex: token.color)) }
        func cased(_ token: CardTypeToken, _ s: String) -> String { token.uppercase ? CardText.uppercased(s) : s }
        let (kicker, kickerColor) = style(Y.kicker)
        CardDraw.text(cased(Y.kicker, content.date), style: kicker, x: side, baseline: L.kickerBaseline, anchor: .start,
                      color: kickerColor, scale: scale, in: &context)
        let (title, titleColor) = style(Y.title)
        for (i, line) in content.titleLines.prefix(Int(L.titleMaxLines)).enumerated() {
            CardDraw.text(cased(Y.title, line), style: title, x: side, baseline: L.titleBaseline + Double(i) * L.titleLineHeight,
                          anchor: .start, color: titleColor, scale: scale, in: &context)
        }
        // The number, then the unit at the number's advance + unitGap.
        let (number, numberColor) = style(Y.number)
        let resolved = context.resolve(Text(verbatim: content.number).font(CardDraw.font(number, scale)).tracking(number.tracking * scale))
        let advance = Double(resolved.measure(in: CGSize(width: 4_000, height: 1_000)).width / scale)
        CardDraw.text(content.number, style: number, x: side, baseline: L.numberBaseline, anchor: .start, color: numberColor, scale: scale, in: &context)
        let (unit, unitColor) = style(Y.unit)
        CardDraw.text(cased(Y.unit, content.unit), style: unit, x: side + advance + L.unitGap, baseline: L.numberBaseline, anchor: .start,
                      color: unitColor, scale: scale, in: &context)
        // Road sign, then chips.
        var x = side
        let y = L.chipTop, h = L.chipHeight
        if content.road != nil, let sign = context.resolveSymbol(id: signSymbol) {
            let width = sign.size.width / scale
            context.draw(sign, in: CGRect(x: x * scale, y: y * scale, width: width * scale, height: L.roadSignSize * scale))
            x += width + L.chipGap
        }
        let (chip, chipColor) = style(Y.chip)
        for text in content.chips {
            let resolvedChip = context.resolve(Text(verbatim: text).font(CardDraw.font(chip, scale)).tracking(chip.tracking * scale))
            let w = Double(resolvedChip.measure(in: CGSize(width: 4_000, height: 1_000)).width / scale) + 2 * L.chipPaddingX
            let rect = CGRect(x: x * scale, y: y * scale, width: w * scale, height: h * scale)
            let shape = Path(roundedRect: rect, cornerRadius: L.chipRadius * scale)
            context.fill(shape, with: .color(Color(cardHex: T.Chip.fill)))
            context.stroke(shape, with: .color(Color(cardHex: T.Chip.stroke)), lineWidth: T.Chip.strokeWidth * scale)
            CardDraw.text(text, style: chip, x: x + L.chipPaddingX, baseline: y + h / 2 + chip.size * 0.36, anchor: .start,
                          color: chipColor, scale: scale, in: &context)
            x += w + L.chipGap
        }
    }
}
