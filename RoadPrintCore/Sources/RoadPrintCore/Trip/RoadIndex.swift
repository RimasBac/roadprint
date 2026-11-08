import Foundation

/// The sign family of a road. Raw values are stable (stored in exports); `rank` breaks ties
/// (motorways and interstates first).
public enum RoadNetwork: String, Sendable, Codable, Equatable, Hashable, CaseIterable {
    case usInterstate, usHighway, canadaHighway, eRoad, ukMotorway, ukARoad, australia, generic

    /// Higher wins a tie in `MainRoadGuesser`.
    public var rank: Int {
        switch self {
        case .usInterstate: 7
        case .ukMotorway: 6
        case .eRoad: 5
        case .canadaHighway: 4
        case .usHighway: 3
        case .ukARoad: 2
        case .australia: 1
        case .generic: 0
        }
    }

    /// Byte code in `roads.rpgeo` (`Tools/roads/FORMAT.md`).
    static func fromFileCode(_ code: UInt8) -> RoadNetwork? {
        switch code {
        case 0: .generic
        case 1: .usInterstate
        case 2: .usHighway
        case 3: .canadaHighway
        case 4: .eRoad
        case 5: .ukMotorway
        case 6: .ukARoad
        case 7: .australia
        default: nil
        }
    }
}

/// The road a trip mostly followed, for the trip summary's road sign.
public struct MainRoad: Sendable, Codable, Equatable, Hashable {
    public var network: RoadNetwork
    /// Short ref as the sign shows it: "80" (usInterstate), "E40", "M6", "A40".
    public var ref: String
    /// ISO 3166-1 alpha-2 (or the Natural Earth A3 fallback) of the road's first matched sample; nil if unknown.
    public var countryCode: String?

    public init(network: RoadNetwork, ref: String, countryCode: String? = nil) {
        self.network = network
        self.ref = ref
        self.countryCode = countryCode
    }
}

public enum RoadIndexError: Error, Equatable {
    case notARoadsFile
    case unsupportedVersion(Int)
    case corrupt
    case resourceMissing
}

/// Nearest-road lookup over the bundled Natural Earth major roads (`roads.rpgeo`,
/// format in `Tools/roads/FORMAT.md`), through a 0.1° grid.
public struct RoadIndex: Sendable {
    public static let supportedVersion = 1

    struct Road: Sendable {
        var network: RoadNetwork
        var ref: String
        var countryCode: String?
    }

    /// Cell size in 1e-5°.
    static let cellSize = 10_000
    static let metersPerDegree = Geo.earthRadiusMeters * .pi / 180
    /// Edges are indexed for lookups up to this far away.
    static let maxRadius = 200.0

    private let roads: [Road]
    /// Vertex v is (coords[2v], coords[2v+1]) in 1e-5°.
    private let coords: [Int32]
    /// Per vertex: the road of the edge from this vertex to the next, or -1 for a part's last vertex.
    private let edgeRoad: [Int32]
    private let cells: [Int32: [Int32]]

