import Foundation

/// Composes the pure pipeline stages: clean → places → (trim, later) → simplify.
/// Later stages (main road) are separate issues (ADR 0003).
public struct TripProcessor: Sendable {
    public var heuristics: ProcessingHeuristics
    /// When set, the trip gets `places`. Nil leaves `places` untouched.
    public var placeIndex: PlaceIndex?
    /// When set, the trip gets `mainRoad` (nil if no road matches enough of the route).
    public var roadIndex: RoadIndex?

    public init(heuristics: ProcessingHeuristics = .default, placeIndex: PlaceIndex? = nil, roadIndex: RoadIndex? = nil) {
        self.heuristics = heuristics
        self.placeIndex = placeIndex
        self.roadIndex = roadIndex
    }

    /// Returns the trip with `points` emptied and the processed fields set.
    public func process(_ trip: Trip) -> Trip {
        let cleaned = RouteCleaner(heuristics: heuristics).clean(trip.points)
        let all = cleaned.points

        let analyzer = TripAnalyzer(heuristics: heuristics.recording)
        var distance = 0.0
        var moving: TimeInterval = 0
        for segment in cleaned.segments {
            // Filled tunnel gaps count as a straight line; unfilled gaps are not driven distance we know.
            for i in segment.indices.dropFirst() { distance += Geo.distance(from: segment[i - 1], to: segment[i]) }
            moving += analyzer.movingTime(of: segment)
        }
        let elapsed = (all.last?.timestamp).flatMap { end in
            all.first.map { end.timeIntervalSince($0.timestamp) }
        } ?? 0

        // Places run on the dense cleaned trace, before trimming, so regions only the trimmed
        // ends cross are still listed. Countries and regions are coarse enough for privacy.
        let places = placeIndex?.places(
            along: all.map { RoutePoint(latitude: $0.latitude, longitude: $0.longitude) })

        // Trim goes here (privacy-trim issue), on the dense cleaned trace.
        let routeSegments = cleaned.segments.map { seg in
            RouteSegment(points: seg.map { RoutePoint(latitude: $0.latitude, longitude: $0.longitude, altitude: $0.altitude) })
        }
        // The main road runs on the dense route after trim, not the simplified one. Until the trim
        // stage lands this is the whole cleaned route.
        let mainRoad = roadIndex.map { MainRoadGuesser(index: $0).guess(segments: routeSegments.map(\.points)) }
        let simplified = DouglasPeucker.simplify(
            ProcessedRoute(segments: routeSegments), tolerance: heuristics.simplifyTolerance)

        var result = trip
        result.storedStartedAt = trip.points.first?.timestamp ?? trip.storedStartedAt
        result.summary = TripSummaryStats(
            distanceMeters: distance, movingTimeSeconds: moving,
            elapsedSeconds: elapsed, gapCount: cleaned.unfilledGapCount)
        result.route = simplified.segments.isEmpty ? nil : simplified
        result.status = cleaned.status
        if let places { result.places = places }
        if let mainRoad { result.mainRoad = mainRoad }  // Optional<Optional>: set only when a road index ran; nil clears a stale value
        result.points = []
        return result
    }
}
