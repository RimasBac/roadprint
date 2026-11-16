import Foundation

/// Career distance after a trip, derived from stored trips plus the profile's starting distance
/// (AGENTS.md §7b.5). Nothing here is a stored counter.
public struct CareerProgress: Sendable, Equatable {
    public var beforeMeters: Double
    public var afterMeters: Double
    public var goalMeters: Double

    public init(otherTripsMeters: Double, thisTripMeters: Double, startingMeters: Double, unit: DistanceUnit) {
        beforeMeters = max(0, startingMeters) + max(0, otherTripsMeters)
        afterMeters = beforeMeters + max(0, thisTripMeters)
        goalMeters = unit.millionMilestoneMeters
    }

    public var beforeFraction: Double { min(1, beforeMeters / goalMeters) }
    public var afterFraction: Double { min(1, afterMeters / goalMeters) }
    public var goalReached: Bool { afterMeters >= goalMeters }
    public var remainingMeters: Double { max(0, goalMeters - afterMeters) }
}

/// How the trip header and the stats row name the places of a trip.
public enum TripPlaceSummary {
    /// Names in route order: regions, or countries when the trip crosses more than one country
    /// or no region is known.
    public static func names(_ places: TripPlaces?) -> [String] {
        guard let places else { return [] }
        if places.countries.count > 1 || places.regions.isEmpty { return places.countries.map(\.name) }
        return places.regions.map(\.name)
    }

    /// At most three names; with more, the first, an ellipsis and the last.
    public static func headerNames(_ names: [String]) -> [String] {
        names.count > 3 ? [names[0], "…", names[names.count - 1]] : names
    }

    public enum Noun: String, Sendable, Equatable { case states, provinces, countries, regions }

    /// "states" for US and AU, "provinces" for CA, "countries" when more than one country.
    public static func noun(_ places: TripPlaces?) -> Noun {
        guard let places else { return .regions }
        if places.countries.count > 1 { return .countries }
        switch places.countries.first?.code.uppercased() {
        case "US", "AU": return .states
        case "CA": return .provinces
        default: return .regions
        }
    }

    public static func count(_ places: TripPlaces?) -> Int { names(places).count }
}
