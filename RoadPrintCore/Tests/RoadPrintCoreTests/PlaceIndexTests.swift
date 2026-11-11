import Foundation
import Testing
@testable import RoadPrintCore

// MARK: synthetic index (tiny, hand-built, so rules are tested without real borders)

private struct SynthFeature {
    var kind: UInt8
    var code: String
    var name: String
    var parent: String
    var rings: [[(Int, Int)]]  // E5 degrees (lon, lat)
}

private func varint(_ v: Int) -> [UInt8] {
    var v = v, out: [UInt8] = []
    while v >= 0x80 { out.append(UInt8(v & 0x7F) | 0x80); v >>= 7 }
    out.append(UInt8(v))
    return out
}

private func svarint(_ v: Int) -> [UInt8] { varint(v < 0 ? -2 * v - 1 : 2 * v) }

private func makeData(_ features: [SynthFeature], version: UInt8 = 1) -> Data {
    let strings = Array(Set(features.flatMap { [$0.code, $0.name, $0.parent] })).sorted()
    var b: [UInt8] = Array("RPGE".utf8) + [version]
    b += varint(strings.count)
    for s in strings { b += varint(s.utf8.count) + Array(s.utf8) }
    b += varint(features.count)
    for f in features {
        let all = f.rings.flatMap { $0 }
        let minX = all.map(\.0).min()!, maxX = all.map(\.0).max()!
        let minY = all.map(\.1).min()!, maxY = all.map(\.1).max()!
        b.append(f.kind)
        for s in [f.code, f.name, f.parent] { b += varint(strings.firstIndex(of: s)!) }
        b += svarint(minX) + svarint(minY) + varint(maxX - minX) + varint(maxY - minY)
        b += varint(f.rings.count)
        for ring in f.rings {
            b += varint(ring.count)
            var px = 0, py = 0
            for (x, y) in ring { b += svarint(x - px) + svarint(y - py); px = x; py = y }
        }
    }
    return Data(b)
}

