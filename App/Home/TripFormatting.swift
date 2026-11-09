import Foundation
import RoadPrintCore

/// Display formatting for trip stats. The distance unit comes from `UserProfile.distanceUnit`.
enum TripFormatting {
    static func distance(meters: Double, unit: DistanceUnit, locale: Locale = .current) -> String {
        let formatter = MeasurementFormatter()
        formatter.locale = locale
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .short
        formatter.numberFormatter.locale = locale
        formatter.numberFormatter.maximumFractionDigits = 1
        formatter.numberFormatter.minimumFractionDigits = 1
        let metric = Measurement(value: meters, unit: UnitLength.meters)
        switch unit {
        case .miles: return formatter.string(from: metric.converted(to: .miles))
        case .kilometers: return formatter.string(from: metric.converted(to: .kilometers))
        }
    }

    /// Regions in order of first visit ("Utah · Nevada · California"); countries if no region is known.
    static func placesLine(_ places: TripPlaces?) -> String? {
        guard let places else { return nil }
        let refs = places.regions.isEmpty ? places.countries : places.regions
        return refs.isEmpty ? nil : refs.map(\.name).joined(separator: " · ")
    }

    /// Whole minutes, rounded down ("17m", "1h 5m").
    static func duration(seconds: TimeInterval) -> String {
        let totalMinutes = Int(max(0, seconds) / 60)
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = totalMinutes >= 60 ? [.hour, .minute] : [.minute]
        formatter.zeroFormattingBehavior = .dropLeading
        let components = DateComponents(hour: totalMinutes / 60, minute: totalMinutes % 60)
        return formatter.string(from: components) ?? "\(totalMinutes)m"
    }
}
