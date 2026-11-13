import Foundation

/// Where `MapSceneBuilder` may put the highest-point label and the region codes.
///
/// The defaults are the in-app trip map. A share card passes its own: its highest-point text is
/// smaller and sits closer to the marker, and no region code may land in the card's fades.
/// Placement stays in the core either way (AGENTS.md §7.5); the app only draws.
public struct MapLabelRules: Sendable, Equatable {
    /// The box reserved for the two-line highest-point label.
    public var summitWidth = 100.0
    public var summitHeight = 28.0
    /// From the marker's centre to the near side of the box.
    public var summitGap = 10.0
    /// How far the top of the box is above the marker's centre.
    public var summitRise = 14.0
    /// Vertical shifts to try, in order, on the right of the marker and then on the left.
    public var summitOffsets: [Double] = [0, 24, -24]
    public var summitRouteClearance = 6.0

    /// Region codes are placed only between these two heights of the view. Nil: the whole view.
    public var regionBand: ClosedRange<Double>?
    public var regionRouteClearance = 12.0
    /// Free space around a region code, to other labels and to the area circles.
    public var regionSpacing = 8.0

    public init() {}

    /// The trip map in the app.
    public static let map = MapLabelRules()
}