private func square(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> [(Int, Int)] {
    [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
}

private let deg = 100_000

/// Country AA: lon 0…1, lat 0…1, with a hole at lon 0.4…0.6 (country HOLE sits inside it).
/// Country BB: lon 1…2, lat 0…1. Regions AA-1 / AA-2 split AA at lon 0.5 (not covering the hole).
private func synth() throws -> PlaceIndex {
    try PlaceIndex(data: makeData([
        SynthFeature(kind: 0, code: "AA", name: "Aland", parent: "AA",
                     rings: [square(0, 0, deg, deg), square(2 * deg / 5, deg / 4, 3 * deg / 5, 3 * deg / 4)]),
        SynthFeature(kind: 0, code: "BB", name: "Bland", parent: "BB", rings: [square(deg, 0, 2 * deg, deg)]),
        SynthFeature(kind: 0, code: "HH", name: "Hole", parent: "HH",
                     rings: [square(2 * deg / 5, deg / 4, 3 * deg / 5, 3 * deg / 4)]),
        SynthFeature(kind: 1, code: "AA-1", name: "West", parent: "AA", rings: [square(0, 0, deg / 2, deg)]),
        SynthFeature(kind: 1, code: "AA-2", name: "East", parent: "AA", rings: [square(deg / 2, 0, deg, deg)]),
    ]))
}

private func route(_ coords: [(Double, Double)]) -> [RoutePoint] {
    coords.map { RoutePoint(latitude: $0.0, longitude: $0.1) }
}

@Test func outlineQueryReturnsIntersectingRingsAndKinds() throws {
    let index = try synth()
    let outlines = index.outlines(south: 0.3, west: 0.45, north: 0.7, east: 0.55)
    #expect(outlines.map(\.place.code) == ["AA", "HH", "AA-1", "AA-2"])
    #expect(outlines[0].kind == .country)
    #expect(outlines[0].rings.count == 2)
    #expect(outlines[2].kind == .region)
    #expect(outlines[2].rings[0][1] == GeoCoordinate(latitude: 0, longitude: 0.5))
    #expect(index.outlines(south: 3, west: 0, north: 4, east: 1).isEmpty)
    #expect(index.outlines(south: .nan, west: 0, north: 4, east: 1).isEmpty)
    #expect(index.outlines(south: 0, west: 170, north: 1, east: -170).isEmpty)
}

@Test func synthPointInPolygonAndHole() throws {
    let index = try synth()
    #expect(index.place(at: 0.5, lon: 0.1).country?.code == "AA")
    #expect(index.place(at: 0.5, lon: 0.1).region?.code == "AA-1")
    #expect(index.place(at: 0.1, lon: 0.9).region?.code == "AA-2")
    #expect(index.place(at: 0.5, lon: 1.5).country?.code == "BB")
    #expect(index.place(at: 0.5, lon: 1.5).region == nil)
    // Inside the hole: AA is not there, the nested country is.
    let hole = index.place(at: 0.5, lon: 0.5)
    #expect(hole.country?.code == "HH")
    #expect(index.place(at: 0.5, lon: 2.5).country == nil)
    #expect(index.place(at: 2, lon: 0.5).country == nil)
}

@Test func synthInvalidInputs() throws {
    let index = try synth()
    #expect(index.place(at: .nan, lon: 0).country == nil)
    #expect(index.place(at: 95, lon: 0).country == nil)
    // Longitudes wrap.
    #expect(index.place(at: 0.5, lon: 360.1).country?.code == "AA")
    #expect(index.place(at: 0.5, lon: -359.9).country?.code == "AA")
}

@Test func synthBorderJitterDoesNotAddACountry() throws {
    let index = try synth()
    // One stray BB point, ~50 m from AA's points on both sides.
    let pts = route([(0.5, 0.9990), (0.5, 0.9995), (0.5, 1.0005), (0.5, 0.9996), (0.5, 0.9999)])
    #expect(index.places(along: pts).countries.map(\.code) == ["AA"])
}

@Test func synthTwoConsecutivePointsCount() throws {
    let index = try synth()
    let pts = route([(0.5, 0.9980), (0.5, 0.9985), (0.5, 0.9990), (0.5, 1.0005), (0.5, 1.0008), (0.5, 0.9996), (0.5, 0.9990)])
    #expect(index.places(along: pts).countries.map(\.code) == ["AA", "BB"])
}

@Test func synthSingleFarPointCountsAsALongRun() throws {
    let index = try synth()
    // A sparse route: the lone BB vertex is ~55 km from both neighbours.
    let pts = route([(0.5, 0.95), (0.5, 1.5), (0.5, 0.05)])
    #expect(index.places(along: pts).countries.map(\.code) == ["AA", "BB"])
}

@Test func synthOrderedAndDeduplicated() throws {
    let index = try synth()
    let pts = route([(0.1, 0.1), (0.1, 0.2), (0.1, 0.7), (0.1, 0.8), (0.1, 1.5), (0.1, 1.6), (0.1, 0.9), (0.1, 0.8), (0.1, 0.1), (0.1, 0.2)])
    let places = index.places(along: pts)
    #expect(places.countries.map(\.code) == ["AA", "BB"])
    #expect(places.regions.map(\.code) == ["AA-1", "AA-2"])
    #expect(places.regions.map(\.name) == ["West", "East"])
}

@Test func synthEmptyRoute() throws {
    let index = try synth()
    #expect(index.places(along: []) == TripPlaces())
    #expect(index.places(along: route([(0.5, 0.1)])).countries.isEmpty)  // one point, no neighbours, under 1 km
}

@Test func synthBandedRingMatchesBruteForce() throws {
    // A spiky ring with more vertices than the band threshold, against a plain even-odd test.
    var ring: [(Int, Int)] = []
    let n = 600
    for i in 0..<n {
        let a = Double(i) / Double(n) * 2 * .pi
        let r = i % 2 == 0 ? 90_000.0 : 60_000.0
        ring.append((Int(100_000 + r * cos(a)), Int(100_000 + r * sin(a))))
    }
    let index = try PlaceIndex(data: makeData([SynthFeature(kind: 0, code: "ST", name: "Star", parent: "ST", rings: [ring])]))
    func brute(_ x: Int, _ y: Int) -> Bool {
        var inside = false
        var j = ring.count - 1
        for i in 0..<ring.count {
            let (ax, ay) = (Double(ring[j].0), Double(ring[j].1)), (bx, by) = (Double(ring[i].0), Double(ring[i].1))
            if (ay > Double(y)) != (by > Double(y)), Double(x) < (bx - ax) * (Double(y) - ay) / (by - ay) + ax { inside.toggle() }
            j = i
        }
        return inside
    }
    var checked = 0, insideCount = 0
    for x in stride(from: 3, to: 200_000, by: 1777) {
        for y in stride(from: 5, to: 200_000, by: 1531) {
            let got = index.place(at: Double(y) / 1e5, lon: Double(x) / 1e5).country != nil
            let want = brute(x, y)
            #expect(got == want)
            checked += 1
            if want { insideCount += 1 }
        }
    }
    #expect(checked > 10_000)
    #expect(insideCount > 1_000)
}

@Test func rejectsBadData() {
    #expect(throws: PlaceIndexError.notAPlacesFile) { try PlaceIndex(data: Data()) }
    #expect(throws: PlaceIndexError.notAPlacesFile) { try PlaceIndex(data: Data("nope-nope".utf8)) }
    #expect(throws: PlaceIndexError.unsupportedVersion(9)) { try PlaceIndex(data: Data(Array("RPGE".utf8) + [9, 0])) }
    let good = makeData([SynthFeature(kind: 0, code: "AA", name: "A", parent: "AA", rings: [square(0, 0, 10, 10)])])
    #expect(throws: PlaceIndexError.corrupt) { try PlaceIndex(data: good.prefix(good.count - 3)) }
    #expect(throws: PlaceIndexError.corrupt) { try PlaceIndex(data: Data(Array("RPGE".utf8) + [1, 0xFF])) }
}

// MARK: the real bundle

private let bundled: PlaceIndex = { try! PlaceIndex.bundled() }()

private func codes(_ lat: Double, _ lon: Double) -> [String] {
    let p = bundled.place(at: lat, lon: lon)
    return [p.country?.code, p.region?.code].compactMap { $0 }
}

private func country(_ lat: Double, _ lon: Double) -> String? {
    bundled.place(at: lat, lon: lon).country?.code
}

@Test func bundleLoadsQuickly() throws {
    var loaded: PlaceIndex?
    let elapsed = try ContinuousClock().measure { loaded = try PlaceIndex.bundled() }
    print("places index load: \(elapsed)")
    #expect(loaded != nil)
    #expect(elapsed < .seconds(1.5))  // spec: 300 ms; loose for debug builds on CI
}

@Test func bundledCitiesAndRegions() {
    #expect(codes(40.7608, -111.891) == ["US", "US-UT"])
    #expect(bundled.place(at: 40.7608, lon: -111.891).region?.name == "Utah")
    #expect(codes(39.5296, -119.8138) == ["US", "US-NV"])
    // Natural Earth's France regions are departments: Paris is FR-75.
    #expect(codes(48.8566, 2.3522) == ["FR", "FR-75"])
    #expect(country(52.5200, 13.4050) == "DE")
    #expect(country(54.6872, 25.2797) == "LT")
    #expect(country(59.9139, 10.7522) == "NO")  // plain ISO_A2 is -99 for Norway
}

@Test func bundledOpenSeaIsNil() {
    let p = bundled.place(at: 0, lon: -30)
    #expect(p.country == nil && p.region == nil)
    #expect(bundled.place(at: -45, lon: -150).country == nil)
}

@Test func bundledAntimeridian() {
    // Fiji, either side of 180°.
    #expect(country(-17.8, 178.4) == "FJ")  // Viti Levu
    #expect(country(-16.85, -179.95) == "FJ")  // Taveuni
    // Chukotka (Russia) either side.
    #expect(country(67.0, 175.0) == "RU")
    #expect(country(67.5, -178.0) == "RU")
    // Aleutians (Alaska) either side.
    #expect(codes(52.9, 172.9) == ["US", "US-AK"])  // Attu
    #expect(codes(51.8, -176.7) == ["US", "US-AK"])  // Adak
    // 180 itself and wrapped longitudes.
    #expect(bundled.place(at: -17.8, lon: 178.4 + 360).country?.code == "FJ")
}

@Test func bundledLesothoIsAHoleInSouthAfrica() {
    #expect(country(-29.31, 27.48) == "LS")  // Maseru
    #expect(country(-29.1, 26.2) == "ZA")  // Bloemfontein, surrounding
    #expect(country(-26.2, 28.05) == "ZA")  // Johannesburg
}

@Test func bundledPlacesAlongI80() throws {
    let route = try i80Route()
    let places = bundled.places(along: route)
    #expect(places.regions.map(\.code) == ["US-UT", "US-NV", "US-CA"])
    #expect(places.countries.map(\.code) == ["US"])
}

private func i80Route() throws -> [RoutePoint] {
    let rows = try JSONDecoder().decode([[Double]].self, from: Fixtures.data("i80-slc-sac-route", ext: "json"))
    return rows.map { RoutePoint(latitude: $0[0], longitude: $0[1]) }
}

@Test func bundledLookupSpeed() throws {
    // ~1,000 points along I-80, densified by interpolation.
    let sparse = try i80Route()
    var dense: [RoutePoint] = []
    for i in 0..<(sparse.count - 1) {
        for k in 0..<3 {
            let f = Double(k) / 3
            dense.append(RoutePoint(
                latitude: sparse[i].latitude + (sparse[i + 1].latitude - sparse[i].latitude) * f,
                longitude: sparse[i].longitude + (sparse[i + 1].longitude - sparse[i].longitude) * f))
        }
    }
    #expect(dense.count >= 1000)
    let pts = Array(dense.prefix(1000))
    var result = TripPlaces()
    let elapsed = ContinuousClock().measure { result = bundled.places(along: pts) }
    print("places lookup, 1000 points: \(elapsed)")
    #expect(!result.regions.isEmpty)
    #expect(elapsed < .seconds(1))  // spec: 200 ms; loose for debug builds on CI
}

// MARK: processor and model

@Test func processorAddsPlacesBeforeTrim() throws {
    // The I-80 GPX fixture is the first 30 km, all in Utah.
    let raw = try Fixtures.points("i80-ui-test")
    let trip = Trip(createdAt: t0, points: raw)
    let withPlaces = TripProcessor(placeIndex: bundled).process(trip)
    #expect(withPlaces.places?.countries.map(\.code) == ["US"])
    #expect(withPlaces.places?.regions.map(\.code) == ["US-UT"])
    let without = TripProcessor().process(trip)
    #expect(without.places == nil)
    // The rest of the processed trip is unchanged.
    var stripped = withPlaces
    stripped.places = nil
    #expect(stripped == without)
}

@Test func tripPlacesRoundTripsAndOldJSONStillDecodes() throws {
    let places = TripPlaces(
        countries: [PlaceRef(code: "US", name: "United States of America")],
        regions: [PlaceRef(code: "US-UT", name: "Utah")])
    let trip = Trip(createdAt: t0, places: places)
    let data = try ExportJSON.encoder().encode(trip)
    #expect(try ExportJSON.decoder().decode(Trip.self, from: data) == trip)

    let old = try ExportJSON.encoder().encode(Trip(createdAt: t0))
    #expect(!String(decoding: old, as: UTF8.self).contains("places"))
    #expect(try ExportJSON.decoder().decode(Trip.self, from: old).places == nil)
}
