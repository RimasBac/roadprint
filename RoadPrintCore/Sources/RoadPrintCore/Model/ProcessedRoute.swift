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

/// A circle that hides an exact place: the shown start or end of a trimmed trip.
public struct ApproximateArea: Sendable, Codable, Equatable {
    public var centerLatitude: Double
    public var centerLongitude: Double
    public var radiusMeters: Double

    public init(centerLatitude: Double, centerLongitude: Double, radiusMeters: Double) {
        self.centerLatitude = centerLatitude
        self.centerLongitude = centerLongitude
        self.radiusMeters = radiusMeters
    }
}

/// The cleaned, trimmed and simplified route kept after processing.
public struct ProcessedRoute: Sendable, Codable, Equatable {
    public var segments: [RouteSegment]
    /// Circle around the first retained point; the real start lies inside it (schema 2).
    /// For a short trip (`segments` is empty) `start == end`: one circle for the whole trip.
    public var start: ApproximateArea?
    /// Circle around the last retained point; the real end lies inside it (schema 2).
    public var end: ApproximateArea?
    /// The highest retained point after trimming, if any point has an altitude (schema 2).
    public var summit: RoutePoint?

    public init(
        segments: [RouteSegment], start: ApproximateArea? = nil,
        end: ApproximateArea? = nil, summit: RoutePoint? = nil
    ) {
        self.segments = segments
        self.start = start
        self.end = end
        self.summit = summit
    }
}

/// Distance, moving time, elapsed time and unfilled gap count. Computed once
/// from the full cleaned trace before trimming, then stored (ADR 0003).
public typealias TripSummaryStats = TripStats
