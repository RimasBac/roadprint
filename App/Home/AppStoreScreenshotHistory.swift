#if DEBUG
import Foundation
import RoadPrintCore

/// Simulated drives over overlapping legs of the bundled I-80 replay, kept in a fresh in-memory store.
enum AppStoreScreenshotHistory {
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
    }
}
#endif
