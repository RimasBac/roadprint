import Foundation

/// Guesses the road a trip mostly followed: resample the route every `sampleSpacing`, find the
/// nearest bundled road within `matchRadius` for each sample, and take the `(network, ref)`
/// with the most matched samples if they cover at least `minShare` of the route length.
/// Ties go to the higher network rank, then the smaller ref, so the result is deterministic.
public struct MainRoadGuesser: Sendable {
    public var index: RoadIndex
    public var sampleSpacing: Double
    public var matchRadius: Double
    public var minShare: Double

    public init(index: RoadIndex, sampleSpacing: Double = 250, matchRadius: Double = 150, minShare: Double = 0.15) {
        self.index = index
        self.sampleSpacing = sampleSpacing
        self.matchRadius = matchRadius
        self.minShare = minShare
    }

    /// Use the **trimmed** route: the privacy-trimmed ends must not influence the sign.
    public func guess(_ route: ProcessedRoute) -> MainRoad? {
        guess(segments: route.segments.map(\.points))
    }

    public func guess(segments: [[RoutePoint]]) -> MainRoad? {
        struct Key: Hashable { var network: RoadNetwork; var ref: String }
        var matched: [Key: (count: Int, country: String?)] = [:]
        var routeLength = 0.0

        for points in segments where !points.isEmpty {
            let (samples, length) = resample(points)
            routeLength += length
            for sample in samples {
                if let road = index.nearestRoad(lat: sample.latitude, lon: sample.longitude, radius: matchRadius) {
                    let key = Key(network: road.network, ref: road.ref)
                    let old = matched[key]
                    matched[key] = ((old?.count ?? 0) + 1, old?.country ?? road.countryCode)
                }
            }
        }
        guard routeLength > 0 else { return nil }

        var best: (key: Key, count: Int, country: String?)?
        for (key, value) in matched {
            guard let current = best else { best = (key, value.count, value.country); continue }
            let wins = value.count != current.count ? value.count > current.count
                : key.network.rank != current.key.network.rank ? key.network.rank > current.key.network.rank
                : key.ref < current.key.ref
            if wins { best = (key, value.count, value.country) }
        }
        guard let winner = best, Double(winner.count) * sampleSpacing >= minShare * routeLength else { return nil }
        return MainRoad(network: winner.key.network, ref: winner.key.ref, countryCode: winner.country)
    }

    /// Points every `sampleSpacing` metres along one segment (the first point included), and the segment's length.
    private func resample(_ points: [RoutePoint]) -> (samples: [RoutePoint], length: Double) {
        var samples = [points[0]]
        var sinceLast = 0.0
        var length = 0.0
        for i in 1..<max(points.count, 1) {
            var a = points[i - 1]
            let b = points[i]
            var d = Geo.distance(from: a, to: b)
            guard d > 0 else { continue }
            length += d
            while sinceLast + d >= sampleSpacing {
                let t = (sampleSpacing - sinceLast) / d
                a = RoutePoint(latitude: a.latitude + (b.latitude - a.latitude) * t,
                               longitude: a.longitude + (b.longitude - a.longitude) * t)
                samples.append(a)
                d = Geo.distance(from: a, to: b)
                sinceLast = 0
            }
            sinceLast += d
        }
        return (samples, length)
    }
}
