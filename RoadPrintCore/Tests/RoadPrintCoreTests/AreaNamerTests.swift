import Foundation
import Testing
@testable import RoadPrintCore

private func area(_ lat: Double, _ lon: Double, _ radius: Double = 3000) -> ApproximateArea {
    ApproximateArea(centerLatitude: lat, centerLongitude: lon, radiusMeters: radius)
}

/// Builds a tiny areas.rppl: (name, lat, lon, population).
private func bundle(_ places: [(String, Double, Double, Int)]) -> Data {
    var b: [UInt8] = Array("RPPL".utf8) + [1]
    func varint(_ v: Int) { var v = v; while v >= 0x80 { b.append(UInt8(v & 0x7F) | 0x80); v >>= 7 }; b.append(UInt8(v)) }
    func svarint(_ v: Int) { varint(v < 0 ? -2 * v - 1 : 2 * v) }
    func str(_ s: String) { let u = Array(s.utf8); varint(u.count); b += u }
    varint(1); str("XX")
    varint(places.count)
    for p in places { str(p.0); svarint(Int((p.1 * 1e4).rounded())); svarint(Int((p.2 * 1e4).rounded())); varint(p.3); varint(0) }
    return Data(b)
}

@Test func bundledNamesTheI80AndEuropeanCities() throws {
    let namer = try AreaNamer.bundled()
    #expect(namer.placeCount > 4000)
    // The I-80 fixture starts in Salt Lake City and ends in Sacramento; both are the city itself.
    #expect(namer.name(for: area(40.760157, -111.889808)) == "Salt Lake City")
    #expect(namer.name(for: area(38.58, -121.49)) == "Sacramento")
    #expect(namer.name(for: area(54.8985, 23.9036)) == "Kaunas")
    #expect(namer.name(for: area(50.0647, 19.945)) == "Kraków")  // diacritics kept
}

@Test func largestPlaceWinsOverANearerSmallerOne() throws {
    // Centred on Ogden with a 40 km radius, Salt Lake City (about 47 km away) and Ogden both qualify; the larger wins.
    let namer = try AreaNamer.bundled()
    #expect(namer.name(for: area(41.2, -111.97, 40_000)) == "Salt Lake City")
}

@Test func nothingNearbyGivesNil() throws {
    let namer = try AreaNamer.bundled()
    #expect(namer.name(for: area(39.5, -117.2)) == nil)  // Nevada desert, 220 km from any city
}

@Test func nearestWithin60kmWhenNoneIsWithinTheAreaPlusSlack() throws {
    // Alpha (larger) is 51 km away, Beta (smaller) 34 km; neither is within 5 km + 25 km, so the nearest wins.
    let namer = try AreaNamer(data: bundle([("Alpha", 40.0, -100.0, 900_000), ("Beta", 40.0, -99.0, 60_000)]))
    #expect(namer.name(for: area(40.0, -99.4, 5000)) == "Beta")
    #expect(namer.name(for: area(40.0, -98.0, 5000)) == nil)  // 85 km from Beta: nothing within 60 km
}

@Test func equalPopulationPicksTheNearerPlace() throws {
    let namer = try AreaNamer(data: bundle([("Far", 40.1, -100.0, 100_000), ("Near", 40.02, -100.0, 100_000)]))
    #expect(namer.name(for: area(40.0, -100.0, 20_000)) == "Near")
}

@Test func longNamesAreReturnedInFullAndAcrossBordersIsAllowed() throws {
    let long = "Llanfairpwllgwyngyllgogerychwyrndrobwll"
    let namer = try AreaNamer(data: bundle([(long, 53.0, -4.0, 80_000)]))
    #expect(long.count > 22)
    #expect(namer.name(for: area(53.0, -4.0)) == long)
}

@Test func antimeridianAndPolesDoNotCrash() throws {
    let namer = try AreaNamer(data: bundle([("Taveuni", -16.8, 179.9, 70_000)]))
    #expect(namer.name(for: area(-16.8, -179.95)) == "Taveuni")
    #expect(namer.name(for: area(89.99, 0)) == nil)
}

@Test func lookupIsFast() throws {
    let namer = try AreaNamer.bundled()
    let clock = ContinuousClock()
    let n = 1000
    let t = clock.measure { for i in 0..<n { _ = namer.name(for: area(40 + Double(i % 10) * 0.1, -112 + Double(i % 7) * 0.1)) } }
    let perLookup = Double(t.components.attoseconds) / 1e18 / Double(n) + Double(t.components.seconds) / Double(n)
    print("AreaNamer lookup: \(perLookup * 1e6) µs")
    #expect(perLookup < 0.001)
}

@Test func rejectsBadFiles() {
    #expect(throws: AreaNamerError.notAnAreasFile) { try AreaNamer(data: Data([1, 2, 3, 4, 5])) }
    #expect(throws: AreaNamerError.unsupportedVersion(9)) { try AreaNamer(data: Data(Array("RPPL".utf8) + [9])) }
}
