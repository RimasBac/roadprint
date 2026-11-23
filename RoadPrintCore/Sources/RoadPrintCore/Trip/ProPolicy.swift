import Foundation

public enum Entitlement: Equatable, Sendable {
    case free
    case pro
}

/// What Pro adds (board, 2026-11-20). Free keeps unlimited recording, the 30-day map and the
/// picture card in every style.
public enum ProFeature: CaseIterable, Sendable {
    case allTimeMap
    case mapFilters
    /// The trip card as a video that draws the route.
    case videoCard
}

public enum PaywallTrigger: CaseIterable, Sendable {
    case tappedAllTime
    case tappedFilter
    case tappedVideo
    case tripEnded
}

public enum ProPolicy {
    public static func isAllowed(_ feature: ProFeature, entitlement: Entitlement) -> Bool {
        switch feature {
        case .allTimeMap, .mapFilters, .videoCard:
            return entitlement == .pro
        }
    }

    /// Free My Map shows a rolling 30 × 24 hours, including both endpoints. Pro has no time limit.
    public static func heatWindow(entitlement: Entitlement, now: Date) -> DateInterval? {
        guard entitlement == .free else { return nil }
        return DateInterval(start: now.addingTimeInterval(-30 * 24 * 60 * 60), end: now)
    }

    /// Apply the entitlement window before choosing map areas, calculating totals or drawing heat.
    public static func filterHeatTrips<Trip>(
        _ trips: [Trip], datedBy date: KeyPath<Trip, Date>, entitlement: Entitlement, now: Date
    ) -> [Trip] {
        guard let window = heatWindow(entitlement: entitlement, now: now) else { return trips }
        return trips.filter { window.contains($0[keyPath: date]) }
    }

    public static func shouldShowPaywall(
        trigger: PaywallTrigger, completedTrips: Int, hasSeenAfterThirdTrip: Bool, entitlement: Entitlement
    ) -> Bool {
        guard entitlement == .free, completedTrips > 0 else { return false }
        switch trigger {
        case .tappedAllTime, .tappedFilter, .tappedVideo:
            return true
        case .tripEnded:
            return completedTrips == 3 && !hasSeenAfterThirdTrip
        }
    }
}
