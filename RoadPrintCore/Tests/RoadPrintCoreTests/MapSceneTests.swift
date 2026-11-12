import Foundation
import XCTest
@testable import RoadPrintCore

final class MapSceneTests: XCTestCase {
    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    }
    private func i80() throws -> MapSceneInput {
        let pairs = try JSONDecoder().decode([[Double]].self, from: Data(contentsOf: fixture("i80-slc-sac-route")))
        let points = pairs.map { RoutePoint(latitude: $0[0], longitude: $0[1]) }
        let first = try XCTUnwrap(points.first), last = try XCTUnwrap(points.last)
        return MapSceneInput(segments: [RouteSegment(points: points)],
            start: ApproximateArea(centerLatitude: first.latitude, centerLongitude: first.longitude, radiusMeters: 8_000),
            end: ApproximateArea(centerLatitude: last.latitude, centerLongitude: last.longitude, radiusMeters: 8_000),
            summit: RoutePoint(latitude: 39.33, longitude: -120.34, altitude: 2206),
            startLabel: "Salt Lake City area", endLabel: "Sacramento area")
    }
    private func output(_ scene: MapScene, name: String) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(scene)
        if let directory = ProcessInfo.processInfo.environment["MAP_SCENE_OUTPUT_DIR"] {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try data.write(to: url.appendingPathComponent(name + ".json"))
        }
        return data
    }
    private func checkLayout(_ scene: MapScene, file: StaticString = #filePath, line: UInt = #line) {
        let inset = MapRect(x: 28, y: 36, width: scene.width - 56, height: scene.height - 72)
        let route = scene.routes.flatMap(\.points)
        XCTAssertTrue(route.allSatisfy(inset.contains), file: file, line: line)
        for area in [scene.startArea, scene.endArea].compactMap({ $0 }) {
            XCTAssertTrue(inset.expanded(0.01).contains(MapRect(x: area.center.x - area.radius, y: area.center.y - area.radius,
                                                   width: area.radius * 2, height: area.radius * 2)), file: file, line: line)
            XCTAssertGreaterThanOrEqual(area.radius, 8, file: file, line: line)
            XCTAssertLessThanOrEqual(area.radius, 22, file: file, line: line)
            XCTAssertEqual(area.radius, min(22, max(8, 8_000 * scene.pointsPerMeter)), accuracy: 0.01, file: file, line: line)
        }
        let xs = route.map(\.x), ys = route.map(\.y)
        if let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() {
            XCTAssertEqual((x0 + x1) / 2, inset.center.x, accuracy: 2, file: file, line: line)
            XCTAssertEqual((y0 + y1) / 2, inset.center.y, accuracy: 2, file: file, line: line)
            let fill = max((x1 - x0) / inset.width, (y1 - y0) / inset.height)
            XCTAssertGreaterThanOrEqual(fill, 0.7, file: file, line: line)
            XCTAssertLessThanOrEqual(fill, 1, file: file, line: line)
        }
        let labels = scene.regionLabels + [scene.startArea?.label, scene.endArea?.label].compactMap { $0 }
        let view = MapRect(x: 8, y: 8, width: scene.width - 16, height: scene.height - 16)
        for (i, label) in labels.enumerated() {
            XCTAssertTrue(view.contains(label.bounds), file: file, line: line)
            XCTAssertTrue(SceneGeometry.clear(label.bounds, of: scene.routes,
                                               by: label.placeCode == nil ? 6 : 12), file: file, line: line)
            for other in labels.dropFirst(i + 1) {
                XCTAssertFalse(label.bounds.expanded(8).intersects(other.bounds), file: file, line: line)
            }
            if let summit = scene.summit?.labelBounds {
                XCTAssertFalse(label.bounds.expanded(8).intersects(summit), file: file, line: line)
            }
            if let code = label.placeCode, let outline = scene.outlines.first(where: { $0.place.code == code }) {
                XCTAssertTrue((label.bounds.corners + [label.anchor]).allSatisfy {
                    SceneGeometry.contains($0, rings: outline.rings)
                }, file: file, line: line)
            }
        }
        if let box = scene.summit?.labelBounds {
            XCTAssertTrue(view.contains(box), file: file, line: line)
            XCTAssertTrue(SceneGeometry.clear(box, of: scene.routes, by: 6), file: file, line: line)
        }
        let clip = MapRect(x: -16, y: -16, width: scene.width + 32, height: scene.height + 32)
        XCTAssertTrue(scene.outlines.flatMap(\.rings).flatMap { $0 }.allSatisfy {
            clip.expanded(0.001).contains($0)
        }, file: file, line: line)
    }

    func testI80SizesCompositionLabelsCirclesAndSummit() throws {
        let places = try PlaceIndex.bundled(), input = try i80()
        for (w, h) in [(320.0, 320.0), (390.0, 460.0), (1080.0, 1100.0)] {
            let scene = try MapSceneBuilder.build(input: input, places: places, size: (w, h))
            checkLayout(scene)
            XCTAssertTrue(scene.regionLabels.contains { $0.text == "NV" })
            XCTAssertTrue(scene.regionLabels.contains { $0.text == "UT" })
            XCTAssertNotNil(scene.startArea); XCTAssertNotNil(scene.endArea)
            XCTAssertEqual(scene.drawOrder, [.landFill, .regionBorders, .countryBorders, .routeGlow,
                                             .route, .areaCircles, .summit, .labels])
            XCTAssertEqual(scene.accessibilitySummary.countryCount, 1)
            XCTAssertEqual(scene.accessibilitySummary.orderedRegionNames, ["Utah", "Nevada", "California"])
            XCTAssertEqual(scene.accessibilitySummary.startName, input.startLabel)
            XCTAssertEqual(scene.accessibilitySummary.endName, input.endLabel)
            let summit = try XCTUnwrap(scene.summit)
            let projection = MapProjection(kind: scene.projection)
            let a = try XCTUnwrap(projection.project(lat: input.summit!.latitude, lon: input.summit!.longitude))
            let b = try XCTUnwrap(projection.project(lat: input.segments[0].points[0].latitude,
                                                   lon: input.segments[0].points[0].longitude))
            let start = try XCTUnwrap(scene.startArea)
            XCTAssertEqual(summit.position.x - start.center.x, (a.x - b.x) * scene.pointsPerMeter, accuracy: 0.01)
            XCTAssertEqual(summit.position.y - start.center.y, -(a.y - b.y) * scene.pointsPerMeter, accuracy: 0.01)
            XCTAssertEqual(input.summit!.latitude, 39.3, accuracy: 0.1)
            XCTAssertEqual(input.summit!.longitude, -120.3, accuracy: 0.1)
            let data = try output(scene, name: "i80-\(Int(w))x\(Int(h))")
            XCTAssertLessThan(data.count, 200_000)
            XCTAssertEqual(try JSONDecoder().decode(MapScene.self, from: data), scene)
            if w == 390 {
                let startLabel = try XCTUnwrap(start.label), end = try XCTUnwrap(scene.endArea)
                let endLabel = try XCTUnwrap(end.label)
                XCTAssertLessThan(startLabel.anchor.x, start.center.x)
                XCTAssertLessThan(startLabel.anchor.y, start.center.y)
                XCTAssertGreaterThan(endLabel.anchor.x, end.center.x)
                XCTAssertGreaterThan(endLabel.anchor.y, end.center.y)
                try compareGolden(scene)
            }
        }
    }

    private func compareGolden(_ scene: MapScene) throws {
        // CI writes the candidate before comparing it, even on a first-run
        // failure. Review and commit that artifact; never update goldens in CI.
        guard let url = Bundle.module.url(forResource: "map-scene-i80-golden", withExtension: "json", subdirectory: "Fixtures") else {
            XCTFail("Missing reviewed golden: copy i80-390x460.json from map-scene-previews to Fixtures/map-scene-i80-golden.json")
            return
        }
        let actual = try JSONSerialization.jsonObject(with: JSONEncoder().encode(scene))
        let expected = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        func compare(_ actual: Any, _ expected: Any, path: String) {
            if let a = actual as? [String: Any], let b = expected as? [String: Any] {
                XCTAssertEqual(Set(a.keys), Set(b.keys), path)
                for key in a.keys.sorted() { if let e = b[key] { compare(a[key]!, e, path: path + "." + key) } }
            } else if let a = actual as? [Any], let b = expected as? [Any] {
                XCTAssertEqual(a.count, b.count, path)
                for (i, pair) in zip(a, b).enumerated() { compare(pair.0, pair.1, path: path + "[\(i)]") }
            } else if let a = actual as? NSNumber, let b = expected as? NSNumber {
                XCTAssertEqual(a.doubleValue, b.doubleValue, accuracy: 0.01, path)
            } else { XCTAssertEqual(String(describing: actual), String(describing: expected), path) }
        }
        compare(actual, expected, path: "scene")
    }

    func testEuropeAndShortTripPreview() throws {
        let places = try PlaceIndex.bundled()
        let cities: [(Double, Double)] = [(54.90,23.90), (52.23,21.01), (50.08,14.44), (48.14,11.58),
                                          (47.27,11.39), (47.0,11.5), (46.5,11.35), (45.44,10.99)]
        var points: [RoutePoint] = []
        for (a, b) in zip(cities, cities.dropFirst()) {
            for i in 0..<20 {
                let t = Double(i) / 20
                points.append(RoutePoint(latitude: a.0 + (b.0 - a.0) * t, longitude: a.1 + (b.1 - a.1) * t))
            }
        }
        points.append(RoutePoint(latitude: cities.last!.0, longitude: cities.last!.1))
        let europe = try MapSceneBuilder.build(input: .init(segments: [.init(points: points)]), places: places, size: (390,460))
        switch europe.projection { case .laeaEurope, .localLAEA: break; default: XCTFail("Europe needs LAEA") }
        XCTAssertTrue(europe.regionLabels.contains { $0.text == "IT" })
        XCTAssertGreaterThanOrEqual(europe.accessibilitySummary.countryCount, 4)
        _ = try output(europe, name: "europe-390x460")
        let short = try MapSceneBuilder.build(input: .init(segments: [.init(points: [
            RoutePoint(latitude: 54.90, longitude: 23.90), RoutePoint(latitude: 54.927, longitude: 23.90)
        ])]), places: places, size: (390,460))
        let span = abs(short.routes[0].points[1].y - short.routes[0].points[0].y)
        XCTAssertLessThan(span, 30) // 3 km in a >=50 km view, not a full-height line.
        XCTAssertLessThanOrEqual(short.pointsPerMeter, (390 - 56 - 44) / 50_000.0)
        _ = try output(short, name: "short-390x460")
    }

    func testGapNeverBecomesRecordedRouteOrCountsUnvisitedCountries() throws {
        let input = MapSceneInput(segments: [
            .init(points: [.init(latitude: 40.76, longitude: -111.89), .init(latitude: 40.75, longitude: -112)]),
            .init(points: []),
            .init(points: [.init(latitude: 39.33, longitude: -120.34), .init(latitude: 38.58, longitude: -121.49)])])
        let scene = try MapSceneBuilder.build(input: input, places: PlaceIndex.bundled(), size: (390,460))
        XCTAssertEqual(scene.routes.map(\.kind), [.recorded, .gap, .recorded])
        XCTAssertEqual(scene.routes[1].points, [scene.routes[0].points.last!, scene.routes[2].points.first!])
        XCTAssertFalse(scene.accessibilitySummary.orderedRegionNames.contains("Nevada"))
        XCTAssertTrue(scene.accessibilitySummary.hasRecordingGap)
    }

    func testEmptyAreaOnlyInvalidInputAndCircleClamp() throws {
        let places = try PlaceIndex.bundled()
        XCTAssertThrowsError(try MapSceneBuilder.build(input: .init(segments: []), places: places, size: (390,460)))
        XCTAssertThrowsError(try MapSceneBuilder.build(input: i80(), places: places, size: (.nan,460)))
        XCTAssertThrowsError(try MapSceneBuilder.build(input: i80(), places: places, size: (40,40)))
        XCTAssertThrowsError(try MapSceneBuilder.build(input: .init(segments: [.init(points: [.init(latitude: .nan, longitude: 0)])]),
                                                      places: places, size: (390,460)))
        for radius in [0.0, 8_000, 1_000_000] {
            let area = ApproximateArea(centerLatitude: 54.9, centerLongitude: 23.9, radiusMeters: radius)
            let scene = try MapSceneBuilder.build(input: .init(segments: [], start: area, end: area), places: places, size: (390,460))
            XCTAssertTrue(scene.routes.isEmpty)
            let start = try XCTUnwrap(scene.startArea)
            XCTAssertEqual(start.center.x, 195, accuracy: 0.01)
            XCTAssertEqual(start.center.y, 230, accuracy: 0.01)
            XCTAssertEqual(start.radius, min(22, max(8, radius * scene.pointsPerMeter)), accuracy: 0.01)
        }
    }

    func testDeterministicBuild() throws {
        let places = try PlaceIndex.bundled(), input = try i80()
        let a = try MapSceneBuilder.build(input: input, places: places, size: (390,460))
        XCTAssertEqual(a, try MapSceneBuilder.build(input: input, places: places, size: (390,460)))
    }

    func testReleaseBuildPerformance() throws {
        #if !DEBUG
        let places = try PlaceIndex.bundled(), input = try i80()
        let start = Date()
        for _ in 0..<5 { _ = try MapSceneBuilder.build(input: input, places: places, size: (390,460)) }
        let elapsed = Date().timeIntervalSince(start) / 5
        print("MapScene I-80 release average: \(elapsed * 1000) ms (loaded PlaceIndex, 5 builds)")
        XCTAssertLessThan(elapsed, 0.150)
        #endif
    }
}
