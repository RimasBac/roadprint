import Foundation
import Testing
@testable import RoadPrintCore

// MARK: synthetic index

private struct SynthRoad {
    var network: UInt8
    var ref: String
    var country = "XX"
    var parts: [[(Int, Int)]]  // E5 degrees (lon, lat)
}

private func varint(_ v: Int) -> [UInt8] {
    var v = v, out: [UInt8] = []
    while v >= 0x80 { out.append(UInt8(v & 0x7F) | 0x80); v >>= 7 }
    out.append(UInt8(v))
    return out
}

private func svarint(_ v: Int) -> [UInt8] { varint(v < 0 ? -2 * v - 1 : 2 * v) }

private func makeRoads(_ roads: [SynthRoad], version: UInt8 = 1) -> Data {
    let strings = Array(Set(roads.flatMap { [$0.ref, $0.country] })).sorted()
    var out: [UInt8] = Array("RPRD".utf8) + [version]
    out += varint(strings.count)
    for s in strings { out += varint(s.utf8.count) + Array(s.utf8) }
    out += varint(roads.count)
    for r in roads {
        out.append(r.network)
        out += varint(strings.firstIndex(of: r.ref)!) + varint(strings.firstIndex(of: r.country)!)
        out += varint(r.parts.count)
        for part in r.parts {
            out += varint(part.count)
            var px = 0, py = 0
            for (x, y) in part { out += svarint(x - px) + svarint(y - py); px = x; py = y }
        }
    }
    return Data(out)
}

/// A line along latitude `lat` from `lon0` to `lon1` degrees.
private func eastWest(_ lat: Double, _ lon0: Double, _ lon1: Double) -> [(Int, Int)] {
    [(Int(lon0 * 1e5), Int(lat * 1e5)), (Int(lon1 * 1e5), Int(lat * 1e5))]
}

/// The route along latitude `lat`, lon 10.00 → 10.20 (about 22 km), in 100 m steps.
private func route(lat: Double = 10.0) -> [RoutePoint] {
    (0...222).map { RoutePoint(latitude: lat, longitude: 10.0 + Double($0) * 0.0009) }
}

/// The route along longitude `lon`, lat 10.00 → 10.20, in 100 m steps.
private func routeNorth(lon: Double) -> [RoutePoint] {
    (0...222).map { RoutePoint(latitude: 10.0 + Double($0) * 0.0009, longitude: lon) }
}

private let interstate: UInt8 = 1, eRoad: UInt8 = 4, generic: UInt8 = 0

// MARK: guesser rules

@Test func shareThresholdIsFifteenPercent() throws {
    func guess(roadEndLon: Double) throws -> MainRoad? {
        let data = makeRoads([SynthRoad(network: interstate, ref: "80", country: "US", parts: [eastWest(10.0, 10.0, roadEndLon)])])
        return MainRoadGuesser(index: try RoadIndex(data: data)).guess(segments: [route()])
    }
    #expect(try guess(roadEndLon: 10.02) == nil)  // 10 % of the route
    #expect(try guess(roadEndLon: 10.04) == MainRoad(network: .usInterstate, ref: "80", countryCode: "US"))  // 20 %
}

@Test func matchRadiusIs150Meters() throws {
    let data = makeRoads([SynthRoad(network: generic, ref: "A1", parts: [eastWest(10.0, 10.0, 10.2)])])
    let guesser = MainRoadGuesser(index: try RoadIndex(data: data))
    #expect(guesser.guess(segments: [route(lat: 10.0 + 120 / 111_195)]) != nil)  // 120 m north
    #expect(guesser.guess(segments: [route(lat: 10.0 + 180 / 111_195)]) == nil)  // 180 m north
}

@Test func mostMatchedDistanceWinsAndTiesGoToTheHigherRank() throws {
    // Road A: 70 % of the route. Road B: the last 30 %.
    let a = SynthRoad(network: generic, ref: "A", parts: [eastWest(10.0, 10.0, 10.14)])
    let b = SynthRoad(network: interstate, ref: "B", parts: [eastWest(10.0, 10.14, 10.2)])
    let guess = MainRoadGuesser(index: try RoadIndex(data: makeRoads([a, b]))).guess(segments: [route()])
    #expect(guess?.ref == "A")

    // Two separate, equally long stretches, one per road: the interstate wins the tie,
    // whatever the file order.
    let n1 = SynthRoad(network: generic, ref: "A", parts: [[(1_000_000, 1_000_000), (1_000_000, 1_020_000)]])
    let n2 = SynthRoad(network: interstate, ref: "B", parts: [[(5_000_000, 1_000_000), (5_000_000, 1_020_000)]])
    let twoStretches = [routeNorth(lon: 10.0), routeNorth(lon: 50.0)]
    for roads in [[n1, n2], [n2, n1]] {
        let tie = MainRoadGuesser(index: try RoadIndex(data: makeRoads(roads))).guess(segments: twoStretches)
        #expect(tie?.network == .usInterstate)
    }
}

