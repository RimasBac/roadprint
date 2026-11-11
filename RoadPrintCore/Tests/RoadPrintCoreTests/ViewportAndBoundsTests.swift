import XCTest
@testable import RoadPrintCore

final class ViewportAndBoundsTests: XCTestCase {
    func testAntimeridianUsesShortInterval() throws {
        let bounds = try XCTUnwrap(GeoBounds(points: [
            GeoCoordinate(latitude: -17.8, longitude: 178),
            GeoCoordinate(latitude: -13.8, longitude: -171.8)
        ]))
        XCTAssertEqual(bounds.longitudeSpan, 10.2, accuracy: 1e-10)
        XCTAssertEqual(bounds.center.longitude, -176.9, accuracy: 1e-10)
    }

    func testBoundsRejectInvalidAndClampLatitude() throws {
        XCTAssertNil(GeoBounds(points: []))
        XCTAssertNil(GeoBounds(points: [GeoCoordinate(latitude: .nan, longitude: 0)]))
        let bounds = try XCTUnwrap(GeoBounds(points: [GeoCoordinate(latitude: 90, longitude: 540)]))
        XCTAssertEqual(bounds.maxLatitude, 89.9)
        XCTAssertEqual(bounds.longitudeSpan, 0)
    }

    func testWideAndTallFits() throws {
        let insets = ViewportInsets(top: 10, left: 20, bottom: 30, right: 40)
        let wide = try XCTUnwrap(ViewportFit(min: PlanePoint(x: 0, y: 0), max: PlanePoint(x: 400_000, y: 100_000), width: 460, height: 240, insets: insets))
        let a = wide.apply(PlanePoint(x: 0, y: 0)), b = wide.apply(PlanePoint(x: 400_000, y: 100_000))
        XCTAssertEqual(b.x - a.x, 400, accuracy: 0.5)
        XCTAssertEqual((a.y + b.y) / 2, 110, accuracy: 0.5)
        XCTAssertLessThan(b.y, a.y)
        let tall = try XCTUnwrap(ViewportFit(min: PlanePoint(x: 0, y: 0), max: PlanePoint(x: 100_000, y: 400_000), width: 460, height: 240, insets: insets))
        let c = tall.apply(PlanePoint(x: 0, y: 0)), d = tall.apply(PlanePoint(x: 100_000, y: 400_000))
        XCTAssertEqual(c.y - d.y, 200, accuracy: 0.5)
        XCTAssertEqual((c.x + d.x) / 2, 220, accuracy: 0.5)
    }

    func testMinimumSpanAndMaximumScale() throws {
        let fit = try XCTUnwrap(ViewportFit(min: PlanePoint(x: 0, y: 0), max: PlanePoint(x: 2_000, y: 0), width: 500, height: 500))
        XCTAssertEqual(fit.apply(PlanePoint(x: 2_000, y: 0)).x - fit.apply(PlanePoint(x: 0, y: 0)).x, 20, accuracy: 1e-9)
        let limited = try XCTUnwrap(ViewportFit(min: PlanePoint(x: 0, y: 0), max: PlanePoint(x: 2_000, y: 0), width: 500, height: 500, maximumScale: 0.001))
        XCTAssertEqual(limited.scale, 0.001)
        XCTAssertNil(ViewportFit(min: PlanePoint(x: 0, y: 0), max: PlanePoint(x: 1, y: 1), width: 0, height: 1))
    }
    func testProjectedI80FitsInsetsAndPreservesAspect() throws {
        let map = MapProjection(kind: .localLAEA(centerLat: 39.67, centerLon: -116.69))
        let points = try [(40.76, -111.89), (38.58, -121.49)].map {
            try XCTUnwrap(map.project(lat: $0.0, lon: $0.1))
        }
        let low = PlanePoint(x: points.map(\.x).min()!, y: points.map(\.y).min()!)
        let high = PlanePoint(x: points.map(\.x).max()!, y: points.map(\.y).max()!)
        let fit = try XCTUnwrap(ViewportFit(min: low, max: high, width: 460, height: 240,
                                           insets: ViewportInsets(top: 10, left: 20, bottom: 30, right: 40)))
        let a = fit.apply(low), b = fit.apply(high)
        XCTAssertEqual(a.x, 20, accuracy: 0.5)
        XCTAssertEqual(b.x, 420, accuracy: 0.5)
        XCTAssertEqual((a.y + b.y) / 2, 110, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(b.y, 10)
        XCTAssertLessThanOrEqual(a.y, 210)
        XCTAssertEqual((b.x-a.x)/(a.y-b.y), (high.x-low.x)/(high.y-low.y), accuracy: 1e-10)
    }

    func testDegenerateAndInvalidFitInputs() throws {
        let zero = PlanePoint(x: 100, y: 200)
        let fit = try XCTUnwrap(ViewportFit(min: zero, max: zero, width: 500, height: 300))
        XCTAssertEqual(fit.apply(zero), PlanePoint(x: 250, y: 150))
        XCTAssertEqual(fit.scale, 300 / 50_000.0)
        XCTAssertNil(ViewportFit(min: zero, max: zero, width: .nan, height: 300))
        XCTAssertNil(ViewportFit(min: zero, max: zero, width: 500, height: 300, minimumSpanMeters: 0))
        XCTAssertNil(ViewportFit(min: zero, max: zero, width: 500, height: 300, maximumScale: 0))
        XCTAssertNil(ViewportFit(min: zero, max: zero, width: 500, height: 300, insets: ViewportInsets(left: -1)))
        XCTAssertNil(ViewportFit(min: zero, max: PlanePoint(x: 0, y: 0), width: 500, height: 300))
    }

}
