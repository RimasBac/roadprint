import Foundation

/// Two consecutive points the car drove between with nothing recorded.
public struct TripGap: Sendable, Codable, Equatable {
    public var startIndex: Int
    public var endIndex: Int
    public var displacementMeters: Double
    public var duration: TimeInterval
}

/// A long wait in one place. For a trailing stop `endIndex == startIndex`.
public struct LongStop: Sendable, Codable, Equatable {
    public var startIndex: Int
    public var endIndex: Int
    public var duration: TimeInterval
}

public struct TripStats: Sendable, Codable, Equatable {
    public var distanceMeters: Double
    public var movingTimeSeconds: TimeInterval
    public var elapsedSeconds: TimeInterval
    public var gapCount: Int

    public init(distanceMeters: Double, movingTimeSeconds: TimeInterval, elapsedSeconds: TimeInterval, gapCount: Int) {
        self.distanceMeters = distanceMeters
        self.movingTimeSeconds = movingTimeSeconds
        self.elapsedSeconds = elapsedSeconds
        self.gapCount = gapCount
    }
}

/// Pure functions over points. All thresholds come from `RecordingHeuristics`.
public struct TripAnalyzer: Sendable {
    public var heuristics: RecordingHeuristics

    public init(heuristics: RecordingHeuristics = .default) {
        self.heuristics = heuristics
    }

    /// Haversine sum across consecutive points, excluding gap legs.
    public func distance(of points: [TrackPoint]) -> Double {
        var total = 0.0
        for i in points.indices.dropFirst() {
            let d = Geo.distance(from: points[i - 1], to: points[i])
            if d < heuristics.gapMinDisplacement { total += d }
        }
        return total
    }

    /// Sum of Δt over consecutive pairs with 0 ≤ Δt ≤ `movingMaxInterval`.
    public func movingTime(of points: [TrackPoint]) -> TimeInterval {
        var total: TimeInterval = 0
        for i in points.indices.dropFirst() {
            let dt = points[i].timestamp.timeIntervalSince(points[i - 1].timestamp)
            if dt >= 0 && dt <= heuristics.movingMaxInterval { total += dt }
        }
        return total
    }

    /// Long waits in place between two recorded points.
    public func longStops(in points: [TrackPoint]) -> [LongStop] {
        var stops: [LongStop] = []
        for i in points.indices.dropFirst() {
            let dt = points[i].timestamp.timeIntervalSince(points[i - 1].timestamp)
            guard dt >= heuristics.longStopMinDuration else { continue }
            if Geo.distance(from: points[i - 1], to: points[i]) < heuristics.longStopMaxDisplacement {
                stops.append(LongStop(startIndex: i - 1, endIndex: i, duration: dt))
            }
        }
        return stops
    }

    /// For a recording trip whose last point is at least `longStopMinDuration` old.
    public func trailingStop(of trip: Trip, now: Date) -> LongStop? {
        guard trip.status == .recording, let last = trip.points.last else { return nil }
        let age = now.timeIntervalSince(last.timestamp)
        guard age >= heuristics.longStopMinDuration else { return nil }
        let index = trip.points.count - 1
        return LongStop(startIndex: index, endIndex: index, duration: age)
    }

    /// Consecutive pairs that moved at least `gapMinDisplacement`.
    public func gaps(in points: [TrackPoint]) -> [TripGap] {
        var result: [TripGap] = []
        for i in points.indices.dropFirst() {
            let d = Geo.distance(from: points[i - 1], to: points[i])
            if d >= heuristics.gapMinDisplacement {
                result.append(TripGap(
                    startIndex: i - 1,
                    endIndex: i,
                    displacementMeters: d,
                    duration: points[i].timestamp.timeIntervalSince(points[i - 1].timestamp)
                ))
            }
        }
        return result
    }

    public func stats(for trip: Trip) -> TripStats {
        // Processed trips have no raw points; the stored summary is the answer.
        if trip.points.isEmpty, let summary = trip.summary { return summary }
        let elapsed: TimeInterval
        if let start = trip.startedAt, let end = trip.effectiveEndedAt {
            elapsed = max(0, end.timeIntervalSince(start))
        } else {
            elapsed = 0
        }
        return TripStats(
            distanceMeters: distance(of: trip.points),
            movingTimeSeconds: movingTime(of: trip.points),
            elapsedSeconds: elapsed,
            gapCount: gaps(in: trip.points).count
        )
    }
}
