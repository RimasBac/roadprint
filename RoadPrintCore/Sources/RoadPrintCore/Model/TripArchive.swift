import Foundation

/// Why an archive could not be read.
public enum ArchiveError: Error, Equatable {
    /// Valid JSON, but not a RoadPrint archive (`format` missing or different).
    case notARoadPrintFile
    /// The archive or one of its trips was written by a newer app. Carries that version.
    case newerVersion(Int)
    /// Not JSON, or the archive is damaged.
    case corrupt
}

/// The export envelope: every trip in one lossless JSON file (docs/data-format.md).
public struct TripArchive: Sendable, Codable, Equatable {
    public static let formatName = "roadprint-archive"
    public static let currentVersion = 1

    public var format: String
    public var archiveVersion: Int
    public var exportedAt: Date
    public var appVersion: String
    public var profile: UserProfile?
    public var trips: [Trip]

    public init(
        exportedAt: Date, appVersion: String, profile: UserProfile? = nil, trips: [Trip]
    ) {
        self.format = Self.formatName
        self.archiveVersion = Self.currentVersion
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.profile = profile
        self.trips = Self.newestFirst(trips)
    }

    /// Newest start first (ties by id, so the output is deterministic).
    public static func newestFirst(_ trips: [Trip]) -> [Trip] {
        trips.sorted {
            let a = $0.startedAt ?? $0.createdAt, b = $1.startedAt ?? $1.createdAt
            return a != b ? a > b : $0.id.uuidString < $1.id.uuidString
        }
    }

    public func encoded() throws -> Data {
        try ExportJSON.encoder().encode(self)
    }

    /// Reads an archive. Checks `format`, then `archiveVersion`, then every trip's
    /// `schemaVersion` before decoding, so each failure gets the right error.
    public static func decode(_ data: Data) throws -> TripArchive {
        struct Header: Decodable {
            var format: String?
            var archiveVersion: Int?
            var trips: [TripHeader]?
        }
        struct TripHeader: Decodable { var schemaVersion: Int? }

        guard (try? JSONSerialization.jsonObject(with: data)) != nil else { throw ArchiveError.corrupt }
        guard let header = try? JSONDecoder().decode(Header.self, from: data),
              header.format == formatName else { throw ArchiveError.notARoadPrintFile }
        guard let version = header.archiveVersion else { throw ArchiveError.corrupt }
        if version > currentVersion { throw ArchiveError.newerVersion(version) }
        if let newest = header.trips?.compactMap(\.schemaVersion).max(),
           newest > Trip.maxSupportedSchemaVersion {
            throw ArchiveError.newerVersion(newest)
        }
        guard version >= 1, let archive = try? ExportJSON.decoder().decode(TripArchive.self, from: data) else {
            throw ArchiveError.corrupt
        }
        return archive
    }
}

/// `RoadPrint-YYYY-MM-DD.json` / `.gpx`, dated in UTC.
public enum ExportFileNames {
    public static func json(on date: Date) -> String { name(date, "json") }
    public static func gpx(on date: Date) -> String { name(date, "gpx") }

    private static func name(_ date: Date, _ ext: String) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "RoadPrint-%04d-%02d-%02d.%@", c.year!, c.month!, c.day!, ext)
    }
}
