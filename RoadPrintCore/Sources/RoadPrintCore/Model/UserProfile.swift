import Foundation

public enum DistanceUnit: String, Sendable, Codable, Equatable, CaseIterable {
    case kilometers
    case miles

    /// Miles for non-metric locales, kilometres otherwise.
    /// Pass `Locale.current.usesMetricSystem` from the app.
    public static func `default`(forUsesMetricSystem usesMetricSystem: Bool) -> DistanceUnit {
        usesMetricSystem ? .kilometers : .miles
    }
}

/// The local profile. No account, no login (AGENTS.md §7b.2).
public struct UserProfile: Sendable, Codable, Equatable, Identifiable {
    public var id: UUID
    public var displayName: String
    public var distanceUnit: DistanceUnit
    /// Miles or kilometres driven before using RoadPrint, stored in metres.
    public var startingCareerDistanceMeters: Double
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        displayName: String,
        distanceUnit: DistanceUnit,
        startingCareerDistanceMeters: Double = 0,
        createdAt: Date,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.distanceUnit = distanceUnit
        self.startingCareerDistanceMeters = startingCareerDistanceMeters
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}
