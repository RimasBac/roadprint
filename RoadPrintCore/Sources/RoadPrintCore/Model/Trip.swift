import Foundation

public enum TripStatus: String, Sendable, Codable, Equatable, CaseIterable {
    case recording
    case completed
    /// Ended with at least one gap: the car moved but nothing was recorded.
    case partial
}

/// Who may see a trip. v1 uses only `private` (AGENTS.md §7b.4).
public enum Visibility: String, Sendable, Codable, Equatable, CaseIterable {
    case `private`
}

/// A recorded trip. A plain value type; the app maps it to and from storage.
public struct Trip: Sendable, Codable, Equatable, Identifiable {
    public static let currentSchemaVersion = 1

    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var schemaVersion: Int
    public var status: TripStatus
    public var visibility: Visibility
    public var points: [TrackPoint]
    /// Set when the trip is ended. Use `effectiveEndedAt` for display.
    public var endedAt: Date?
    /// Set from the first raw point by `TripProcessor` (ADR 0003). Use `startedAt`.
    public var storedStartedAt: Date?
    /// Set by `TripProcessor`, computed from the full cleaned trace (ADR 0003).
    public var summary: TripSummaryStats?
    /// Set by `TripProcessor`; `points` is empty once it exists (ADR 0003).
    public var route: ProcessedRoute?
    /// Set by `TripProcessor` when it has a `PlaceIndex`. Computed on the cleaned trace before trimming (ADR 0003).
    public var places: TripPlaces?

    enum CodingKeys: String, CodingKey {
        case id, createdAt, updatedAt, schemaVersion, status, visibility, points, endedAt
        case storedStartedAt = "startedAt"
        case summary, route, places
    }

    public init(
        id: UUID = UUID(),
        createdAt: Date,
        updatedAt: Date? = nil,
        schemaVersion: Int = Trip.currentSchemaVersion,
        status: TripStatus = .recording,
        visibility: Visibility = .private,
        points: [TrackPoint] = [],
        endedAt: Date? = nil,
        storedStartedAt: Date? = nil,
        summary: TripSummaryStats? = nil,
        route: ProcessedRoute? = nil,
        places: TripPlaces? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.schemaVersion = schemaVersion
        self.status = status
        self.visibility = visibility
        self.points = points
        self.endedAt = endedAt
        self.storedStartedAt = storedStartedAt
        self.summary = summary
        self.route = route
        self.places = places
    }

    /// The stored start time, else the first point's time for unprocessed trips.
    public var startedAt: Date? { storedStartedAt ?? points.first?.timestamp }

    /// `endedAt` if the trip was ended, otherwise the last point's time.
    public var effectiveEndedAt: Date? { endedAt ?? points.last?.timestamp }
}
