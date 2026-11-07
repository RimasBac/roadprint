import Foundation

/// Douglas–Peucker line simplification, iterative (safe for 20k+ points).
/// Distances are measured in a local equirectangular projection, in metres.
public enum DouglasPeucker {
    public static func clampedTolerance(_ tolerance: Double) -> Double {
        min(max(tolerance, ProcessingHeuristics.simplifyToleranceRange.lowerBound),
            ProcessingHeuristics.simplifyToleranceRange.upperBound)
    }

    /// Local planar coordinates in metres, centred on the mean latitude.
    /// The antimeridian is out of scope (longitudes are not unwrapped).
    public static func project(_ points: [RoutePoint]) -> [(x: Double, y: Double)] {
        guard !points.isEmpty else { return [] }
        let meanLat = points.reduce(0) { $0 + $1.latitude } / Double(points.count)
        let kx = Geo.earthRadiusMeters * .pi / 180 * cos(meanLat * .pi / 180)
        let ky = Geo.earthRadiusMeters * .pi / 180
        return points.map { (x: $0.longitude * kx, y: $0.latitude * ky) }
    }

    /// Distance from `p` to the segment `a`–`b` (to `a` if they coincide).
    public static func distance(
        _ p: (x: Double, y: Double), toSegment a: (x: Double, y: Double), _ b: (x: Double, y: Double)
    ) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        var t = 0.0
        if len2 > 0 { t = min(1, max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2)) }
        return hypot(p.x - a.x - t * dx, p.y - a.y - t * dy)
    }

    /// Indices (ascending) of the points to keep. The first and last points and
    /// every index in `forceKeep` are always kept.
    public static func simplifiedIndices(
        _ points: [RoutePoint], tolerance: Double = 15, forceKeep: Set<Int> = []
    ) -> [Int] {
        let n = points.count
        guard n > 2 else { return Array(points.indices) }
        let tol = clampedTolerance(tolerance)
        let xy = project(points)
        var keep = [Bool](repeating: false, count: n)
        keep[0] = true
        keep[n - 1] = true
        var forced = [Bool](repeating: false, count: n)
        for i in forceKeep where i >= 0 && i < n {
            forced[i] = true
            keep[i] = true
        }
        var stack = [(0, n - 1)]
        while let (lo, hi) = stack.popLast() {
            guard hi - lo > 1 else { continue }
            var maxDist = -1.0, far = -1, firstForced = -1
            for i in (lo + 1)..<hi {
                if forced[i], firstForced < 0 { firstForced = i }
                let d = distance(xy[i], toSegment: xy[lo], xy[hi])
                if d > maxDist { maxDist = d; far = i }
            }
            let split = maxDist > tol ? far : firstForced
            guard split >= 0 else { continue }
            keep[split] = true
            stack.append((lo, split))
            stack.append((split, hi))
        }
        return keep.indices.filter { keep[$0] }
    }

    public static func simplify(
        _ points: [RoutePoint], tolerance: Double = 15, forceKeep: Set<Int> = []
    ) -> [RoutePoint] {
        simplifiedIndices(points, tolerance: tolerance, forceKeep: forceKeep).map { points[$0] }
    }

    /// Simplifies each segment on its own, so segment endpoints are kept.
    public static func simplify(_ route: ProcessedRoute, tolerance: Double = 15) -> ProcessedRoute {
        ProcessedRoute(segments: route.segments.map {
            RouteSegment(points: simplify($0.points, tolerance: tolerance))
        })
    }
}
