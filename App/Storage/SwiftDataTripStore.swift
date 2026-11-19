import Foundation
import SwiftData
import RoadPrintCore

/// SwiftData implementation of the core `TripStore`. The only file that touches `@Model` types.
///
/// `append` is batched: points are buffered in memory and written when 20 are pending or 30 s
/// have passed since the last write. Call `flush()` on End and when the app backgrounds.
/// Every read flushes first, so callers never observe stale data.
actor SwiftDataTripStore: TripStore {
    static let flushPointCount = 20
    static let flushInterval: TimeInterval = 30

    private let context: ModelContext
    private let now: @Sendable () -> Date
    private var pending: [UUID: (points: [TrackPoint], updatedAt: Date)] = [:]
    private var lastFlush: Date

    init(container: ModelContainer, now: @escaping @Sendable () -> Date = { Date() }) {
        self.context = ModelContext(container)
        self.context.autosaveEnabled = false
        self.now = now
        self.lastFlush = now()
    }

    static let cloudContainerID = "iCloud.com.rimasbac.roadprint"

    /// `cloudKitDatabase` is always explicit (ADR 0005): the default, `.automatic`, would turn CloudKit on
    /// by itself. `url == nil` keeps the default store file every installed build uses; tests pass their own.
    /// Turning sync on or off rebuilds the container on the same file.
    static func makeContainer(inMemory: Bool = false, url: URL? = nil, sync: Bool = false) throws -> ModelContainer {
        let schema = Schema([TripRecord.self])
        let database: ModelConfiguration.CloudKitDatabase = sync && !inMemory ? .private(cloudContainerID) : .none
        let config: ModelConfiguration
        if let url {
            config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: database)
        } else {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: database)
        }
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Removes records that share an `id` (ADR 0005 §5), keeping `TripDeduplicator`'s survivor.
    @discardableResult
    func removeDuplicates() throws -> Int {
        try flush()
        let records = try context.fetch(FetchDescriptor<TripRecord>(sortBy: [SortDescriptor(\.createdAt)]))
        guard Set(records.map(\.id)).count != records.count else { return 0 }
        let plan = TripDeduplicator.plan(try records.map(map))
        for index in plan.delete { context.delete(records[index]) }
        try context.save()
        return plan.delete.count
    }

    // MARK: TripStore

    func deduplicate() throws { try removeDuplicates() }

    func save(_ trip: Trip) throws {
        pending[trip.id] = nil
        let record = try fetchRecord(id: trip.id) ?? {
            let r = TripRecord()
            context.insert(r)
            return r
        }()
        try apply(trip, to: record)
        try context.save()
    }

    func trip(id: UUID) throws -> Trip? {
        try flush()
        return try fetchRecord(id: id).map(map)
    }

    func allTrips() throws -> [Trip] {
        try flush()
        return try context.fetch(FetchDescriptor<TripRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )).reduce(into: ([UUID: Bool](), [TripRecord]())) { acc, record in
            // Identical copies are kept in the store (see `TripDeduplicator`) but listed once.
            if acc.0.updateValue(true, forKey: record.id) == nil { acc.1.append(record) }
        }.1.map(map)
    }

    func activeTrip() throws -> Trip? {
        try flush()
        let recording = TripStatus.recording.rawValue
        var descriptor = FetchDescriptor<TripRecord>(
            predicate: #Predicate { $0.statusRaw == recording },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first.map(map)
    }

    func append(_ points: [TrackPoint], toTripWithID id: UUID, updatedAt: Date) throws {
        guard try fetchRecord(id: id) != nil else { throw TripStoreError.tripNotFound(id) }
        var entry = pending[id] ?? (points: [], updatedAt: updatedAt)
        entry.points.append(contentsOf: points)
        entry.updatedAt = updatedAt
        pending[id] = entry
        let total = pending.values.reduce(0) { $0 + $1.points.count }
        if total >= Self.flushPointCount || now().timeIntervalSince(lastFlush) >= Self.flushInterval {
            try flush()
        }
    }

    func delete(id: UUID) throws {
        if let record = try fetchRecord(id: id) {
            context.delete(record)
            do {
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
        pending[id] = nil
    }

    /// Writes buffered points. Call on End and on backgrounding.
    func flush() throws {
        lastFlush = now()
        guard !pending.isEmpty else { return }
        let batch = pending
        for (id, entry) in batch {
            guard let record = try fetchRecord(id: id) else { pending[id] = nil; continue }
            var points = try decodePoints(record.pointsData)
            points.append(contentsOf: entry.points)
            record.pointsData = try Self.encoder.encode(points)
            record.updatedAt = entry.updatedAt
        }
        try context.save()
        pending = [:]
    }

    // MARK: Mapping

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    private func fetchRecord(id: UUID) throws -> TripRecord? {
        var descriptor = FetchDescriptor<TripRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func decodePoints(_ data: Data?) throws -> [TrackPoint] {
        guard let data, !data.isEmpty else { return [] }
        return try Self.decoder.decode([TrackPoint].self, from: data)
    }

    private func apply(_ trip: Trip, to record: TripRecord) throws {
        record.id = trip.id
        record.createdAt = trip.createdAt
        record.updatedAt = trip.updatedAt
        record.schemaVersion = trip.schemaVersion
        record.statusRaw = trip.status.rawValue
        record.visibilityRaw = trip.visibility.rawValue
        record.endedAt = trip.endedAt
        // One write: a processed trip arrives with `points == []`, so the raw points are dropped here.
        record.pointsData = trip.points.isEmpty ? nil : try Self.encoder.encode(trip.points)
        record.storedStartedAt = trip.storedStartedAt
        record.routeData = try encode(trip.route)
        record.summaryData = try encode(trip.summary)
        record.placesData = try encode(trip.places)
        record.mainRoadData = try encode(trip.mainRoad)
    }

    private func map(_ record: TripRecord) throws -> Trip {
        Trip(
            id: record.id,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            schemaVersion: record.schemaVersion,
            status: TripStatus(rawValue: record.statusRaw) ?? .completed,
            visibility: Visibility(rawValue: record.visibilityRaw) ?? .private,
            points: try decodePoints(record.pointsData),
            endedAt: record.endedAt,
            storedStartedAt: record.storedStartedAt,
            summary: try decode(record.summaryData),
            route: try decode(record.routeData),
            places: try decode(record.placesData),
            mainRoad: try decode(record.mainRoadData)
        )
    }

    private func encode<T: Encodable>(_ value: T?) throws -> Data? {
        try value.map { try Self.encoder.encode($0) }
    }

    private func decode<T: Decodable>(_ data: Data?) throws -> T? {
        guard let data, !data.isEmpty else { return nil }
        return try Self.decoder.decode(T.self, from: data)
    }
}
