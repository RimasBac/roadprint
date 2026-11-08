import Foundation

public enum Geo {
    /// Mean Earth radius in metres.
    public static let earthRadiusMeters = 6_371_008.8

    /// Great-circle distance in metres (haversine).
    public static func distance(from a: TrackPoint, to b: TrackPoint) -> Double {
        distance(lat1: a.latitude, lon1: a.longitude, lat2: b.latitude, lon2: b.longitude)
    }

    public static func distance(from a: RoutePoint, to b: RoutePoint) -> Double {
        distance(lat1: a.latitude, lon1: a.longitude, lat2: b.latitude, lon2: b.longitude)
    }

    public static func distance(lat1 degLat1: Double, lon1: Double, lat2 degLat2: Double, lon2: Double) -> Double {
        let lat1 = degLat1 * .pi / 180
        let lat2 = degLat2 * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (lon2 - lon1) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadiusMeters * asin(min(1, sqrt(h)))
    }
}
