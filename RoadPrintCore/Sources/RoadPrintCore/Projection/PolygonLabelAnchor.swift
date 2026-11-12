import Foundation

/// Finds a point inside an even-odd polygon furthest from its boundary. Rings
/// may describe multiple islands and holes. Coordinates are screen points.
enum PolygonLabelAnchor {
    private struct Cell {
        let x: Double, y: Double, half: Double, distance: Double
        var upperBound: Double { distance + half * sqrt(2.0) }
    }

    static func find(rings: [[PlanePoint]], precision: Double = 0.5) -> PlanePoint? {
        let rings = rings.filter { $0.count >= 3 && $0.allSatisfy { $0.x.isFinite && $0.y.isFinite } }
        let vertices = rings.flatMap { $0 }
        guard !vertices.isEmpty, precision.isFinite, precision > 0,
              let minX = vertices.map(\.x).min(), let maxX = vertices.map(\.x).max(),
              let minY = vertices.map(\.y).min(), let maxY = vertices.map(\.y).max() else { return nil }
        let width = maxX - minX, height = maxY - minY
        guard width.isFinite, height.isFinite, min(width, height) > 0 else { return nil }
        // A coastal sliver must not allocate width/height initial cells.
        // Larger cells still bound the same search and converge to precision.
        let cellSize = max(min(width, height), max(width, height) / 64)

        func cell(_ x: Double, _ y: Double, _ half: Double) -> Cell {
            Cell(x: x, y: y, half: half, distance: signedDistance(x: x, y: y, rings: rings))
        }
        // A max heap bounds work while preserving deterministic tie ordering.
        var heap: [Cell] = []
        func push(_ item: Cell) {
            heap.append(item)
            var i = heap.count - 1
            while i > 0 {
                let parent = (i - 1) / 2
                if heap[parent].upperBound >= heap[i].upperBound { break }
                heap.swapAt(parent, i); i = parent
            }
        }
        func pop() -> Cell {
            heap.swapAt(0, heap.count - 1)
            let result = heap.removeLast()
            var i = 0
            while 2 * i + 1 < heap.count {
                let left = 2 * i + 1, right = left + 1
                let child = right < heap.count && heap[right].upperBound > heap[left].upperBound ? right : left
                if heap[i].upperBound >= heap[child].upperBound { break }
                heap.swapAt(i, child); i = child
            }
            return result
        }
        let half = cellSize / 2
        var x = minX
        while x < maxX {
            var y = minY
            while y < maxY { push(cell(x + half, y + half, half)); y += cellSize }
            x += cellSize
        }
        var best = cell((minX + maxX) / 2, (minY + maxY) / 2, 0)
        while !heap.isEmpty {
            let current = pop()
            if current.distance > best.distance { best = current }
            if current.upperBound - best.distance <= precision { continue }
            let h = current.half / 2
            for dx in [-h, h] { for dy in [-h, h] { push(cell(current.x + dx, current.y + dy, h)) } }
        }
        return best.distance > 0 ? PlanePoint(x: best.x, y: best.y) : nil
    }

    private static func signedDistance(x: Double, y: Double, rings: [[PlanePoint]]) -> Double {
        var inside = false
        var minSquared = Double.greatestFiniteMagnitude
        for ring in rings {
            var previous = ring[ring.count - 1]
            for point in ring {
                if (point.y > y) != (previous.y > y),
                   x < (previous.x - point.x) * (y - point.y) / (previous.y - point.y) + point.x {
                    inside.toggle()
                }
                let dx = point.x - previous.x, dy = point.y - previous.y
                let lengthSquared = dx * dx + dy * dy
                let t = lengthSquared > 0 ? max(0, min(1, ((x - previous.x) * dx + (y - previous.y) * dy) / lengthSquared)) : 0
                let ex = x - (previous.x + t * dx), ey = y - (previous.y + t * dy)
                minSquared = min(minSquared, ex * ex + ey * ey)
                previous = point
            }
        }
        return (inside ? 1 : -1) * minSquared.squareRoot()
    }
}
