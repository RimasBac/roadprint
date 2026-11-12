import Foundation
import Testing
@testable import RoadPrintCore

private func i80Segments() throws -> [RouteSegment] {
    let pts = try Fixtures.points("i80-slc-sac").map {
        RoutePoint(latitude: $0.latitude, longitude: $0.longitude, altitude: $0.altitude)
    }
    return [RouteSegment(points: pts)]
}

private func summitOf(_ segments: [RouteSegment]) -> RoutePoint? {
    segments.flatMap(\.points).filter { $0.altitude != nil }.max { $0.altitude! < $1.altitude! }
}

/// A straight north-south line, `count` points `stepDegrees` apart (0.0006° is about 67 m).
private func line(count: Int, stepDegrees: Double, startLat: Double = 40, altitude: (Int) -> Double?) -> RouteSegment {
    RouteSegment(points: (0..<count).map {
        RoutePoint(latitude: startLat + Double($0) * stepDegrees, longitude: -111, altitude: altitude($0))
    })
}

private func length(_ segments: [RouteSegment]) -> Double {
    let pts = segments.flatMap(\.points)
    return zip(pts, pts.dropFirst()).reduce(0) { $0 + Geo.distance(from: $1.0, to: $1.1) }
}

@Test func i80ImperialProfileHasSummitAndTicks() throws {
    let segs = try i80Segments()
    let summit = try #require(summitOf(segs))
    let p = try #require(ElevationProfile.make(segments: segs, summit: summit, unit: .miles))
    let miles = length(segs) / DistanceUnit.metersPerMile
    #expect(abs(p.totalDistance - miles) < 1e-9)
    #expect(abs(p.summit.altitude - summit.altitude! / 0.3048) < 1e-6)
    #expect(abs(p.summit.distance - 390.1) < 1)  // fixture summit, about mile 390
    #expect(p.yTicks.map(\.value) == [0, 2000, 4000, 6000])
    #expect(p.yTicks.dropFirst().allSatisfy(\.isThousands) && !p.yTicks[0].isThousands)
    #expect(p.yTicks.allSatisfy { $0.unit == .foot } && p.yMax >= p.summit.altitude)
    #expect(p.xTicks.dropLast().map(\.value) == [0, 200, 400])  // 600 is within 15 % of the end
    #expect(abs(p.xTicks.last!.value - miles) < 1e-9 && p.xTicks.allSatisfy { $0.unit == .mile })
}

@Test func metricProfileUsesKilometresAndMetres() throws {
    let segs = try i80Segments()
    let summit = try #require(summitOf(segs))
    let p = try #require(ElevationProfile.make(segments: segs, summit: summit, unit: .kilometers))
    #expect(p.yTicks.map(\.value) == [0, 1000, 2000])
    #expect(p.yMax >= summit.altitude! && p.altitudeUnit == .meter && p.distanceUnit == .kilometer)
    #expect(abs(p.summit.altitude - summit.altitude!) < 1e-9)
    #expect(abs(p.xTicks.last!.value - length(segs) / 1000) < 1e-9)
    #expect(Array(p.xTicks.prefix(2).map(\.value)) == [0, 500])
}

@Test func downsamplingKeepsEndsAndSummitWithinBudget() throws {
    let segs = try i80Segments()
    let summit = try #require(summitOf(segs))
    let trip = 1_044_500.0  // 649 mi
    let p = try #require(ElevationProfile.make(segments: segs, summit: summit, unit: .miles, tripDistanceMeters: trip, maxSamples: 200))
    let samples = p.series.flatMap { $0 }
    #expect(samples.count <= 200 && samples.count > 50)
    #expect(samples.first!.distance == 0)
    #expect(abs(samples.last!.distance - 649) < 0.5)
    #expect(abs(p.totalDistance - samples.last!.distance) < 1e-9)
    #expect(abs(p.xTicks.last!.value - trip / DistanceUnit.metersPerMile) < 1e-9)
    #expect(samples.contains(p.summit))
    #expect(zip(samples, samples.dropFirst()).allSatisfy { $0.distance <= $1.distance })
    #expect(samples.map(\.altitude).max()! == p.summit.altitude)
}

