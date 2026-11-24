import Foundation

// The Print card layout engine: a port of `build()` and `check()` in Tools/design/print-card.mjs.
// The public surface is in PrintCard.swift; everything here is internal.
//
// Differences from the reference that are about output format, not layout:
// - Routes are output as dense polylines (Catmull-Rom sampled, `samplesPerSegment` per segment)
//   instead of SVG cubic Bézier paths.
// - The title arrow is one polyline (shaft, upper barb, back to the tip, lower barb); with round caps
//   and joins it draws the same mark as the reference's three-part path.

private typealias T = CardTokens.Print

/// `Lk(k)`: `print.layout`, with `print.sticker.layout` overrides in the sticker layout.
struct PrintLayoutValues: Sendable {
    let sticker: Bool
    let wordmarkBaseline, signTop, signHeight: Double
    let routeBoxTop, routeBoxBottom, routeBoxTallHeight, routeTopGap: Double
    let titleBaseline, titleLineHeight, dateGap, numberBaseline: Double

    init(_ mode: PrintLayoutMode) {
        typealias Lf = T.Layout
        typealias Ls = T.Sticker.Layout
        sticker = mode == .sticker
        wordmarkBaseline = sticker ? Ls.wordmarkBaseline : Lf.wordmarkBaseline
        signTop = sticker ? Ls.signTop : Lf.signTop
        signHeight = sticker ? Ls.signHeight : Lf.signHeight
        routeBoxTop = sticker ? Ls.routeBoxTop : Lf.routeBoxTop
        routeBoxBottom = sticker ? Ls.routeBoxBottom : Lf.routeBoxBottom
        routeBoxTallHeight = sticker ? Ls.routeBoxTallHeight : Lf.routeBoxTallHeight
        routeTopGap = sticker ? Ls.routeTopGap : Lf.routeTopGap
        titleBaseline = sticker ? Ls.titleBaseline : Lf.titleBaseline
        titleLineHeight = sticker ? Ls.titleLineHeight : Lf.titleLineHeight
        dateGap = sticker ? Ls.dateGap : Lf.dateGap
        numberBaseline = sticker ? Ls.numberBaseline : Lf.numberBaseline
    }
}

/// `TY(k)`: a type token at the layout's size, with its paint role and case.
struct PrintStyle: Sendable {
    var text: CardTextStyle
    var upper: Bool
    var paint: PrintPaint

    init(_ token: CardTypeToken, size: Double? = nil) {
        text = CardTextStyle(token, size: size)
        upper = token.uppercase
        paint = token.color == CardTokens.Color.route ? .accent : token.color == T.Color.muted ? .muted : .text
    }
    var size: Double { text.size }
    func at(_ size: Double) -> PrintStyle { var s = self; s.text.size = size; return s }
    func cased(_ s: String) -> String { upper ? CardText.uppercased(s) : s }
}

/// A placed shape with its bounds (text: the ink box; marks: their extent incl. stroke width).
struct PrintItem: Sendable {
    var shape: PrintShape
    var bounds: CardRect
}

/// A named box for the checks (`boxes` in the reference).
struct PrintBox: Sendable {
    var name: String
    var rect: CardRect
    var block: PrintBlock
}

struct PrintRawLayout: Sendable {
    var items: [PrintItem]
    var boxes: [PrintBox]
    var glow: [[CardPoint]]
    var elevationFill: PrintArea?
}

enum PrintGeometry {
    static let samplesPerSegment = 8

    /// Douglas–Peucker (`simplify` in the reference): perpendicular distance to the chord.
    static func simplify(_ p: [CardPoint], tolerance: Double) -> [CardPoint] {
        guard p.count > 2 else { return p }
        var keep = [Bool](repeating: false, count: p.count)
        keep[0] = true; keep[p.count - 1] = true
        var stack = [(0, p.count - 1)]
        while let (a, b) = stack.popLast() {
            let ax = p[a].x, ay = p[a].y, dx = p[b].x - ax, dy = p[b].y - ay
            let n = hypot(dx, dy) == 0 ? 1e-9 : hypot(dx, dy)
            var best = 0.0, bi = -1
            if b > a + 1 {
                for i in (a + 1)..<b {
                    let d = abs((p[i].x - ax) * dy - (p[i].y - ay) * dx) / n
                    if d > best { best = d; bi = i }
                }
            }
            if best > tolerance { keep[bi] = true; stack.append((a, bi)); stack.append((bi, b)) }
        }
        return p.indices.filter { keep[$0] }.map { p[$0] }
    }

