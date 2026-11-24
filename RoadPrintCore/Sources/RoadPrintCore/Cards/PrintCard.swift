import Foundation

// Print share card v3 (Design/cards/print/README.md): the layout engine. A Foundation-only port of
// Tools/design/print-card.mjs `build()`. The app draws the result; it never places anything itself.
//
// CONTRACT (owned by the app integration): the public types and signatures in this file are what
// App/Share uses. Implement the bodies; add internal helpers freely (other files are fine). Change a
// public signature only if it is wrong, and say why in your report.

public enum PrintInk: String, Sendable, CaseIterable, Codable {
    /// White type, amber route, ink shadow: dark and busy photos (v2).
    case light
    /// Dark type, day route, white halo: bright photos (`print.inkDark`).
    case dark
}

public enum PrintLayoutMode: String, Sendable, CaseIterable, Codable {
    /// The board's v2 layout: header at the top, route, elevation strip, number and stats.
    case full
    /// Everything below y 690 (`print.sticker`): wordmark and sign, route, title, date, number, stats.
    case sticker
}

/// The four blocks a driver can move or hide in the editor (README "Editor concept").
public enum PrintBlock: String, Sendable, CaseIterable, Codable {
    /// Wordmark, title, date and road sign (sticker: wordmark and sign sit with the route block).
    case header
    /// Route, rings, area labels and the highest-point dot.
    case route
    /// The ELEVATION kicker, the strip and its highest-point label. Full layout only.
    case elevation
    /// The big number, its unit, the hairline and the stats row.
    case stats
}

/// The colour roles the app maps to the ink's colours (light: `print.color`, `color.*`;
/// dark: `print.inkDark.color`).
public enum PrintPaint: String, Sendable, Codable {
    case text, muted, accent, route, casing, gap, ink
}

/// Everything the card shows, already localized and formatted by the app from a `TripShareSummary`.
public struct PrintCardInput: Sendable {
    /// Title places, e.g. "Utah", "California". The layout upper-cases them.
    public var from: String
    public var to: String
    /// "Wednesday, November 4".
    public var date: String
    /// "RoadPrint".
    public var wordmark: String
    /// Area labels at the rings, e.g. "Salt Lake City area". Upper-cased by the layout.
    public var startLabel: String
    public var endLabel: String
    /// The privacy-filtered route from the share summary; each segment break is a recording gap.
    /// Nil or empty with `hideRoute` false: treated as hide route.
    public var route: [RouteSegment]?
    /// Hide route: the two named places' city centres (never trip points).
    public var hideRoute: Bool
    public var placeCenters: [GeoPoint]
    /// "649" and "MILES" (the layout does not upper-case these).
    public var distanceValue: String
    public var distanceUnit: String
    /// Up to three (label, value) pairs, in order: moving time, regions, career distance or highest
    /// point. Labels are upper-cased by the layout.
    public var stats: [(label: String, value: String)]
    /// "ELEVATION" and "HIGHEST POINT · 7,102 FT" for the strip.
    public var elevationKicker: String
    public var summitLabel: String
    /// Width ÷ height of the road sign the app will draw, or nil for none. The sign is drawn at
    /// `print.layout.signHeight` (sticker: `print.sticker.layout.signHeight`), right-aligned at the safe edge.
    public var signAspect: Double?

    public init(from: String, to: String, date: String, wordmark: String, startLabel: String, endLabel: String,
                route: [RouteSegment]?, hideRoute: Bool, placeCenters: [GeoPoint],
                distanceValue: String, distanceUnit: String, stats: [(label: String, value: String)],
                elevationKicker: String, summitLabel: String, signAspect: Double?) {
        self.from = from; self.to = to; self.date = date; self.wordmark = wordmark
        self.startLabel = startLabel; self.endLabel = endLabel
        self.route = route; self.hideRoute = hideRoute; self.placeCenters = placeCenters
        self.distanceValue = distanceValue; self.distanceUnit = distanceUnit; self.stats = stats
        self.elevationKicker = elevationKicker; self.summitLabel = summitLabel; self.signAspect = signAspect
    }
}

/// One text run to draw: `string` is final (already cased); the app sets it at `x` on `baseline`.
public struct PrintText: Sendable, Hashable {
    /// The SVG id, e.g. "title", "date", "distance", "stat-1-value".
    public var id: String
    public var string: String
    public var style: CardTextStyle
    public var x: Double
    public var baseline: Double
    public var anchor: CardTextAnchor
    public var paint: PrintPaint
    public var opacity: Double
    public var block: PrintBlock
}

/// One mark to draw, in draw order. Lines are already smoothed (Catmull-Rom sampled densely) and
/// simplified; the app strokes them as polylines with round caps and joins unless `dash` says otherwise.
public enum PrintShape: Sendable, Hashable {
    case text(PrintText)
    /// A polyline per run. `dash` nil: solid, round caps. Non-nil: [dash, gap] with round caps
    /// (`[0, 16]` draws round dots every 16 px).
    case stroke(id: String, runs: [[CardPoint]], width: Double, paint: PrintPaint, opacity: Double, dash: [Double]?, block: PrintBlock)
    case fillCircle(id: String, center: CardPoint, radius: Double, paint: PrintPaint, opacity: Double, block: PrintBlock)
    /// A ring: dashed when `dash` is non-nil.
    case strokeCircle(id: String, center: CardPoint, radius: Double, width: Double, paint: PrintPaint, opacity: Double, dash: [Double]?, block: PrintBlock)
    /// A filled circle with an outline (the highest-point dots).
    case dot(id: String, center: CardPoint, radius: Double, fill: PrintPaint, stroke: PrintPaint, strokeWidth: Double, strokeOpacity: Double, block: PrintBlock)
    /// The arrow in the title, a polyline with round caps.
    case arrow(points: [CardPoint], width: Double, paint: PrintPaint, block: PrintBlock)
    /// The road sign's box: the app draws `RoadSign` into it.
    case sign(rect: CardRect, block: PrintBlock)

