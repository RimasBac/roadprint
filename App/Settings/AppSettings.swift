import Foundation
import RoadPrintCore

/// Settings the driver can change. Kept in `UserDefaults` until the profile gets its own store (M7).
enum AppSettings {
    /// Raw `DistanceUnit` value. Empty until the driver picks one in You → Settings.
    static let distanceUnitKey = "RPDistanceUnit"
    static let didCompleteFirstLaunchKey = "RPDidCompleteFirstLaunch"

    static let helpURLs = (
        privacy: URL(string: "https://rimasbac.github.io/roadprint/privacy.html")!,
        support: URL(string: "https://rimasbac.github.io/roadprint/support.html")!
    )

    /// Whether iCloud sync is on (ADR 0005). Unset means the default: on in release builds. Debug builds
    /// default to off so UI tests and simulators need no iCloud account; pass `-RPICloudSync YES` to try it.
    static let iCloudSyncKey = "RPICloudSync"

    static var iCloudSyncEnabled: Bool {
        if let stored = UserDefaults.standard.object(forKey: iCloudSyncKey) as? Bool { return stored }
        #if DEBUG
        return false
        #else
        return true
        #endif
    }

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
