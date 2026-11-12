import Foundation

public enum AreaNamerError: Error, Equatable {
    case notAnAreasFile
    case unsupportedVersion(Int)
    case corrupt
    case resourceMissing
}

/// Names an approximate area ("Salt Lake City" for "Salt Lake City area") from the bundled
/// Natural Earth populated places (`areas.rppl`, format in `Tools/places/FORMAT.md`).
///
/// Privacy: only the already approximate `ApproximateArea` goes in, never the trimmed raw points.
/// The app adds the word "area" through the String Catalog, and truncates names it can't fit.
public struct AreaNamer: Sendable {
    public static let supportedVersion = 1
    /// A place may lie this far outside the area circle and still win by population.
    public static let largestPlaceSlackMeters = 25_000.0
    /// Otherwise the nearest place within this distance of the centre.
    public static let nearestPlaceMeters = 60_000.0

    struct Place: Sendable {
        var name: String
        var lat: Double
        var lon: Double
        var population: Int
    }

    private static let cellDegrees = 1.0
    private let places: [Place]
    /// Grid index: 1° cells → place indices. A lookup reads a handful of cells, not all places.
    private let grid: [Int: [Int]]

    public init(data: Data) throws {
        let bytes = [UInt8](data)
        var pos = 0
        func byte() throws -> UInt8 {
            guard pos < bytes.count else { throw AreaNamerError.corrupt }
            defer { pos += 1 }
            return bytes[pos]
        }
        func varint() throws -> Int {
            var result = 0, shift = 0
            while true {
                let b = try byte()
                result |= Int(b & 0x7F) << shift
                if b < 0x80 { return result }
                shift += 7
                guard shift < 56 else { throw AreaNamerError.corrupt }
            }
        }
        func svarint() throws -> Int {
            let v = try varint()
            return v & 1 == 0 ? v >> 1 : -((v + 1) >> 1)
        }
        func string() throws -> String {
            let n = try varint()
            guard n >= 0, pos + n <= bytes.count else { throw AreaNamerError.corrupt }
            defer { pos += n }
            return String(decoding: bytes[pos..<pos + n], as: UTF8.self)
        }
        guard bytes.count >= 5, Array(bytes[0..<4]) == Array("RPPL".utf8) else { throw AreaNamerError.notAnAreasFile }
        pos = 4
        let version = Int(try byte())
        guard version == Self.supportedVersion else { throw AreaNamerError.unsupportedVersion(version) }
        let countryCount = try varint()
        guard countryCount <= bytes.count else { throw AreaNamerError.corrupt }
        for _ in 0..<countryCount { _ = try string() }
        let count = try varint()
        guard count <= bytes.count else { throw AreaNamerError.corrupt }
        var places: [Place] = []
        places.reserveCapacity(count)
        var grid: [Int: [Int]] = [:]
        for i in 0..<count {
            let name = try string()
            let lat = Double(try svarint()) / 1e4, lon = Double(try svarint()) / 1e4
            let pop = try varint()
            _ = try varint()  // country index
            places.append(Place(name: name, lat: lat, lon: lon, population: pop))
            grid[Self.cell(lat: lat, lon: lon), default: []].append(i)
        }
        self.places = places
        self.grid = grid
    }

    public static func bundled() throws -> AreaNamer {
        guard let url = Bundle.module.url(forResource: "areas", withExtension: "rppl") else {
            throw AreaNamerError.resourceMissing
        }
        return try AreaNamer(data: Data(contentsOf: url))
    }

    public var placeCount: Int { places.count }

    /// The largest place within the area radius + 25 km (equal population: the nearer one),
    /// otherwise the nearest within 60 km, otherwise nil. Names are returned in full
    /// (English, diacritics kept); a place across a border is allowed.
    public func name(for area: ApproximateArea) -> String? {
        let lat = area.centerLatitude, lon = area.centerLongitude
        let largestLimit = area.radiusMeters + Self.largestPlaceSlackMeters
        let reach = max(largestLimit, Self.nearestPlaceMeters)

        var largest: (index: Int, distance: Double)?
        var nearest: (index: Int, distance: Double)?
        for i in candidates(lat: lat, lon: lon, reachMeters: reach) {
            let p = places[i]
            let d = Geo.distance(lat1: lat, lon1: lon, lat2: p.lat, lon2: p.lon)
            if d <= largestLimit {
                if let l = largest {
                    let q = places[l.index]
                    if p.population > q.population || (p.population == q.population && d < l.distance) { largest = (i, d) }
                } else {
                    largest = (i, d)
                }
            }
            if d <= Self.nearestPlaceMeters, nearest == nil || d < nearest!.distance { nearest = (i, d) }
        }
        return (largest ?? nearest).map { places[$0.index].name }
    }

    private static func cell(lat: Double, lon: Double) -> Int {
        let r = Int((lat + 90) / cellDegrees), c = Int((lon + 180) / cellDegrees)
        return r * 1000 + c
    }

    private func candidates(lat: Double, lon: Double, reachMeters: Double) -> [Int] {
        let dLat = reachMeters / 111_000
        let cosLat = max(0.01, cos(min(abs(lat) + dLat, 89.9) * .pi / 180))
        let dLon = min(180, reachMeters / (111_000 * cosLat))
        let rows = Int(((lat - dLat + 90) / Self.cellDegrees).rounded(.down))...Int(((lat + dLat + 90) / Self.cellDegrees).rounded(.down))
        let lonLo = Int(((lon - dLon + 180) / Self.cellDegrees).rounded(.down))
        let lonHi = Int(((lon + dLon + 180) / Self.cellDegrees).rounded(.down))
        var out: [Int] = []
        for r in rows where r >= 0 && r <= 180 {
            for c in lonLo...lonHi {
                let wrapped = ((c % 360) + 360) % 360  // across the antimeridian
                if let list = grid[r * 1000 + wrapped] { out += list }
            }
        }
        return out
    }
}
