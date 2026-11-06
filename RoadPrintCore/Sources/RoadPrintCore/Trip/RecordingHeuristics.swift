import Foundation

/// Every recording threshold in one place.
public struct RecordingHeuristics: Sendable, Codable, Equatable {
    /// Intervals up to this long count as moving time (seconds). With a 100 m
    /// distance filter a parked car produces no points, so long intervals are stops.
    public var movingMaxInterval: TimeInterval
    /// A stop is at least this long (seconds).
    public var longStopMinDuration: TimeInterval
    /// ...and moved less than this (metres).
    public var longStopMaxDisplacement: Double
    /// A gap is a jump of at least this many metres between consecutive points.
    public var gapMinDisplacement: Double

    public init(
        movingMaxInterval: TimeInterval = 120,
        longStopMinDuration: TimeInterval = 2 * 3600,
        longStopMaxDisplacement: Double = 1_000,
        gapMinDisplacement: Double = 2_000
    ) {
        self.movingMaxInterval = movingMaxInterval
        self.longStopMinDuration = longStopMinDuration
        self.longStopMaxDisplacement = longStopMaxDisplacement
        self.gapMinDisplacement = gapMinDisplacement
    }

    public static let `default` = RecordingHeuristics()
}
