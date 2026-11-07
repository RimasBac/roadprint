import Foundation

/// One stored route vertex. No timestamp and no accuracy, by design: speed
/// can't be derived from stored data (plan §4.2, AGENTS.md §8, ADR 0003).
public struct RoutePoint: Sendable, Codable, Equatable {
    /// Degrees, WGS84.
    public var latitude: Double
    /// Degrees, WGS84.
    public var longitude: Double
    /// Metres above sea level, if known.
    public var altitude: Double?

    public init(latitude: Double, longitude: Double, altitude: Double? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
    }
}

/// A continuous run of the route. A break between segments is an unfilled
/// recording gap, drawn dotted.
public struct RouteSegment: Sendable, Codable, Equatable {
    public var points: [RoutePoint]

    public init(points: [RoutePoint]) {
        self.points = points
    }
}

/// The cleaned, trimmed and simplified route kept after processing.
public struct ProcessedRoute: Sendable, Codable, Equatable {
    public var segments: [RouteSegment]

    public init(segments: [RouteSegment]) {
        self.segments = segments
    }
}

/// Distance, moving time, elapsed time and unfilled gap count. Computed once
/// from the full cleaned trace before trimming, then stored (ADR 0003).
public typealias TripSummaryStats = TripStats
