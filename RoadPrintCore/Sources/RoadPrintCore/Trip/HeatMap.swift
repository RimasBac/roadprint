import Foundation

/// How often each stretch of road was driven: the data behind "My map" (plan §4.5).
///
/// The world is cut into cells about 1 km wide. A cell's count is the number of trips that pass
/// through it, so driving one road twice in one trip counts once. Each trip's route is then cut
/// into runs of one heat level. Privacy: it reads only trimmed routes, and nothing leaves the phone.
public struct HeatMap: Sendable, Equatable {
    public struct Run: Sendable, Equatable {
        /// 1 (driven once or twice) to 5 (15 times or more).
        public var level: Int
        public var points: [RoutePoint]
    }

    /// Coldest first, so a renderer draws them in order and the hottest ends on top.
    public var runs: [Run]
    /// The largest number of trips through one cell. 0 when there is nothing to draw.
    public var maxCount: Int

    /// The fewest trips for levels 1 to 5: 1–2, 3–5, 6–9, 10–14, 15 or more (mockup 3).
    public static let levelFloors = [1, 3, 6, 10, 15]

    public static func level(count: Int) -> Int {
        (levelFloors.lastIndex { count >= $0 } ?? 0) + 1
    }

    /// About 1.1 km of latitude.
    static let cellDegrees = 0.01
    /// Stored routes are simplified, so points can be far apart: walk them in steps this long.
    static let stepMeters = 400.0

    struct Cell: Hashable {
        var row: Int32
        var column: Int32
    }

    static func cell(_ point: RoutePoint) -> Cell {
        let row = (point.latitude / cellDegrees).rounded(.down)
        // Keep cells about square: a longitude step grows away from the equator.
        let middle = (row + 0.5) * cellDegrees
        let step = cellDegrees / max(cos(middle * .pi / 180), 0.05)
        return Cell(row: Int32(row), column: Int32((point.longitude / step).rounded(.down)))
    }

    static func densify(_ points: [RoutePoint]) -> [RoutePoint] {
        guard var previous = points.first else { return [] }
        var out = [previous]
        for point in points.dropFirst() {
            let pieces = Int((Geo.distance(from: previous, to: point) / stepMeters).rounded(.up))
            if pieces > 1 {
                for index in 1..<pieces {
                    let t = Double(index) / Double(pieces)
                    out.append(RoutePoint(latitude: previous.latitude + (point.latitude - previous.latitude) * t,
                                          longitude: previous.longitude + (point.longitude - previous.longitude) * t))
                }
            }
            out.append(point)
            previous = point
        }
        return out
    }

    /// - Parameter routes: one entry per trip: that trip's trimmed route segments.
    public static func make(routes: [[RouteSegment]]) -> HeatMap {
        let trips = routes.map { $0.map { densify($0.points) }.filter { $0.count > 1 } }
        var counts: [Cell: Int] = [:]
        for trip in trips {
            var seen = Set<Cell>()
            for segment in trip {
                for point in segment { seen.insert(cell(point)) }
            }
            for cell in seen { counts[cell, default: 0] += 1 }
        }
        var runs: [Run] = []
        for trip in trips {
            for segment in trip {
                var current = [segment[0]]
                var currentLevel = 0
                for (a, b) in zip(segment, segment.dropFirst()) {
                    // A step is as hot as its cooler end, so a shared stretch needs both ends shared.
                    let heat = level(count: min(counts[cell(a)] ?? 1, counts[cell(b)] ?? 1))
                    if heat != currentLevel, current.count > 1 {
                        runs.append(Run(level: currentLevel, points: current))
                        current = [a]
                    }
                    currentLevel = heat
                    current.append(b)
                }
                if current.count > 1 { runs.append(Run(level: currentLevel, points: current)) }
            }
        }
        // Coldest first; equal levels keep their order, so the result is the same every time.
        let ordered = runs.enumerated().sorted {
            $0.element.level == $1.element.level ? $0.offset < $1.offset : $0.element.level < $1.element.level
        }.map(\.element)
        return HeatMap(runs: ordered, maxCount: counts.values.max() ?? 0)
    }
}
