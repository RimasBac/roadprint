import Foundation
import Testing
@testable import RoadPrintCore

@Test func sceneInputRespectsShareRoutePrivacy() throws {
    let point = RoutePoint(latitude: 40, longitude: -110, altitude: 1000)
    let area = ApproximateArea(centerLatitude: 40, centerLongitude: -110, radiusMeters: 500)
    let route = ProcessedRoute(segments: [RouteSegment(points: [point])], start: area, end: area, summit: point)
    let trip = Trip(createdAt: Date(timeIntervalSince1970: 0), route: route)
    let input = MapSceneInput(trip: trip, startLabel: "Start")
    #expect(input.segments == route.segments)
    #expect(input.start == area)
    #expect(input.startLabel == "Start")
    let summary = try #require(TripShareSummary.make(from: trip, options: ShareOptions(includeRoute: false)))
    let sharedInput = MapSceneInput(summary: summary)
    #expect(sharedInput.segments.isEmpty)
    #expect(sharedInput.start == nil)
    #expect(sharedInput.end == nil)
    #expect(sharedInput.summit == nil)
}
