import XCTest
@testable import RoadPrintCore

final class TripSummaryInfoTests: XCTestCase {
    private func ref(_ c: String, _ n: String) -> PlaceRef { PlaceRef(code: c, name: n) }

    func testCareerProgress() {
        let p = CareerProgress(otherTripsMeters: 1_000, thisTripMeters: 500, startingMeters: 10_000, unit: .kilometers)
        XCTAssertEqual(p.beforeMeters, 11_000)
        XCTAssertEqual(p.afterMeters, 11_500)
        XCTAssertEqual(p.afterFraction, 11_500 / 1_000_000_000, accuracy: 1e-12)
        XCTAssertFalse(p.goalReached)
    }

    func testGoalReachedClampsBar() {
        let p = CareerProgress(otherTripsMeters: 0, thisTripMeters: 10, startingMeters: 2_000_000_000, unit: .kilometers)
        XCTAssertTrue(p.goalReached)
        XCTAssertEqual(p.afterFraction, 1)
        XCTAssertEqual(p.remainingMeters, 0)
    }

    func testHeaderNamesAbbreviate() {
        XCTAssertEqual(TripPlaceSummary.headerNames(["A", "B", "C"]), ["A", "B", "C"])
        XCTAssertEqual(TripPlaceSummary.headerNames(["A", "B", "C", "D"]), ["A", "…", "D"])
    }

    func testNounAndNames() {
        let us = TripPlaces(countries: [ref("US", "United States")], regions: [ref("US-UT", "Utah"), ref("US-NV", "Nevada")])
        XCTAssertEqual(TripPlaceSummary.noun(us), .states)
        XCTAssertEqual(TripPlaceSummary.names(us), ["Utah", "Nevada"])
        let ca = TripPlaces(countries: [ref("CA", "Canada")], regions: [ref("CA-BC", "British Columbia")])
        XCTAssertEqual(TripPlaceSummary.noun(ca), .provinces)
        let two = TripPlaces(countries: [ref("US", "United States"), ref("CA", "Canada")], regions: [ref("US-WA", "Washington")])
        XCTAssertEqual(TripPlaceSummary.noun(two), .countries)
        XCTAssertEqual(TripPlaceSummary.names(two), ["United States", "Canada"])
        XCTAssertEqual(TripPlaceSummary.noun(nil), .regions)
    }
}