    /// Catmull-Rom through the points (`smooth` in the reference, tension 0.5 / 3), sampled densely.
    static func smooth(_ p: [CardPoint], samples: Int = samplesPerSegment) -> [CardPoint] {
        guard p.count >= 3 else { return p }
        let t = 0.5 / 3
        var out = [p[0]]
        out.reserveCapacity(1 + (p.count - 1) * samples)
        for i in 0..<(p.count - 1) {
            let p0 = p[max(i - 1, 0)], p1 = p[i], p2 = p[i + 1], p3 = p[min(i + 2, p.count - 1)]
            let c1 = CardPoint(x: p1.x + (p2.x - p0.x) * t, y: p1.y + (p2.y - p0.y) * t)
            let c2 = CardPoint(x: p2.x - (p3.x - p1.x) * t, y: p2.y - (p3.y - p1.y) * t)
            for s in 1...samples {
                let u = Double(s) / Double(samples), v = 1 - u
                let a = v * v * v, b = 3 * v * v * u, c = 3 * v * u * u, d = u * u * u
                out.append(CardPoint(x: a * p1.x + b * c1.x + c * c2.x + d * p2.x,
                                     y: a * p1.y + b * c1.y + c * c2.y + d * p2.y))
            }
        }
        return out
    }

    /// `kmBetween` in the reference: equirectangular distance in km.
    static func km(_ a: RoutePoint, _ b: RoutePoint) -> Double {
        let r = Double.pi / 180
        let x = (b.longitude - a.longitude) * r * cos((a.latitude + b.latitude) / 2 * r)
        let y = (b.latitude - a.latitude) * r
        return hypot(x, y) * 6371
    }

    static func bounds(of points: [CardPoint], pad: Double) -> CardRect? {
        guard let f = points.first else { return nil }
        var r = CardRect(minX: f.x, minY: f.y, maxX: f.x, maxY: f.y)
        for q in points {
            r.minX = min(r.minX, q.x); r.maxX = max(r.maxX, q.x)
            r.minY = min(r.minY, q.y); r.maxY = max(r.maxY, q.y)
        }
        return CardRect(minX: r.minX - pad, minY: r.minY - pad, maxX: r.maxX + pad, maxY: r.maxY + pad)
    }

    static func circle(_ c: CardPoint, _ r: Double) -> CardRect {
        CardRect(minX: c.x - r, minY: c.y - r, maxX: c.x + r, maxY: c.y + r)
    }
}

extension PrintShape {
    /// The shape moved down by `dy`, optionally in another block.
    func moved(by dy: Double, to newBlock: PrintBlock? = nil) -> PrintShape {
        func p(_ q: CardPoint) -> CardPoint { CardPoint(x: q.x, y: q.y + dy) }
        switch self {
        case .text(var t):
            t.baseline += dy; if let newBlock { t.block = newBlock }
            return .text(t)
        case let .stroke(id, runs, width, paint, opacity, dash, b):
            return .stroke(id: id, runs: runs.map { $0.map(p) }, width: width, paint: paint, opacity: opacity, dash: dash, block: newBlock ?? b)
        case let .fillCircle(id, c, r, paint, opacity, b):
            return .fillCircle(id: id, center: p(c), radius: r, paint: paint, opacity: opacity, block: newBlock ?? b)
        case let .strokeCircle(id, c, r, w, paint, opacity, dash, b):
            return .strokeCircle(id: id, center: p(c), radius: r, width: w, paint: paint, opacity: opacity, dash: dash, block: newBlock ?? b)
        case let .dot(id, c, r, fill, stroke, sw, so, b):
            return .dot(id: id, center: p(c), radius: r, fill: fill, stroke: stroke, strokeWidth: sw, strokeOpacity: so, block: newBlock ?? b)
        case let .arrow(points, w, paint, b):
            return .arrow(points: points.map(p), width: w, paint: paint, block: newBlock ?? b)
        case let .sign(rect, b):
            return .sign(rect: rect.offsetBy(dy: dy), block: newBlock ?? b)
        }
    }
}

/// `build(cd)` from the reference for one (ink, layout) pair, before the arrangement.
struct PrintCardBuilder<M: CardTextMeasuring> {
    let measurer: M
    let ink: PrintInk
    let lk: PrintLayoutValues

    static var W: Double { T.Export.width }
    static var H: Double { T.Export.height }
    static var L: Double { T.SafeArea.side }
    static var R: Double { T.Export.width - T.SafeArea.side }

    private var items: [PrintItem] = []
    private var boxes: [PrintBox] = []

    init(measurer: M, ink: PrintInk, mode: PrintLayoutMode) {
        self.measurer = measurer; self.ink = ink; self.lk = PrintLayoutValues(mode)
    }

    // MARK: text

    func measure(_ s: String, _ st: PrintStyle) -> CardInkBox { measurer.ink(s, style: st.text) }

    /// `textBox` in the reference: the ink box of `s` set at x on baseline y with `anchor`.
    func textBox(_ st: PrintStyle, _ s: String, _ x: Double, _ y: Double, _ anchor: CardTextAnchor = .start) -> CardRect {
        let m = measure(s, st)
        let x0 = anchor == .end ? x - m.width - m.x : anchor == .middle ? x - m.width / 2 : x + m.x
        return CardRect(minX: x0, minY: y + m.top, maxX: x0 + m.width, maxY: y + m.bottom)
    }

