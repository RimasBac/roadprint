import XCTest
@testable import RoadPrintCore

final class ProjectionChooserTests: XCTestCase {
    private func bounds(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) throws -> GeoBounds {
        try XCTUnwrap(GeoBounds(points: [GeoCoordinate(latitude: lat1, longitude: lon1),
                                       GeoCoordinate(latitude: lat2, longitude: lon2)]))
    }
    func testNamedRoutesAndSizePrecedence() throws {
        for b in [try bounds(40.76, -111.89, 38.58, -121.49),
                  try bounds(54.9, 23.9, 45.44, 10.99),
                  try bounds(-31.95, 115.86, -34.93, 138.6),
                  try bounds(61, -150, 64, -145), // Alaska
                  try bounds(19.7, -155.1, 21.3, -157.8)] { // Hawaii
            XCTAssertEqual(ProjectionChooser.choose(for: b), .localLAEA(centerLat: b.center.latitude, centerLon: b.center.longitude))
        }
        XCTAssertEqual(ProjectionChooser.choose(for: try bounds(40.71, -74.01, 34.05, -118.24)), .albersUSA)
        XCTAssertEqual(ProjectionChooser.choose(for: try bounds(38.72, -9.14, 60.17, 24.94)), .laeaEurope)
        let pacific = try bounds(35.7, 139.7, 37.8, -122.4)
        XCTAssertLessThan(pacific.longitudeSpan, 100)
        XCTAssertEqual(ProjectionChooser.choose(for: pacific), .robinson(centralMeridian: pacific.meanLongitude))
    }
    func testMeanIsUnwrappedAndIndependentOfPointOrder() throws {
        let points = [GeoCoordinate(latitude: 10, longitude: 170),
                      GeoCoordinate(latitude: 20, longitude: -160),
                      GeoCoordinate(latitude: -20, longitude: 175)]
        let a = try XCTUnwrap(GeoBounds(points: points))
        let b = try XCTUnwrap(GeoBounds(points: Array(points.reversed())))
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.meanLongitude, -178.3333333333333, accuracy: 1e-10)
        XCTAssertEqual(ProjectionChooser.choose(for: a), .robinson(centralMeridian: a.meanLongitude))
    }
    func testLocalThresholdAndRegionalEdges() throws {
        let degrees = ProjectionChooser.localSpanMeters / Geo.earthRadiusMeters * 180 / Double.pi
        let small = try bounds(0, 0, degrees - 1e-5, 0)
        let large = try bounds(0, 0, degrees + 1e-5, 0)
        XCTAssertEqual(ProjectionChooser.choose(for: small), .localLAEA(centerLat: small.center.latitude, centerLon: 0))
        XCTAssertEqual(ProjectionChooser.choose(for: large), .robinson(centralMeridian: 0))
        XCTAssertEqual(ProjectionChooser.choose(for: try bounds(24, -125, 50, -66)), .albersUSA)
        let outside = try bounds(23.9, -125, 50, -66)
        XCTAssertEqual(ProjectionChooser.choose(for: outside), .robinson(centralMeridian: outside.meanLongitude))
        XCTAssertEqual(ProjectionChooser.choose(for: try bounds(35, -25, 72, 45)), .laeaEurope)
        let outsideEurope = try bounds(34.9, -25, 72, 45)
        XCTAssertEqual(ProjectionChooser.choose(for: outsideEurope), .robinson(centralMeridian: outsideEurope.meanLongitude))
    }
}
