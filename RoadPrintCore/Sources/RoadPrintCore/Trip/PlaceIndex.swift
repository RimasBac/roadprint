import Foundation

/// A country or region: ISO 3166-1 alpha-2 (or the Natural Earth A3 fallback) for a country,
/// ISO 3166-2 for a region. `name` is English.
public struct PlaceRef: Sendable, Codable, Equatable, Hashable {
    public var code: String
    public var name: String

    public init(code: String, name: String) {
        self.code = code
        self.name = name
    }
}

/// Countries and regions a trip crossed, in order of first visit, without repeats.
public struct TripPlaces: Sendable, Codable, Equatable {
    public var countries: [PlaceRef]
    public var regions: [PlaceRef]

    public init(countries: [PlaceRef] = [], regions: [PlaceRef] = []) {
        self.countries = countries
        self.regions = regions
    }
}

/// Raw geographic rings for a place. Rings use even-odd filling, including holes.
public struct PlaceOutline: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case country, region }
    public var kind: Kind
    public var place: PlaceRef
    public var rings: [[GeoCoordinate]]
}

public enum PlaceIndexError: Error, Equatable {
    case notAPlacesFile
    case unsupportedVersion(Int)
    case corrupt
    case resourceMissing
}

/// Offline point-in-country/region lookup over the bundled Natural Earth outlines
/// (`places.rpgeo`, format in `Tools/places/FORMAT.md`).
public struct PlaceIndex: Sendable {
    public static let supportedVersion = 1

    struct Ring: Sendable {
        var start: Int  // vertex index into `coords` (vertex v is coords[2v], coords[2v+1])
        var count: Int
        var minX: Int32, minY: Int32, maxX: Int32, maxY: Int32
        /// Big rings get a y-band index so a lookup touches a fraction of the edges.
        var bandStarts: [Int32] = []
        var bandEdges: [Int32] = []
        var bandMinY: Int32 = 0
        var bandHeight: Int32 = 1
    }

    struct Feature: Sendable {
        var isCountry: Bool
        var ref: PlaceRef
        var parentCode: String
        var minX: Int32, minY: Int32, maxX: Int32, maxY: Int32
        var rings: [Ring]
    }

    static let bandCount = 64
    static let bandThreshold = 256

    private let features: [Feature]
    private let coords: [Int32]
    private let countryCount: Int
    private let countryByCode: [String: Int]
    private let regionsByParent: [String: [Int]]

