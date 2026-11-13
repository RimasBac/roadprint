import XCTest
import RoadPrintCore
@testable import RoadPrint

@MainActor
final class ShareCardTests: XCTestCase {
    private let en = Locale(identifier: "en_US")
    private let utah = PlaceRef(code: "US-UT", name: "Utah")
    private let nevada = PlaceRef(code: "US-NV", name: "Nevada")
    private let california = PlaceRef(code: "US-CA", name: "California")
    private let usa = PlaceRef(code: "US", name: "United States of America")

    func testBigNumberFollowsTheSharedDisplayRule() {
        XCTAssertEqual(ShareCardText.distance(meters: 1_037_117.8, unit: .miles, locale: en).value, "644")
        XCTAssertEqual(ShareCardText.distance(meters: 9_400, unit: .kilometers, locale: en).value, "9.4")
        XCTAssertEqual(ShareCardText.distance(meters: 2_068_000, unit: .kilometers, locale: en).value, "2,068")
        XCTAssertEqual(ShareCardText.distance(meters: 2_068_000, unit: .kilometers, locale: Locale(identifier: "de_DE")).value, "2.068")
    }

    func testSubtitleNamesFirstAndLastPlaceThenTheDay() {
        let day = ShareDay(year: 2026, month: 11, day: 4)
        XCTAssertEqual(ShareCardText.subtitle(places: TripPlaces(countries: [usa], regions: [utah, nevada, california]),
                                              day: day, locale: en), "Utah → California · Nov 4")
        XCTAssertEqual(ShareCardText.subtitle(places: TripPlaces(countries: [usa], regions: [utah]), day: day, locale: en),
                       "Utah · Nov 4")
        let lithuania = PlaceRef(code: "LT", name: "Lithuania"), latvia = PlaceRef(code: "LV", name: "Latvia")
        XCTAssertEqual(ShareCardText.subtitle(places: TripPlaces(countries: [lithuania, latvia],
                                                                 regions: [PlaceRef(code: "LT-KU", name: "Kaunas")]),
                                              day: day, locale: en), "Lithuania → Latvia · Nov 4")
        XCTAssertEqual(ShareCardText.subtitle(places: TripPlaces(), day: day, locale: en), "Nov 4")
    }

    func testCardContentComesFromTheShareSummary() throws {
        let trip = Trip(
            createdAt: Date(timeIntervalSince1970: 1_793_750_400), status: .completed,
            endedAt: Date(timeIntervalSince1970: 1_793_790_000),
            summary: TripStats(distanceMeters: 1_037_117.8, movingTimeSeconds: 37_336, elapsedSeconds: 39_000, gapCount: 0),
            route: ProcessedRoute(segments: [RouteSegment(points: [
                RoutePoint(latitude: 40.76, longitude: -111.89, altitude: 1300),
                RoutePoint(latitude: 39.33, longitude: -120.34, altitude: 2206),
                RoutePoint(latitude: 38.58, longitude: -121.49, altitude: 10)])],
                                  summit: RoutePoint(latitude: 39.33, longitude: -120.34, altitude: 2206)),
            places: TripPlaces(countries: [usa], regions: [utah, nevada, california]))
        let summary = try XCTUnwrap(TripShareSummary.make(from: trip, options: ShareOptions(includeRoute: true)))
        let content = ShareCardText.content(summary: summary, unit: .miles, altitude: "7,238 ft", locale: en)
        XCTAssertEqual(content.distanceValue, "644")
        XCTAssertTrue(content.subtitle.hasPrefix("Utah → California · "))
        // The altitude is on the map, so the second chip counts the states.
        XCTAssertEqual(content.chips, [TripFormatting.duration(seconds: 37_336), "3 states"])
        XCTAssertEqual(content.title, "Utah → California")
        XCTAssertEqual(content.stats.map(\.value), ["644", "10:22", "3", "7,238"])
        XCTAssertEqual(content.stats.last?.label, "ft summit")
        XCTAssertEqual(content.crossedCodes, ["US", "US-UT", "US-NV", "US-CA"])
        XCTAssertEqual(ShareCardText.roadName(MainRoad(network: .usInterstate, ref: "80", countryCode: "US")), "I-80")
        XCTAssertEqual(ShareCardText.roadName(MainRoad(network: .eRoad, ref: "E67")), "E67")
        // Without a route there is no marker on the map, so the altitude gets a chip.
        let hidden = try XCTUnwrap(TripShareSummary.make(from: trip, options: ShareOptions(includeRoute: false)))
        XCTAssertNil(hidden.route)
        XCTAssertEqual(ShareCardText.content(summary: hidden, unit: .miles, altitude: "7,238 ft", locale: en).chips,
                       [TripFormatting.duration(seconds: 37_336), "3 states", "7,238 ft"])
    }

    func testPlaceCountUsesTheRightWord() {
        XCTAssertEqual(ShareCardText.placeCount(TripPlaces(countries: [usa], regions: [utah]))?.noun, "state")
        XCTAssertEqual(ShareCardText.placeCount(TripPlaces(countries: [usa], regions: [utah, nevada]))?.noun, "states")
        let lithuania = PlaceRef(code: "LT", name: "Lithuania"), latvia = PlaceRef(code: "LV", name: "Latvia")
        let counties = [PlaceRef(code: "LT-KU", name: "Kaunas"), PlaceRef(code: "LT-KL", name: "Klaipėda")]
        XCTAssertEqual(ShareCardText.placeCount(TripPlaces(countries: [lithuania], regions: counties))?.noun, "regions")
        let abroad = ShareCardText.placeCount(TripPlaces(countries: [lithuania, latvia], regions: counties))
        XCTAssertEqual(abroad?.count, 2)
        XCTAssertEqual(abroad?.noun, "countries")
        XCTAssertNil(ShareCardText.placeCount(TripPlaces()))
        XCTAssertEqual(ShareCardText.clock(seconds: 37_336), "10:22")
        XCTAssertEqual(ShareCardText.clock(seconds: 2_820), "0:47")
        // Without an elevation strip the map grows by the strip's height, so no band stays empty.
        XCTAssertEqual(ShareCardMetrics.map(.nightHighway, hasElevation: true).height + 54,
                       ShareCardMetrics.map(.nightHighway, hasElevation: false).height)
    }

    func testElevationTickText() {
        XCTAssertEqual(ElevationChartView.tickText(ProfileTick(value: 8000, unit: .foot), showUnit: true, locale: en), "8k ft")
        XCTAssertEqual(ElevationChartView.tickText(ProfileTick(value: 200, unit: .mile), showUnit: false, locale: en), "200")
        XCTAssertEqual(ElevationChartView.tickText(ProfileTick(value: 500, unit: .meter), showUnit: true, locale: en), "500 m")
        XCTAssertEqual(ElevationChartView.tickText(ProfileTick(value: 0, unit: .kilometer), showUnit: false, locale: en), "0")
    }
}
