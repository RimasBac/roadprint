import Foundation

public enum TripDeduplicator {
    /// Picks one survivor per trip ID and returns indices into the supplied snapshot.
    /// Survivors are ordered by the first occurrence of each ID. Deletions are in snapshot order.
    ///
    /// For a local store, a recording survives over a finished copy regardless of timestamp.
    /// Pass `protectRecordings: false` for archive copies, which have no active local recording.
    /// Otherwise, the newest update wins, followed by route presence and the total number of
    /// raw and processed route points.
    ///
    /// Different contents with the same rank are ordered by their sorted-key JSON bytes.
    /// For identical contents, the first record survives. Use a stable record order across
    /// devices if they need to retain the same physical record among identical copies.
    public static func plan(
        _ trips: [Trip], protectRecordings: Bool = true
    ) -> (keep: [Int], delete: [Int]) {
        var survivorByID: [UUID: Int] = [:]
        var order: [UUID] = []
        for (index, trip) in trips.enumerated() {
            if let current = survivorByID[trip.id] {
                if prefers(trip, over: trips[current], protectRecordings: protectRecordings) {
                    survivorByID[trip.id] = index
                }
            } else {
                survivorByID[trip.id] = index
                order.append(trip.id)
            }
        }
        let keep = order.compactMap { survivorByID[$0] }
        let survivors = Set(keep)
        return (keep, trips.indices.filter { !survivors.contains($0) })
    }

    private static func prefers(_ candidate: Trip, over current: Trip, protectRecordings: Bool) -> Bool {
        let candidateRecording = candidate.status == .recording
        let currentRecording = current.status == .recording
        if protectRecordings && candidateRecording != currentRecording { return candidateRecording }
        if candidate.updatedAt != current.updatedAt { return candidate.updatedAt > current.updatedAt }

        let candidateHasRoute = candidate.route != nil
        let currentHasRoute = current.route != nil
        if candidateHasRoute != currentHasRoute { return candidateHasRoute }
        let candidatePoints = pointCount(candidate)
        let currentPoints = pointCount(current)
        if candidatePoints != currentPoints { return candidatePoints > currentPoints }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN"
        )
        guard let candidateKey = try? encoder.encode(candidate) else { return false }
        guard let currentKey = try? encoder.encode(current) else { return true }
        return candidateKey.lexicographicallyPrecedes(currentKey)
    }

    private static func pointCount(_ trip: Trip) -> Int {
        trip.route?.segments.reduce(trip.points.count) { $0 + $1.points.count } ?? trip.points.count
    }
}
