import Foundation

/// Geometry shared by the builder and its invariant tests.
enum SceneGeometry {
    static func distanceSquared(_ p: PlanePoint, _ a: PlanePoint, _ b: PlanePoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y, length = dx * dx + dy * dy
        let t = length > 0 ? max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / length)) : 0
        return pow(p.x - a.x - t * dx, 2) + pow(p.y - a.y - t * dy, 2)
    }

    static func simplifiedIndices(_ points: [PlanePoint], tolerance: Double = 0.5) -> [Int] {
        guard points.count > 2 else { return Array(points.indices) }
        var keep = Set([0, points.count - 1]), stack = [(0, points.count - 1)]
        while let (a, b) = stack.popLast() {
            guard b > a + 1 else { continue }
            var furthest = tolerance * tolerance, index: Int?
            for i in (a + 1)..<b {
                let d = distanceSquared(points[i], points[a], points[b])
                if d > furthest { furthest = d; index = i }
            }
            if let i = index { keep.insert(i); stack.append((a, i)); stack.append((i, b)) }
        }
        return keep.sorted()
    }

    static func simplify(_ points: [PlanePoint]) -> [PlanePoint] {
        simplifiedIndices(points).map { points[$0] }
    }

    /// Liang–Barsky segment clipping; also used for exact route/label collision.
    static func clip(_ a: PlanePoint, _ b: PlanePoint, to rect: MapRect) -> [PlanePoint]? {
        let dx = b.x - a.x, dy = b.y - a.y
        var low = 0.0, high = 1.0
        for (p, q) in [(-dx, a.x - rect.x), (dx, rect.x + rect.width - a.x),
                       (-dy, a.y - rect.y), (dy, rect.y + rect.height - a.y)] {
            if p == 0 { if q < 0 { return nil }; continue }
            let r = q / p
            if p < 0 { low = max(low, r) } else { high = min(high, r) }
            if low > high { return nil }
        }
        return [PlanePoint(x: a.x + low * dx, y: a.y + low * dy),
                PlanePoint(x: a.x + high * dx, y: a.y + high * dy)]
    }

    static func clear(_ rect: MapRect, of routes: [MapScene.Route], by margin: Double) -> Bool {
        let box = rect.expanded(margin)
        for route in routes {
            if route.points.contains(where: box.contains) { return false }
            for (a, b) in zip(route.points, route.points.dropFirst()) {
                if clip(a, b, to: box) != nil { return false }
            }
        }
        return true
    }

    static func contains(_ point: PlanePoint, rings: [[PlanePoint]]) -> Bool {
        var inside = false
        for ring in rings where ring.count >= 3 {
            var a = ring[ring.count - 1]
            for b in ring {
                if (a.y > point.y) != (b.y > point.y),
                   point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
                a = b
            }
        }
        return inside
    }

    /// Sutherland–Hodgman clipping preserves even-odd holes. Do not simplify
    /// again after clipping: both sides of a shared border must retain its path.
    static func clipRing(_ ring: [PlanePoint], to rect: MapRect) -> [PlanePoint] {
        var points = ring
        if !points.isEmpty, points.first == points.last { points.removeLast() }
        for edge in 0..<4 {
            let axisX = edge < 2
            let bound = [rect.x, rect.x + rect.width, rect.y, rect.y + rect.height][edge]
            func value(_ p: PlanePoint) -> Double { axisX ? p.x : p.y }
            func inside(_ p: PlanePoint) -> Bool { edge % 2 == 0 ? value(p) >= bound : value(p) <= bound }
            guard let last = points.last else { return [] }
            var result: [PlanePoint] = [], a = last
            for b in points {
                if inside(a) != inside(b) {
                    let t = (bound - value(a)) / (value(b) - value(a))
                    result.append(PlanePoint(x: a.x + t * (b.x - a.x), y: a.y + t * (b.y - a.y)))
                }
                if inside(b) { result.append(b) }
                a = b
            }
            points = result
        }
        guard points.count >= 3 else { return [] }
        if points.first != points.last { points.append(points[0]) }
        return points
    }
}

/// Topology before simplification: each undirected edge is visited once. Split
/// chains at junctions, simplify each chain once, and reuse its retained vertices
/// in every owning ring, including rings with the opposite winding.
enum SharedOutlineSimplifier {
    private struct Key: Hashable {
        let x: Int64, y: Int64
        init(_ p: PlanePoint) { x = Int64((p.x * 1e7).rounded()); y = Int64((p.y * 1e7).rounded()) }
    }
    private struct Edge: Hashable {
        let a: Int, b: Int
        init(_ x: Int, _ y: Int) { a = min(x, y); b = max(x, y) }
    }
    static func simplify(_ rings: [[PlanePoint]]) -> [[PlanePoint]] {
        var ids: [Key: Int] = [:], vertices: [PlanePoint] = []
        let indexed: [[Int]] = rings.map { ring in
            var result: [Int] = []
            for point in ring {
                let key = Key(point)
                let id: Int
                if let existing = ids[key] { id = existing }
                else { id = vertices.count; ids[key] = id; vertices.append(point) }
                if result.last != id { result.append(id) }
            }
            if result.count > 1, result.first != result.last { result.append(result[0]) }
            return result
        }
        var adjacency = [[Int]](repeating: [], count: vertices.count)
        var edges = Set<Edge>()
        for ring in indexed {
            for (a, b) in zip(ring, ring.dropFirst()) where a != b {
                if edges.insert(Edge(a, b)).inserted { adjacency[a].append(b); adjacency[b].append(a) }
            }
        }
        var visited = Set<Edge>(), retained = Set<Int>()
        func walk(_ start: Int, _ next: Int) {
            var chain = [start], previous = start, current = next
            visited.insert(Edge(start, next))
            while true {
                chain.append(current)
                if current == start || adjacency[current].count != 2 { break }
                let n = adjacency[current].first { $0 != previous }!
                if !visited.insert(Edge(current, n)).inserted { break }
                previous = current; current = n
            }
            for i in SceneGeometry.simplifiedIndices(chain.map { vertices[$0] }) { retained.insert(chain[i]) }
        }
        for start in vertices.indices where adjacency[start].count != 2 {
            for next in adjacency[start] where !visited.contains(Edge(start, next)) { walk(start, next) }
        }
        for start in vertices.indices {
            for next in adjacency[start] where !visited.contains(Edge(start, next)) { walk(start, next) }
        }
        return indexed.map { ring in ring.filter { retained.contains($0) }.map { vertices[$0] } }
    }
}
