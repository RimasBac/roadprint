import Foundation

/// Cuts the first and last stretch off a route and describes the cut ends as
/// approximate circles (plan §4.2, §4.3, §5.4 step 4). Pure and deterministic.
public enum PrivacyTrim {
    public struct Result: Sendable, Equatable {
        /// Trimmed segments. Empty for a short trip.
        public var segments: [[RoutePoint]]
        public var start: ApproximateArea
        /// Equal to `start` for a short trip.
        public var end: ApproximateArea
        /// The highest retained point, if any retained point has an altitude.
        public var summit: RoutePoint?
        /// Where `summit` sits in `segments`.
        public var summitLocation: (segment: Int, index: Int)?

        public static func == (a: Result, b: Result) -> Bool {
            a.segments == b.segments && a.start == b.start && a.end == b.end && a.summit == b.summit
                && a.summitLocation?.segment == b.summitLocation?.segment
                && a.summitLocation?.index == b.summitLocation?.index
        }
    }

    /// 64-bit FNV-1a over the UUID's 16 bytes. Stable across runs, platforms and Swift versions.
    public static func fnv1a(_ id: UUID) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        withUnsafeBytes(of: id.uuid) { bytes in
            for byte in bytes {
                hash ^= UInt64(byte)
                hash = hash &* 0x0000_0100_0000_01b3
            }
        }
        return hash
    }

    /// Base trim plus a deterministic offset in `0..<jitter` seeded from the trip UUID.
    /// The same value serves the start and the end of one trip.
    public static func trimDistance(for id: UUID, base: Double = 8_000, jitter: Double = 2_000) -> Double {
        let fraction = Double(fnv1a(id) >> 11) / Double(UInt64(1) << 53)
        return base + fraction * jitter
    }

    public static func trimDistance(for id: UUID, heuristics: ProcessingHeuristics) -> Double {
        trimDistance(for: id, base: heuristics.trimBaseMeters, jitter: heuristics.trimJitterMeters)
    }

    /// Trims `trimMeters` off each end, measured along the path. A break between
    /// segments (an unfilled gap) adds no length. Returns nil if there are no points.
    ///
    /// Short trip (path ≤ 2 × trim + margin): no segments, and one circle at the
    /// point half way along the path with radius max(trim, path / 2), as both
    /// `start` and `end`.
    public static func trim(
        _ segments: [[RoutePoint]], trimMeters: Double, shortTripMarginMeters: Double = 2_000
    ) -> Result? {
        let segs = segments.filter { !$0.isEmpty }
        guard !segs.isEmpty else { return nil }
        let cums = segs.map(cumulative)
        var bases: [Double] = []
        var total = 0.0
        for c in cums { bases.append(total); total += c.last ?? 0 }

        if total <= 2 * trimMeters + shortTripMarginMeters {
            let center = point(at: total / 2, segs, cums, bases)
            let area = ApproximateArea(
                centerLatitude: center.latitude, centerLongitude: center.longitude,
                radiusMeters: max(trimMeters, total / 2))
            return Result(segments: [], start: area, end: area, summit: nil, summitLocation: nil)
        }

        let from = trimMeters, to = total - trimMeters
        var out: [[RoutePoint]] = []
        for (i, seg) in segs.enumerated() {
            let len = cums[i].last ?? 0
            let lo = max(from - bases[i], 0), hi = min(to - bases[i], len)
            guard hi > lo else { continue }
            var kept = [interpolate(seg, cums[i], at: lo)]
            for j in seg.indices where cums[i][j] > lo && cums[i][j] < hi { kept.append(seg[j]) }
            kept.append(interpolate(seg, cums[i], at: hi))
            out.append(kept)
        }
        guard let first = out.first?.first, let last = out.last?.last else {
            // Cannot happen when total > 2 × trim, kept for safety.
            return nil
        }

        var summitLocation: (segment: Int, index: Int)?
        var best = -Double.infinity
        for (s, seg) in out.enumerated() {
            for (j, p) in seg.enumerated() {
                if let alt = p.altitude, alt > best { best = alt; summitLocation = (s, j) }
            }
        }
        return Result(
            segments: out,
            start: ApproximateArea(centerLatitude: first.latitude, centerLongitude: first.longitude, radiusMeters: trimMeters),
            end: ApproximateArea(centerLatitude: last.latitude, centerLongitude: last.longitude, radiusMeters: trimMeters),
            summit: summitLocation.map { out[$0.segment][$0.index] },
            summitLocation: summitLocation)
    }

    // MARK: helpers

    private static func cumulative(_ seg: [RoutePoint]) -> [Double] {
        var cum = [0.0]
        cum.reserveCapacity(seg.count)
        for i in seg.indices.dropFirst() { cum.append(cum[i - 1] + Geo.distance(from: seg[i - 1], to: seg[i])) }
        return cum
    }

    /// The point `x` metres along one segment (linear in latitude and longitude between vertices).
    private static func interpolate(_ seg: [RoutePoint], _ cum: [Double], at x: Double) -> RoutePoint {
        guard x > 0 else { return seg[0] }
        guard x < cum[cum.count - 1] else { return seg[seg.count - 1] }
        // First vertex strictly past x; x lies between it and its predecessor.
        var lo = 0, hi = cum.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if cum[mid] <= x { lo = mid } else { hi = mid }
        }
        let a = seg[lo], b = seg[hi]
        let span = cum[hi] - cum[lo]
        let t = span > 0 ? (x - cum[lo]) / span : 0
        let altitude: Double? = {
            guard let aa = a.altitude, let bb = b.altitude else { return nil }
            return aa + (bb - aa) * t
        }()
        return RoutePoint(
            latitude: a.latitude + (b.latitude - a.latitude) * t,
            longitude: a.longitude + (b.longitude - a.longitude) * t,
            altitude: altitude)
    }

    private static func point(
        at d: Double, _ segs: [[RoutePoint]], _ cums: [[Double]], _ bases: [Double]
    ) -> RoutePoint {
        for i in segs.indices where d <= bases[i] + (cums[i].last ?? 0) {
            return interpolate(segs[i], cums[i], at: max(0, d - bases[i]))
        }
        return segs[segs.count - 1][segs[segs.count - 1].count - 1]
    }
}