@Test func overlappingRoadsPreferTheHigherRank() throws {
    let low = SynthRoad(network: generic, ref: "N1", parts: [eastWest(10.0, 10.0, 10.2)])
    let high = SynthRoad(network: eRoad, ref: "E1", parts: [eastWest(10.0, 10.0, 10.2)])
    for roads in [[low, high], [high, low]] {
        let guess = MainRoadGuesser(index: try RoadIndex(data: makeRoads(roads))).guess(segments: [route()])
        #expect(guess?.ref == "E1")
    }
}

@Test func longDiagonalRoadIsFoundFarFromItsEnds() throws {
    // 2° diagonal: its bounding box covers hundreds of grid cells.
    let data = makeRoads([SynthRoad(network: eRoad, ref: "E9", parts: [[(1_000_000, 1_000_000), (1_200_000, 1_200_000)]])])
    let index = try RoadIndex(data: data)
    #expect(index.nearestRoad(lat: 11.0, lon: 11.0, radius: 150)?.ref == "E9")
    #expect(index.nearestRoad(lat: 11.5, lon: 11.5, radius: 150)?.ref == "E9")
    #expect(index.nearestRoad(lat: 10.0, lon: 12.0, radius: 150) == nil)
    #expect(index.nearestRoad(lat: 12.0, lon: 10.0, radius: 150) == nil)
}

@Test func negativeCoordinatesAndEmptyInputs() throws {
    let data = makeRoads([SynthRoad(network: generic, ref: "S1", parts: [[(-7_000_000, -3_000_000), (-6_900_000, -3_000_000)]])])
    let index = try RoadIndex(data: data)
    #expect(index.nearestRoad(lat: -30.0, lon: -69.5, radius: 150)?.ref == "S1")
    let guesser = MainRoadGuesser(index: index)
    #expect(guesser.guess(segments: []) == nil)
    #expect(guesser.guess(segments: [[]]) == nil)
    #expect(guesser.guess(ProcessedRoute(segments: [])) == nil)
    // A single point has no length; a route shorter than one sample still counts.
    #expect(guesser.guess(segments: [[RoutePoint(latitude: -30.0, longitude: -69.5)]]) == nil)
    let short = [RoutePoint(latitude: -30.0, longitude: -69.5), RoutePoint(latitude: -30.0, longitude: -69.4995)]
    #expect(guesser.guess(segments: [short])?.ref == "S1")
}

@Test func gapsBetweenSegmentsAreNotBridged() throws {
    // A segment on the road and one far away of the same length: 50 %, still a match.
    let data = makeRoads([SynthRoad(network: generic, ref: "A", parts: [eastWest(10.0, 10.0, 10.2)])])
    let guesser = MainRoadGuesser(index: try RoadIndex(data: data))
    let far = routeNorth(lon: 50.0)
    #expect(guesser.guess(segments: [route(), far])?.ref == "A")
    // With five far segments the road is 17 % of the length, with seven 12.5 %.
    #expect(guesser.guess(segments: [route()] + Array(repeating: far, count: 5)) != nil)
    #expect(guesser.guess(segments: [route()] + Array(repeating: far, count: 7)) == nil)
}

@Test func rejectsBadFiles() throws {
    let good = makeRoads([SynthRoad(network: generic, ref: "A", parts: [eastWest(10.0, 10.0, 10.2)])])
    #expect(throws: RoadIndexError.notARoadsFile) { try RoadIndex(data: Data()) }
    #expect(throws: RoadIndexError.notARoadsFile) { try RoadIndex(data: Data("RPGE-places".utf8)) }
    #expect(throws: RoadIndexError.unsupportedVersion(9)) { try RoadIndex(data: makeRoads([], version: 9)) }
    #expect(throws: RoadIndexError.corrupt) { try RoadIndex(data: good.prefix(good.count - 2)) }
    #expect(throws: RoadIndexError.corrupt) { try RoadIndex(data: Data(Array("RPRD".utf8) + [1, 0xFF])) }
    let badNetwork = makeRoads([SynthRoad(network: 99, ref: "A", parts: [eastWest(10.0, 10.0, 10.2)])])
    #expect(throws: RoadIndexError.corrupt) { try RoadIndex(data: badNetwork) }
}

@Test func networkRanksAndFileCodes() {
    let ranked = RoadNetwork.allCases.sorted { $0.rank > $1.rank }
    #expect(ranked.first == .usInterstate)
    #expect(ranked.last == .generic)
    #expect(Set(RoadNetwork.allCases.map(\.rank)).count == RoadNetwork.allCases.count)
    #expect(RoadNetwork.fromFileCode(4) == .eRoad)
    #expect(RoadNetwork.fromFileCode(8) == nil)
}

// MARK: the real bundle

private let bundledRoads: RoadIndex = { try! RoadIndex.bundled() }()

private func loadRoute(_ name: String) throws -> [RoutePoint] {
    let pairs = try JSONDecoder().decode([[Double]].self, from: Fixtures.data(name, ext: "json"))
    return pairs.map { RoutePoint(latitude: $0[0], longitude: $0[1]) }
}

