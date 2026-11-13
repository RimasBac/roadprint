import Foundation

/// Only the route and approximate places needed to lay out a map. Constructing
/// from a share summary never recovers data that the privacy filter removed.
public struct MapSceneInput: Sendable, Equatable {
    public var segments: [RouteSegment]
    public var start: ApproximateArea?
    public var end: ApproximateArea?
    public var summit: RoutePoint?
    public var startLabel: String?
    public var endLabel: String?
    /// True for one trip: a break between two segments is a recording gap, drawn dotted.
    /// False when the segments are separate lines, as on the heat map of many trips.
    public var connectsSegments = true

    public init(segments: [RouteSegment], start: ApproximateArea? = nil,
                end: ApproximateArea? = nil, summit: RoutePoint? = nil,
                startLabel: String? = nil, endLabel: String? = nil) {
        self.segments = segments
        self.start = start
        self.end = end
        self.summit = summit
        self.startLabel = startLabel
        self.endLabel = endLabel
    }

    public init(trip: Trip, startLabel: String? = nil, endLabel: String? = nil) {
        self.init(segments: trip.route?.segments ?? [], start: trip.route?.start,
                  end: trip.route?.end, summit: trip.route?.summit,
                  startLabel: startLabel, endLabel: endLabel)
    }

    public init(summary: TripShareSummary, startLabel: String? = nil, endLabel: String? = nil) {
        self.init(segments: summary.route ?? [], start: summary.start, end: summary.end,
                  summit: summary.summit, startLabel: startLabel, endLabel: endLabel)
    }
}