    /// Places already-cased text and records its box under `name` for the checks (nil: no check box).
    @discardableResult
    mutating func text(_ id: String, _ s: String, _ st: PrintStyle, x: Double, y: Double, anchor: CardTextAnchor = .start,
                       opacity: Double = 1, block: PrintBlock, box name: String?, paint: PrintPaint? = nil) -> CardRect {
        let b = textBox(st, s, x, y, anchor)
        items.append(PrintItem(shape: .text(PrintText(id: id, string: s, style: st.text, x: x, baseline: y, anchor: anchor,
                                                      paint: paint ?? st.paint, opacity: opacity, block: block)), bounds: b))
        if let name { boxes.append(PrintBox(name: name, rect: b, block: block)) }
        return b
    }

    static func trimEnd(_ s: String) -> String {
        var t = s
        while let c = t.last, c.isWhitespace { t.removeLast() }
        return t
    }

    /// `fit` in the reference: full size, then down to `fitMinScale`, then an ellipsis at that size.
    func fit(_ st: PrintStyle, _ s: String, _ maxW: Double) -> (s: String, size: Double) {
        let minScale = T.Layout.fitMinScale
        let w = measure(s, st).width
        if w <= maxW { return (s, st.size) }
        let k = maxW / w
        if k >= minScale { return (s, (st.size * k * 10).rounded(.down) / 10) }
        let small = st.at(st.size * minScale)
        var t = s
        while t.count > 1 && measure(Self.trimEnd(t) + "…", small).width > maxW { t.removeLast() }
        return (Self.trimEnd(t) + "…", small.size)
    }

    mutating func add(_ shape: PrintShape, bounds: CardRect?) {
        items.append(PrintItem(shape: shape, bounds: bounds ?? CardRect(minX: 0, minY: 0, maxX: 0, maxY: 0)))
    }

    mutating func box(_ name: String, _ r: CardRect, _ block: PrintBlock) { boxes.append(PrintBox(name: name, rect: r, block: block)) }

    // MARK: build

