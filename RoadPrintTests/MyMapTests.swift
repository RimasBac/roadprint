import XCTest
import RoadPrintCore
@testable import RoadPrint

@MainActor
final class MyMapTests: XCTestCase {
    private let utah = PlaceRef(code: "US-UT", name: "Utah")
    private let nevada = PlaceRef(code: "US-NV", name: "Nevada")
    private let california = PlaceRef(code: "US-CA", name: "California")
    private let usa = PlaceRef(code: "US", name: "United States of America")
    private let lithuania = PlaceRef(code: "LT", name: "Lithuania")
    /// 6 November 2026.
    private let now = Date(timeIntervalSince1970: 1_794_000_000)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    /// "I-80" or "US-50" as a main road.
    private func trip(daysAgo: Double, regions: [PlaceRef], road: String?, area: WorldArea = .northAmerica,
                      segments: [RouteSegment] = [], meters: Double = 100_000) -> HeatTrip {
        let main = road.map { name in
            name.hasPrefix("I-") ? MainRoad(network: .usInterstate, ref: String(name.dropFirst(2)))
                : MainRoad(network: .usHighway, ref: String(name.dropFirst(3)))
        }
        return HeatTrip(id: UUID(), date: now.addingTimeInterval(-daysAgo * 86_400), distanceMeters: meters,
                        segments: segments, regions: regions, countries: [area == .europe ? lithuania : usa],
                        mainRoad: main, area: area)
    }

    func testTopRoadsCountTripsBusiestFirst() {
        let trips = [trip(daysAgo: 5, regions: [utah], road: "I-80", meters: 200_000),
                     trip(daysAgo: 6, regions: [utah], road: "US-50", meters: 900_000),
                     trip(daysAgo: 7, regions: [utah], road: "I-80", meters: 300_000),
                     trip(daysAgo: 8, regions: [utah], road: nil),
                     trip(daysAgo: 9, regions: [utah], road: "I-15", meters: 900_000)]
        let top = MyMapLogic.topRoads(trips)
        XCTAssertEqual(top.map(\.name), ["I-80", "I-15", "US-50"], "most trips first, then the longest distance")
        XCTAssertEqual(top.first?.trips, 2)
        XCTAssertEqual(top.first?.meters, 500_000)
        XCTAssertEqual(top.first?.road, MainRoad(network: .usInterstate, ref: "80"))
        XCTAssertEqual(MyMapLogic.topRoads(trips, limit: 1).count, 1)
        XCTAssertTrue(MyMapLogic.topRoads([trip(daysAgo: 1, regions: [], road: nil)]).isEmpty)
        XCTAssertEqual(MyMapLogic.tripCount(1), "1 trip")
        XCTAssertEqual(MyMapLogic.tripCount(12), "12 trips")
        // The sample maps have roads, so Top roads shows there too.
        XCTAssertFalse(MyMapLogic.topRoads(HeatTrip.samples(.usa, count: 50)).isEmpty)
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
        XCTAssertEqual(MyMapLogic.tripsLine(trips), "3 trips · 3 states")
        XCTAssertEqual(MyMapLogic.tripsLine([trips[2]]), "1 trip · 1 state")
    }

    /// Trips in Europe and in America are never drawn on one map (board, 2026-11-13).
    func testFarApartTripsGetSeparateMaps() {
        XCTAssertEqual(WorldArea.of(latitude: 54.9, longitude: 23.9), .europe)       // Kaunas
        XCTAssertEqual(WorldArea.of(latitude: 41.9, longitude: -87.6), .northAmerica) // Chicago
        XCTAssertEqual(WorldArea.of(latitude: 21.3, longitude: -157.9), .northAmerica) // Honolulu
        XCTAssertEqual(WorldArea.of(latitude: -23.5, longitude: -46.6), .southAmerica) // São Paulo
        XCTAssertEqual(WorldArea.of(latitude: -33.9, longitude: 151.2), .oceania)     // Sydney
        XCTAssertEqual(WorldArea.of(latitude: 35.7, longitude: 139.7), .asia)         // Tokyo
        XCTAssertEqual(WorldArea.of(latitude: 25.2, longitude: 55.3), .asia)          // Dubai
        XCTAssertEqual(WorldArea.of(latitude: -1.3, longitude: 36.8), .africa)        // Nairobi

        let home = (0..<3).map { _ in trip(daysAgo: 3, regions: [], road: nil, area: .europe) }
        let abroad = (0..<2).map { _ in trip(daysAgo: 3, regions: [utah], road: nil) }
        let trips = abroad + home
        XCTAssertEqual(MyMapLogic.areas(trips), [.europe, .northAmerica], "busiest first")
        XCTAssertEqual(MyMapLogic.shownArea(trips, chosen: nil), .europe)
        XCTAssertEqual(MyMapLogic.shownArea(trips, chosen: .northAmerica), .northAmerica)
        XCTAssertEqual(MyMapLogic.shownArea(trips, chosen: .asia), .europe, "a part with no trips is never shown")
        XCTAssertNil(MyMapLogic.shownArea(home, chosen: nil), "one part of the world: nothing to choose")
        XCTAssertEqual(MyMapLogic.filtered(trips, by: MapFilter(), now: now, calendar: calendar).map(\.id), home.map(\.id))
        XCTAssertEqual(MyMapLogic.filtered(trips, by: MapFilter(area: .northAmerica), now: now, calendar: calendar).map(\.id),
                       abroad.map(\.id))
    }

    func testMapShapeFollowsTheTrips() {
        func across(_ south: Double, _ west: Double, _ north: Double, _ east: Double) -> [HeatTrip] {
            [trip(daysAgo: 1, regions: [], road: nil, segments: [RouteSegment(points: [
                RoutePoint(latitude: south, longitude: west), RoutePoint(latitude: north, longitude: east)])])]
        }
        XCTAssertEqual(MyMapLogic.aspect(across(30, -120, 45, -75)), 1.55, "the USA is wide: capped")
        XCTAssertEqual(MyMapLogic.aspect(across(36, 10, 60, 14)), 1.0, "a north–south run: capped")
        XCTAssertEqual(MyMapLogic.aspect([]), 1.15)
        XCTAssertEqual(MyMapLogic.legendMax(0), 8)
        XCTAssertEqual(MyMapLogic.legendMax(3), 8)
        XCTAssertEqual(MyMapLogic.legendMax(244), 244)
        XCTAssertLessThan(HeatMapArt.width(0), HeatMapArt.width(1))
        let en = Locale(identifier: "en_US")
        XCTAssertEqual(MyMapLogic.totalDistance(meters: 8_437_000, unit: .kilometers, locale: en).value, "8,437")
        XCTAssertEqual(MyMapLogic.totalDistance(meters: 60_330 * 1609.344, unit: .miles, locale: en).value, "60.3K")
        XCTAssertEqual(MyMapLogic.totalDistance(meters: 724_888 * 1609.344, unit: .miles, locale: en).value, "725K")
        XCTAssertEqual(HeatTrip.samples(.mixed, count: 20).count, 20)
    }
}
