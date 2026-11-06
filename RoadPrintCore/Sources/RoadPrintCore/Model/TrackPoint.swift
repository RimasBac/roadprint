import Foundation

/// One recorded location sample.
///
/// No speed or course field, by design (plan §4.2, AGENTS.md §8). Never add one.
public struct TrackPoint: Sendable, Codable, Equatable {
    /// Degrees, WGS84.
    public var latitude: Double
    /// Degrees, WGS84.
    public var longitude: Double
    /// Metres above sea level, if known.
    public var altitude: Double?
    public var timestamp: Date
    /// Metres.
    public var horizontalAccuracy: Double
    /// Metres, if known.
    public var verticalAccuracy: Double?

    public init(
        latitude: Double,
        longitude: Double,
        altitude: Double? = nil,
        timestamp: Date,
        horizontalAccuracy: Double,
        verticalAccuracy: Double? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.timestamp = timestamp
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
    }
}
