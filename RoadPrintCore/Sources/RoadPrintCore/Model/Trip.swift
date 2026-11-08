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
    /// Version of a trip that still has raw points.
    public static let currentSchemaVersion = 1
    /// Version `TripProcessor` writes: adds the trimmed route and approximate areas.
    public static let processedSchemaVersion = 2
    /// The newest version readers accept. Anything newer is rejected on decode.
    public static let maxSupportedSchemaVersion = 2

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
    /// Set by `TripProcessor` when it has a `RoadIndex`. Computed on the trimmed route (ROA-41); nil if no road covers enough of it.
    public var mainRoad: MainRoad?

    enum CodingKeys: String, CodingKey {
        case id, createdAt, updatedAt, schemaVersion, status, visibility, points, endedAt
        case storedStartedAt = "startedAt"
        case summary, route, places, mainRoad
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
        places: TripPlaces? = nil,
        mainRoad: MainRoad? = nil
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
        self.mainRoad = mainRoad
    }

    /// The stored start time, else the first point's time for unprocessed trips.
    public var startedAt: Date? { storedStartedAt ?? points.first?.timestamp }

    /// `endedAt` if the trip was ended, otherwise the last point's time.
    public var effectiveEndedAt: Date? { endedAt ?? points.last?.timestamp }
}

extension Trip {
    /// Accepts schema 1 (raw points) and 2 (processed); rejects newer versions.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decode(Int.self, forKey: .schemaVersion)
        guard version <= Trip.maxSupportedSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion, in: c,
                debugDescription: "Unsupported schemaVersion \(version); newest supported is \(Trip.maxSupportedSchemaVersion)")
        }
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            createdAt: try c.decode(Date.self, forKey: .createdAt),
            updatedAt: try c.decode(Date.self, forKey: .updatedAt),
            schemaVersion: version,
            status: try c.decode(TripStatus.self, forKey: .status),
            visibility: try c.decode(Visibility.self, forKey: .visibility),
            points: try c.decode([TrackPoint].self, forKey: .points),
            endedAt: try c.decodeIfPresent(Date.self, forKey: .endedAt),
            storedStartedAt: try c.decodeIfPresent(Date.self, forKey: .storedStartedAt),
            summary: try c.decodeIfPresent(TripSummaryStats.self, forKey: .summary),
            route: try c.decodeIfPresent(ProcessedRoute.self, forKey: .route),
            places: try c.decodeIfPresent(TripPlaces.self, forKey: .places),
            mainRoad: try c.decodeIfPresent(MainRoad.self, forKey: .mainRoad))
    }
}
