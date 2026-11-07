import Foundation

/// Composes the pure pipeline stages: clean → (trim, later) → simplify.
/// Later stages (places, main road) are separate issues (ADR 0003).
public struct TripProcessor: Sendable {
    public var heuristics: ProcessingHeuristics

    public init(heuristics: ProcessingHeuristics = .default) {
        self.heuristics = heuristics
    }

    /// Returns the trip with `points` emptied and the processed fields set.
    public func process(_ trip: Trip) -> Trip {
        // Already processed: the raw points are gone, so rebuilding would wipe route and summary.
        guard !trip.points.isEmpty else { return trip }
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
        // Same span as TripAnalyzer.stats: first raw point to endedAt (or the last raw point).
        let end = trip.effectiveEndedAt
        let elapsed = trip.points.first.flatMap { first in
            end.map { max(0, $0.timeIntervalSince(first.timestamp)) }
        } ?? 0

        // Trim goes here (privacy-trim issue), on the dense cleaned trace.
        let routeSegments = cleaned.segments.map { seg in
            RouteSegment(points: seg.map { RoutePoint(latitude: $0.latitude, longitude: $0.longitude, altitude: $0.altitude) })
        }
        let simplified = DouglasPeucker.simplify(
            ProcessedRoute(segments: routeSegments), tolerance: heuristics.simplifyTolerance)

        var result = trip
        result.storedStartedAt = trip.points.first?.timestamp ?? trip.storedStartedAt
        result.summary = TripSummaryStats(
            distanceMeters: distance, movingTimeSeconds: moving,
            elapsedSeconds: elapsed, gapCount: cleaned.unfilledGapCount)
        result.route = simplified.segments.isEmpty ? nil : simplified
        result.endedAt = end  // survives points = []
        result.status = cleaned.status
        result.points = []
        return result
    }
}
