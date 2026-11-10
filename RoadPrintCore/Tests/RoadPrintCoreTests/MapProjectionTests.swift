import Foundation
import XCTest
@testable import RoadPrintCore

final class MapProjectionTests: XCTestCase {
    private func projection(_ name: String) -> MapProjection {
        switch name {
        case "local": return MapProjection(kind: .localLAEA(centerLat: 40, centerLon: -115))
        case "albers": return MapProjection(kind: .albersUSA)
        case "europe": return MapProjection(kind: .laeaEurope)
        default: return MapProjection(kind: .robinson(centralMeridian: 170))
        }
    }

    private struct Reference: Decodable {
        let projection: String
        let lat, lon, x, y: Double
    }
    private struct Golden: Decodable {
        let projection: String
        let lat, lon: Double
        let x, y: String
    }
    private func fixture<T: Decodable>(_ name: String, as: T.Type) throws -> T {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    func testProj4Reference() throws {
        let points = try fixture("projection-reference", as: [Reference].self)
        for name in ["local", "albers", "europe", "robinson"] {
            XCTAssertGreaterThanOrEqual(points.filter { $0.projection == name }.count, 5)
        }
        for p in points {
            let result = try XCTUnwrap(projection(p.projection).project(lat: p.lat, lon: p.lon))
            let tolerance = p.projection == "robinson" ? 2 * .pi * Geo.earthRadiusMeters * 0.8487 * 0.001 : 1
            XCTAssertEqual(result.x, p.x, accuracy: tolerance, "\(p)")
            XCTAssertEqual(result.y, p.y, accuracy: tolerance, "\(p)")
        }
    }

    // Run unchanged on Linux and the iOS simulator; strings retain six decimal places.
    func testGoldenWithinOneMicrometre() throws {
        for p in try fixture("projection-golden", as: [Golden].self) {
            let result = try XCTUnwrap(projection(p.projection).project(lat: p.lat, lon: p.lon))
            XCTAssertEqual(result.x, try XCTUnwrap(Double(p.x)), accuracy: 1e-6, "\(p)")
            XCTAssertEqual(result.y, try XCTUnwrap(Double(p.y)), accuracy: 1e-6, "\(p)")
        }
    }

    func testSeededRoundTrips() throws {
        // Fixed LCG, independent of Swift's randomized hashing and random generator.
        var seed: UInt64 = 50
        func random(_ low: Double, _ high: Double) -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return low + (high - low) * Double(seed >> 11) / 9007199254740992
        }
        for name in ["local", "albers", "europe"] {
            let map = projection(name)
            for _ in 0..<1_000 {
                let lat = name == "europe" ? random(35, 72) : random(24, 50)
                let lon = name == "europe" ? random(-25, 45) : random(-125, -66)
                let point = try XCTUnwrap(map.project(lat: lat, lon: lon))
                let result = try XCTUnwrap(map.inverse(point))
                XCTAssertEqual(result.latitude, lat, accuracy: 1e-7)
                XCTAssertEqual(result.longitude, lon, accuracy: 1e-7)
            }
        }
    }

    func testValidationWrappingClampingAndDomains() throws {
        for name in ["local", "albers", "europe", "robinson"] {
            let map = projection(name)
            for invalid in [Double.nan, .infinity, -.infinity] {
                XCTAssertNil(map.project(lat: invalid, lon: 0))
                XCTAssertNil(map.project(lat: 0, lon: invalid))
                XCTAssertNil(map.inverse(PlanePoint(x: invalid, y: 0)))
                XCTAssertNil(map.inverse(PlanePoint(x: 0, y: invalid)))
            }
            XCTAssertEqual(map.project(lat: 90, lon: 0), map.project(lat: 89.9, lon: 0))
            XCTAssertEqual(map.project(lat: -100, lon: 0), map.project(lat: -89.9, lon: 0))
            XCTAssertEqual(map.project(lat: 40, lon: 245), map.project(lat: 40, lon: -115))
            if let p = map.project(lat: .greatestFiniteMagnitude, lon: .greatestFiniteMagnitude) {
                XCTAssertTrue(p.x.isFinite && p.y.isFinite)
            }
        }
        XCTAssertNil(MapProjection(kind: .localLAEA(centerLat: .nan, centerLon: 0)).project(lat: 0, lon: 0))
        XCTAssertNil(MapProjection(kind: .robinson(centralMeridian: .infinity)).project(lat: 0, lon: 0))
        let local = MapProjection(kind: .localLAEA(centerLat: 0, centerLon: 0))
        XCTAssertNil(local.project(lat: 0, lon: 180))
        XCTAssertNil(local.project(lat: 0, lon: 100))
        XCTAssertNil(local.inverse(PlanePoint(x: 20_000_000, y: 0)))
        XCTAssertNil(projection("albers").inverse(PlanePoint(x: 1e100, y: 1e100)))
        XCTAssertNil(projection("robinson").inverse(PlanePoint(x: 0, y: 0)))
        XCTAssertEqual(local.inverse(PlanePoint(x: 0, y: 0)), GeoCoordinate(latitude: 0, longitude: 0))
    }

    func testKindCodableRoundTrip() throws {
        let kinds: [MapProjectionKind] = [.localLAEA(centerLat: -17, centerLon: 179), .albersUSA,
                                        .laeaEurope, .robinson(centralMeridian: 170)]
        XCTAssertEqual(try JSONDecoder().decode([MapProjectionKind].self, from: JSONEncoder().encode(kinds)), kinds)
    }

    func testReleaseProjectionPerformance() throws {
        #if DEBUG
        throw XCTSkip("50 ms budget is measured in release: swift test -c release --filter MapProjectionTests/testReleaseProjectionPerformance")
        #else
        for name in ["local", "albers", "europe", "robinson"] {
            let points = (0..<100_000).map { i in
                GeoCoordinate(latitude: 35 + Double(i % 200) / 10,
                              longitude: (name == "europe" ? -15 : -125) + Double(i % 500) / 10)
            }
            let map = projection(name)
            // Warm up the math library, then consume every result to prevent dead-code elimination.
            _ = map.project(lat: points[0].latitude, lon: points[0].longitude)
            let start = Date.timeIntervalSinceReferenceDate
            var checksum = 0.0
            var count = 0
            for point in points {
                if let p = map.project(lat: point.latitude, lon: point.longitude) { checksum += p.x + p.y; count += 1 }
            }
            let milliseconds = (Date.timeIntervalSinceReferenceDate - start) * 1_000
            print("PROJECTION_BENCHMARK release \(name) 100000 points: \(milliseconds) ms; checksum \(checksum)")
            XCTAssertEqual(count, 100_000)
            XCTAssertTrue(checksum.isFinite)
            XCTAssertLessThan(milliseconds, 50, name)
        }
        #endif
    }
}
