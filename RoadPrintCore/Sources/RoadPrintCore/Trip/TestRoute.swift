import Foundation

/// TEMPORARY test tool (board, 2026-11-12). Builds the raw points of a made-up drive, so trips,
/// maps and totals can be tested without driving. The points go through the normal
/// `TripProcessor`, so the result is stored and counted exactly like a recorded trip.
///
/// A drive follows a real road when the app can get one (`points(along:)`), and otherwise a
/// gently bent line between the two places (`points(from:to:)`).
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

    private static func spacing(forLength meters: Double) -> Double {
        min(spacingRangeMeters.upperBound, max(spacingRangeMeters.lowerBound, meters / targetPointCount))
    }

    /// Points along `road` (a real road's line, in driving order), evenly spaced however unevenly
    /// the road's own points lie. The drive ends at the road's last point at `end`; earlier points
    /// count back at `speedMetersPerSecond`. Empty if the road is shorter than 1 km.
    public static func points(along road: [GeoCoordinate], endingAt end: Date, seed: UInt64 = 0) -> [TrackPoint] {
        let usable = road.filter {
            $0.latitude.isFinite && $0.longitude.isFinite && abs($0.latitude) <= 90 && abs($0.longitude) <= 180
        }
        guard let first = usable.first, let last = usable.last else { return [] }
        var length = 0.0
        for (a, b) in zip(usable, usable.dropFirst()) {
            length += Geo.distance(lat1: a.latitude, lon1: a.longitude, lat2: b.latitude, lon2: b.longitude)
        }
        guard length >= 1_000 else { return [] }

        let step = spacing(forLength: length)
        var out = [first]
        var sinceLast = 0.0
        for (a, b) in zip(usable, usable.dropFirst()) {
            let piece = Geo.distance(lat1: a.latitude, lon1: a.longitude, lat2: b.latitude, lon2: b.longitude)
            guard piece > 0 else { continue }
            var at = step - sinceLast
            while at <= piece {
                let t = at / piece
                out.append(GeoCoordinate(latitude: a.latitude + (b.latitude - a.latitude) * t,
                                         longitude: a.longitude + (b.longitude - a.longitude) * t))
                at += step
            }
            sinceLast = piece - (at - step)
        }
        // The drive ends exactly where the road ends. A last step shorter than half a step is
        // merged into the one before it, so no two points are nearly on top of each other.
        if sinceLast < step / 2, out.count > 1 { out.removeLast() }
        out.append(last)
        return track(out, endingAt: end, seed: seed)
    }

    /// Points along the great circle from `from` to `to`, bent into gentle road-like curves that
    /// fade out at both ends: the fallback when no real road is available. The last point is
    /// stamped `end`; earlier ones count back at `speedMetersPerSecond`. Empty if the places are
    /// the same or exactly opposite. `seed` picks the curve shape, so the same input always gives
    /// the same route.
    public static func points(from: GeoCoordinate, to: GeoCoordinate, endingAt end: Date,
                              seed: UInt64 = 0) -> [TrackPoint] {
        // One road per pair of places: the shape is always built from the southern place, and the
        // drive the other way is that shape reversed. So repeated test trips overlap on the heat map.
        let reversed = from.latitude > to.latitude || (from.latitude == to.latitude && from.longitude > to.longitude)
        let a = unitVector(reversed ? to : from), b = unitVector(reversed ? from : to)
        let dot = max(-1, min(1, a.x * b.x + a.y * b.y + a.z * b.z))
        let omega = acos(dot)
        let distance = omega * Geo.earthRadiusMeters
        guard distance >= 1_000, omega < .pi - 1e-6 else { return [] }

        // The normal of the great-circle plane: a sideways direction at every point of the route.
        let cross = (x: a.y * b.z - a.z * b.y, y: a.z * b.x - a.x * b.z, z: a.x * b.y - a.y * b.x)
        let crossLength = (cross.x * cross.x + cross.y * cross.y + cross.z * cross.z).squareRoot()
        guard crossLength > 0 else { return [] }
        let n = (x: cross.x / crossLength, y: cross.y / crossLength, z: cross.z / crossLength)

        let steps = max(2, Int((distance / spacing(forLength: distance)).rounded(.up)))
        let amplitude = min(distance * 0.03, 3_000)
        // One bend about every 60 km and a smaller one about every 25 km, whatever the length.
        let slow = max(1, (distance / 60_000).rounded()), quick = max(2, (distance / 25_000).rounded())
        let phase1 = Double(seed % 628) / 100, phase2 = Double((seed / 628) % 628) / 100
        let sinOmega = sin(omega)

        var coordinates: [GeoCoordinate] = []
        coordinates.reserveCapacity(steps + 1)
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
        }
        if reversed { coordinates.reverse() }
        return track(coordinates, endingAt: end, seed: seed)
    }

    /// Made-up rolling hills between 0 and 560 m: a few broad ones however long the drive is, so
    /// the elevation chart of a long trip is a landscape and not a comb. `u` is the share of the
    /// distance, counted from the southern end.
    static func altitude(_ u: Double, phase1: Double, phase2: Double) -> Double {
        220 + 150 * sin(2 * .pi * 1.5 * u + phase2) + 50 * sin(2 * .pi * 4 * u + phase1)
            + 20 * sin(2 * .pi * 9 * u + phase1 + phase2) + 120 * sin(.pi * u)
    }

    /// Stamps the coordinates with times at a steady speed and gives them the made-up hills.
    private static func track(_ coordinates: [GeoCoordinate], endingAt end: Date, seed: UInt64) -> [TrackPoint] {
        guard let first = coordinates.first, let last = coordinates.last, coordinates.count > 1 else { return [] }
        var along: [Double] = [0]
        along.reserveCapacity(coordinates.count)
        for i in coordinates.indices.dropFirst() {
            along.append(along[i - 1] + Geo.distance(
                lat1: coordinates[i - 1].latitude, lon1: coordinates[i - 1].longitude,
                lat2: coordinates[i].latitude, lon2: coordinates[i].longitude))
        }
        let total = along[along.count - 1]
        guard total > 0 else { return [] }
        // The hills belong to the road, not to the direction: the drive back climbs the same ones.
        let southFirst = !(first.latitude > last.latitude || (first.latitude == last.latitude && first.longitude > last.longitude))
        let phase1 = Double(seed % 628) / 100, phase2 = Double((seed / 628) % 628) / 100
        return coordinates.indices.map { i in
            let t = along[i] / total
            return TrackPoint(latitude: coordinates[i].latitude, longitude: coordinates[i].longitude,
                              altitude: altitude(southFirst ? t : 1 - t, phase1: phase1, phase2: phase2),
                              timestamp: end.addingTimeInterval(-(total - along[i]) / speedMetersPerSecond),
                              horizontalAccuracy: 5, verticalAccuracy: 5)
        }
    }

    private static func unitVector(_ c: GeoCoordinate) -> (x: Double, y: Double, z: Double) {
        let lat = c.latitude * .pi / 180, lon = c.longitude * .pi / 180
        return (cos(lat) * cos(lon), cos(lat) * sin(lon), sin(lat))
    }
}