    public init(data: Data) throws {
        var r = RoadReader(bytes: [UInt8](data))
        guard r.bytes.count >= 5, Array(r.bytes[0..<4]) == Array("RPRD".utf8) else { throw RoadIndexError.notARoadsFile }
        r.pos = 4
        let version = Int(try r.byte())
        guard version == Self.supportedVersion else { throw RoadIndexError.unsupportedVersion(version) }

        let stringCount = try r.count(minBytesEach: 1)
        var strings: [String] = []
        strings.reserveCapacity(stringCount)
        for _ in 0..<stringCount {
            let len = try r.varint()
            guard len >= 0, r.pos + len <= r.bytes.count,
                  let s = String(bytes: r.bytes[r.pos..<(r.pos + len)], encoding: .utf8) else { throw RoadIndexError.corrupt }
            r.pos += len
            strings.append(s)
        }
        func string(_ i: Int) throws -> String {
            guard i >= 0, i < strings.count else { throw RoadIndexError.corrupt }
            return strings[i]
        }

        let roadCount = try r.count(minBytesEach: 6)
        var roads: [Road] = []
        roads.reserveCapacity(roadCount)
        var coords: [Int32] = []
        coords.reserveCapacity(r.bytes.count)
        var edgeRoad: [Int32] = []
        edgeRoad.reserveCapacity(r.bytes.count / 2)
        for roadIndex in 0..<roadCount {
            guard let network = RoadNetwork.fromFileCode(try r.byte()) else { throw RoadIndexError.corrupt }
            let ref = try string(try r.varint())
            let country = try string(try r.varint())
            roads.append(Road(network: network, ref: ref, countryCode: country.isEmpty ? nil : country))
            let partCount = try r.count(minBytesEach: 5)
            for _ in 0..<partCount {
                let n = try r.count(minBytesEach: 2)
                guard n >= 2 else { throw RoadIndexError.corrupt }
                var x = 0, y = 0
                for i in 0..<n {
                    x += try r.svarint()
                    y += try r.svarint()
                    guard abs(x) <= 18_000_000, abs(y) <= 9_000_000 else { throw RoadIndexError.corrupt }
                    coords.append(Int32(x))
                    coords.append(Int32(y))
                    edgeRoad.append(i == n - 1 ? -1 : Int32(roadIndex))
                }
            }
        }
        self.roads = roads
        self.coords = coords
        self.edgeRoad = edgeRoad
        self.cells = Self.buildGrid(coords: coords, edgeRoad: edgeRoad)
    }

    /// The index bundled with RoadPrintCore.
    public static func bundled() throws -> RoadIndex {
        guard let url = Bundle.module.url(forResource: "roads", withExtension: "rpgeo") else {
            throw RoadIndexError.resourceMissing
        }
        return try RoadIndex(data: Data(contentsOf: url))
    }

    // MARK: grid

    private static func cellKey(_ cx: Int, _ cy: Int) -> Int32 {
        Int32((cx + 1_800) * 2_000 + (cy + 1_000))
    }

    private static func floorDiv(_ a: Int, _ b: Int) -> Int {
        a >= 0 ? a / b : -((-a + b - 1) / b)
    }

    /// Lon margin in 1e-5° for `maxRadius` at a latitude (1e-5°), capped near the poles.
    private static func margins(latE5: Int) -> (x: Double, y: Double) {
        let cosLat = max(cos(Double(latE5) * 1e-5 * .pi / 180), 0.05)
        let degrees = maxRadius / metersPerDegree
        return (degrees * 1e5 / cosLat, degrees * 1e5)
    }

    private static func buildGrid(coords: [Int32], edgeRoad: [Int32]) -> [Int32: [Int32]] {
        var cells: [Int32: [Int32]] = [:]
        let cell = Double(cellSize)
        for a in 0..<edgeRoad.count where edgeRoad[a] >= 0 {
            let ax = Double(coords[2 * a]), ay = Double(coords[2 * a + 1])
            let bx = Double(coords[2 * a + 2]), by = Double(coords[2 * a + 3])
            let m = margins(latE5: Int(max(abs(ay), abs(by))))
            let x0 = min(ax, bx) - m.x, x1 = max(ax, bx) + m.x
            let y0 = min(ay, by) - m.y, y1 = max(ay, by) + m.y
            let cx0 = floorDiv(Int(x0.rounded(.down)), cellSize), cx1 = floorDiv(Int(x1.rounded(.down)), cellSize)
            let cy0 = floorDiv(Int(y0.rounded(.down)), cellSize), cy1 = floorDiv(Int(y1.rounded(.down)), cellSize)
            let exactTest = (cx1 - cx0 + 1) * (cy1 - cy0 + 1) > 4
            for cx in cx0...cx1 {
                for cy in cy0...cy1 {
                    if exactTest,
                       !segmentHitsRect(ax, ay, bx, by,
                                        Double(cx) * cell - m.x, Double(cy) * cell - m.y,
                                        Double(cx + 1) * cell + m.x, Double(cy + 1) * cell + m.y) { continue }
                    cells[cellKey(cx, cy), default: []].append(Int32(a))
                }
            }
        }
        return cells
    }

