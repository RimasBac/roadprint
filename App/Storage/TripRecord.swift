import Foundation
import SwiftData
import RoadPrintCore

/// Private storage type. Never leaves `App/Storage/`; the rest of the app sees `Trip`.
///
/// CloudKit-compatible (ADR 0005): every property is optional or defaulted, no `@Attribute(.unique)`,
/// no relationships. There is deliberately no speed field.
///
/// Schema rules once sync ships (CloudKit Production cannot rename, delete or retype a field):
/// additive changes only, and every released shape is frozen as a fixture in
/// `RoadPrintTests/TripStoreMigrationTests.swift`. Everything that says where or when someone
/// drove is `.allowsCloudEncryption`; only the random `id` and the small enums stay plain.
@Model
final class TripRecord {
    var id: UUID = UUID()
    @Attribute(.allowsCloudEncryption)
    var createdAt: Date = Date(timeIntervalSince1970: 0)
    @Attribute(.allowsCloudEncryption)
    var updatedAt: Date = Date(timeIntervalSince1970: 0)
    var schemaVersion: Int = 1
    var statusRaw: String = TripStatus.recording.rawValue
    var visibilityRaw: String = Visibility.private.rawValue
    @Attribute(.allowsCloudEncryption)
    var endedAt: Date?
    /// All points of the trip as one encoded `[TrackPoint]` (not one row per point).
    @Attribute(.externalStorage, .allowsCloudEncryption)
    var pointsData: Data?
    /// Set when the trip is processed (§5.4). Raw points are deleted at the same time.
    @Attribute(.allowsCloudEncryption)
    var storedStartedAt: Date?
    /// Encoded `ProcessedRoute`: geometry, start/end areas and summit, encrypted as one blob.
    @Attribute(.externalStorage, .allowsCloudEncryption)
    var routeData: Data?
    /// Encoded `TripSummaryStats`, `TripPlaces` and `MainRoad`.
    @Attribute(.allowsCloudEncryption)
    var summaryData: Data?
    @Attribute(.allowsCloudEncryption)
    var placesData: Data?
    @Attribute(.allowsCloudEncryption)
    var mainRoadData: Data?

    init() {}
}
