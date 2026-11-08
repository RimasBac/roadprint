import Foundation

/// A calendar date with no time of day.
public struct ShareDay: Sendable, Codable, Equatable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }
}

public struct ShareOptions: Sendable {
    public var includeRoute: Bool
    public var timeZone: TimeZone

    public init(includeRoute: Bool, timeZone: TimeZone = .current) {
        self.includeRoute = includeRoute
        self.timeZone = timeZone
    }
}

/// The only thing that leaves a trip (AGENTS.md §7b.3). **Share cards render only
/// from this type, never from a `Trip`**, so a future feed reuses the same privacy
/// rules. It has no timestamps, accuracy or speed; the route is present only when
/// `ShareOptions.includeRoute` is set, and is coarsened again (50 m, 1e-4°, whole metres).
public struct TripShareSummary: Sendable, Codable, Equatable {
    public static let currentSchemaVersion = 1
    static let simplifyTolerance = 50.0
    static let coordinateScale = 1e4

    public var schemaVersion: Int
    public var tripID: UUID
    public var day: ShareDay
    public var distanceMeters: Double
    public var movingTimeSeconds: Double
    public var places: TripPlaces
    public var mainRoad: MainRoad?
    /// Empty until badges exist (M7).
    public var badgeIDs: [String]
    public var summitAltitudeMeters: Double?
    public var route: [RouteSegment]?
    public var start: ApproximateArea?
    public var end: ApproximateArea?
    public var summit: RoutePoint?

    /// Nil for a trip that isn't processed (`route == nil && summary == nil`).
    public static func make(from trip: Trip, options: ShareOptions) -> TripShareSummary? {
        guard trip.route != nil || trip.summary != nil else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = options.timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: trip.startedAt ?? trip.createdAt)
        let day = ShareDay(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)

        var out = TripShareSummary(
            schemaVersion: currentSchemaVersion, tripID: trip.id, day: day,
            distanceMeters: trip.summary?.distanceMeters ?? 0,
            movingTimeSeconds: trip.summary?.movingTimeSeconds ?? 0,
            places: trip.places ?? TripPlaces(), mainRoad: trip.mainRoad, badgeIDs: [],
            summitAltitudeMeters: trip.route?.summit?.altitude.map { $0.rounded() })
        if options.includeRoute, let r = trip.route {
            out.route = r.segments.map { seg in
                var pts = DouglasPeucker.simplify(seg.points, tolerance: simplifyTolerance).map(coarsen)
                pts = pts.enumerated().filter { $0.offset == 0 || $0.element != pts[$0.offset - 1] }.map(\.element)
                return RouteSegment(points: pts)
            }
            out.start = r.start.map(coarsen)
            out.end = r.end.map(coarsen)
            out.summit = r.summit.map(coarsen)
        }
        return out
    }

    private static func round4(_ v: Double) -> Double { (v * coordinateScale).rounded() / coordinateScale }

    private static func coarsen(_ p: RoutePoint) -> RoutePoint {
        RoutePoint(latitude: round4(p.latitude), longitude: round4(p.longitude), altitude: p.altitude.map { $0.rounded() })
    }

    private static func coarsen(_ a: ApproximateArea) -> ApproximateArea {
        ApproximateArea(centerLatitude: round4(a.centerLatitude), centerLongitude: round4(a.centerLongitude), radiusMeters: a.radiusMeters)
    }
}