    /// Liang–Barsky segment/rectangle test.
    private static func segmentHitsRect(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double,
                                        _ minX: Double, _ minY: Double, _ maxX: Double, _ maxY: Double) -> Bool {
        var t0 = 0.0, t1 = 1.0
        let dx = bx - ax, dy = by - ay
        for (p, q) in [(-dx, ax - minX), (dx, maxX - ax), (-dy, ay - minY), (dy, maxY - ay)] {
            if p == 0 {
                if q < 0 { return false }
            } else {
                let t = q / p
                if p < 0 { if t > t1 { return false }; t0 = max(t0, t) } else { if t < t0 { return false }; t1 = min(t1, t) }
            }
        }
        return true
    }

    // MARK: lookup

    /// The nearest road within `radius` metres (at most 200), or nil. Roads within 1 m of each
    /// other in distance go to the higher network rank.
    func nearestRoad(lat: Double, lon: Double, radius: Double) -> Road? {
        guard lat.isFinite, lon.isFinite, abs(lat) <= 90, radius > 0 else { return nil }
        let radius = min(radius, Self.maxRadius)
        var lon = lon.truncatingRemainder(dividingBy: 360)
        if lon >= 180 { lon -= 360 } else if lon < -180 { lon += 360 }
        let px = lon * 1e5, py = lat * 1e5
        let cx = Self.floorDiv(Int(px.rounded(.down)), Self.cellSize)
        let cy = Self.floorDiv(Int(py.rounded(.down)), Self.cellSize)
        guard let edges = cells[Self.cellKey(cx, cy)] else { return nil }

        // Metres per 1e-5° east and north at this latitude.
        let ky = Self.metersPerDegree * 1e-5
        let kx = ky * cos(lat * .pi / 180)
        var best = Double.infinity
        var bestRoad: Int32 = -1
        for e in edges {
            let a = Int(e)
            let ax = (Double(coords[2 * a]) - px) * kx, ay = (Double(coords[2 * a + 1]) - py) * ky
            let bx = (Double(coords[2 * a + 2]) - px) * kx, by = (Double(coords[2 * a + 3]) - py) * ky
            let dx = bx - ax, dy = by - ay
            let len2 = dx * dx + dy * dy
            let t = len2 > 0 ? min(max(-(ax * dx + ay * dy) / len2, 0), 1) : 0
            let d = hypot(ax + t * dx, ay + t * dy)
            guard d <= radius else { continue }
            let road = edgeRoad[a]
            if d < best - 1 || (d <= best + 1 && bestRoad >= 0 && roads[Int(road)].network.rank > roads[Int(bestRoad)].network.rank) {
                best = min(best, d)
                bestRoad = road
            }
        }
        return bestRoad >= 0 ? roads[Int(bestRoad)] : nil
    }

    // MARK: decoding

    private struct RoadReader {
        var bytes: [UInt8]
        var pos = 0

        mutating func byte() throws -> UInt8 {
            guard pos < bytes.count else { throw RoadIndexError.corrupt }
            defer { pos += 1 }
            return bytes[pos]
        }

        mutating func varint() throws -> Int {
            var result = 0, shift = 0
            while true {
                let b = try byte()
                result |= Int(b & 0x7F) << shift
                if b < 0x80 { return result }
                shift += 7
                guard shift < 56 else { throw RoadIndexError.corrupt }
            }
        }

        mutating func svarint() throws -> Int {
            let v = try varint()
            return v & 1 == 0 ? v >> 1 : -((v + 1) >> 1)
        }

        mutating func count(minBytesEach: Int) throws -> Int {
            let n = try varint()
            guard n >= 0, n <= (bytes.count - pos) / minBytesEach + 1 else { throw RoadIndexError.corrupt }
            return n
        }
    }
}
