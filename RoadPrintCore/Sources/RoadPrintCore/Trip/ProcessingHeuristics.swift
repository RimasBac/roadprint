import Foundation

/// Every processing threshold in one place (ADR 0003).
public struct ProcessingHeuristics: Sendable, Codable, Equatable {
    public static let simplifyToleranceRange: ClosedRange<Double> = 10...30

    /// Points with a negative or larger horizontal accuracy (metres) are dropped.
    public var maxHorizontalAccuracy: Double
    /// A point implying more than this speed (m/s) from the last kept point is a spike.
    public var spikeSpeed: Double
    /// A jump is a real relocation if this many following points are reachable from it.
    public var relocationConfirmCount: Int
    /// A gap is filled (a tunnel) only if its duration is at most this (seconds)...
    public var filledGapMaxDuration: TimeInterval
    /// ...its displacement is at most this (metres)...
    public var filledGapMaxDisplacement: Double
    /// ...and its implied speed is at most this (m/s).
    public var filledGapMaxSpeed: Double
    /// Douglas–Peucker tolerance in metres. Clamped to `simplifyToleranceRange`.
    public var simplifyTolerance: Double
    /// Privacy trim: metres cut from each end, before the per-trip offset (plan §4.3).
    public var trimBaseMeters: Double
    /// The per-trip offset is a deterministic value in `0..<trimJitterMeters`, seeded from the trip UUID.
    public var trimJitterMeters: Double
    /// A trip whose path is at most `2 × trim + shortTripMarginMeters` keeps no route, only one circle.
    public var shortTripMarginMeters: Double
    /// Gap detection threshold (`gapMinDisplacement`).
    public var recording: RecordingHeuristics

    public init(
        maxHorizontalAccuracy: Double = 100,
        spikeSpeed: Double = 75,
        relocationConfirmCount: Int = 3,
        filledGapMaxDuration: TimeInterval = 15 * 60,
        filledGapMaxDisplacement: Double = 25_000,
        filledGapMaxSpeed: Double = 45,
        simplifyTolerance: Double = 15,
        trimBaseMeters: Double = 8_000,
        trimJitterMeters: Double = 2_000,
        shortTripMarginMeters: Double = 2_000,
        recording: RecordingHeuristics = .default
    ) {
        self.trimBaseMeters = trimBaseMeters
        self.trimJitterMeters = trimJitterMeters
        self.shortTripMarginMeters = shortTripMarginMeters
        self.maxHorizontalAccuracy = maxHorizontalAccuracy
        self.spikeSpeed = spikeSpeed
        self.relocationConfirmCount = relocationConfirmCount
        self.filledGapMaxDuration = filledGapMaxDuration
        self.filledGapMaxDisplacement = filledGapMaxDisplacement
        self.filledGapMaxSpeed = filledGapMaxSpeed
        self.simplifyTolerance = simplifyTolerance
        self.recording = recording
    }

    public static let `default` = ProcessingHeuristics()
}
