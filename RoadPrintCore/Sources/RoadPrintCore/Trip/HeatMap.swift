import Foundation

/// Every trip merged into one road network with a count per stretch: the data behind "My map"
/// (plan §4.5).
///
/// The area the trips cover is cut into a fine grid (about 700 cells across, so a cell is smaller
/// than a point on the phone). Every route is walked in steps shorter than a cell. A cell remembers
/// which trips passed and the average position of their points, so many drives over one road
/// collapse into a single clean line on that road, instead of a bundle of slightly different ones.
/// Neighbouring cells that follow each other on a route are joined; the joined cells form the lines.
///
/// Privacy: it reads only trimmed routes, and nothing leaves the phone.
public struct HeatMap: Sendable, Equatable {
    public struct Line: Sendable, Equatable {
        public var points: [RoutePoint]
        /// How many trips drove this stretch.
        public var count: Int
        /// 0 (driven once) to 1 (the most driven road), in `levels` steps.
        public var heat: Double
    }

    /// Coldest first, so a renderer draws them in order and the hottest ends on top.
    public var lines: [Line]
    /// The largest number of trips over one stretch. 0 when there is nothing to draw.
    public var maxCount: Int
    public var tripCount: Int
    /// Width of a grid cell.
    public var cellMeters: Double

    public static let empty = HeatMap(lines: [], maxCount: 0, tripCount: 0, cellMeters: 0)

    /// With only a few repeats the scale still ends here, so a road driven twice is warm, not white-hot.
    public static let fullScaleCount = 8
    /// A line changes colour in this many steps.
    public static let levels = 12

    /// Logarithmic, because the eye should tell 2 from 4 as easily as 40 from 80.
    public static func heat(count: Int, maxCount: Int) -> Double {
        guard count > 1 else { return 0 }
        return min(1, log(Double(count)) / log(Double(max(maxCount, fullScaleCount))))
    }

    static func level(count: Int, maxCount: Int) -> Int {
        Int((heat(count: count, maxCount: maxCount) * Double(levels - 1)).rounded())
    }

    static let cellMetersRange = 120.0...5_000.0
    /// Steps are shorter than half a cell, so a route never skips a cell.
    static let stepFraction = 0.45
    private static let rowStride = 1 << 20