    mutating func build(_ input: PrintCardInput) -> PrintRawLayout {
        let L = Self.L, R = Self.R, W = Self.W
        let sticker = lk.sticker
        let full = T.Typography.self
        // sticker: the wordmark and sign row sits with the route block (moved to the header if the route is hidden)
        let rowBlock: PrintBlock = sticker ? .route : .header

        // header: wordmark and sign
        let wm = PrintStyle(full.wordmark)
        text("wordmark", wm.cased(input.wordmark), wm, x: L + 2, y: lk.wordmarkBaseline, block: rowBlock, box: "wordmark")
        var signBox: CardRect?
        if let aspect = input.signAspect, aspect > 0 {
            let h = lk.signHeight, w = h * aspect
            let r = CardRect(minX: R - w, minY: lk.signTop, maxX: R, maxY: lk.signTop + h)
            add(.sign(rect: r, block: rowBlock), bounds: r); box("sign", r, rowBlock)
            signBox = r
        }

        // title: one line "A → B" if it fits left of the sign; else "A" then "→ B" at one size:
        // full, then down to 80 %, then an ellipsis at 80 %
        let ti = PrintStyle(full.title, size: sticker ? T.Sticker.Typography.Title.size : nil)
        let k0 = ti.size / full.title.size // the arrow geometry is drawn for the full layout's title size
        let aw = T.Layout.titleArrowWidth * k0, ag = T.Layout.titleArrowGap * k0
        let maxW1 = sticker || signBox == nil ? R - L : signBox!.minX - T.Layout.titleSignGap - L
        let A = ti.cased(input.from), B = ti.cased(input.to)
        let accent: PrintPaint = .accent
        func arrow(_ x: Double, _ y: Double, _ size: Double) -> Double {
            let k = size / ti.size, my = y - 34 * k * k0, len = aw * k, hd = 16 * k * k0
            let sw = T.Layout.titleArrowStroke * k * k0
            let tip = CardPoint(x: x + len, y: my)
            let pts = [CardPoint(x: x, y: my), tip, CardPoint(x: x + len - hd - 1, y: my - hd), tip, CardPoint(x: x + len - hd - 1, y: my + hd)]
            let hs = sw / 2 // round caps reach half a stroke past the path
            let r = CardRect(minX: x - hs, minY: my - hd - hs, maxX: x + len + hs, maxY: my + hd + hs)
            add(.arrow(points: pts, width: sw, paint: accent, block: .header), bounds: r)
            box("arrow", r, .header)
            return x + len + ag * k
        }
        // every line starts with its ink exactly on the safe edge
        func atL(_ st: PrintStyle, _ s: String) -> Double { L - measure(s, st).x }
        var y = lk.titleBaseline
        let firstTitle: CardRect
        if measure(A, ti).width + measure(B, ti).width + aw + 2 * ag <= maxW1 {
            let x0 = atL(ti, A)
            firstTitle = text("title", A, ti, x: x0, y: y, block: .header, box: "title")
            let bx = arrow(firstTitle.maxX + ag, y, ti.size)
            text("title-2", B, ti, x: bx, y: y, block: .header, box: "title")
        } else {
            let w1 = maxW1, w2 = R - L - aw - ag
            let size = min(fit(ti, A, w1).size, fit(ti, B, w2).size), st = ti.at(size)
            func clip(_ s: String, _ w: Double) -> String {
                if measure(s, st).width <= w { return s }
                var t = s
                while t.count > 1 && measure(t + "…", st).width > w { t = Self.trimEnd(String(t.dropLast())) }
                return t + "…"
            }
            let a = clip(A, w1), bb = clip(B, w2 - ag * size / ti.size)
            if sticker { y -= lk.titleLineHeight * size / ti.size } // titleBaseline is the last line: the stack grows up
            firstTitle = text("title", a, st, x: atL(st, a), y: y, block: .header, box: "title")
            y += lk.titleLineHeight * size / ti.size
            let bx = arrow(L + T.Layout.titleArrowStroke * k0 * size / ti.size / 2, y, size)
            text("title-2", bb, st, x: bx, y: y, block: .header, box: "title")
        }
        let dt = PrintStyle(full.date, size: sticker ? T.Sticker.Typography.Date.size : nil)
        let dateY = y + lk.dateGap
        text("date", dt.cased(input.date), dt, x: L + 2, y: dateY, block: .header, box: "date")

        // route box: wide, or tall when that draws the route larger
        let segments = (input.route ?? []).map(\.points).filter { !$0.isEmpty }
        let hidden = input.hideRoute || segments.isEmpty
        let pts = hidden ? [] : segments.flatMap { $0 }
        let hasAlt = !hidden && pts.contains { $0.altitude != nil }
        let strip = hasAlt && !sticker
        let top = sticker ? lk.routeBoxTop : max(lk.routeBoxTop, dateY + lk.routeTopGap)
        let bottom = sticker ? min(lk.routeBoxBottom, firstTitle.minY - lk.routeTopGap)
            : strip ? lk.routeBoxBottom : T.Layout.routeBottomNoElevation
        let src: [GeoPoint] = hidden ? Array(input.placeCenters.prefix(2))
            : pts.map { GeoPoint(latitude: $0.latitude, longitude: $0.longitude) }

        var start: CardPoint?, end: CardPoint?
        var summitIndex: Int?
        var glow: [[CardPoint]] = []
        var proj: (GeoPoint) -> CardPoint = { _ in CardPoint(x: 0, y: 0) }
        let rt = T.Route.self, rg = T.Ring.self

        if !src.isEmpty {
            let lat0 = src.reduce(0) { $0 + $1.latitude } / Double(src.count), kx = cos(lat0 * .pi / 180)
            let gx = src.map { $0.longitude * kx }, gy = src.map { -$0.latitude }
            let ext = (gx.min()!, gx.max()!, gy.min()!, gy.max()!)
            let rawW = ext.1 - ext.0, rawH = ext.3 - ext.2
            let gw = rawW == 0 ? 1e-9 : rawW, gh = rawH == 0 ? 1e-9 : rawH
            let wide = CardRect(minX: T.Layout.routeBoxLeft, minY: top, maxX: T.Layout.routeBoxRight, maxY: bottom)
            let tw = T.Layout.routeBoxTallWidth, th = min(lk.routeBoxTallHeight, bottom - top), tcy = (top + bottom) / 2
            let tall = CardRect(minX: W / 2 - tw / 2, minY: tcy - th / 2, maxX: W / 2 + tw / 2, maxY: tcy + th / 2)
            func scaleIn(_ b: CardRect) -> Double { min(b.width / gw, b.height / gh) }
            let rb = hidden ? CardRect(minX: wide.minX + 120, minY: wide.minY + 60, maxX: wide.maxX - 120, maxY: wide.maxY - 60)
                : scaleIn(tall) > scaleIn(wide) * 1.05 ? tall : wide
            // a single point (or two equal places): centred, no scale
            let sc = rawW < 1e-12 && rawH < 1e-12 ? 0 : scaleIn(rb)
            let ox = rb.minX + (rb.width - gw * sc) / 2 - ext.0 * sc
            let oy = rb.minY + (rb.height - gh * sc) / 2 - ext.2 * sc
            proj = { CardPoint(x: $0.longitude * kx * sc + ox, y: -$0.latitude * sc + oy) }
        }
        func projR(_ p: RoutePoint) -> CardPoint { proj(GeoPoint(latitude: p.latitude, longitude: p.longitude)) }

        if !hidden {
            // split at recording gaps; each run is simplified and smoothed on its own
            let runs = segments.map { seg in PrintGeometry.smooth(PrintGeometry.simplify(seg.map(projR), tolerance: rt.simplifyTolerance)) }
            let gaps = (1..<max(1, segments.count)).map { i in [projR(segments[i - 1].last!), projR(segments[i][0])] }
            let glowOpacity = ink == .dark ? T.InkDark.Route.glowOpacity : rt.Glow.opacity
            if glowOpacity > 0 { glow = runs }
            let casingOpacity = ink == .dark ? T.InkDark.Route.casingOpacity : rt.Casing.opacity
            add(.stroke(id: "route-casing", runs: runs, width: rt.Casing.width, paint: .casing, opacity: casingOpacity, dash: nil, block: .route),
                bounds: PrintGeometry.bounds(of: runs.flatMap { $0 }, pad: rt.Casing.width / 2))
            if !gaps.isEmpty {
                add(.stroke(id: "route-gap", runs: gaps, width: rt.Gap.width, paint: .gap, opacity: 1, dash: [0, rt.Gap.spacing], block: .route),
                    bounds: PrintGeometry.bounds(of: gaps.flatMap { $0 }, pad: rt.Gap.width / 2))
            }
            add(.stroke(id: "route", runs: runs, width: rt.Core.width, paint: .route, opacity: 1, dash: nil, block: .route),
                bounds: PrintGeometry.bounds(of: runs.flatMap { $0 }, pad: rt.Core.width / 2))
            start = projR(pts[0]); end = projR(pts[pts.count - 1])
            var best: Double?
            for (i, p) in pts.enumerated() { if let a = p.altitude, best == nil || a > best! { best = a; summitIndex = i } }
            let hw = rt.Core.width / 2
            for p in pts { box("route", PrintGeometry.circle(projR(p), hw), .route) }
        } else if src.count >= 2 {
            start = proj(src[0]); end = proj(src[1])
            let line = [start!, end!]
            add(.stroke(id: "places-connector", runs: [line], width: rt.Gap.width, paint: .gap, opacity: rt.HiddenConnector.opacity,
                        dash: [0, rt.Gap.spacing], block: .route),
                bounds: PrintGeometry.bounds(of: line, pad: rt.Gap.width / 2))
        } else if src.count == 1 {
            start = proj(src[0]); end = start
        }
        if let start, let end {
            for (c, id) in [(start, "start"), (end, "end")] {
                add(.fillCircle(id: "\(id)-fill", center: c, radius: rg.radius, paint: .route, opacity: rg.fillOpacity, block: .route),
                    bounds: PrintGeometry.circle(c, rg.radius))
                add(.strokeCircle(id: "\(id)-ring", center: c, radius: rg.radius, width: rg.strokeWidth, paint: .route, opacity: 1,
                                  dash: [rg.dash, rg.dashGap], block: .route),
                    bounds: PrintGeometry.circle(c, rg.radius + rg.strokeWidth / 2))
                add(.fillCircle(id: "\(id)-halo", center: c, radius: rg.dotHaloRadius, paint: .ink, opacity: rg.dotHaloOpacity, block: .route),
                    bounds: PrintGeometry.circle(c, rg.dotHaloRadius))
                add(.fillCircle(id: id, center: c, radius: rg.dotRadius, paint: .text, opacity: 1, block: .route),
                    bounds: PrintGeometry.circle(c, rg.dotRadius))
            }
            let rr = rg.radius + rg.strokeWidth / 2
            box("ring", PrintGeometry.circle(start, rr), .route); box("ring", PrintGeometry.circle(end, rr), .route)
        }
        let sm = T.Summit.self
        if let si = summitIndex, hasAlt { // the highest-point dot stays on the route in both layouts
            let c = projR(pts[si])
            add(.dot(id: "highest-point", center: c, radius: sm.radius, fill: .text, stroke: .ink, strokeWidth: sm.strokeWidth,
                     strokeOpacity: sm.strokeOpacity, block: .route),
                bounds: PrintGeometry.circle(c, sm.radius + sm.strokeWidth / 2))
            box("summit", PrintGeometry.circle(c, sm.radius), .route)
        }

        // elevation strip
        var fill: PrintArea?
        if strip, let si = summitIndex, let start, let end {
            let et = T.Layout.elevationTop, eb = T.Layout.elevationBaseline, ev = T.Elevation.self
            let kt = PrintStyle(full.kicker)
            let kb = text("elevation-kicker", kt.cased(input.elevationKicker), kt, x: L + 2, y: et - T.Layout.elevationKickerGap,
                          block: .elevation, box: "kicker")
            var d = 0.0
            var ds = [0.0]
            for i in 1..<max(1, pts.count) { d += PrintGeometry.km(pts[i - 1], pts[i]); ds.append(d) }
            let flip = end.x < start.x, amax = pts[si].altitude!, amin = 0.0, span = amax - amin
            func E(_ i: Int) -> CardPoint {
                let u = d > 0 ? ds[i] / d : (pts.count > 1 ? Double(i) / Double(pts.count - 1) : 0)
                let a = pts[i].altitude ?? amin
                let v = span > 0 ? (a - amin) / span : 0
                return CardPoint(x: flip ? R - u * (R - L) : L + u * (R - L), y: eb - v * (eb - et))
            }
            var runs: [[CardPoint]] = [[]]
            var i = 0
            for (s, seg) in segments.enumerated() {
                if s > 0 && !runs[runs.count - 1].isEmpty { runs.append([]) }
                for p in seg { if p.altitude != nil { runs[runs.count - 1].append(E(i)) }; i += 1 }
            }
            runs = runs.filter { !$0.isEmpty }
            let lines = runs.map { PrintGeometry.simplify($0, tolerance: ev.simplifyTolerance) }
            let areas = lines.map { s in s + [CardPoint(x: s[s.count - 1].x, y: eb), CardPoint(x: s[0].x, y: eb)] }
            fill = PrintArea(runs: areas, top: et, bottom: eb)
            let all = lines.flatMap { $0 }
            add(.stroke(id: "elevation-casing", runs: lines, width: ev.casingWidth, paint: .ink, opacity: ev.casingOpacity, dash: nil, block: .elevation),
                bounds: PrintGeometry.bounds(of: all, pad: ev.casingWidth / 2))
            if lines.count > 1 {
                let gaps = (1..<lines.count).map { [lines[$0 - 1][lines[$0 - 1].count - 1], lines[$0][0]] }
                add(.stroke(id: "elevation-gap", runs: gaps, width: rt.Gap.width * 0.7, paint: .gap, opacity: 1,
                            dash: [0, rt.Gap.spacing * 0.75], block: .elevation),
                    bounds: PrintGeometry.bounds(of: gaps.flatMap { $0 }, pad: rt.Gap.width * 0.35))
            }
            add(.stroke(id: "elevation", runs: lines, width: ev.lineWidth, paint: .route, opacity: 1, dash: nil, block: .elevation),
                bounds: PrintGeometry.bounds(of: all, pad: ev.lineWidth / 2))
            let tp = E(si)
            add(.dot(id: "elevation-highest", center: tp, radius: sm.stripRadius, fill: .text, stroke: .ink, strokeWidth: sm.stripStrokeWidth,
                     strokeOpacity: sm.stripStrokeOpacity, block: .elevation),
                bounds: PrintGeometry.circle(tp, sm.stripRadius + sm.stripStrokeWidth / 2))
            // the label: above the dot on the side with room, else beside it; never on the kicker
            let st = PrintStyle(full.summitLabel), lab = st.cased(input.summitLabel), gap = T.Layout.summitLabelGap
            let cands: [(Double, Double, CardTextAnchor)] = [(tp.x - gap, tp.y - 16, .end), (tp.x + gap, tp.y - 16, .start),
                                                             (tp.x + gap, tp.y + 8, .start), (tp.x - gap, tp.y + 8, .end)]
            let pick = cands.first { c in
                let bb = textBox(st, lab, c.0, c.1, c.2)
                return bb.minX >= L && bb.maxX <= R
                    && !(bb.minX < kb.maxX + 14 && bb.maxX > kb.minX - 14 && bb.minY < kb.maxY + 6 && bb.maxY > kb.minY - 6)
            } ?? cands[0]
            text("highest-label", lab, st, x: pick.0, y: pick.1, anchor: pick.2, block: .elevation, box: "summit label")
        }

        // area labels: 8 spots around each ring, outward first; keep the first that clears everything placed so far
        if let start, let end {
            let al = PrintStyle(full.areaLabel), off = T.Layout.areaLabelOffset, clr = T.Layout.labelClearance
            func hits(_ b: CardRect, _ list: [CardRect]) -> Bool { list.contains { b.intersects($0, margin: clr) } }
            let routeBoxes = boxes.filter { $0.name == "route" }.map(\.rect)
            let ends = [(start, input.startLabel, "start-label"), (end, input.endLabel, "end-label")]
            for (k, (c, name, id)) in ends.enumerated() where !name.isEmpty {
                let f = fit(al, al.cased(name), T.Layout.areaLabelMaxWidth), st = al.at(f.size)
                let m = measure(f.s, st), h = m.bottom - m.top, x = c.x, y = c.y
                let spots: [(Double, Double, CardTextAnchor)] = [
                    (x + off, y + h / 2, .start), (x - off, y + h / 2, .end), (x, y - off, .middle), (x, y + off + h, .middle),
                    (x + off * 0.8, y - off * 0.8, .start), (x - off * 0.8, y - off * 0.8, .end),
                    (x + off * 0.8, y + off * 0.8 + h, .start), (x - off * 0.8, y + off * 0.8 + h, .end)]
                let other = k == 1 ? start : end
                let outward = x < other.x ? [1, 0, 5, 7, 2, 3, 4, 6] : [0, 1, 4, 6, 2, 3, 5, 7]
                let others = boxes.filter { $0.name != "route" }.map(\.rect)
                var pick: (Double, Double, CardTextAnchor)?
                for i in outward {
                    let (sx, ly, anchor) = spots[i]
                    var lx = sx
                    var b = textBox(st, f.s, lx, ly, anchor)
                    let shift = b.minX < L ? L - b.minX : b.maxX > R ? R - b.maxX : 0 // slide along the edge, never past it
                    if shift != 0 { lx += shift; b = CardRect(minX: b.minX + shift, minY: b.minY, maxX: b.maxX + shift, maxY: b.maxY) }
                    if b.minY < T.SafeArea.top { continue }
                    if !hits(b, others) && !hits(b, routeBoxes) { pick = (lx, ly, anchor); break }
                }
                let p = pick ?? spots[outward[0]]
                text(id, f.s, st, x: p.0, y: p.1, anchor: p.2, opacity: 0.9, block: .route, box: "area label")
            }
        }

        // the big number and unit
        let nt = PrintStyle(full.number, size: sticker ? T.Sticker.Typography.Number.size : nil)
        let ut = PrintStyle(full.unit, size: sticker ? T.Sticker.Typography.Unit.size : nil)
        let nstr = input.distanceValue, unit = input.distanceUnit // not upper-cased (contract)
        var ns = nt.size, us = ut.size
        func fullWidth() -> Double { measure(nstr, nt.at(ns)).width + T.Layout.unitGap * ns / nt.size + measure(unit, ut.at(us)).width }
        while fullWidth() > R - L && ns > nt.size * T.Layout.numberMinScale { ns -= 4; us = ut.size * ns / nt.size }
        let nb = lk.numberBaseline
        let nbx = text("distance", nstr, nt.at(ns), x: L - measure(nstr, nt.at(ns)).x, y: nb, block: .stats, box: "number")
        text("distance-unit", unit, ut.at(us), x: nbx.maxX + T.Layout.unitGap * ns / nt.size, y: nb, block: .stats, box: "unit")

        // stats: the app passes the final list (moving time, regions, career distance or highest point)
        let hl = T.Hairline.self, sl = PrintStyle(full.statLabel), sv = PrintStyle(full.statValue)
        let cols = Array(input.stats.prefix(Int(T.Layout.statsColumns)))
        if !cols.isEmpty {
            let cw = (R - L) / Double(cols.count), inset = T.Layout.statsDividerInset
            let rule = [CardPoint(x: L, y: T.Layout.statsRule), CardPoint(x: R, y: T.Layout.statsRule)]
            add(.stroke(id: "stats-rule", runs: [rule], width: hl.width, paint: .text, opacity: hl.opacity, dash: nil, block: .stats),
                bounds: PrintGeometry.bounds(of: rule, pad: hl.width / 2))
            for (i, col) in cols.enumerated() {
                let x = L + 2 + Double(i) * cw
                if i > 0 {
                    let line = [CardPoint(x: x - inset, y: T.Layout.statsDividerTop), CardPoint(x: x - inset, y: T.Layout.statsDividerBottom)]
                    add(.stroke(id: "stat-\(i + 1)-divider", runs: [line], width: hl.width, paint: .text, opacity: hl.opacity, dash: nil, block: .stats),
                        bounds: PrintGeometry.bounds(of: line, pad: hl.width / 2))
                }
                let lf = fit(sl, sl.cased(col.label), cw - inset - 8), vf = fit(sv, sv.cased(col.value), cw - inset - 8)
                text("stat-\(i + 1)-label", lf.s, sl.at(lf.size), x: x, y: T.Layout.statsLabelBaseline, block: .stats, box: "stat")
                text("stat-\(i + 1)-value", vf.s, sv.at(vf.size), x: x, y: T.Layout.statsValueBaseline, block: .stats, box: "stat")
            }
        }

        return PrintRawLayout(items: items, boxes: boxes, glow: glow, elevationFill: fill)
    }
}

