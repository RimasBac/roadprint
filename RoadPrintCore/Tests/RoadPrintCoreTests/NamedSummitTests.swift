import XCTest
@testable import RoadPrintCore

final class NamedSummitTests: XCTestCase {
    func testWellKnownPassesGetTheirName() {
        // The I-80 fixture's highest point.
        XCTAssertEqual(NamedSummit.name(at: RoutePoint(latitude: 39.33, longitude: -120.34, altitude: 2_206)), "Donner Summit")
        XCTAssertEqual(NamedSummit.name(at: RoutePoint(latitude: 47.005, longitude: 11.505, altitude: 1_360)), "Brenner Pass")
        // No altitude known: the place decides.
        XCTAssertEqual(NamedSummit.name(at: RoutePoint(latitude: 39.68, longitude: -105.90)), "Eisenhower Tunnel")
    }

    func testNoNameAwayFromAPassOrFarBelowIt() {
        XCTAssertNil(NamedSummit.name(at: RoutePoint(latitude: 54.90, longitude: 23.90, altitude: 120)), "Kaunas")
        // The Gotthard road tunnel runs about 1,100 m below the pass.
        XCTAssertNil(NamedSummit.name(at: RoutePoint(latitude: 46.57, longitude: 8.59, altitude: 1_175)))
        XCTAssertNil(NamedSummit.name(at: RoutePoint(latitude: 39.60, longitude: -120.34, altitude: 2_206)), "29 km away")
    }

    func testListIsSane() {
        XCTAssertEqual(Set(NamedSummit.passes.map(\.name)).count, NamedSummit.passes.count, "no name twice")
        for pass in NamedSummit.passes {
            XCTAssertTrue((-90...90).contains(pass.latitude) && (-180...180).contains(pass.longitude), pass.name)
            XCTAssertTrue((200...4_000).contains(pass.altitudeMeters), pass.name)
        }
    }
}
