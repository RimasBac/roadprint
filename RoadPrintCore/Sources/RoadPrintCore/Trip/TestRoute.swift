import Foundation

/// TEMPORARY test tool (board, 2026-11-12). Builds the raw points of a made-up drive between two
/// places, so trips, maps and totals can be tested without driving. The points go through the
/// normal `TripProcessor`, so the result is stored and counted exactly like a recorded trip.
///
/// Delete together with `AreaNamer.place(named:)` and the app's "Add a test trip" screen.
public enum TestRoute {
    /// A steady 90 km/h, well under the cleaner's spike speed.
    public static let speedMetersPerSecond = 25.0
    /// Spacing between points: at least the recorder's 100 m filter, and never close to the
    /// 2 km gap threshold however long the drive is.
    public static let spacingRangeMeters: ClosedRange<Double> = 200...1_000
    /// Longer drives use wider spacing instead of more points.
    public static let targetPointCount = 20_000.0

    /// Points along the great circle from `from` to `to`, bent into gentle road-like curves that
    /// fade out at both ends. The last point is stamped `end`; earlier ones count back at
    /// `speedMetersPerSecond`. Empty if the places are the same or exactly opposite.
    /// `seed` picks the curve shape, so the same input always gives the same route.
    public static func points(from: GeoCoordinate, to: GeoCoordinate, endingAt end: Date,
                              seed: UInt64 = 0) -> [TrackPoint] {
        // One road per pair of places: the drive back is the drive there, reversed.
        if from.latitude > to.latitude || (from.latitude == to.latitude && from.longitude > to.longitude) {
            let there = points(from: to, to: from, endingAt: end, seed: seed)
            return zip(there.reversed(), there).map { place, time in
                TrackPoint(latitude: place.latitude, longitude: place.longitude, altitude: place.altitude,
                           timestamp: time.timestamp, horizontalAccuracy: 5, verticalAccuracy: 5)
            }
        }
        let a = unitVector(from), b = unitVector(to)
        let dot = max(-1, min(1, a.x * b.x + a.y * b.y + a.z * b.z))
        let omega = acos(dot)
        let distance = omega * Geo.earthRadiusMeters
        guard distance >= 1_000, omega < .pi - 1e-6 else { return [] }

        // The normal of the great-circle plane: a sideways direction at every point of the route.
        let cross = (x: a.y * b.z - a.z * b.y, y: a.z * b.x - a.x * b.z, z: a.x * b.y - a.y * b.x)
        let crossLength = (cross.x * cross.x + cross.y * cross.y + cross.z * cross.z).squareRoot()
        guard crossLength > 0 else { return [] }
        let n = (x: cross.x / crossLength, y: cross.y / crossLength, z: cross.z / crossLength)

        let spacing = min(spacingRangeMeters.upperBound,
                          max(spacingRangeMeters.lowerBound, distance / targetPointCount))
        let steps = max(2, Int((distance / spacing).rounded(.up)))
        let amplitude = min(distance * 0.03, 3_000)
        // One bend about every 60 km and a smaller one about every 25 km, whatever the length.
        let slow = max(1, (distance / 60_000).rounded()), quick = max(2, (distance / 25_000).rounded())
        let phase1 = Double(seed % 628) / 100, phase2 = Double((seed / 628) % 628) / 100
        let sinOmega = sin(omega)

        var coordinates: [GeoCoordinate] = []
        var altitudes: [Double] = []
        coordinates.reserveCapacity(steps + 1)
        altitudes.reserveCapacity(steps + 1)
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let wa = sin((1 - t) * omega) / sinOmega, wb = sin(t * omega) / sinOmega
            let p = (x: wa * a.x + wb * b.x, y: wa * a.y + wb * b.y, z: wa * a.z + wb * b.z)
            // Two slow waves, zero at both ends so the drive starts and ends at the places.
            let wave = 0.6 * sin(2 * .pi * slow * t + phase1) + 0.4 * sin(2 * .pi * quick * t + phase2)
            let delta = amplitude * sin(.pi * t) * wave / Geo.earthRadiusMeters
            let q = (x: cos(delta) * p.x + sin(delta) * n.x,
                     y: cos(delta) * p.y + sin(delta) * n.y,
                     z: cos(delta) * p.z + sin(delta) * n.z)
            coordinates.append(GeoCoordinate(latitude: asin(max(-1, min(1, q.z))) * 180 / .pi,
                                             longitude: atan2(q.y, q.x) * 180 / .pi))
            // Made-up rolling hills (0 to 560 m), so the elevation chart and the highest point
            // have something to show.
            altitudes.append(220 + 160 * sin(2 * .pi * slow * t + phase2)
                             + 60 * sin(2 * .pi * quick * t + phase1) + 120 * sin(.pi * t))
        }

        var along: [Double] = [0]
        along.reserveCapacity(coordinates.count)
        for i in coordinates.indices.dropFirst() {
            along.append(along[i - 1] + Geo.distance(
                lat1: coordinates[i - 1].latitude, lon1: coordinates[i - 1].longitude,
                lat2: coordinates[i].latitude, lon2: coordinates[i].longitude))
        }
        let total = along[along.count - 1]
        return coordinates.indices.map { i in
            TrackPoint(latitude: coordinates[i].latitude, longitude: coordinates[i].longitude,
                       altitude: altitudes[i],
                       timestamp: end.addingTimeInterval(-(total - along[i]) / speedMetersPerSecond),
                       horizontalAccuracy: 5, verticalAccuracy: 5)
        }
    }

    private static func unitVector(_ c: GeoCoordinate) -> (x: Double, y: Double, z: Double) {
        let lat = c.latitude * .pi / 180, lon = c.longitude * .pi / 180
        return (cos(lat) * cos(lon), cos(lat) * sin(lon), sin(lat))
    }
}