enum PrintChecks {
    /// `check()` in the reference: safe area (no exceptions), labels on marks, labels on labels.
    static func issues(_ boxes: [PrintBox]) -> [String] {
        let L = T.SafeArea.side, R = T.Export.width - T.SafeArea.side
        let top = T.SafeArea.top, bottom = T.Export.height - T.SafeArea.bottom
        func r(_ b: CardRect) -> String { "[\(Int(b.minX.rounded())),\(Int(b.minY.rounded())),\(Int(b.maxX.rounded())),\(Int(b.maxY.rounded()))]" }
        var errs: [String] = []
        for b in boxes where b.rect.minX < L - 0.5 || b.rect.maxX > R + 0.5 || b.rect.minY < top || b.rect.maxY > bottom {
            errs.append("\(b.name) outside safe area \(r(b.rect))")
        }
        let labelKeys = ["label", "title", "date", "wordmark", "kicker", "sign", "arrow"]
        let labels = boxes.filter { b in labelKeys.contains { b.name.contains($0) } }
        let marks = boxes.filter { $0.name.contains("route") || $0.name.contains("ring") || $0.name.hasSuffix("summit") }
        func overlap(_ a: CardRect, _ c: CardRect) -> Bool { a.minX < c.maxX && a.maxX > c.minX && a.minY < c.maxY && a.maxY > c.minY }
        for a in labels {
            if let m = marks.first(where: { overlap(a.rect, $0.rect) }) { errs.append("\(a.name) touches \(m.name)") }
        }
        for i in labels.indices {
            for j in labels.indices where j > i && overlap(labels[i].rect, labels[j].rect) {
                errs.append("\(labels[i].name) overlaps \(labels[j].name) \(r(labels[i].rect))/\(r(labels[j].rect))")
            }
        }
        var seen = Set<String>()
        return errs.filter { seen.insert($0).inserted }
    }
}