@Test func bundledRoadsLoadQuickly() throws {
    var loaded: RoadIndex?
    let elapsed = try ContinuousClock().measure { loaded = try RoadIndex.bundled() }
    print("road index load: \(elapsed)")
    #expect(loaded != nil)
    #expect(elapsed < .seconds(1.5))  // spec: 300 ms; loose for debug builds on CI
}

@Test func i80RouteIsInterstate80() throws {
    let guess = MainRoadGuesser(index: bundledRoads).guess(segments: [try loadRoute("i80-slc-sac-route")])
    #expect(guess == MainRoad(network: .usInterstate, ref: "80", countryCode: "US"))
}

/// Eight vertices of Natural Earth's E40 near Ostend and Bruges (Belgium).
private let e40Belgium: [RoutePoint] = [
    (51.16499, 2.92371), (51.18264, 2.96944), (51.18899, 2.99298), (51.19205, 3.01736),
    (51.19197, 3.02945), (51.18904, 3.05358), (51.18178, 3.08433), (51.16928, 3.12132),
].map { RoutePoint(latitude: $0.0, longitude: $0.1) }

@Test func e40InBelgiumIsAnERoad() {
    let guess = MainRoadGuesser(index: bundledRoads).guess(segments: [e40Belgium])
    #expect(guess == MainRoad(network: .eRoad, ref: "E40", countryCode: "BE"))
}

@Test func openCountryHasNoMainRoad() {
    // The Australian interior, and the open North Sea.
    let outback = (0...80).map { RoutePoint(latitude: -25.0 - Double($0) * 0.01, longitude: 125.0 + Double($0) * 0.01) }
    let sea = (0...80).map { RoutePoint(latitude: 55.0 + Double($0) * 0.01, longitude: 3.0) }
    let guesser = MainRoadGuesser(index: bundledRoads)
    #expect(guesser.guess(segments: [outback]) == nil)
    #expect(guesser.guess(segments: [sea]) == nil)
}

@Test func thousandSamplesAreFast() throws {
    // About 250 km of I-80 = 1,000 samples.
    var pts = try loadRoute("i80-slc-sac-route")
    var length = 0.0
    if let cut = pts.indices.dropFirst().first(where: { i in
        length += Geo.distance(from: pts[i - 1], to: pts[i])
        return length >= 250_000
    }) { pts = Array(pts[..<cut]) }
    var guess: MainRoad?
    let elapsed = ContinuousClock().measure { guess = MainRoadGuesser(index: bundledRoads).guess(segments: [pts]) }
    print("main road, ~1000 samples: \(elapsed)")
    #expect(guess?.ref == "80")
    #expect(elapsed < .seconds(1))  // spec: 200 ms; loose for debug builds on CI
}

// MARK: processor and model

/// A dense GPS trace along a polyline: 25 m steps, one per second.
private func trace(_ line: [RoutePoint]) -> [TrackPoint] {
    var out: [TrackPoint] = []
    var time = t0
    for i in 1..<line.count {
        let d = Geo.distance(from: line[i - 1], to: line[i])
        let steps = max(1, Int(d / 25))
        for s in 0..<steps {
            let f = Double(s) / Double(steps)
            out.append(TrackPoint(
                latitude: line[i - 1].latitude + (line[i].latitude - line[i - 1].latitude) * f,
                longitude: line[i - 1].longitude + (line[i].longitude - line[i - 1].longitude) * f,
                timestamp: time, horizontalAccuracy: 5))
            time += 1
        }
    }
    return out
}

@Test func processorAddsMainRoad() {
    let trip = Trip(createdAt: t0, points: trace(e40Belgium))
    let with = TripProcessor(roadIndex: bundledRoads).process(trip)
    #expect(with.mainRoad == MainRoad(network: .eRoad, ref: "E40", countryCode: "BE"))
    // Without an index the field stays untouched; the rest of the trip is the same.
    let without = TripProcessor().process(trip)
    #expect(without.mainRoad == nil)
    var stripped = with
    stripped.mainRoad = nil
    #expect(stripped == without)
    // With an index and no match, a stale value is cleared.
    var stale = trip
    stale.mainRoad = MainRoad(network: .generic, ref: "X")
    let offRoad = (0...80).map { RoutePoint(latitude: -25.0 - Double($0) * 0.01, longitude: 125.0) }
    stale.points = trace(offRoad)
    #expect(TripProcessor(roadIndex: bundledRoads).process(stale).mainRoad == nil)
}

@Test func mainRoadRoundTripsAndOldJSONStillDecodes() throws {
    let trip = Trip(createdAt: t0, mainRoad: MainRoad(network: .ukMotorway, ref: "M6", countryCode: "GB"))
    let data = try ExportJSON.encoder().encode(trip)
    #expect(String(decoding: data, as: UTF8.self).contains("ukMotorway"))
    #expect(try ExportJSON.decoder().decode(Trip.self, from: data) == trip)

    let old = try ExportJSON.encoder().encode(Trip(createdAt: t0))
    #expect(!String(decoding: old, as: UTF8.self).contains("mainRoad"))
    #expect(try ExportJSON.decoder().decode(Trip.self, from: old).mainRoad == nil)
}
