import XCTest
import RoadPrintCore
@testable import RoadPrint

@MainActor
final class MyMapTests: XCTestCase {
    private let utah = PlaceRef(code: "US-UT", name: "Utah")
    private let nevada = PlaceRef(code: "US-NV", name: "Nevada")
    private let california = PlaceRef(code: "US-CA", name: "California")
    private let usa = PlaceRef(code: "US", name: "United States of America")
    /// 6 November 2026.
    private let now = Date(timeIntervalSince1970: 1_794_000_000)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    private func trip(daysAgo: Double, regions: [PlaceRef], road: String?) -> HeatTrip {
        HeatTrip(id: UUID(), date: now.addingTimeInterval(-daysAgo * 86_400), distanceMeters: 100_000,
                 segments: [], regions: regions, countries: [usa], road: road)
    }

    func testFiltersNarrowTheTrips() {
        let recent = trip(daysAgo: 5, regions: [utah, nevada], road: "I-80")
        let autumn = trip(daysAgo: 40, regions: [california], road: "US-50")
        let lastYear = trip(daysAgo: 400, regions: [utah], road: nil)
        let trips = [recent, autumn, lastYear]
        func ids(_ filter: MapFilter) -> [UUID] {
            MyMapLogic.filtered(trips, by: filter, now: now, calendar: calendar).map(\.id)
        }

        XCTAssertEqual(ids(MapFilter()), trips.map(\.id), "all time, no filter")
        XCTAssertEqual(ids(MapFilter(period: .last30Days)), [recent.id])
        XCTAssertEqual(ids(MapFilter(year: 2025)), [lastYear.id])
        // The year belongs to All time: Last 30 days ignores it.
        XCTAssertEqual(ids(MapFilter(period: .last30Days, year: 2025)), [recent.id])
        XCTAssertEqual(ids(MapFilter(placeCode: "US-UT")), [recent.id, lastYear.id])
        XCTAssertEqual(ids(MapFilter(road: "US-50")), [autumn.id])
        XCTAssertEqual(ids(MapFilter(year: 2026, placeCode: "US-UT", road: "I-80")), [recent.id])
        XCTAssertEqual(ids(MapFilter(placeCode: "US-CA", road: "I-80")), [])

        XCTAssertFalse(MapFilter().isNarrowed)
        XCTAssertFalse(MapFilter(period: .last30Days, year: 2025).isNarrowed)
        XCTAssertTrue(MapFilter(road: "I-80").isNarrowed)
    }

    func testFilterChoicesComeFromTheTrips() {
        let trips = [trip(daysAgo: 5, regions: [utah, nevada], road: "I-80"),
                     trip(daysAgo: 40, regions: [california, nevada], road: "US-50"),
                     trip(daysAgo: 400, regions: [utah], road: nil)]
        XCTAssertEqual(MyMapLogic.years(trips, calendar: calendar), [2026, 2025])
        XCTAssertEqual(MyMapLogic.places(trips).map(\.name), ["California", "Nevada", "Utah"])
        XCTAssertEqual(MyMapLogic.roads(trips), ["I-80", "US-50"])
        let count = MyMapLogic.placeCount(trips)
        XCTAssertEqual(count?.count, 3)
        XCTAssertEqual(count?.noun, "states")
        // More than one country: the place filter lists countries.
        let abroad = HeatTrip(id: UUID(), date: now, distanceMeters: 1, segments: [],
                              regions: [], countries: [PlaceRef(code: "CA", name: "Canada")], road: nil)
        XCTAssertEqual(MyMapLogic.places(trips + [abroad]).map(\.name), ["Canada", "United States of America"])
    }

    func testLegendMatchesTheHeatLevels() {
        XCTAssertEqual((1...5).map { MyMapLogic.legendLabel(level: $0) }, ["1–2", "3–5", "6–9", "10–14", "15+"])
        XCTAssertEqual(MyMapLogic.legendLabel(level: 9), "")
        XCTAssertLessThan(HeatMapArt.width(1), HeatMapArt.width(5))
    }
}
