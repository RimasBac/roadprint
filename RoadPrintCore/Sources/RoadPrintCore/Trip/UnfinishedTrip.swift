import Foundation

/// What to offer when the app opens and a trip is still marked as recording
/// (plan §4.2, SCREENS S5 and S6).
public enum UnfinishedTripAction: Sendable, Codable, Equatable {
    /// Nothing odd: carry on recording.
    case none
    /// A long wait in one place: offer "End it there?". `stopStart` is the time
    /// of the last point before the wait. For a stop still in progress the
    /// duration runs up to `now`.
    case forgotToEnd(stopStart: Date, stopDuration: TimeInterval)
    /// The car moved with nothing recorded (iOS stopped the app): mark the trip
    /// partial and draw the gap dotted.
    case interrupted(gapStart: Date, gapEnd: Date)
}

extension TripAnalyzer {
    /// The long stop to offer to end the trip at: the earliest recorded or trailing stop.
    public func unfinishedStop(points: [TrackPoint], now: Date) -> LongStop? {
        let trip = Trip(createdAt: points.first?.timestamp ?? now, status: .recording, points: points)
        let candidates = longStops(in: points) + [trailingStop(of: trip, now: now)].compactMap { $0 }
        return candidates.min { $0.startIndex < $1.startIndex }
    }

    /// Decides what to offer for an open trip. A long stop wins over a gap: ending
    /// the trip there may drop the gap. If a gap remains before the cut, the
    /// trimmed trip is `partial` (see `endingTrip(_:at:)`).
    public func unfinishedTripAction(points: [TrackPoint], now: Date) -> UnfinishedTripAction {
        guard !points.isEmpty else { return .none }
        if let stop = unfinishedStop(points: points, now: now) {
            return .forgotToEnd(stopStart: points[stop.startIndex].timestamp, stopDuration: stop.duration)
        }
        if let gap = gaps(in: points).first {
            return .interrupted(gapStart: points[gap.startIndex].timestamp, gapEnd: points[gap.endIndex].timestamp)
        }
        return .none
    }

    /// Ends the trip at the start of `stop`: drops the points after it, sets
    /// `endedAt`, and marks it `partial` if a gap remains, else `completed`.
    /// Returns the trip unchanged if the stop does not fit its points.
    public func endingTrip(_ trip: Trip, at stop: LongStop, updatedAt: Date? = nil) -> Trip {
        guard trip.points.indices.contains(stop.startIndex) else { return trip }
        var trimmed = trip
        trimmed.points = Array(trip.points[...stop.startIndex])
        trimmed.endedAt = trimmed.points[stop.startIndex].timestamp
        trimmed.status = gaps(in: trimmed.points).isEmpty ? .completed : .partial
        if let updatedAt { trimmed.updatedAt = updatedAt }
        return trimmed
    }
}
