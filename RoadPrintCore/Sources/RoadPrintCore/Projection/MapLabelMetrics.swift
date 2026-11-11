import Foundation

/// Deterministic estimates for map labels. These average advances approximate
/// Inter at the sizes and tracking specified by Design/tokens.json; they are
/// deliberately independent of platform font APIs.
public enum MapLabelMetrics {
    public enum Style: Sendable {
        case region
        case map
    }

    public struct Size: Sendable, Equatable {
        public let width: Double
        public let height: Double
    }

    public static func measure(_ text: String, style: Style) -> Size {
        let count = text.count
        guard count > 0 else { return Size(width: 0, height: 0) }
        let advance: Double
        let tracking: Double
        let height: Double
        switch style {
        case .region: (advance, tracking, height) = (7.8, 2.5, 13)
        case .map: (advance, tracking, height) = (6.6, 0, 12)
        }
        return Size(width: Double(count) * advance + Double(count - 1) * tracking,
                    height: height)
    }
}
