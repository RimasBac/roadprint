import Foundation

public enum DistanceUnit: String, Sendable, Codable, Equatable, CaseIterable {
    case kilometers
    case miles

    static let milesRegionCodes: Set<String> = ["US", "GB", "LR", "MM", "PR", "GU", "VI", "AS", "MP"]

    /// Miles for the US, GB, LR, MM and the US territories (PR, GU, VI, AS, MP), kilometres otherwise and when nil.
    /// Pass an ISO 3166-1 alpha-2 region code, e.g. `Locale.current.region?.identifier`.
    public static func `default`(forRegionCode regionCode: String?) -> DistanceUnit {
        guard let code = regionCode?.uppercased() else { return .kilometers }
        return milesRegionCodes.contains(code) ? .miles : .kilometers
    }

    /// Miles for non-metric locales, kilometres otherwise.
    @available(*, deprecated, message: "Use default(forRegionCode:); the UK reports metric but drives in miles.")
    public static func `default`(forUsesMetricSystem usesMetricSystem: Bool) -> DistanceUnit {
        usesMetricSystem ? .kilometers : .miles
    }

    public static let metersPerMile = 1609.344

    /// Distance in this unit, unrounded.
    public func convert(meters: Double) -> Double {
        switch self {
        case .kilometers: meters / 1000
        case .miles: meters / Self.metersPerMile
        }
    }

    /// Display rule shared with Android: below 10 one decimal, otherwise whole numbers.
    public func displayValue(meters: Double) -> Double {
        let v = convert(meters: meters)
        return abs(v) < 10 ? (v * 10).rounded() / 10 : v.rounded()
    }

    /// 1,000,000 of this unit, in metres (both are milestones, plan §4.6).
    public var millionMilestoneMeters: Double {
        switch self {
        case .kilometers: 1_000_000_000
        case .miles: 1_000_000 * Self.metersPerMile
        }
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
