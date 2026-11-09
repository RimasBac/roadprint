import Foundation
import OSLog
import RoadPrintCore

/// Runs the core `TripProcessor` off the main actor and stores the result (plan §5.4 steps 2–7).
///
/// The bundled place and road indexes load once, on first use, and stay cached. Processing is
/// all-or-nothing: the processed trip (with `points = []`) goes to the store in one `save`, so the
/// raw points are deleted only after the processed trip is written. On any failure the trip keeps
/// its raw points and `processPending()` retries it on the next launch.
actor TripProcessingService {
    private static let log = Logger(subsystem: "com.rimasbac.roadprint", category: "processing")

    private let store: any TripStore
    private var processor: TripProcessor?

    init(store: any TripStore) {
        self.store = store
    }

    /// A trip that has ended but still holds raw points and no summary.
    nonisolated static func needsProcessing(_ trip: Trip) -> Bool {
        trip.status != .recording && trip.summary == nil && !trip.points.isEmpty
    }

    /// Processes and stores one trip. Returns false (raw points kept) if it failed.
    @discardableResult
    func process(_ trip: Trip) async -> Bool {
        guard Self.needsProcessing(trip) else { return true }
        do {
            let processed = try loadedProcessor().process(trip)
            try await store.save(processed)
            return true
        } catch {
            Self.log.error("Processing failed, raw points kept: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// Retries every ended trip that is still unprocessed. Call on launch.
    func processPending() async {
        do {
            for trip in try await store.allTrips() where Self.needsProcessing(trip) {
                await process(trip)
            }
        } catch {
            Self.log.error("Could not list trips to process: \(String(describing: error), privacy: .public)")
        }
    }

    private func loadedProcessor() throws -> TripProcessor {
        if let processor { return processor }
        let loaded = TripProcessor(
            placeIndex: try PlaceIndex.bundled(),
            roadIndex: try RoadIndex.bundled())
        processor = loaded
        return loaded
    }
}
