import Foundation

/// Fully laid out map art. Renderers consume drawOrder and coordinates without
/// measuring text, choosing projections, or moving labels. Units are points, y down.
public struct MapScene: Sendable, Codable, Equatable {
    public enum Layer: String, Sendable, Codable, CaseIterable {
        case landFill, regionBorders, countryBorders, routeGlow, route, areaCircles, summit, labels
    }
    public struct Route: Sendable, Codable, Equatable {
        public enum Kind: String, Sendable, Codable { case recorded, gap }
        public var kind: Kind
        public var points: [PlanePoint]
    }
    public struct Outline: Sendable, Codable, Equatable {
        public enum Kind: String, Sendable, Codable { case country, region }
        public var kind: Kind
        public var place: PlaceRef
        /// Closed rings, even-odd fill; already clipped to the view plus 16 pt.
        public var rings: [[PlanePoint]]
    }
    public struct Area: Sendable, Codable, Equatable {
        public var center: PlanePoint
        public var radius: Double
        public var label: MapLabel?
    }
    public struct Summit: Sendable, Codable, Equatable {
        public var position: PlanePoint
        public var altitudeMeters: Double
        /// Reserved label box. The app formats the altitude and fits text in it.
        public var labelBounds: MapRect?
    }
    public struct AccessibilitySummary: Sendable, Codable, Equatable {
        public var orderedRegionNames: [String]
        public var countryCount: Int
        public var startName: String?
        public var endName: String?
        public var hasRecordingGap: Bool
    }
    public var width: Double
    public var height: Double
    public var projection: MapProjectionKind
    public var pointsPerMeter: Double
    public var routes: [Route]
    public var outlines: [Outline]
    public var regionLabels: [MapLabel]
    public var startArea: Area?
    public var endArea: Area?
    public var summit: Summit?
    public var drawOrder: [Layer]
    public var accessibilitySummary: AccessibilitySummary
}

public struct MapLabel: Sendable, Codable, Equatable {
    public var text: String
    public var placeCode: String?
    /// The renderer draws text centred in this box; no platform text layout pass.
    public var bounds: MapRect
    public var anchor: PlanePoint { bounds.center }
}

public struct MapRect: Sendable, Codable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public var center: PlanePoint { PlanePoint(x: x + width / 2, y: y + height / 2) }
    var corners: [PlanePoint] {
        [PlanePoint(x: x, y: y), PlanePoint(x: x + width, y: y),
         PlanePoint(x: x + width, y: y + height), PlanePoint(x: x, y: y + height)]
    }
    func expanded(_ amount: Double) -> MapRect {
        MapRect(x: x - amount, y: y - amount, width: width + 2 * amount, height: height + 2 * amount)
    }
    func contains(_ p: PlanePoint) -> Bool {
        p.x >= x && p.x <= x + width && p.y >= y && p.y <= y + height
    }
    func contains(_ rect: MapRect) -> Bool { rect.corners.allSatisfy(contains) }
    func intersects(_ other: MapRect) -> Bool {
        x <= other.x + other.width && x + width >= other.x &&
        y <= other.y + other.height && y + height >= other.y
    }
}
