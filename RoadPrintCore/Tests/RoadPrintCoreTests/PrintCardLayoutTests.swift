import Foundation
import Testing
@testable import RoadPrintCore

// Print card layout (ROA-124): the port of Tools/design/print-card.mjs build() and check(), measured
// with a deterministic fake (the app measures with CoreText).

/// Fixed advances: Barlow 0.52 × size, Inter 0.58 × size per character, plus tracking; caps 0.72 × size
/// above the baseline, descenders 0.2 × size below.
private struct FakeMeasurer: CardTextMeasuring {
    func ink(_ text: String, style: CardTextStyle) -> CardInkBox {
        let n = Double(text.count)
        guard n > 0 else { return .empty }
        let adv = (style.family.hasPrefix("Barlow") ? 0.52 : 0.58) * style.size
        let descender = text.contains { "gjpqy,".contains($0) }
        return CardInkBox(x: 0.03 * style.size, width: n * (adv + style.tracking) - style.tracking,
                          top: -0.72 * style.size, bottom: descender ? 0.2 * style.size : 0)
    }
}

private let measurer = FakeMeasurer()
private let places = [GeoPoint(latitude: 40.761, longitude: -111.891), GeoPoint(latitude: 38.582, longitude: -121.494)]

/// The I-80 fixture with a synthetic altitude profile: 1,300 m base and a 2,165 m peak at 35 %.
private func i80Points(altitude: Bool = true) throws -> [RoutePoint] {
    let pairs = try JSONDecoder().decode([[Double]].self, from: Fixtures.data("i80-slc-sac-route", ext: "json"))
    let n = Double(pairs.count - 1)
    return pairs.enumerated().map { i, p in
        let u = Double(i) / n
        return RoutePoint(latitude: p[0], longitude: p[1], altitude: altitude ? 1300 + 865 * exp(-pow((u - 0.35) / 0.08, 2)) : nil)
    }
}

/// A north–south pass (Innsbruck to Bolzano shape): 0.77° of latitude, a few hundredths of longitude.
private func northSouth() -> [RoutePoint] {
    (0...120).map { i in
        let u = Double(i) / 120
        return RoutePoint(latitude: 47.268 - 0.77 * u, longitude: 11.393 + 0.04 * sin(u * 9), altitude: 600 + 800 * sin(u * .pi))
    }
}

private func input(_ route: [RouteSegment]?, from: String = "Utah", to: String = "California",
                   ends: (String, String) = ("Salt Lake City area", "Sacramento area"), hide: Bool = false,
                   stats: [(label: String, value: String)]? = nil) -> PrintCardInput {
    PrintCardInput(from: from, to: to, date: "Wednesday, November 4", wordmark: "RoadPrint",
                   startLabel: ends.0, endLabel: ends.1, route: route, hideRoute: hide, placeCenters: places,
                   distanceValue: "649", distanceUnit: "MILES",
                   stats: stats ?? [("Moving time", "10h 52m"), ("States", "3"), ("Career miles", "1,284,961")],
                   elevationKicker: "ELEVATION", summitLabel: "HIGHEST POINT · 7,102 FT", signAspect: 1.0)
}

private func i80(_ altitude: Bool = true) throws -> PrintCardInput { input([RouteSegment(points: try i80Points(altitude: altitude))]) }

/// I-80 with no points between 45 % and 55 %: two segments.
private func i80Gap() throws -> PrintCardInput {
    let p = try i80Points(), n = p.count
    return input([RouteSegment(points: Array(p[..<(n * 45 / 100)])), RouteSegment(points: Array(p[(n * 55 / 100)...]))])
}

private func cases() throws -> [(String, PrintCardInput)] {
    [("i80", try i80()), ("north-south", input([RouteSegment(points: northSouth())], from: "Tyrol", to: "South Tyrol",
                                                 ends: ("Innsbruck area", "Bolzano area"))),
     ("recording-gap", try i80Gap()), ("no-altitude", try i80(false)),
     ("long-names", input([RouteSegment(points: try i80Points())], from: "North Salt Lake", to: "West Sacramento",
                          ends: ("North Salt Lake area", "West Sacramento area"))),
     ("longer-names", input([RouteSegment(points: northSouth())], from: "Bezirk Innsbruck-Land", to: "Autonome Provinz Bozen – Südtirol",
                            ends: ("Innsbruck-Land area", "Bozen – Südtirol area"))),
     ("hide-route", input([RouteSegment(points: try i80Points())], hide: true)),
     ("no-route", input(nil))]
}

