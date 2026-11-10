import Foundation

/// Size is checked before region; thresholds describe visual coverage, not borders.
public enum ProjectionChooser {
    /// Routes whose largest bounds dimension is below 2,500 km use local LAEA.
    public static let localSpanMeters = 2_500_000.0
    /// Southern edge of the rectangular conterminous-US coverage.
    public static let conusSouth = 24.0
    /// Northern edge of the rectangular conterminous-US coverage.
    public static let conusNorth = 50.0
    /// Western edge of the rectangular conterminous-US coverage.
    public static let conusWest = -125.0
    /// Eastern edge of the rectangular conterminous-US coverage.
    public static let conusEast = -66.0
    /// Southern edge of the Europe coverage.
    public static let europeSouth = 35.0
    /// Northern edge of the Europe coverage.
    public static let europeNorth = 72.0
    /// Western edge of the Europe coverage.
    public static let europeWest = -25.0
    /// Eastern edge of the Europe coverage.
    public static let europeEast = 45.0

    /// Uses meridional arc and the widest parallel arc inside the bounds to estimate span.
    /// Robinson is centred on the mean sample longitude after unwrapping.
    public static func choose(for bounds: GeoBounds) -> MapProjectionKind {
        let center = bounds.center
        let radians = Double.pi / 180
        let height = (bounds.maxLatitude - bounds.minLatitude) * radians * Geo.earthRadiusMeters
        let nearestEquator = bounds.minLatitude <= 0 && bounds.maxLatitude >= 0
            ? 0 : min(abs(bounds.minLatitude), abs(bounds.maxLatitude))
        let width = bounds.longitudeSpan * radians * Geo.earthRadiusMeters * cos(nearestEquator * radians)
        if max(height, width) < localSpanMeters {
            return .localLAEA(centerLat: center.latitude, centerLon: center.longitude)
        }
        if bounds.minLatitude >= conusSouth, bounds.maxLatitude <= conusNorth,
           bounds.minLongitude >= conusWest, bounds.maxLongitude <= conusEast { return .albersUSA }
        if bounds.minLatitude >= europeSouth, bounds.maxLatitude <= europeNorth,
           bounds.minLongitude >= europeWest, bounds.maxLongitude <= europeEast { return .laeaEurope }
        return .robinson(centralMeridian: bounds.meanLongitude)
    }
}