    public var block: PrintBlock {
        switch self {
        case .text(let t): t.block
        case .stroke(_, _, _, _, _, _, let b), .fillCircle(_, _, _, _, _, let b), .strokeCircle(_, _, _, _, _, _, _, let b),
             .dot(_, _, _, _, _, _, _, let b), .arrow(_, _, _, let b), .sign(_, let b): b
        }
    }
}

/// The elevation strip's fill: closed areas under the line, filled with `paint` fading from
/// `print.elevation.fillTopOpacity` at `top` to `fillBottomOpacity` at `bottom`. Drawn above the shadow.
public struct PrintArea: Sendable, Hashable {
    public var runs: [[CardPoint]]
    public var top: Double
    public var bottom: Double
}

/// A laid-out card. Draw order (README "Layer order" and "How the app draws it natively"):
/// 1. the shadow of `art` (light: ink, wide + tight passes; dark: white halo; `PrintCardLayout.shadow`),
/// 2. `glow` (route runs, blurred; empty for dark ink), 3. `elevationFill`, 4. `art`.
public struct PrintCardLayout: Sendable {
    public var ink: PrintInk
    public var mode: PrintLayoutMode
    public var art: [PrintShape]
    public var glow: [[CardPoint]]
    public var elevationFill: PrintArea?
    /// Vertical extent of each visible block (ink boxes and marks, export px), after the arrangement.
    public var blocks: [PrintBlock: ClosedRange<Double>]
    /// Safe-area and collision problems (`print-card.mjs` `check`); empty when the card is clean.
    public var issues: [String]
}

/// Where the driver moved blocks and which ones they hid (the editor). Offsets are export px, y down.
public struct PrintArrangement: Sendable, Hashable, Codable {
    public var offsets: [PrintBlock: Double]
    public var hidden: Set<PrintBlock>
    public init(offsets: [PrintBlock: Double] = [:], hidden: Set<PrintBlock> = []) {
        self.offsets = offsets; self.hidden = hidden
    }
    public static let standard = PrintArrangement()
}

public enum PrintCard {
    /// Lays out the card. Port of `build()` in Tools/design/print-card.mjs, with `MODE` = (ink, mode):
    /// the same fitting, wrapping, label placement and checks, the tokens from `CardTokens.Print`.
    /// `arrangement` then moves blocks by their offsets and drops hidden ones (an arrangement from
    /// `PrintCard.move` is always valid; others are applied as given and reported in `issues`).
    public static func layout(_ input: PrintCardInput, ink: PrintInk, mode: PrintLayoutMode,
                              arrangement: PrintArrangement = .standard,
                              measurer: some CardTextMeasuring) -> PrintCardLayout {
        var builder = PrintCardBuilder(measurer: measurer, ink: ink, mode: mode)
        let raw = builder.build(input)
        return PrintArranger.arrange(raw, ink: ink, mode: mode, arrangement: arrangement)
    }

    /// The editor: `block` dragged by `dy` from `arrangement`. Vertical only; the block stops at the
    /// safe area (top 220, bottom 1600) and at its neighbours' edges (12 px apart), so blocks never
    /// overlap or swap order. Returns the new arrangement.
    public static func move(_ block: PrintBlock, by dy: Double, in arrangement: PrintArrangement,
                            layout: PrintCardLayout) -> PrintArrangement {
        PrintArranger.move(block, by: dy, in: arrangement, layout: layout)
    }

    /// Whether the driver may hide `block` now: the header (with the wordmark) never; the route and
    /// the stats not both; the elevation strip always.
    public static func canHide(_ block: PrintBlock, in arrangement: PrintArrangement) -> Bool {
        switch block {
        case .header: false
        case .elevation: true
        case .route: !arrangement.hidden.contains(.stats)
        case .stats: !arrangement.hidden.contains(.route)
        }
    }

    /// The shadow recipe for `ink` (light: `print.shadow`; dark: `print.inkDark.shadow`), and its colour.
    public static func shadow(for ink: PrintInk) -> (color: String, opacity: Double, blur: Double, offsetY: Double,
                                                      tightOpacity: Double, tightBlur: Double, tightOffsetY: Double, tightSpread: Double) {
        switch ink {
        case .light:
            typealias S = CardTokens.Print.Shadow
            return (CardTokens.Print.Color.ink, S.opacity, S.blur, S.offsetY, S.tightOpacity, S.tightBlur, S.tightOffsetY, S.tightSpread)
        case .dark:
            typealias S = CardTokens.Print.InkDark.Shadow
            return (CardTokens.Print.InkDark.Color.halo, S.opacity, S.blur, S.offsetY, S.tightOpacity, S.tightBlur, S.tightOffsetY, S.tightSpread)
        }
    }

    /// sRGB hex for a paint role in `ink`.
    public static func color(_ paint: PrintPaint, ink: PrintInk) -> String {
        switch ink {
        case .light:
            switch paint {
            case .text: return CardTokens.Color.text
            case .muted: return CardTokens.Print.Color.muted
            case .accent, .route: return CardTokens.Color.route
            case .casing, .ink: return CardTokens.Print.Color.ink
            case .gap: return CardTokens.Color.textSecondary
            }
        case .dark:
            typealias D = CardTokens.Print.InkDark.Color
            switch paint {
            case .text: return D.text
            case .muted: return D.muted
            case .accent: return D.accent
            case .route: return D.route
            case .casing: return D.casing
            case .gap: return D.gap
            case .ink: return D.halo
            }
        }
    }
}
