#if DEBUG
import Foundation
import RoadPrintCore

/// A simulated long-haul driver's history for the App Store screenshots, kept in a fresh in-memory
/// store: the I-80 replay route driven several times, and runs across the US Interstate network.
enum AppStoreScreenshotHistory {
    /// Career miles driven before the app, so the screenshots show a seasoned driver closing in on a
    /// million miles (about 846,000 with the seeded trips) rather than a first-week rookie. Lower it by
    /// the fixture's `miles` change when `us-interstate-runs.json` is regenerated.
    static let startingCareerMeters = 813_800 * DistanceUnit.metersPerMile

    /// `us-interstate-runs.json`, from Tools/fixtures/make-interstate-runs.mjs: day-sized runs between
    /// junction cities, every point a vertex of the app's road index, so trip processing finds the road.
    private struct Runs: Decodable {
        struct Run: Decodable {
            let road: String
            let repeatCount: Int
            /// [latitude, longitude] pairs.
            let points: [[Double]]

            enum CodingKeys: String, CodingKey { case road, repeatCount = "repeat", points }
        }
        let runs: [Run]
    }

    static func seed(in store: any TripStore, now: Date) async throws {
        try await seedI80(in: store, now: now)
        try await seedInterstateRuns(in: store, now: now)
    }

    /// The replay route's legs in the last week: the brightest road on the map and the top road.
    private static func seedI80(in store: any TripStore, now: Date) async throws {
        guard let url = Bundle.main.url(forResource: "i80-slc-sac", withExtension: "gpx") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let trace = try GPXReader.parse(Data(contentsOf: url))
        // Indices for Elko, Winnemucca, Reno and Sacramento in the replay GPX.
        let elko = 369, winnemucca = 569, reno = 833, sacramento = 1044
        let legs = [reno...sacramento, elko...reno, reno...sacramento,
                    winnemucca...sacramento, 0...elko, reno...sacramento]
        guard trace.indices.contains(sacramento) else { throw CocoaError(.fileReadCorruptFile) }

        for (index, leg) in legs.enumerated() {
            let departure = now.addingTimeInterval(-86_400 * Double(index + 1))
            let original = trace[leg.lowerBound].timestamp
            let points = trace[leg].map { sample in
                var point = sample
                point.timestamp = departure.addingTimeInterval(sample.timestamp.timeIntervalSince(original))
                return point
            }
            try await store.save(Trip(createdAt: departure, status: .completed,
                                      points: points, endedAt: points.last?.timestamp))
        }
    }

    /// One trip per run (more for the runs hauled repeatedly), two days apart, starting 40 days back
    /// so they sit outside the recent window and fill the lifetime map.
    private static func seedInterstateRuns(in store: any TripStore, now: Date) async throws {
        guard let url = Bundle.main.url(forResource: "us-interstate-runs", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let runs = try JSONDecoder().decode(Runs.self, from: Data(contentsOf: url)).runs
        var day = 40
        for run in runs {
            let corridor = run.points.compactMap { pair -> (lat: Double, lon: Double)? in
                pair.count == 2 ? (lat: pair[0], lon: pair[1]) : nil
            }
            guard corridor.count > 1 else { throw CocoaError(.fileReadCorruptFile) }
            for _ in 0..<max(1, run.repeatCount) {
                let departure = now.addingTimeInterval(-86_400 * Double(day))
                let points = samples(along: corridor, departure: departure, spacing: 1_500)
                try await store.save(Trip(createdAt: departure, status: .completed,
                                          points: points, endedAt: points.last?.timestamp))
                day += 2
            }
        }
    }

    /// A fix every `spacing` metres or less along the corridor, at 26 m/s (58 mph). Keep `spacing` under
    /// RecordingHeuristics.gapMinDisplacement (2 km), or processing splits the trip at every fix.
    private static func samples(along corridor: [(lat: Double, lon: Double)], departure: Date,
                                spacing: Double) -> [TrackPoint] {
        let first = corridor[0]
        var points = [TrackPoint(latitude: first.lat, longitude: first.lon,
                                 timestamp: departure, horizontalAccuracy: 5)]
        var elapsed: TimeInterval = 0
        for (start, end) in zip(corridor, corridor.dropFirst()) {
            let distance = Geo.distance(lat1: start.lat, lon1: start.lon, lat2: end.lat, lon2: end.lon)
            let steps = max(1, Int(ceil(distance / spacing)))
            let stepDuration = distance / Double(steps) / 26
            for step in 1...steps {
                let fraction = Double(step) / Double(steps)
                elapsed += stepDuration
                points.append(TrackPoint(latitude: start.lat + (end.lat - start.lat) * fraction,
                                         longitude: start.lon + (end.lon - start.lon) * fraction,
                                         timestamp: departure.addingTimeInterval(elapsed), horizontalAccuracy: 5))
            }
        }
        return points
    }
}
#endif