private func layout(_ i: PrintCardInput, _ ink: PrintInk = .light, _ mode: PrintLayoutMode = .full,
                    _ arrangement: PrintArrangement = .standard) -> PrintCardLayout {
    PrintCard.layout(i, ink: ink, mode: mode, arrangement: arrangement, measurer: measurer)
}

private func texts(_ l: PrintCardLayout) -> [String: PrintText] {
    var out: [String: PrintText] = [:]
    for case .text(let t) in l.art { out[t.id] = t }
    return out
}

private func stroke(_ l: PrintCardLayout, _ id: String) -> (runs: [[CardPoint]], width: Double, paint: PrintPaint, opacity: Double, dash: [Double]?)? {
    for case let .stroke(sid, runs, width, paint, opacity, dash, _) in l.art where sid == id { return (runs, width, paint, opacity, dash) }
    return nil
}

private func ids(_ l: PrintCardLayout) -> Set<String> {
    Set(l.art.compactMap { s -> String? in
        switch s {
        case .text(let t): t.id
        case .stroke(let id, _, _, _, _, _, _), .fillCircle(let id, _, _, _, _, _), .strokeCircle(let id, _, _, _, _, _, _, _),
             .dot(let id, _, _, _, _, _, _, _): id
        case .arrow: "title-arrow"
        case .sign: "road-sign"
        }
    })
}

private func inkTop(_ t: PrintText) -> Double { t.baseline + measurer.ink(t.string, style: t.style).top }

// MARK: - variants and checks

@Test(arguments: PrintInk.allCases, PrintLayoutMode.allCases)
func printCardMainCasesHaveNoIssues(ink: PrintInk, mode: PrintLayoutMode) throws {
    for (name, i) in try cases() {
        let l = layout(i, ink, mode)
        #expect(l.issues.isEmpty, "\(ink) \(mode) \(name): \(l.issues)")
        #expect(l.ink == ink && l.mode == mode)
        #expect(!l.art.isEmpty)
    }
}

