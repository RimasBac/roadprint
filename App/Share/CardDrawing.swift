import CoreText
import SwiftUI
import RoadPrintCore

/// Measures card text with the bundled fonts through CoreText, for the core's card layouts
/// (`CardTextMeasuring`). Ink boxes match what `CardDraw.text` draws: same font, size and tracking.
final class CoreTextMeasurer: CardTextMeasuring, @unchecked Sendable {
    static let shared = CoreTextMeasurer()

    private struct Key: Hashable {
        let text: String
        let style: CardTextStyle
    }

    // Guarded by `lock`: CoreText objects are immutable once made, the caches are not.
    private let lock = NSLock()
    private var fonts: [String: CTFont] = [:]
    private var boxes: [Key: CardInkBox] = [:]

    /// "Inter-SemiBold", "BarlowCondensed-Bold": the PostScript names the app bundles.
    static func postScriptName(family: String, weight: Int) -> String {
        let suffix: String
        switch weight {
        case ..<450: suffix = "Regular"
        case ..<550: suffix = "Medium"
        case ..<650: suffix = "SemiBold"
        default: suffix = "Bold"
        }
        return family.replacingOccurrences(of: " ", with: "") + "-" + suffix
    }

    func ink(_ text: String, style: CardTextStyle) -> CardInkBox {
        lock.lock()
        defer { lock.unlock() }
        let key = Key(text: text, style: style)
        if let box = boxes[key] { return box }
        let name = Self.postScriptName(family: style.family, weight: style.weight)
        let fontKey = "\(name)@\(style.size)"
        let font = fonts[fontKey] ?? CTFontCreateWithName(name as CFString, CGFloat(style.size), nil)
        fonts[fontKey] = font
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTKernAttributeName as String): style.tracking,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let bounds = CTLineGetImageBounds(line, nil)
        let box = bounds.isNull || bounds.isEmpty ? CardInkBox.empty
            : CardInkBox(x: Double(bounds.minX), width: Double(bounds.width), top: Double(-bounds.maxY), bottom: Double(-bounds.minY))
        boxes[key] = box
        return box
    }
}

extension Color {
    /// A colour from a token's sRGB hex string ("#rrggbb"), as the core's `CardTokens` carry them.
    init(cardHex hex: String, opacity: Double = 1) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let value = UInt32(digits, radix: 16) ?? 0
        self.init(.sRGB,
                  red: Double((value >> 16) & 0xff) / 255,
                  green: Double((value >> 8) & 0xff) / 255,
                  blue: Double(value & 0xff) / 255,
                  opacity: opacity)
    }
}

/// Canvas helpers shared by the Print and Terrain cards. Card geometry is in export pixels
/// (1080 × 1920); `scale` maps it to the canvas (one point = three pixels on a 360 × 640 card).
enum CardDraw {
    static func point(_ p: CardPoint, _ scale: CGFloat) -> CGPoint {
        CGPoint(x: p.x * scale, y: p.y * scale)
    }

    static func polyline(_ run: [CardPoint], _ scale: CGFloat) -> Path {
        var path = Path()
        guard let first = run.first else { return path }
        path.move(to: point(first, scale))
        for p in run.dropFirst() { path.addLine(to: point(p, scale)) }
        return path
    }

    static func font(_ style: CardTextStyle, _ scale: CGFloat) -> Font {
        .custom(CoreTextMeasurer.postScriptName(family: style.family, weight: style.weight), fixedSize: style.size * scale)
    }

    /// Draws `string` with its origin at `x` on `baseline` (SVG `<text>` semantics), anchored.
    static func text(_ string: String, style: CardTextStyle, x: Double, baseline: Double, anchor: CardTextAnchor,
                     color: Color, scale: CGFloat, in context: inout GraphicsContext) {
        let resolved = context.resolve(Text(verbatim: string)
            .font(font(style, scale))
            .tracking(style.tracking * scale)
            .foregroundColor(color))
        let size = resolved.measure(in: CGSize(width: 4_000, height: 1_000))
        let left: CGFloat
        switch anchor {
        case .start: left = x * scale
        case .middle: left = x * scale - size.width / 2
        case .end: left = x * scale - size.width
        }
        let top = baseline * scale - resolved.firstBaseline(in: size)
        context.draw(resolved, at: CGPoint(x: left, y: top), anchor: .topLeading)
    }

    static func circle(_ center: CardPoint, radius: Double, _ scale: CGFloat) -> Path {
        let c = point(center, scale), r = radius * scale
        return Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }

    /// A dash pattern in export pixels as a stroke style; a zero dash draws round dots.
    static func stroke(width: Double, dash: [Double]?, _ scale: CGFloat) -> StrokeStyle {
        guard let dash else { return StrokeStyle(lineWidth: width * scale, lineCap: .round, lineJoin: .round) }
        return StrokeStyle(lineWidth: width * scale, lineCap: .round, lineJoin: .round,
                           dash: dash.map { max($0, 0.01) * scale })
    }
}
