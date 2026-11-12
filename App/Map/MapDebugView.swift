#if DEBUG
import SwiftUI
import RoadPrintCore

/// DEBUG-only: shows the hard-coded I-80 fixture. Launch with `-RPMapFixture i80` or `i80-gap`;
/// theme via `-RPDebugTheme night|day`. Add `-RPMapAnimate YES` to play the draw animation.
struct MapDebugView: View {
    let fixture: String

    static func input(fixture: String) -> MapSceneInput? {
        guard let url = Bundle.main.url(forResource: "i80-slc-sac-route", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let pairs = try? JSONDecoder().decode([[Double]].self, from: data) else { return nil }
        let points = pairs.map { RoutePoint(latitude: $0[0], longitude: $0[1]) }
        guard let first = points.first, let last = points.last else { return nil }
        let segments: [RouteSegment]
        if fixture == "i80-gap" {
            let a = points.count / 2
            segments = [RouteSegment(points: Array(points[..<(a - 20)])), RouteSegment(points: Array(points[(a + 20)...]))]
        } else if fixture == "short" {
            return MapSceneInput(segments: [RouteSegment(points: Array(points[..<4]))],
                                 start: ApproximateArea(centerLatitude: first.latitude, centerLongitude: first.longitude, radiusMeters: 800),
                                 end: nil, summit: nil, startLabel: "Salt Lake City area", endLabel: nil)
        } else {
            segments = [RouteSegment(points: points)]
        }
        return MapSceneInput(segments: segments,
            start: ApproximateArea(centerLatitude: first.latitude, centerLongitude: first.longitude, radiusMeters: 8_000),
            end: ApproximateArea(centerLatitude: last.latitude, centerLongitude: last.longitude, radiusMeters: 8_000),
            summit: RoutePoint(latitude: 39.33, longitude: -120.34, altitude: 2206),
            startLabel: "Salt Lake City area", endLabel: "Sacramento area")
    }

    /// `-RPDebugTheme night|day`; nil follows the system (used by the appearance-switch test).
    private static var debugScheme: ColorScheme? {
        switch UserDefaults.standard.string(forKey: "RPDebugTheme") {
        case "night": .dark
        case "day": .light
        default: nil
        }
    }

    var body: some View {
        VStack {
            if let input = Self.input(fixture: fixture) {
                TripMapView(input: input, animateDraw: UserDefaults.standard.bool(forKey: "RPMapAnimate"))
                    .frame(height: 460)
            } else {
                Text("Fixture missing")
            }
            Spacer()
        }
        .preferredColorScheme(Self.debugScheme)
    }
}
#endif