    public init(data: Data) throws {
        var r = Reader(bytes: [UInt8](data))
        guard r.bytes.count >= 5, Array(r.bytes[0..<4]) == Array("RPGE".utf8) else { throw PlaceIndexError.notAPlacesFile }
        r.pos = 4
        let version = Int(try r.byte())
        guard version == Self.supportedVersion else { throw PlaceIndexError.unsupportedVersion(version) }

        let stringCount = try r.count(minBytesEach: 1)
        var strings: [String] = []
        strings.reserveCapacity(stringCount)
        for _ in 0..<stringCount {
            let len = try r.varint()
            guard len >= 0, r.pos + len <= r.bytes.count else { throw PlaceIndexError.corrupt }
            guard let s = String(bytes: r.bytes[r.pos..<(r.pos + len)], encoding: .utf8) else { throw PlaceIndexError.corrupt }
            r.pos += len
            strings.append(s)
        }
        func string(_ i: Int) throws -> String {
            guard i >= 0, i < strings.count else { throw PlaceIndexError.corrupt }
            return strings[i]
        }

        let featureCount = try r.count(minBytesEach: 8)
        var features: [Feature] = []
        features.reserveCapacity(featureCount)
        var coords: [Int32] = []
        coords.reserveCapacity(r.bytes.count)  // about one vertex per 2-3 bytes
        for _ in 0..<featureCount {
            let kind = try r.byte()
            guard kind <= 1 else { throw PlaceIndexError.corrupt }
            let code = try string(try r.varint())
            let name = try string(try r.varint())
            let parent = try string(try r.varint())
            let minX = try r.svarint(), minY = try r.svarint()
            let maxX = minX + (try r.varint()), maxY = minY + (try r.varint())
            let ringCount = try r.count(minBytesEach: 1)
            var rings: [Ring] = []
            rings.reserveCapacity(ringCount)
            for _ in 0..<ringCount {
                let n = try r.count(minBytesEach: 2)
                guard n >= 3 else { throw PlaceIndexError.corrupt }
                let start = coords.count / 2
                var x = 0, y = 0
                var rminX = Int.max, rminY = Int.max, rmaxX = Int.min, rmaxY = Int.min
                for _ in 0..<n {
                    x += try r.svarint()
                    y += try r.svarint()
                    coords.append(Int32(truncatingIfNeeded: x))
                    coords.append(Int32(truncatingIfNeeded: y))
                    rminX = min(rminX, x); rmaxX = max(rmaxX, x)
                    rminY = min(rminY, y); rmaxY = max(rmaxY, y)
                }
                var ring = Ring(
                    start: start, count: n,
                    minX: Int32(truncatingIfNeeded: rminX), minY: Int32(truncatingIfNeeded: rminY),
                    maxX: Int32(truncatingIfNeeded: rmaxX), maxY: Int32(truncatingIfNeeded: rmaxY))
                if n >= Self.bandThreshold { Self.buildBands(&ring, coords: coords) }
                rings.append(ring)
            }
            features.append(Feature(
                isCountry: kind == 0, ref: PlaceRef(code: code, name: name), parentCode: parent,
                minX: Int32(truncatingIfNeeded: minX), minY: Int32(truncatingIfNeeded: minY),
                maxX: Int32(truncatingIfNeeded: maxX), maxY: Int32(truncatingIfNeeded: maxY), rings: rings))
        }

        // The file lists countries first, then regions.
        let countryCount = features.prefix { $0.isCountry }.count
        guard !features[countryCount...].contains(where: \.isCountry) else { throw PlaceIndexError.corrupt }
        var countryByCode: [String: Int] = [:]
        for i in 0..<countryCount { countryByCode[features[i].ref.code] = i }
        var regionsByParent: [String: [Int]] = [:]
        for i in countryCount..<features.count { regionsByParent[features[i].parentCode, default: []].append(i) }

        self.features = features
        self.coords = coords
        self.countryCount = countryCount
        self.countryByCode = countryByCode
        self.regionsByParent = regionsByParent
    }

    /// The index bundled with RoadPrintCore.
    public static func bundled() throws -> PlaceIndex {
        guard let url = Bundle.module.url(forResource: "places", withExtension: "rpgeo") else {
            throw PlaceIndexError.resourceMissing
        }
        return try PlaceIndex(data: Data(contentsOf: url))
    }

    // MARK: lookup

    /// Returns rings whose geographic bounding boxes intersect the query. Longitude
    /// ranges may cross the antimeridian (west > east). Rings are not clipped.
    public func outlines(south: Double, west: Double, north: Double, east: Double) -> [PlaceOutline] {
        guard [south, west, north, east].allSatisfy(\.isFinite),
              south >= -90, north <= 90, south <= north,
              west >= -180, west <= 180, east >= -180, east <= 180 else { return [] }
        func intersects(_ minX: Int32, _ minY: Int32, _ maxX: Int32, _ maxY: Int32) -> Bool {
            let x0 = Double(minX) / 1e5, x1 = Double(maxX) / 1e5
            let longitudeMatches = west <= east ? x1 >= west && x0 <= east : x1 >= west || x0 <= east
            return longitudeMatches && Double(maxY) / 1e5 >= south && Double(minY) / 1e5 <= north
        }
        return features.compactMap { feature in
            guard intersects(feature.minX, feature.minY, feature.maxX, feature.maxY) else { return nil }
            let rings = feature.rings.filter { intersects($0.minX, $0.minY, $0.maxX, $0.maxY) }.map { ring in
                (ring.start..<(ring.start + ring.count)).map { vertex in
                    GeoCoordinate(latitude: Double(coords[2 * vertex + 1]) / 1e5,
                                  longitude: Double(coords[2 * vertex]) / 1e5)
                }
            }
            guard !rings.isEmpty else { return nil }
            return PlaceOutline(kind: feature.isCountry ? .country : .region, place: feature.ref, rings: rings)
        }
    }

