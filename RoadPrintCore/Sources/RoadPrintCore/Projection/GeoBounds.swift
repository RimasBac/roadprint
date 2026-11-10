import Foundation

/// A coordinate in degrees, independent of any platform location framework.
public struct GeoCoordinate: Sendable, Codable, Equatable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// The smallest longitude interval containing the supplied coordinates.
/// Longitudes are unwrapped, so `maxLongitude` may be greater than 180.
public struct GeoBounds: Sendable, Equatable {
    public let minLatitude: Double
    public let maxLatitude: Double
    public let minLongitude: Double
    public let maxLongitude: Double

    /// Mean sample longitude after unwrapping into the smallest interval.
    public let meanLongitude: Double

    public var longitudeSpan: Double { maxLongitude - minLongitude }
    public var center: GeoCoordinate {
        GeoCoordinate(latitude: (minLatitude + maxLatitude) / 2,
                      longitude: Self.normalize((minLongitude + maxLongitude) / 2))
    }

    /// Returns nil for an empty collection or a non-finite coordinate.
    public init?(points: [GeoCoordinate]) {
        guard !points.isEmpty, points.allSatisfy({ $0.latitude.isFinite && $0.longitude.isFinite }) else { return nil }
        let latitudes = points.map { min(89.9, max(-89.9, $0.latitude)) }
        let longitudes = points.map { Self.normalize($0.longitude) }.sorted()
        var largestGap = -Double.infinity
        var startIndex = 0
        for index in longitudes.indices {
            let next = index + 1 < longitudes.count ? longitudes[index + 1] : longitudes[0] + 360
            let gap = next - longitudes[index]
            if gap > largestGap {
                largestGap = gap
                startIndex = (index + 1) % longitudes.count
            }
        }
        minLatitude = latitudes.min()!
        maxLatitude = latitudes.max()!
        minLongitude = longitudes[startIndex]
        maxLongitude = minLongitude + 360 - largestGap
        let start = minLongitude
        meanLongitude = Self.normalize(longitudes.reduce(0) { sum, lon in
            sum + (lon < start ? lon + 360 : lon) / Double(longitudes.count)
        })
    }

    static func normalize(_ longitude: Double) -> Double {
        let remainder = longitude.truncatingRemainder(dividingBy: 360)
        if remainder < -180 { return remainder + 360 }
        if remainder >= 180 { return remainder - 360 }
        return remainder
    }
}
