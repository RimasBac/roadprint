import XCTest
import RoadPrintCore

/// Runs the same six-decimal golden fixture as Linux on the actual iOS math library.
final class ProjectionGoldenTests: XCTestCase {
    private struct Golden: Decodable {
        let projection: String
        let lat, lon: Double
        let x, y: String
    }

    func testProjectedCoordinatesMatchGoldenWithinOneMicrometre() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "projection-golden", withExtension: "json"))
        let points = try JSONDecoder().decode([Golden].self, from: Data(contentsOf: url))
        for point in points {
            let kind: MapProjectionKind
            switch point.projection {
            case "local": kind = .localLAEA(centerLat: 40, centerLon: -115)
            case "albers": kind = .albersUSA
            case "europe": kind = .laeaEurope
            case "robinson": kind = .robinson(centralMeridian: 170)
            default: XCTFail("Unknown projection \(point.projection)"); continue
            }
            let result = try XCTUnwrap(MapProjection(kind: kind).project(lat: point.lat, lon: point.lon))
            XCTAssertEqual(result.x, try XCTUnwrap(Double(point.x)), accuracy: 1e-6)
            XCTAssertEqual(result.y, try XCTUnwrap(Double(point.y)), accuracy: 1e-6)
        }
    }
}
