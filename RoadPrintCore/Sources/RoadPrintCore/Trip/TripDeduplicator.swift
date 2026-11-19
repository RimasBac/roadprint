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
    ///
    /// Identical copies are the danger: each device sees them in its own order, picks a different
    /// "first" and deletes the other, and after sync both are gone. So identical copies are never
    /// deleted unless the caller supplies `tieBreakers` (one stable key per record, the same on every
    /// device, for example the CloudKit record name): then the smallest key survives. Without keys
    /// they are neither kept nor deleted; the store hides the extras when it reads.
    public static func plan(
        _ trips: [Trip], protectRecordings: Bool = true, tieBreakers: [String]? = nil
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
        if let tieBreakers, tieBreakers.count == trips.count {
            // Among identical copies the smallest stable key survives, the same on every device.
            for (index, trip) in trips.enumerated() {
                guard let current = survivorByID[trip.id], current != index,
                      sameContent(trip, trips[current]), tieBreakers[index] < tieBreakers[current]
                else { continue }
                survivorByID[trip.id] = index
            }
        }
        let keep = order.compactMap { survivorByID[$0] }
        let survivors = Set(keep)
        let delete = trips.indices.filter { index in
            guard !survivors.contains(index), let survivor = survivorByID[trips[index].id] else { return false }
            return tieBreakers != nil || !sameContent(trips[index], trips[survivor])
        }
        return (keep, delete)
    }

    private static func sameContent(_ a: Trip, _ b: Trip) -> Bool {
        guard let ka = try? encoder.encode(a), let kb = try? encoder.encode(b) else { return false }
        return ka == kb
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN"
        )
        return encoder
    }()

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

        guard let candidateKey = try? encoder.encode(candidate) else { return false }
        guard let currentKey = try? encoder.encode(current) else { return true }
        return candidateKey.lexicographicallyPrecedes(currentKey)
    }

    private static func pointCount(_ trip: Trip) -> Int {
        trip.route?.segments.reduce(trip.points.count) { $0 + $1.points.count } ?? trip.points.count
    }
}
