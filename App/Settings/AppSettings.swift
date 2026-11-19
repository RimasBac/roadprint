import Foundation
import RoadPrintCore

/// Settings the driver can change. Kept in `UserDefaults` until the profile gets its own store (M7).
enum AppSettings {
    /// Raw `DistanceUnit` value. Empty until the driver picks one in You → Settings.
    static let distanceUnitKey = "RPDistanceUnit"

    /// Set once the paywall has opened after the 3rd trip (docs/pro.md). Never reset.
    static let paywallAfterThirdTripKey = "RPSeenPaywallAfterThirdTrip"

    static var hasSeenPaywallAfterThirdTrip: Bool {
        get { UserDefaults.standard.bool(forKey: paywallAfterThirdTripKey) }
        set { UserDefaults.standard.set(newValue, forKey: paywallAfterThirdTripKey) }
    }

    /// The driver's choice if there is one, else the default for the phone's region.
    static func distanceUnit(stored: String, fallback: DistanceUnit) -> DistanceUnit {
        DistanceUnit(rawValue: stored) ?? fallback
    }
}

extension AppEnvironment {
    /// The same environment with the driver's unit choice applied to the profile.
    func withDistanceUnit(stored: String) -> AppEnvironment {
        var copy = self
        copy.profile.distanceUnit = AppSettings.distanceUnit(stored: stored, fallback: profile.distanceUnit)
        return copy
    }
}
