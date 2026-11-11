import Foundation

/// Route acceptance and live GPS readiness are separate: delivery can be delayed or batched.
public struct LocationFixPolicy: Sendable {
    public static let freshnessInterval: TimeInterval = 15
    public let sessionStartedAt: Date

    public init(sessionStartedAt: Date) {
        self.sessionStartedAt = sessionStartedAt
    }

    /// Keep every valid fix collected in this capture session, regardless of delivery delay.
    /// Cached locations from before this session must not enter its route.
    public func accepts(timestamp: Date, horizontalAccuracy: Double) -> Bool {
        horizontalAccuracy >= 0 && timestamp >= sessionStartedAt
    }

    /// Freshness affects only live readiness, never whether an accepted route fix is saved.
    public func isRecent(timestamp: Date, receivedAt: Date) -> Bool {
        let age = receivedAt.timeIntervalSince(timestamp)
        return timestamp >= sessionStartedAt && age >= 0 && age < Self.freshnessInterval
    }
}
