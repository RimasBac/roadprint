#if DEBUG
import Foundation
import RoadPrintCore

/// Simulated Western US drives for the lifetime map, kept in a fresh in-memory store.
enum AppStoreScreenshotHistory {
    /// Career miles driven before the app, so the screenshots show a seasoned driver closing in on a
    /// million miles (about 846,000 with the seeded trips) rather than a first-week rookie.
    static let startingCareerMeters = 842_600 * DistanceUnit.metersPerMile

    // Approximate road corridors, with waypoints at towns and major bends.
    private static let corridors: [[(lat: Double, lon: Double)]] = [
        // I-5 north from Sacramento to Medford.
        [(38.58, -121.49), (38.68, -121.77), (39.21, -122.01), (40.18, -122.24),
         (40.59, -122.39), (41.31, -122.31), (41.73, -122.64), (42.33, -122.87)],
        // CA-99 south from Sacramento to Bakersfield.
        [(38.58, -121.49), (37.96, -121.27), (37.66, -120.99), (37.30, -120.48),
         (36.96, -120.06), (36.74, -119.82), (36.21, -119.35), (35.38, -119.05)],
        // I-15 south from Salt Lake City to Las Vegas.
        [(40.76, -111.89), (40.23, -111.67), (39.71, -111.84), (39.36, -112.33),
         (38.60, -112.59), (37.68, -113.06), (37.10, -113.58), (36.81, -114.07), (36.17, -115.14)],
        // I-84 northwest from the Wasatch Front to Boise.
        [(40.76, -111.89), (41.51, -112.02), (41.90, -112.60), (42.33, -113.59),
         (42.60, -114.45), (42.96, -115.30), (43.59, -116.21)],
        // US-95 north from Winnemucca to the Snake River Plain.
        [(40.97, -117.74), (41.57, -117.81), (42.00, -117.72), (42.88, -117.30),
         (43.14, -117.12), (43.55, -116.79), (43.59, -116.21)],
        // US-50 across Nevada, from the Reno area to Ely.
        [(39.53, -119.81), (39.16, -119.77), (39.43, -119.22), (39.47, -118.78),
         (39.49, -117.07), (39.51, -115.96), (39.25, -114.89)],
    ]

    static func seed(in store: any TripStore, now: Date) async throws {
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

        for (index, corridor) in corridors.enumerated() {
            // Keep some drives outside the recent window so they add to the lifetime map.
            let departure = now.addingTimeInterval(-86_400 * Double(40 + index * 7))
            let points = samples(along: corridor, departure: departure)
            try await store.save(Trip(createdAt: departure, status: .completed,
                                      points: points, endedAt: points.last?.timestamp))
        }
    }

    private static func samples(along corridor: [(lat: Double, lon: Double)], departure: Date) -> [TrackPoint] {
        let first = corridor[0]
        var points = [TrackPoint(latitude: first.lat, longitude: first.lon,
                                 timestamp: departure, horizontalAccuracy: 5)]
        var elapsed: TimeInterval = 0
        for (start, end) in zip(corridor, corridor.dropFirst()) {
            let distance = Geo.distance(lat1: start.lat, lon1: start.lon, lat2: end.lat, lon2: end.lon)
            let steps = max(1, Int(ceil(distance / 500)))
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