enum PrintArranger {
    /// Moves blocks by their offsets, drops hidden ones and runs the checks on the result.
    static func arrange(_ raw: PrintRawLayout, ink: PrintInk, mode: PrintLayoutMode, arrangement: PrintArrangement) -> PrintCardLayout {
        var items = raw.items, boxes = raw.boxes
        let hidden = arrangement.hidden
        // sticker with the route hidden: the wordmark and sign row joins the header, just above the title
        if mode == .sticker && hidden.contains(.route) {
            let isRow: (String) -> Bool = { $0 == "wordmark" || $0 == "sign" }
            let titleTop = boxes.filter { $0.name == "title" || $0.name == "arrow" }.map(\.rect.minY).min()
            let rowBottom = boxes.filter { isRow($0.name) }.map(\.rect.maxY).max()
            if let titleTop, let rowBottom {
                let dy = titleTop - T.Layout.titleSignGap - rowBottom
                for i in items.indices {
                    let s = items[i].shape
                    var row = false
                    if case .sign = s { row = true }
                    if case .text(let t) = s, t.id == "wordmark" { row = true }
                    if row { items[i] = PrintItem(shape: s.moved(by: dy, to: .header), bounds: items[i].bounds.offsetBy(dy: dy)) }
                }
                for i in boxes.indices where isRow(boxes[i].name) {
                    boxes[i].rect = boxes[i].rect.offsetBy(dy: dy); boxes[i].block = .header
                }
            }
        }
        func dy(_ b: PrintBlock) -> Double { arrangement.offsets[b] ?? 0 }
        items = items.filter { !hidden.contains($0.shape.block) }.map {
            let d = dy($0.shape.block)
            return d == 0 ? $0 : PrintItem(shape: $0.shape.moved(by: d), bounds: $0.bounds.offsetBy(dy: d))
        }
        boxes = boxes.filter { !hidden.contains($0.block) }.map { var b = $0; b.rect = b.rect.offsetBy(dy: dy(b.block)); return b }
        let glow = hidden.contains(.route) ? [] : raw.glow.map { $0.map { CardPoint(x: $0.x, y: $0.y + dy(.route)) } }
        var fill: PrintArea?
        if let f = raw.elevationFill, !hidden.contains(.elevation) {
            let d = dy(.elevation)
            fill = PrintArea(runs: f.runs.map { $0.map { CardPoint(x: $0.x, y: $0.y + d) } }, top: f.top + d, bottom: f.bottom + d)
        }
        var ranges: [PrintBlock: ClosedRange<Double>] = [:]
        for it in items {
            let b = it.shape.block, r = it.bounds
            if let old = ranges[b] { ranges[b] = min(old.lowerBound, r.minY)...max(old.upperBound, r.maxY) } else { ranges[b] = r.minY...r.maxY }
        }
        return PrintCardLayout(ink: ink, mode: mode, art: items.map(\.shape), glow: glow, elevationFill: fill,
                               blocks: ranges, issues: PrintChecks.issues(boxes))
    }