    /// The country and region containing a point, or nil where there is none (open sea,
    /// or a country without admin-1 data). Longitudes outside −180…180 are wrapped.
    public func place(at lat: Double, lon: Double) -> (country: PlaceRef?, region: PlaceRef?) {
        let found = lookup(lat: lat, lon: lon, hint: (nil, nil))
        return (found.country.map { features[$0].ref }, found.region.map { features[$0].ref })
    }

    /// Countries and regions the route crossed. A place counts only if at least two
    /// consecutive points fall in it, or the run (with its neighbouring edges) is at
    /// least 1 km long, so border jitter doesn't add a country.
    public func places(along points: [RoutePoint]) -> TripPlaces {
        var countryKeys: [Int?] = []
        var regionKeys: [Int?] = []
        countryKeys.reserveCapacity(points.count)
        regionKeys.reserveCapacity(points.count)
        var hint: (country: Int?, region: Int?) = (nil, nil)
        for p in points {
            let found = lookup(lat: p.latitude, lon: p.longitude, hint: hint)
            countryKeys.append(found.country)
            regionKeys.append(found.region)
            hint = found
        }
        let countries = Self.qualifying(countryKeys, points: points).map { features[$0].ref }
        let regions = Self.qualifying(regionKeys, points: points).map { features[$0].ref }
        return TripPlaces(countries: countries, regions: regions)
    }

    static let minRunLength = 1000.0

    /// Feature indices with a qualifying run, in order of first qualifying run.
    private static func qualifying(_ keys: [Int?], points: [RoutePoint]) -> [Int] {
        var result: [Int] = []
        var seen = Set<Int>()
        var i = 0
        while i < keys.count {
            guard let key = keys[i] else { i += 1; continue }
            var j = i + 1
            while j < keys.count, keys[j] == key { j += 1 }
            if !seen.contains(key) {
                var ok = j - i >= 2
                if !ok {
                    var length = 0.0
                    let from = max(i - 1, 0), to = min(j, points.count - 1)
                    if from < to { for k in from..<to { length += distance(points[k], points[k + 1]) } }
                    ok = length >= minRunLength
                }
                if ok { seen.insert(key); result.append(key) }
            }
            i = j
        }
        return result
    }

