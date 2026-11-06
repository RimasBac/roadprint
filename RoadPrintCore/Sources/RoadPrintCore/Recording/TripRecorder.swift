import Foundation

public enum TripRecorderError: Error, Equatable {
    case alreadyRecording
    case notRecording
    case invalidStop
}

/// Drives one recording trip through a `TripStore`. Bumps `updatedAt` on every write.
public actor TripRecorder {
    private let store: any TripStore
    private let clock: @Sendable () -> Date
    private let analyzer: TripAnalyzer
    private var activeID: UUID?
    private var isStarting = false

    public init(
        store: any TripStore,
        clock: @escaping @Sendable () -> Date = { Date() },
        heuristics: RecordingHeuristics = .default
    ) {
        self.store = store
        self.clock = clock
        self.analyzer = TripAnalyzer(heuristics: heuristics)
    }

    /// Creates a recording trip.
    public func start() async throws -> Trip {
        if activeID != nil || isStarting { throw TripRecorderError.alreadyRecording }
        isStarting = true
        defer { isStarting = false }
        if try await store.activeTrip() != nil { throw TripRecorderError.alreadyRecording }
        let now = clock()
        let trip = Trip(createdAt: now, updatedAt: now, status: .recording)
        try await store.save(trip)
        activeID = trip.id
        return trip
    }

    /// Appends a batch of points to the active trip.
    public func record(_ points: [TrackPoint]) async throws {
        let id = try await requireActiveID()
        guard !points.isEmpty else { return }
        try await store.append(points, toTripWithID: id, updatedAt: clock())
    }

    /// Ends the active trip: `partial` if it has any gap, otherwise `completed`.
    @discardableResult
    public func end(at endedAt: Date) async throws -> Trip {
        let id = try await requireActiveID()
        guard let trip = try await store.trip(id: id) else { throw TripStoreError.tripNotFound(id) }
        return try await finish(trip, endedAt: endedAt)
    }

    /// After a relaunch: the trip still recording, if any.
    public func resumeIfNeeded() async throws -> Trip? {
        guard let trip = try await store.activeTrip() else {
            activeID = nil
            return nil
        }
        activeID = trip.id
        return trip
    }

    /// Cuts the active trip at the start of a long stop and completes it there.
    @discardableResult
    public func endAtStop(_ stop: LongStop) async throws -> Trip {
        let id = try await requireActiveID()
        guard var trip = try await store.trip(id: id) else { throw TripStoreError.tripNotFound(id) }
        guard trip.points.indices.contains(stop.startIndex) else { throw TripRecorderError.invalidStop }
        trip.points = Array(trip.points[...stop.startIndex])
        return try await finish(trip, endedAt: trip.points[stop.startIndex].timestamp)
    }

    private func finish(_ trip: Trip, endedAt: Date) async throws -> Trip {
        var trip = trip
        trip.endedAt = endedAt
        trip.status = analyzer.gaps(in: trip.points).isEmpty ? .completed : .partial
        trip.updatedAt = clock()
        try await store.save(trip)
        activeID = nil
        return trip
    }

    private func requireActiveID() async throws -> UUID {
        if let activeID { return activeID }
        if let trip = try await store.activeTrip() {
            activeID = trip.id
            return trip.id
        }
        throw TripRecorderError.notRecording
    }
}