@Test func singleSampleSpikeIsRemovedAndNeverBecomesTheSummit() throws {
    var segs = try i80Segments()
    let summit = try #require(summitOf(segs))
    let spikeIndex = 200
    let neighbour = segs[0].points[spikeIndex].altitude!
    segs[0].points[spikeIndex].altitude = neighbour + 900
    let p = try #require(ElevationProfile.make(segments: segs, summit: summit, unit: .kilometers, maxSamples: 2000))
    #expect(abs(p.summit.altitude - summit.altitude!) < 1e-9)
    #expect(p.series.flatMap { $0 }.allSatisfy { $0.altitude <= summit.altitude! + 1e-9 })
    #expect(p.series[0][spikeIndex].altitude < neighbour + 100)
}

@Test func gapGivesTwoSeriesAndNoSampleAcrossIt() throws {
    let a = line(count: 80, stepDegrees: 0.0006) { 100 + Double($0) }
    let b = line(count: 80, stepDegrees: 0.0006, startLat: 40.2) { 200 + Double($0) }
    let p = try #require(ElevationProfile.make(segments: [a, b], summit: b.points.last, unit: .kilometers))
    #expect(p.series.count == 2)
    let gapStart = p.series[0].last!.distance, gapEnd = p.series[1].first!.distance
    #expect(gapEnd - gapStart > 20)  // the straight-line gap is part of the x axis
    #expect(p.series.flatMap { $0 }.allSatisfy { $0.distance <= gapStart || $0.distance >= gapEnd })
}

@Test func noAltitudeOrMostlyMissingAltitudeGivesNil() {
    let none = line(count: 300, stepDegrees: 0.0006) { _ in nil }
    #expect(ElevationProfile.make(segments: [none], summit: nil, unit: .miles) == nil)
    let sparse = line(count: 300, stepDegrees: 0.0006) { $0 % 3 == 0 ? 100 : nil }  // a third
    #expect(ElevationProfile.make(segments: [sparse], summit: nil, unit: .miles) == nil)
    let enough = line(count: 300, stepDegrees: 0.0006) { $0 % 3 == 0 ? nil : 100 }  // two thirds
    #expect(ElevationProfile.make(segments: [enough], summit: nil, unit: .miles) != nil)
}

@Test func fewerThanTwentyValidSamplesOrUnderFiveKmGivesNil() {
    let fewSamples = line(count: 19, stepDegrees: 0.005) { _ in 100 }  // about 10 km
    #expect(ElevationProfile.make(segments: [fewSamples], summit: nil, unit: .kilometers) == nil)
    let short = line(count: 61, stepDegrees: 0.0006) { _ in 100 }  // about 4 km
    #expect(length([short]) < 5000)
    #expect(ElevationProfile.make(segments: [short], summit: nil, unit: .kilometers) == nil)
}

@Test func belowSeaLevelAxisStartsAtTheTickBelowTheMinimum() throws {
    let seg = line(count: 200, stepDegrees: 0.001) { -86 + 400 * sin(Double($0) / 30) + 400 }  // about -86 ... 714 m
    let alts = seg.points.map { $0.altitude! }
    let p = try #require(ElevationProfile.make(segments: [seg], summit: nil, unit: .kilometers))
    #expect(p.yMin < 0 && p.yMin <= alts.min()! + 1e-9)
    #expect(p.yMax >= alts.max()! - 1e-9)
    #expect(p.yTicks.count >= 2 && p.yTicks.count <= 4)
    #expect(p.yTicks.map(\.value).contains(0))
}

@Test func processedRouteOverloadMatchesSegments() throws {
    let segs = try i80Segments()
    let summit = try #require(summitOf(segs))
    let route = ProcessedRoute(segments: segs, summit: summit)
    #expect(ElevationProfile.make(route: route, unit: .miles) == ElevationProfile.make(segments: segs, summit: summit, unit: .miles))
}
