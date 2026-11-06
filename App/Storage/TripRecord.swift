import Foundation
import SwiftData
import RoadPrintCore

/// Private storage type. Never leaves `App/Storage/`; the rest of the app sees `Trip`.
///
/// CloudKit-compatible from day one (M5 turns sync on): every property has a default,
/// no unique constraints, no relationships. There is deliberately no speed field.
@Model
final class TripRecord {
    var id: UUID = UUID()
    var createdAt: Date = Date(timeIntervalSince1970: 0)
    var updatedAt: Date = Date(timeIntervalSince1970: 0)
    var schemaVersion: Int = 1
    var statusRaw: String = TripStatus.recording.rawValue
    var visibilityRaw: String = Visibility.private.rawValue
    var endedAt: Date?
    /// All points of the trip as one encoded `[TrackPoint]` (not one row per point).
    @Attribute(.externalStorage, .allowsCloudEncryption)
    var pointsData: Data?

    init() {}
}