    static let blockGap = 12.0

    static func move(_ block: PrintBlock, by dy: Double, in arrangement: PrintArrangement, layout: PrintCardLayout) -> PrintArrangement {
        guard let r = layout.blocks[block], !arrangement.hidden.contains(block) else { return arrangement }
        let ordered = layout.blocks.filter { !arrangement.hidden.contains($0.key) }
            .sorted { ($0.value.lowerBound, $0.value.upperBound) < ($1.value.lowerBound, $1.value.upperBound) }
        guard let idx = ordered.firstIndex(where: { $0.key == block }) else { return arrangement }
        var lo = T.SafeArea.top - r.lowerBound
        var hi = (T.Export.height - T.SafeArea.bottom) - r.upperBound
        if let aboveBottom = ordered[..<idx].map(\.value.upperBound).max() { lo = max(lo, aboveBottom + blockGap - r.lowerBound) }
        if let belowTop = ordered[(idx + 1)...].map(\.value.lowerBound).min() { hi = min(hi, belowTop - blockGap - r.upperBound) }
        // never forced to jump: an arrangement that is already too tight can only move towards room
        let d = min(max(dy, min(lo, 0)), max(hi, 0))
        var out = arrangement
        out.offsets[block] = (arrangement.offsets[block] ?? 0) + d
        return out
    }
}
