import Foundation

/// Display formatting for trip stats. Distance unit follows the device's measurement system.
enum TripFormatting {
    static func distance(meters: Double, locale: Locale = .current) -> String {
        let formatter = MeasurementFormatter()
        formatter.locale = locale
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .short
        formatter.numberFormatter.locale = locale
        formatter.numberFormatter.maximumFractionDigits = 1
        formatter.numberFormatter.minimumFractionDigits = 1
        let metric = Measurement(value: meters, unit: UnitLength.meters)
        switch locale.measurementSystem {
        case .us, .uk:
            return formatter.string(from: metric.converted(to: .miles))
        default:
            return formatter.string(from: metric.converted(to: .kilometers))
        }
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