    private static func distance(_ a: RoutePoint, _ b: RoutePoint) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1, dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * Geo.earthRadiusMeters * asin(min(1, sqrt(h)))
    }

    private func lookup(lat: Double, lon: Double, hint: (country: Int?, region: Int?)) -> (country: Int?, region: Int?) {
        guard lat.isFinite, lon.isFinite, abs(lat) <= 90 else { return (nil, nil) }
        var lon = lon.truncatingRemainder(dividingBy: 360)
        if lon >= 180 { lon -= 360 } else if lon < -180 { lon += 360 }
        let x = Int32((lon * 1e5).rounded()), y = Int32((lat * 1e5).rounded())

        var country: Int?
        if let h = hint.country, contains(h, x, y) {
            country = h
        } else {
            for i in 0..<countryCount where contains(i, x, y) { country = i; break }
        }

        var region: Int?
        if let h = hint.region, contains(h, x, y), country == nil || features[h].parentCode == features[country!].ref.code {
            region = h
        } else if let c = country {
            for i in regionsByParent[features[c].ref.code] ?? [] where contains(i, x, y) { region = i; break }
        } else {
            for i in countryCount..<features.count where contains(i, x, y) { region = i; break }
        }
        // Coastline mismatch between the two layers: the region still names its country.
        if country == nil, let r = region { country = countryByCode[features[r].parentCode] }
        return (country, region)
    }

    private func contains(_ index: Int, _ x: Int32, _ y: Int32) -> Bool {
        let f = features[index]
        guard x >= f.minX, x <= f.maxX, y >= f.minY, y <= f.maxY else { return false }
        var inside = false
        for ring in f.rings where x >= ring.minX && x <= ring.maxX && y >= ring.minY && y <= ring.maxY {
            if ringContains(ring, x, y) { inside.toggle() }  // even-odd across rings: holes just work
        }
        return inside
    }

    /// Crossing parity of a ray towards +x.
    private func ringContains(_ ring: Ring, _ x: Int32, _ y: Int32) -> Bool {
        var inside = false
        let px = Double(x), py = Double(y)
        func edge(_ a: Int, _ b: Int) {
            let ax = Double(coords[2 * a]), ay = Double(coords[2 * a + 1])
            let bx = Double(coords[2 * b]), by = Double(coords[2 * b + 1])
            if (ay > py) != (by > py), px < (bx - ax) * (py - ay) / (by - ay) + ax { inside.toggle() }
        }
        if ring.bandStarts.isEmpty {
            var prev = ring.start + ring.count - 1
            for cur in ring.start..<(ring.start + ring.count) { edge(prev, cur); prev = cur }
        } else {
            let band = min(max(Int((y - ring.bandMinY) / ring.bandHeight), 0), Self.bandCount - 1)
            for e in ring.bandEdges[Int(ring.bandStarts[band])..<Int(ring.bandStarts[band + 1])] {
                let a = ring.start + Int(e)
                edge(a, e == Int32(ring.count - 1) ? ring.start : a + 1)
            }
        }
        return inside
    }

    /// Edge `e` runs from vertex `e` to vertex `e + 1` (wrapping), listed in every band its y-range touches.
    private static func buildBands(_ ring: inout Ring, coords: [Int32]) {
        let height = Int32((Int(ring.maxY) - Int(ring.minY)) / bandCount + 1)
        ring.bandMinY = ring.minY
        ring.bandHeight = height
        func band(_ y: Int32) -> Int { min(Int((y - ring.minY) / height), bandCount - 1) }
        func span(_ e: Int) -> ClosedRange<Int> {
            let a = ring.start + e, b = e == ring.count - 1 ? ring.start : a + 1
            let ya = coords[2 * a + 1], yb = coords[2 * b + 1]
            return band(min(ya, yb))...band(max(ya, yb))
        }
        var counts = [Int32](repeating: 0, count: bandCount + 1)
        for e in 0..<ring.count { for b in span(e) { counts[b + 1] += 1 } }
        for b in 0..<bandCount { counts[b + 1] += counts[b] }
        var fill = counts
        var edges = [Int32](repeating: 0, count: Int(counts[bandCount]))
        for e in 0..<ring.count {
            for b in span(e) { edges[Int(fill[b])] = Int32(e); fill[b] += 1 }
        }
        ring.bandStarts = counts
        ring.bandEdges = edges
    }

    // MARK: decoding

    private struct Reader {
        var bytes: [UInt8]
        var pos = 0

        mutating func byte() throws -> UInt8 {
            guard pos < bytes.count else { throw PlaceIndexError.corrupt }
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
                guard shift < 56 else { throw PlaceIndexError.corrupt }
            }
        }

        mutating func svarint() throws -> Int {
            let v = try varint()
            return v & 1 == 0 ? v >> 1 : -((v + 1) >> 1)
        }

        /// A count that can't exceed what the remaining bytes could hold.
        mutating func count(minBytesEach: Int) throws -> Int {
            let n = try varint()
            guard n >= 0, n <= (bytes.count - pos) / minBytesEach + 1 else { throw PlaceIndexError.corrupt }
            return n
        }
    }
}
