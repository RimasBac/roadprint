import Foundation

/// Projection parameters in degrees. Regional projections use a sphere, not EPSG ellipsoids.
public enum MapProjectionKind: Sendable, Codable, Equatable {
    case localLAEA(centerLat: Double, centerLon: Double)
    case albersUSA
    case laeaEurope
    case robinson(centralMeridian: Double)
}

/// Immutable, reusable projection with origin constants cached at construction.
/// Output axes point east and north, in metres on a 6,371,008.8 m sphere.
public struct MapProjection: Sendable {
    public let kind: MapProjectionKind
    private let longitudeOrigin: Double
    private let sinOrigin: Double
    private let cosOrigin: Double
    private let n: Double
    private let c: Double
    private let rhoOrigin: Double
    private let valid: Bool
    private static let radians = Double.pi / 180
    private static let radius = Geo.earthRadiusMeters
    private static let robinsonX: [Double] = [1, 0.9986, 0.9954, 0.99, 0.9822, 0.973, 0.96, 0.9427, 0.9216, 0.8962, 0.8679, 0.835, 0.7986, 0.7597, 0.7186, 0.6732, 0.6213, 0.5722, 0.5322]
    private static let robinsonY: [Double] = [0, 0.062, 0.124, 0.186, 0.248, 0.31, 0.372, 0.434, 0.4958, 0.5571, 0.6176, 0.6769, 0.7346, 0.7903, 0.8435, 0.8936, 0.9394, 0.9761, 1]

    public init(kind: MapProjectionKind) {
        self.kind = kind
        let lat: Double
        let lon: Double
        switch kind {
        case let .localLAEA(centerLat, centerLon): (lat, lon) = (centerLat, centerLon)
        case .laeaEurope: (lat, lon) = (52, 10)
        case .albersUSA: (lat, lon) = (23, -96)
        case let .robinson(centralMeridian): (lat, lon) = (0, centralMeridian)
        }
        valid = lat.isFinite && lon.isFinite
        let phi = min(89.9, max(-89.9, lat.isFinite ? lat : 0)) * Self.radians
        longitudeOrigin = GeoBounds.normalize(lon.isFinite ? lon : 0)
        sinOrigin = sin(phi)
        cosOrigin = cos(phi)
        // USGS spherical Albers, standard parallels 29.5 and 45.5 degrees.
        let s1 = sin(29.5 * Self.radians)
        n = (s1 + sin(45.5 * Self.radians)) / 2
        c = 1 - s1 * s1 + 2 * n * s1
        rhoOrigin = Self.radius * sqrt(c - 2 * n * sinOrigin) / n
    }

    /// Clamps latitude to ±89.9°, wraps longitude to [-180, 180), and rejects
    /// non-finite inputs. LAEA clips the far hemisphere (including its horizon).
    /// No non-finite result is returned, even for invalid projection parameters.
    public func project(lat: Double, lon: Double) -> PlanePoint? {
        guard valid, lat.isFinite, lon.isFinite else { return nil }
        let latitude = min(89.9, max(-89.9, lat))
        let phi = latitude * Self.radians
        let delta = GeoBounds.normalize(GeoBounds.normalize(lon) - longitudeOrigin) * Self.radians
        let point: PlanePoint
        switch kind {
        case .localLAEA, .laeaEurope:
            let s = sin(phi), co = cos(phi), cd = cos(delta)
            let dot = sinOrigin * s + cosOrigin * co * cd
            guard dot > 0 else { return nil }
            let k = Self.radius * sqrt(2 / (1 + dot))
            point = PlanePoint(x: k * co * sin(delta), y: k * (cosOrigin * s - sinOrigin * co * cd))
        case .albersUSA:
            let rho = Self.radius * sqrt(c - 2 * n * sin(phi)) / n
            let theta = n * delta
            point = PlanePoint(x: rho * sin(theta), y: rhoOrigin - rho * cos(theta))
        case .robinson:
            // Snyder's five-degree table, piecewise linear interpolation.
            let row = abs(latitude) / 5
            let index = min(17, Int(row))
            let fraction = row - Double(index)
            let x = Self.robinsonX[index] + fraction * (Self.robinsonX[index + 1] - Self.robinsonX[index])
            let y = Self.robinsonY[index] + fraction * (Self.robinsonY[index + 1] - Self.robinsonY[index])
            point = PlanePoint(x: 0.8487 * Self.radius * delta * x,
                               y: 1.3523 * Self.radius * y * (latitude < 0 ? -1 : 1))
        }
        return point.x.isFinite && point.y.isFinite ? point : nil
    }

    /// Inverts LAEA inside its visible hemisphere and Albers inside its longitude
    /// branch. Returns nil for Robinson or a point outside the drawable domain.
    public func inverse(_ point: PlanePoint) -> GeoCoordinate? {
        guard valid, point.x.isFinite, point.y.isFinite else { return nil }
        let phi: Double
        let delta: Double
        switch kind {
        case .localLAEA, .laeaEurope:
            let rho = hypot(point.x, point.y)
            guard rho < Self.radius * sqrt(2) else { return nil }
            if rho == 0 {
                return GeoCoordinate(latitude: asin(sinOrigin) / Self.radians, longitude: longitudeOrigin)
            }
            let angle = 2 * asin(rho / (2 * Self.radius))
            let sc = sin(angle), cc = cos(angle)
            phi = asin(min(1, max(-1, cc * sinOrigin + point.y * sc * cosOrigin / rho)))
            delta = atan2(point.x * sc, rho * cosOrigin * cc - point.y * sinOrigin * sc)
        case .albersUSA:
            let y = rhoOrigin - point.y
            let rho = hypot(point.x, y)
            let argument = (c - pow(rho * n / Self.radius, 2)) / (2 * n)
            guard argument >= -1, argument <= 1 else { return nil }
            phi = asin(argument)
            delta = atan2(point.x, y) / n
            guard abs(delta) <= .pi else { return nil }
        case .robinson: return nil
        }
        let lat = phi / Self.radians
        let lon = GeoBounds.normalize(longitudeOrigin + delta / Self.radians)
        guard lat.isFinite, lon.isFinite, abs(lat) <= 89.900000001 else { return nil }
        return GeoCoordinate(latitude: lat, longitude: lon)
    }
}
