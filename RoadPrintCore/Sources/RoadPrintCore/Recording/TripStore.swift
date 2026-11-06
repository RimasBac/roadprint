import Foundation

public enum TripStoreError: Error, Equatable {
    case tripNotFound(UUID)
}

/// Storage behind a protocol (AGENTS.md §7.2). SwiftData + CloudKit is one implementation.
public protocol TripStore: Sendable {
    func save(_ trip: Trip) async throws
    func trip(id: UUID) async throws -> Trip?
    /// Newest first.
    func allTrips() async throws -> [Trip]
    /// The trip with status `recording`, if any.
    func activeTrip() async throws -> Trip?
    /// Appends points and sets the trip's `updatedAt`.
    func append(_ points: [TrackPoint], toTripWithID id: UUID, updatedAt: Date) async throws
    func delete(id: UUID) async throws
}

/// For tests and previews.
public actor InMemoryTripStore: TripStore {
    private var trips: [UUID: Trip] = [:]

    public init() {}

    public func save(_ trip: Trip) {
        trips[trip.id] = trip
    }

    public func trip(id: UUID) -> Trip? {
        trips[id]
    }

    public func allTrips() -> [Trip] {
        trips.values.sorted { $0.createdAt > $1.createdAt }
    }

    public func activeTrip() -> Trip? {
        allTrips().first { $0.status == .recording }
    }

    public func append(_ points: [TrackPoint], toTripWithID id: UUID, updatedAt: Date) throws {
        guard var trip = trips[id] else { throw TripStoreError.tripNotFound(id) }
        trip.points.append(contentsOf: points)
        trip.updatedAt = updatedAt
        trips[id] = trip
    }

    public func delete(id: UUID) {
        trips[id] = nil
    }
}
