import XCTest
import RoadPrintCore

final class ProPolicyTests: XCTestCase {
    func testFeatureAccessByEntitlement() {
        let cases: [(entitlement: Entitlement, allowed: Bool)] = [(.free, false), (.pro, true)]
        for entry in cases {
            for feature in ProFeature.allCases {
                XCTAssertEqual(ProPolicy.isAllowed(feature, entitlement: entry.entitlement), entry.allowed,
                               "\(feature), \(entry.entitlement)")
            }
        }
    }

    func testHeatWindowAndTripFilteringInUTCAndPlus14() throws {
        let formatter = ISO8601DateFormatter()
        let cases = [
            (now: "2026-01-15T12:30:00Z", cutoff: "2025-12-16T12:30:00Z"),
            (now: "2026-01-16T02:30:00+14:00", cutoff: "2025-12-17T02:30:00+14:00")
        ]
        for entry in cases {
            let now = try XCTUnwrap(formatter.date(from: entry.now))
            let cutoff = try XCTUnwrap(formatter.date(from: entry.cutoff))
            let trips = [cutoff.addingTimeInterval(-1), cutoff, cutoff.addingTimeInterval(1),
                         now, now.addingTimeInterval(1)]
            XCTAssertEqual(ProPolicy.heatWindow(entitlement: .free, now: now),
                           DateInterval(start: cutoff, end: now), entry.now)
            XCTAssertNil(ProPolicy.heatWindow(entitlement: .pro, now: now), entry.now)
            XCTAssertEqual(ProPolicy.filterHeatTrips(trips, datedBy: \.self, entitlement: .free, now: now),
                           [cutoff, cutoff.addingTimeInterval(1), now], entry.now)
            XCTAssertEqual(ProPolicy.filterHeatTrips(trips, datedBy: \.self, entitlement: .pro, now: now),
                           trips, entry.now)
        }
    }

    func testPaywallByEntitlementTripCountAndPriorPresentation() {
        let cases: [(trips: Int, seen: Bool, freeTap: Bool, freeTripEnded: Bool)] = [
            (0, false, false, false),
            (0, true, false, false),
            (1, false, true, false),
            (1, true, true, false),
            (2, false, true, false),
            (2, true, true, false),
            (3, false, true, true),
            (3, true, true, false),
            (4, false, true, false),
            (4, true, true, false)
        ]
        for entry in cases {
            for trigger in PaywallTrigger.allCases {
                let context = "\(trigger), \(entry.trips) completed trips, seen: \(entry.seen)"
                XCTAssertEqual(ProPolicy.shouldShowPaywall(trigger: trigger, completedTrips: entry.trips,
                                                           hasSeenAfterThirdTrip: entry.seen, entitlement: .free),
                               trigger == .tripEnded ? entry.freeTripEnded : entry.freeTap, context)
                XCTAssertFalse(ProPolicy.shouldShowPaywall(trigger: trigger, completedTrips: entry.trips,
                                                           hasSeenAfterThirdTrip: entry.seen, entitlement: .pro),
                               context)
            }
        }
    }
}
