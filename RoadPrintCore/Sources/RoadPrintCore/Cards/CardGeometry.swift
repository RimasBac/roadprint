import Foundation

/// A point on a share card in export pixels (1080 × 1920), y down.
public struct CardPoint: Sendable, Hashable, Codable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// A rectangle on a share card in export pixels, y down.
public struct CardRect: Sendable, Hashable, Codable {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double
    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX; self.minY = minY; self.maxX = maxX; self.maxY = maxY
    }
    public var width: Double { maxX - minX }
    public var height: Double { maxY - minY }
    public func offsetBy(dx: Double = 0, dy: Double) -> CardRect {
        CardRect(minX: minX + dx, minY: minY + dy, maxX: maxX + dx, maxY: maxY + dy)
    }
    public func intersects(_ other: CardRect, margin: Double = 0) -> Bool {
        minX < other.maxX + margin && maxX > other.minX - margin && minY < other.maxY + margin && maxY > other.minY - margin
    }
}

/// A geographic point in degrees.
public struct GeoPoint: Sendable, Hashable, Codable {
    public var latitude: Double
    public var longitude: Double
    public init(latitude: Double, longitude: Double) { self.latitude = latitude; self.longitude = longitude }
}

/// One text run as the card draws it: the font from the tokens at a size in export pixels.
public struct CardTextStyle: Sendable, Hashable {
    /// "Inter" or "Barlow Condensed".
    public var family: String
    public var weight: Int
    public var size: Double
    /// Extra space after every character, export pixels (SVG letter-spacing, CoreText kern).
    public var tracking: Double
    public init(family: String, weight: Int, size: Double, tracking: Double) {
        self.family = family; self.weight = weight; self.size = size; self.tracking = tracking
    }
    public init(_ token: CardTypeToken, size: Double? = nil) {
        self.init(family: token.family, weight: token.weight, size: size ?? token.size, tracking: token.tracking)
    }
}

/// The ink box of a text run set at x = 0 on baseline 0 (y down): where its glyphs actually draw.
/// `x` is the left side bearing of the first glyph (a "1" starts further right than a "6").
public struct CardInkBox: Sendable, Hashable {
    public var x: Double
    public var width: Double
    /// Negative: above the baseline.
    public var top: Double
    public var bottom: Double
    public init(x: Double, width: Double, top: Double, bottom: Double) {
        self.x = x; self.width = width; self.top = top; self.bottom = bottom
    }
    public static let empty = CardInkBox(x: 0, width: 0, top: 0, bottom: 0)
}

/// Measures text with the real fonts. The app implements it with CoreText; tests use a fixed-advance
/// fake. The core never measures text itself, so layout stays Foundation-only (AGENTS.md §2, §7.5).
public protocol CardTextMeasuring: Sendable {
    func ink(_ text: String, style: CardTextStyle) -> CardInkBox
}

public enum CardTextAnchor: String, Sendable, Hashable, Codable {
    case start, middle, end
}

public enum CardText {
    /// Upper case as the cards set it: German rules, and ß as SS (`print-card.mjs` `cased`).
    public static func uppercased(_ s: String) -> String {
        s.uppercased(with: Locale(identifier: "de_DE")).replacingOccurrences(of: "ß", with: "SS")
    }
}
