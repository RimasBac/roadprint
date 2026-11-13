import Foundation
import Testing
@testable import RoadPrintCore

private let analyzer = TripAnalyzer()

@Test func unfinishedNoPointsIsNone() {
    #expect(analyzer.unfinishedTripAction(points: [], now: t0) == .none)
}

@Test func unfinishedRecentTripIsNone() {
    let points = [pt(0, 0, t: 0), pt(0, 0.001, t: 60)]
    #expect(analyzer.unfinishedTripAction(points: points, now: t0.addingTimeInterval(600)) == .none)
}

@Test func unfinishedLongStopFixtureOffersEnd() throws {
    let points = try Fixtures.points("i80-long-stop")
    let stop = try #require(analyzer.longStops(in: points).first)
    let now = points.last!.timestamp.addingTimeInterval(60)
    guard case let .forgotToEnd(start, duration) = analyzer.unfinishedTripAction(points: points, now: now) else {
        Issue.record("expected forgotToEnd"); return
    }
    #expect(start == points[stop.startIndex].timestamp)
    #expect(duration >= 9 * 3600)
}

@Test func unfinishedGapFixtureIsInterrupted() throws {
    let points = try Fixtures.points("i80-gap")
    let gap = try #require(analyzer.gaps(in: points).first)
    let now = points.last!.timestamp.addingTimeInterval(60)
    #expect(analyzer.unfinishedTripAction(points: points, now: now)
        == .interrupted(gapStart: points[gap.startIndex].timestamp, gapEnd: points[gap.endIndex].timestamp))
}

@Test func unfinishedStopInProgressUsesTimeSinceLastPoint() {
    let points = [pt(0, 0, t: 0), pt(0, 0.001, t: 60)]
    let now = t0.addingTimeInterval(60 + 3 * 3600)
    #expect(analyzer.unfinishedTripAction(points: points, now: now)
        == .forgotToEnd(stopStart: points[1].timestamp, stopDuration: 3 * 3600))
}

@Test func unfinishedJustUnderThresholdIsNone() {
    let points = [pt(0, 0, t: 0)]
    let now = t0.addingTimeInterval(RecordingHeuristics.default.longStopMinDuration - 1)
    #expect(analyzer.unfinishedTripAction(points: points, now: now) == .none)
}

@Test func unfinishedGapAndLongStopOffersStopFirst() {
    // gap (~5.5 km jump) then a 3 h wait in place
    let points = [pt(0, 0, t: 0), pt(0, 0.05, t: 200), pt(0, 0.0501, t: 3 * 3600 + 300)]
    let now = t0.addingTimeInterval(3 * 3600 + 400)
    #expect(analyzer.unfinishedTripAction(points: points, now: now)
        == .forgotToEnd(stopStart: points[1].timestamp, stopDuration: 3 * 3600 + 100))
    let trip = Trip(createdAt: t0, points: points)
    let stop = analyzer.unfinishedStop(points: points, now: now)!
    // the gap is before the cut, so the trimmed trip is partial
    #expect(analyzer.endingTrip(trip, at: stop).status == .partial)
}

@Test func endingTripAtStopDropsLaterPoints() throws {
    let points = try Fixtures.points("i80-long-stop")
    let stop = try #require(analyzer.longStops(in: points).first)
    let trip = Trip(createdAt: points[0].timestamp, status: .recording, points: points)
    let ended = analyzer.endingTrip(trip, at: stop, updatedAt: t0)
    #expect(ended.points.count == stop.startIndex + 1)
    #expect(ended.endedAt == points[stop.startIndex].timestamp)
    #expect(ended.status == .completed)
    #expect(ended.updatedAt == t0)
}

@Test func endingTripWithBadStopLeavesTripAlone() {
    let trip = Trip(createdAt: t0, points: [pt(0, 0, t: 0)])
    let bad = LongStop(startIndex: 5, endIndex: 6, duration: 9 * 3600)
    #expect(analyzer.endingTrip(trip, at: bad) == trip)
}