    /// - Parameters:
    ///   - routes: one entry per trip: that trip's trimmed route segments.
    ///   - cellsAcross: how many cells the longer side of the covered area is cut into.
    public static func make(routes: [[RouteSegment]], cellsAcross: Double = 700) -> HeatMap {
        let trips = routes.map { $0.map(\.points).filter { $0.count > 1 } }.filter { !$0.isEmpty }
        var minLat = Double.infinity, maxLat = -Double.infinity
        var minLon = Double.infinity, maxLon = -Double.infinity
        for trip in trips {
            for segment in trip {
                for point in segment {
                    minLat = min(minLat, point.latitude); maxLat = max(maxLat, point.latitude)
                    minLon = min(minLon, point.longitude); maxLon = max(maxLon, point.longitude)
                }
            }
        }
        guard !trips.isEmpty, minLat.isFinite, minLon.isFinite else { return .empty }

        // A flat local grid in metres: good enough to bin points, and the same for every trip.
        let metersPerLat = 110_574.0
        let metersPerLon = 111_320.0 * max(cos((minLat + maxLat) / 2 * .pi / 180), 0.05)
        let span = max((maxLon - minLon) * metersPerLon, (maxLat - minLat) * metersPerLat)
        let cell = min(cellMetersRange.upperBound, max(cellMetersRange.lowerBound, span / max(cellsAcross, 1)))
        let step = cell * stepFraction

        let words = (trips.count + 63) / 64
        var index: [Int: Int] = [:]          // grid key -> cell number
        var keys: [Int] = []
        var sumLat: [Double] = [], sumLon: [Double] = [], samples: [Double] = []
        var bits: [UInt64] = []              // `words` per cell: which trips passed
        var edges = Set<UInt64>()            // undirected pairs of cell numbers

        func cellNumber(_ lat: Double, _ lon: Double) -> Int {
            let x = Int(((lon - minLon) * metersPerLon / cell).rounded(.down))
            let y = Int(((lat - minLat) * metersPerLat / cell).rounded(.down))
            let key = (y + 1) * rowStride + x + 1
            if let found = index[key] { return found }
            let number = keys.count
            index[key] = number
            keys.append(key)
            sumLat.append(0); sumLon.append(0); samples.append(0)
            bits.append(contentsOf: repeatElement(0, count: words))
            return number
        }

        for (trip, segments) in trips.enumerated() {
            let word = trip / 64, mask = UInt64(1) << UInt64(trip % 64)
            for segment in segments {
                var previous = -1
                func visit(_ lat: Double, _ lon: Double) {
                    let number = cellNumber(lat, lon)
                    sumLat[number] += lat; sumLon[number] += lon; samples[number] += 1
                    bits[number * words + word] |= mask
                    if previous >= 0, previous != number {
                        let low = UInt64(min(previous, number)), high = UInt64(max(previous, number))
                        edges.insert(low << 32 | high)
                    }
                    previous = number
                }
                for (a, b) in zip(segment, segment.dropFirst()) {
                    let dx = (b.longitude - a.longitude) * metersPerLon, dy = (b.latitude - a.latitude) * metersPerLat
                    let pieces = max(1, Int((hypot(dx, dy) / step).rounded(.up)))
                    for piece in 0..<pieces {
                        let t = Double(piece) / Double(pieces)
                        visit(a.latitude + (b.latitude - a.latitude) * t, a.longitude + (b.longitude - a.longitude) * t)
                    }
                }
                if let last = segment.last { visit(last.latitude, last.longitude) }
            }
        }

        // A cell's count is the number of different trips through it or a cell next to it. That way
        // a road that runs along a cell border, with trips falling on either side, still counts them all.
        let cells = keys.count
        var counts = [Int](repeating: 0, count: cells)
        var union = [UInt64](repeating: 0, count: words)
        for number in 0..<cells {
            for w in 0..<words { union[w] = 0 }
            for dy in -1...1 {
                for dx in -1...1 {
                    guard let near = index[keys[number] + dy * rowStride + dx] else { continue }
                    for w in 0..<words { union[w] |= bits[near * words + w] }
                }
            }
            counts[number] = union.reduce(0) { $0 + $1.nonzeroBitCount }
        }
        // A stretch is as busy as its quieter end. The scale ends at the busiest stretch that is
        // drawn, not at a crossing where two roads' trips add up.
        func stretchCount(_ edge: UInt64) -> Int { min(counts[Int(edge >> 32)], counts[Int(edge & 0xFFFF_FFFF)]) }
        let maxCount = edges.map(stretchCount).max() ?? counts.max() ?? 0

        // Neighbours of every cell, with the heat level of the stretch between them.
        var neighbours = [[(cell: Int, level: Int, count: Int)]](repeating: [], count: cells)
        for edge in edges {
            let a = Int(edge >> 32), b = Int(edge & 0xFFFF_FFFF)
            let count = stretchCount(edge)
            let heatLevel = level(count: count, maxCount: maxCount)
            neighbours[a].append((b, heatLevel, count))
            neighbours[b].append((a, heatLevel, count))
        }
        // Dictionary order is not fixed: sort, so the same trips always give the same lines.
        for number in 0..<cells { neighbours[number].sort { $0.cell < $1.cell } }

        func point(_ number: Int) -> RoutePoint {
            RoutePoint(latitude: sumLat[number] / samples[number], longitude: sumLon[number] / samples[number])
        }
        // A line runs through cells with exactly two neighbours of one level, and ends anywhere else.
        func isJoint(_ number: Int) -> Bool {
            let n = neighbours[number]
            return n.count != 2 || n[0].level != n[1].level
        }
        var walked = Set<UInt64>()
        func key(_ a: Int, _ b: Int) -> UInt64 { UInt64(min(a, b)) << 32 | UInt64(max(a, b)) }
        var lines: [Line] = []
        func walk(from start: Int, towards first: (cell: Int, level: Int, count: Int)) {
            guard walked.insert(key(start, first.cell)).inserted else { return }
            var points = [point(start), point(first.cell)]
            var previous = start, current = first.cell, count = first.count
            while !isJoint(current), current != start {
                let options = neighbours[current]
                let next = options[0].cell == previous ? options[1] : options[0]
                guard walked.insert(key(current, next.cell)).inserted else { break }
                points.append(point(next.cell))
                count = max(count, next.count)
                previous = current
                current = next.cell
            }
            lines.append(Line(points: points, count: count,
                              heat: Double(first.level) / Double(levels - 1)))
        }
        for number in 0..<cells where isJoint(number) {
            for neighbour in neighbours[number] { walk(from: number, towards: neighbour) }
        }
        // What is left are closed loops with no joint.
        for number in 0..<cells {
            for neighbour in neighbours[number] { walk(from: number, towards: neighbour) }
        }

        // Coldest first; equal heat keeps its order.
        let ordered = lines.enumerated().sorted {
            $0.element.heat == $1.element.heat ? $0.offset < $1.offset : $0.element.heat < $1.element.heat
        }.map(\.element)
        return HeatMap(lines: ordered, maxCount: maxCount, tripCount: trips.count, cellMeters: cell)
    }
}

/// A heat map laid out for one view: the base map and every line in view points.
public struct HeatScene: Sendable, Codable, Equatable {
    public struct Line: Sendable, Codable, Equatable {
        public var points: [PlanePoint]
        public var count: Int
        public var heat: Double
    }

    /// Outlines and labels. Its own `routes` are only a thinned copy used to place the labels;
    /// draw `lines` instead.
    public var map: MapScene
    /// Coldest first.
    public var lines: [Line]
    public var maxCount: Int
}