@Test func printCardStickerKeepsEverythingBelow690() throws {
    for ink in PrintInk.allCases {
        for (name, i) in try cases() {
            for arrangement in [PrintArrangement.standard, PrintArrangement(hidden: [.route])] {
                let l = layout(i, ink, .sticker, arrangement)
                #expect(l.blocks[.elevation] == nil, "\(name)")
                for (block, r) in l.blocks { #expect(r.lowerBound >= CardTokens.Print.Sticker.Layout.signTop, "\(name) \(block) \(r)") }
                #expect(l.glow.flatMap { $0 }.allSatisfy { $0.y >= 690 }, "\(name)")
                #expect(l.elevationFill == nil)
            }
        }
    }
}

@Test func printCardStickerHasNoStripButKeepsTheHighestPointDot() throws {
    let l = layout(try i80(), .light, .sticker)
    let all = ids(l)
    #expect(all.contains("highest-point"))
    #expect(!all.contains("elevation") && !all.contains("elevation-kicker") && !all.contains("highest-label"))
    // the wordmark and sign row belongs to the route block
    #expect(texts(l)["wordmark"]?.block == .route)
    #expect(texts(l)["wordmark"]?.baseline == CardTokens.Print.Sticker.Layout.wordmarkBaseline)
}

@Test func printCardFullLayoutHasTheStripAndItsLabel() throws {
    let l = layout(try i80())
    let t = texts(l)
    #expect(t["elevation-kicker"]?.block == .elevation)
    #expect(t["highest-label"]?.string == "HIGHEST POINT · 7,102 FT")
    #expect(stroke(l, "elevation") != nil && stroke(l, "elevation-casing") != nil)
    let fill = try #require(l.elevationFill)
    #expect(fill.top == CardTokens.Print.Layout.elevationTop && fill.bottom == CardTokens.Print.Layout.elevationBaseline)
    // the route ends to the left (west), so the strip is mirrored: it starts at the right edge
    let line = try #require(stroke(l, "elevation")?.runs.first)
    #expect(abs(line[0].x - (1080 - 72)) < 0.01 && abs(line[line.count - 1].x - 72) < 0.01)
    // the strip's highest point sits at the top of the strip
    let dotY: Double? = l.art.lazy.compactMap { s -> Double? in
        if case let .dot("elevation-highest", c, _, _, _, _, _, _) = s { return c.y }
        return nil
    }.first
    #expect(dotY.map { abs($0 - CardTokens.Print.Layout.elevationTop) < 0.01 } == true)
    // text is upper-cased where the tokens say so; the distance is not
    #expect(t["wordmark"]?.string == "ROADPRINT" && t["stat-1-label"]?.string == "MOVING TIME")
    #expect(t["distance-unit"]?.string == "MILES" && t["distance"]?.string == "649")
    #expect(t["start-label"]?.string == "SALT LAKE CITY AREA" && t["start-label"]?.opacity == 0.9)
}

@Test func printCardTitleAndNumberStartOnTheSafeEdge() throws {
    let l = layout(try i80())
    let t = texts(l)
    for id in ["title", "distance"] {
        let x = try #require(t[id]); #expect(abs(x.x + measurer.ink(x.string, style: x.style).x - 72) < 1e-9, "\(id)")
    }
}

// MARK: - dark ink

@Test func printCardDarkInkHasNoGlowAndUsesTheDarkPaints() throws {
    let light = layout(try i80(), .light), dark = layout(try i80(), .dark)
    #expect(!light.glow.isEmpty)
    #expect(dark.glow.isEmpty)
    #expect(stroke(light, "route-casing")?.opacity == CardTokens.Print.Route.Casing.opacity)
    #expect(stroke(dark, "route-casing")?.opacity == CardTokens.Print.InkDark.Route.casingOpacity)
    #expect(PrintCard.color(.text, ink: .dark) == "#16181d")
    #expect(PrintCard.color(.muted, ink: .dark) == CardTokens.Print.InkDark.Color.muted)
    #expect(PrintCard.color(.route, ink: .dark) == "#e8830a" && PrintCard.color(.casing, ink: .dark) == "#9c4e00")
    #expect(PrintCard.color(.accent, ink: .dark) == "#9c4e00" && PrintCard.color(.gap, ink: .dark) == "#5d6470")
    #expect(PrintCard.color(.ink, ink: .dark) == "#ffffff")
    #expect(PrintCard.color(.text, ink: .light) == "#f0efec" && PrintCard.color(.muted, ink: .light) == "#e4e5e8")
    #expect(PrintCard.color(.accent, ink: .light) == "#ffb547" && PrintCard.color(.route, ink: .light) == "#ffb547")
    #expect(PrintCard.color(.casing, ink: .light) == "#0b0c10" && PrintCard.color(.ink, ink: .light) == "#0b0c10")
    #expect(PrintCard.color(.gap, ink: .light) == "#a6aab4")
    let ls = PrintCard.shadow(for: .light), ds = PrintCard.shadow(for: .dark)
    #expect(ls.color == "#0b0c10" && ls.opacity == 0.62 && ls.offsetY == 3 && ls.tightSpread == 5)
    #expect(ds.color == "#ffffff" && ds.opacity == 0.5 && ds.offsetY == 0 && ds.tightOffsetY == 0 && ds.tightOpacity == 0.85)
    // paint roles: the wordmark, unit and arrow are accent; the date is muted
    let t = texts(dark)
    #expect(t["wordmark"]?.paint == .accent && t["distance-unit"]?.paint == .accent && t["date"]?.paint == .muted)
    #expect(dark.art.contains { if case .arrow(_, _, .accent, .header) = $0 { true } else { false } })
}

// MARK: - route box

/// The full layout's wide box: 118–962 × (date baseline + 60, at least 480) to 830 (1105 with no strip).
private func wideBox(_ l: PrintCardLayout) throws -> CardRect {
    let Lk = CardTokens.Print.Layout.self
    let top = max(Lk.routeBoxTop, try #require(texts(l)["date"]).baseline + Lk.routeTopGap)
    return CardRect(minX: Lk.routeBoxLeft, minY: top, maxX: Lk.routeBoxRight, maxY: l.elevationFill == nil ? Lk.routeBottomNoElevation : Lk.routeBoxBottom)
}

@Test func printCardNorthSouthRouteFillsTheBandHeightCentred() throws {
    let l = layout(input([RouteSegment(points: northSouth())], from: "Tyrol", to: "South Tyrol", ends: ("Innsbruck area", "Bolzano area")))
    let box = try wideBox(l)
    let pts = try #require(stroke(l, "route")?.runs.first)
    let minY = pts.map(\.y).min()!, maxY = pts.map(\.y).max()!, minX = pts.map(\.x).min()!, maxX = pts.map(\.x).max()!
    // height-limited: spans the band. The tall box (520 wide, its height clamped to the band) never draws a
    // route larger than the wide box, so both give this same fit, centred on x 540
    #expect(abs(minY - box.minY) < 3 && abs(maxY - box.maxY) < 3)
    #expect(abs((minX + maxX) / 2 - 540) < 20)
    #expect(maxX - minX < CardTokens.Print.Layout.routeBoxTallWidth)
}

@Test func printCardWideRouteFillsTheBoxWidthOrHeight() throws {
    for l in [layout(try i80()), layout(try i80(false)), layout(input([RouteSegment(points: try i80Points())], from: "Ely", to: "Reno"))] {
        let box = try wideBox(l)
        let pts = try #require(stroke(l, "route")?.runs.first)
        let minY = pts.map(\.y).min()!, maxY = pts.map(\.y).max()!, minX = pts.map(\.x).min()!, maxX = pts.map(\.x).max()!
        #expect(minX >= box.minX - 1 && maxX <= box.maxX + 1 && minY >= box.minY - 1 && maxY <= box.maxY + 1)
        #expect(abs(maxX - minX - box.width) < 2 || abs(maxY - minY - box.height) < 2)
        #expect(abs((minX + maxX) / 2 - 540) < 1)
    }
}

@Test func printCardNoAltitudeHasNoStripAndAGrownRouteBox() throws {
    let l = layout(try i80(false))
    #expect(l.blocks[.elevation] == nil && l.elevationFill == nil)
    #expect(!ids(l).contains("highest-point"))
    let with = try #require(stroke(layout(try i80()), "route")?.runs.first), without = try #require(stroke(l, "route")?.runs.first)
    let h = { (p: [CardPoint]) in p.map(\.y).max()! - p.map(\.y).min()! }
    #expect(h(without) >= h(with))
}

// MARK: - title

@Test func printCardShortTitleIsOneLine() throws {
    let l = layout(try i80(), .light, .sticker)
    let t = texts(l)
    #expect(t["title"]?.baseline == t["title-2"]?.baseline)
    #expect(t["title"]?.baseline == CardTokens.Print.Sticker.Layout.titleBaseline)
    #expect(t["title"]?.style.size == CardTokens.Print.Sticker.Typography.Title.size)
}

@Test func printCardStickerTwoLineTitleGrowsUpAndTheRouteGivesWay() throws {
    let names = (from: "Bezirk Innsbruck-Land", to: "Autonome Provinz Bozen – Südtirol")
    let short = layout(try i80(), .light, .sticker)
    let long = layout(input([RouteSegment(points: try i80Points())], from: names.from, to: names.to), .light, .sticker)
    let t = texts(long)
    let last = CardTokens.Print.Sticker.Layout.titleBaseline
    #expect(t["title-2"]?.baseline == last)
    #expect(try #require(t["title"]).baseline < last)
    #expect(t["title-2"]?.string.hasSuffix("…") == true)
    let top = inkTop(try #require(t["title"]))
    let longRoute = try #require(stroke(long, "route")?.runs.first), shortRoute = try #require(stroke(short, "route")?.runs.first)
    #expect(longRoute.map(\.y).max()! <= top - CardTokens.Print.Sticker.Layout.routeTopGap + 0.01)
    #expect(longRoute.map(\.y).max()! < shortRoute.map(\.y).max()!)
    #expect(long.issues.isEmpty, "\(long.issues)")
}

@Test func printCardLongNamesWrapAtFullSizeThenEllipsize() throws {
    // full layout: wraps beside the sign; "WEST SACRAMENTO" fits line 2 at full size
    let wrap = texts(layout(input([RouteSegment(points: try i80Points())], from: "North Salt Lake", to: "West Sacramento")))
    #expect(try #require(wrap["title-2"]).baseline == CardTokens.Print.Layout.titleBaseline + CardTokens.Print.Layout.titleLineHeight)
    #expect(wrap["title"]?.string == "NORTH SALT LAKE" && wrap["title-2"]?.string == "WEST SACRAMENTO")
    #expect(wrap["date"]?.baseline == CardTokens.Print.Layout.titleBaseline + 96 + CardTokens.Print.Layout.dateGap)
    // too long at 80 %: an ellipsis at 80 %
    let clip = texts(layout(input([RouteSegment(points: try i80Points())], from: "Bezirk Innsbruck-Land", to: "Autonome Provinz Bozen – Südtirol")))
    let second = try #require(clip["title-2"])
    #expect(second.string.hasSuffix("…"))
    #expect(abs(second.style.size - CardTokens.Print.Typography.title.size * CardTokens.Print.Layout.fitMinScale) < 1e-9)
    #expect(second.string.hasPrefix("AUTONOME"))
    #expect(second.string.uppercased() == second.string)
}

// MARK: - gaps, hide route

@Test func printCardRecordingGapIsDotted() throws {
    let l = layout(try i80Gap())
    let gap = try #require(stroke(l, "route-gap"))
    #expect(gap.dash == [0, CardTokens.Print.Route.Gap.spacing] && gap.paint == .gap && gap.width == CardTokens.Print.Route.Gap.width)
    #expect(gap.runs.count == 1 && gap.runs[0].count == 2)
    #expect(stroke(l, "route")?.runs.count == 2)
    let eg = try #require(stroke(l, "elevation-gap"))
    #expect(eg.dash == [0, CardTokens.Print.Route.Gap.spacing * 0.75])
    #expect(stroke(l, "elevation")?.runs.count == 2)
    #expect(l.issues.isEmpty, "\(l.issues)")
}

@Test func printCardRouteRunsAreSmoothedDensely() throws {
    let l = layout(try i80())
    let run = try #require(stroke(l, "route")?.runs.first)
    #expect(run.count > 200)
    #expect((run.count - 1) % PrintGeometry.samplesPerSegment == 0)
    #expect(stroke(l, "route-gap") == nil)
}

@Test func printCardHideRouteShowsThePlacesOnly() throws {
    for mode in PrintLayoutMode.allCases {
        let l = layout(input([RouteSegment(points: try i80Points())], hide: true), .light, mode)
        let all = ids(l)
        #expect(!all.contains("route") && !all.contains("highest-point") && !all.contains("elevation"))
        #expect(all.contains("places-connector") && all.contains("start") && all.contains("end"))
        #expect(stroke(l, "places-connector")?.opacity == CardTokens.Print.Route.HiddenConnector.opacity)
        #expect(l.glow.isEmpty && l.elevationFill == nil && l.blocks[.elevation] == nil)
        // the start ring sits at the place centre: Salt Lake City is east of Sacramento
        var centres: [String: CardPoint] = [:]
        for case let .fillCircle(id, c, _, _, _, _) in l.art { centres[id] = c }
        #expect(try #require(centres["start"]).x > (try #require(centres["end"])).x)
    }
}

@Test func printCardMissingRouteIsTreatedAsHideRoute() {
    let l = layout(input([]))
    #expect(ids(l).contains("places-connector"))
}

// MARK: - arrangement, move, hide

@Test func printCardArrangementMovesAndHidesBlocks() throws {
    let base = layout(try i80())
    let moved = layout(try i80(), .light, .full, PrintArrangement(offsets: [.stats: -40]))
    #expect(texts(moved)["distance"]!.baseline == texts(base)["distance"]!.baseline - 40)
    #expect(moved.blocks[.stats]!.lowerBound == base.blocks[.stats]!.lowerBound - 40)
    #expect(texts(moved)["title"]!.baseline == texts(base)["title"]!.baseline)
    // a hidden elevation block drops the strip but does not re-flow the others
    let noStrip = layout(try i80(), .light, .full, PrintArrangement(hidden: [.elevation]))
    #expect(noStrip.blocks[.elevation] == nil && noStrip.elevationFill == nil)
    #expect(!ids(noStrip).contains("elevation-kicker"))
    #expect(stroke(noStrip, "route")?.runs == stroke(base, "route")?.runs)
    #expect(ids(noStrip).contains("highest-point"))
    #expect(noStrip.issues.isEmpty)
    // an out-of-range offset is applied as given and reported
    let off = layout(try i80(), .light, .full, PrintArrangement(offsets: [.header: -200]))
    #expect(off.issues.contains { $0.contains("outside safe area") })
}

@Test(arguments: PrintLayoutMode.allCases)
func printCardMoveClampsAtNeighboursAndTheSafeArea(mode: PrintLayoutMode) throws {
    let i = try i80()
    let l0 = layout(i, .light, mode)
    let order = l0.blocks.sorted { $0.value.lowerBound < $1.value.lowerBound }.map(\.key)
    // the topmost block stops at the safe-area top, the bottom one at 1600
    let first = order[0], last = order[order.count - 1]
    var a = PrintCard.move(first, by: -5000, in: .standard, layout: l0)
    var l = layout(i, .light, mode, a)
    #expect(abs(l.blocks[first]!.lowerBound - CardTokens.Print.SafeArea.top) < 1e-9)
    a = PrintCard.move(last, by: 5000, in: .standard, layout: l0)
    l = layout(i, .light, mode, a)
    #expect(abs(l.blocks[last]!.upperBound - (1920 - CardTokens.Print.SafeArea.bottom)) < 1e-9)
    #expect(l.issues.isEmpty, "\(l.issues)")
    // the stats block slides up until it is 12 px under its neighbour, then stops; blocks keep their order
    let above = order[order.firstIndex(of: .stats)! - 1]
    a = PrintCard.move(.stats, by: -5000, in: .standard, layout: l0)
    l = layout(i, .light, mode, a)
    #expect(abs(l.blocks[.stats]!.lowerBound - (l.blocks[above]!.upperBound + 12)) < 1e-9)
    // accumulates: a further drag up changes nothing, a drag down adds to the offset
    let again = PrintCard.move(.stats, by: -30, in: a, layout: l)
    #expect(again.offsets[.stats] == a.offsets[.stats])
    let down = PrintCard.move(.stats, by: 10, in: a, layout: l)
    #expect(abs(down.offsets[.stats]! - (a.offsets[.stats]! + 10)) < 1e-9)
    // a small move inside the room is applied as is
    let small = PrintCard.move(first, by: -3, in: .standard, layout: l0)
    #expect(small.offsets[first] == -3 || l0.blocks[first]!.lowerBound - 3 < CardTokens.Print.SafeArea.top)
}

@Test func printCardMoveIgnoresHiddenNeighbours() throws {
    let i = try i80()
    let arrangement = PrintArrangement(hidden: [.elevation])
    let l0 = layout(i, .light, .full, arrangement)
    let a = PrintCard.move(.stats, by: -5000, in: arrangement, layout: l0)
    let l = layout(i, .light, .full, a)
    #expect(abs(l.blocks[.stats]!.lowerBound - (l.blocks[.route]!.upperBound + 12)) < 1e-9)
    #expect(l.issues.isEmpty, "\(l.issues)")
}

@Test func printCardCanHideRules() {
    #expect(!PrintCard.canHide(.header, in: .standard))
    #expect(!PrintCard.canHide(.header, in: PrintArrangement(hidden: [.route])))
    #expect(PrintCard.canHide(.elevation, in: .standard))
    #expect(PrintCard.canHide(.elevation, in: PrintArrangement(hidden: [.route])))
    #expect(PrintCard.canHide(.route, in: .standard) && PrintCard.canHide(.stats, in: .standard))
    #expect(!PrintCard.canHide(.route, in: PrintArrangement(hidden: [.stats])))
    #expect(!PrintCard.canHide(.stats, in: PrintArrangement(hidden: [.route])))
    #expect(PrintCard.canHide(.route, in: PrintArrangement(hidden: [.elevation])))
}

@Test(arguments: PrintInk.allCases)
func printCardStickerWithHiddenRouteKeepsTheWordmark(ink: PrintInk) throws {
    let l = layout(try i80(), ink, .sticker, PrintArrangement(hidden: [.route]))
    let t = texts(l)
    let wm = try #require(t["wordmark"])
    #expect(wm.block == .header)
    #expect(l.blocks[.route] == nil)
    #expect(!ids(l).contains("route") && !ids(l).contains("start-label"))
    let sign: CardRect? = l.art.lazy.compactMap { if case let .sign(r, .header) = $0 { r } else { nil } }.first
    let titleTop = inkTop(try #require(t["title"]))
    let rowBottom = max(try #require(sign).maxY, wm.baseline + measurer.ink(wm.string, style: wm.style).bottom)
    #expect(abs(titleTop - CardTokens.Print.Layout.titleSignGap - rowBottom) < 1e-9)
    #expect(l.issues.isEmpty, "\(l.issues)")
    // the full layout keeps the wordmark in the header anyway
    #expect(texts(layout(try i80(), ink, .full, PrintArrangement(hidden: [.route])))["wordmark"]?.block == .header)
}

// MARK: - stats, number

@Test func printCardStatsRowLaysOutThePassedColumns() throws {
    let two = layout(input([RouteSegment(points: try i80Points(altitude: false))], stats: [("Moving time", "10h 52m"), ("States", "3")]))
    let t = texts(two)
    #expect(t["stat-2-value"] != nil && t["stat-3-value"] == nil)
    #expect(stroke(two, "stat-2-divider") != nil && stroke(two, "stat-3-divider") == nil)
    #expect(abs(t["stat-2-label"]!.x - (72 + 2 + (1080 - 144) / 2.0)) < 1e-9)
    #expect(stroke(two, "stats-rule")?.opacity == CardTokens.Print.Hairline.opacity)
    let hp = texts(layout(input([RouteSegment(points: try i80Points())],
                                stats: [("Moving time", "10h 52m"), ("States", "3"), ("Highest point", "7,102 ft")])))
    #expect(hp["stat-3-label"]?.string == "HIGHEST POINT" && hp["stat-3-value"]?.string == "7,102 ft")
}

@Test func printCardBigNumberShrinksToFit() throws {
    var i = try i80()
    i.distanceValue = "1,197"
    let n = try #require(texts(layout(i))["distance"])
    #expect(n.style.size < CardTokens.Print.Typography.number.size)
    #expect(n.style.size >= CardTokens.Print.Typography.number.size * CardTokens.Print.Layout.numberMinScale - 4)
    #expect(layout(i).issues.isEmpty)
}

// MARK: - geometry helpers

@Test func printGeometrySimplifyKeepsCorners() {
    let p = [CardPoint(x: 0, y: 0), CardPoint(x: 5, y: 0.5), CardPoint(x: 10, y: 0), CardPoint(x: 10, y: 10)]
    #expect(PrintGeometry.simplify(p, tolerance: 1.2) == [p[0], p[2], p[3]])
    let s = PrintGeometry.smooth(p)
    #expect(s.first == p[0] && s.last == p[3] && s.count == 1 + 3 * PrintGeometry.samplesPerSegment)
}
