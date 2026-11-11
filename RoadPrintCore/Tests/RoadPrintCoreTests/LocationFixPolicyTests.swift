import Foundation
import XCTest
@testable import RoadPrintCore

final class LocationFixPolicyTests: XCTestCase {
    func testDelayedFixIsAcceptedWithoutClaimingGPSIsReady() {
        let start = Date(timeIntervalSince1970: 1000)
        let policy = LocationFixPolicy(sessionStartedAt: start)
        let received = start.addingTimeInterval(60)
        let delayed = start.addingTimeInterval(10)
        XCTAssertTrue(policy.accepts(timestamp: delayed, horizontalAccuracy: 5))
        XCTAssertFalse(policy.isRecent(timestamp: delayed, receivedAt: received))
        let recent = received.addingTimeInterval(-1)
        XCTAssertTrue(policy.accepts(timestamp: recent, horizontalAccuracy: 5))
        XCTAssertTrue(policy.isRecent(timestamp: recent, receivedAt: received))
    }

    func testPreSessionCacheCannotBecomeRouteOrReadyEvenWhenRecent() {
        let start = Date(timeIntervalSince1970: 1000)
        let policy = LocationFixPolicy(sessionStartedAt: start)
        let cached = start.addingTimeInterval(-1)
        XCTAssertFalse(policy.accepts(timestamp: cached, horizontalAccuracy: 5))
        XCTAssertFalse(policy.isRecent(timestamp: cached, receivedAt: start.addingTimeInterval(1)))
        XCTAssertFalse(policy.accepts(timestamp: start, horizontalAccuracy: -1))
    }

    func testFreshnessBoundaryDoesNotChangeRouteAcceptance() {
        let start = Date(timeIntervalSince1970: 1000)
        let policy = LocationFixPolicy(sessionStartedAt: start)
        XCTAssertTrue(policy.accepts(timestamp: start, horizontalAccuracy: 0))
        XCTAssertTrue(policy.isRecent(timestamp: start, receivedAt: start.addingTimeInterval(14.9)))
        XCTAssertFalse(policy.isRecent(timestamp: start, receivedAt: start.addingTimeInterval(15)))
        XCTAssertTrue(policy.accepts(timestamp: start, horizontalAccuracy: 0))
    }
}
