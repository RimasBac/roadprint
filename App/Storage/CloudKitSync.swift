import Foundation
import SwiftData
import CoreData
import CloudKit
import RoadPrintCore

/// The one `TripStore` the app uses. It forwards to a `SwiftDataTripStore` and can swap it for a
/// container with the other `cloudKitDatabase` value on the same store file (ADR 0005 §7): a live
/// container can't switch sync on or off.
actor SwitchableTripStore: TripStore {
    private var store: SwiftDataTripStore
    private(set) var syncEnabled: Bool

    init(sync: Bool) throws {
        syncEnabled = sync
        store = SwiftDataTripStore(container: try SwiftDataTripStore.makeContainer(sync: sync))
    }

    func rebuild(sync: Bool) async throws {
        guard sync != syncEnabled else { return }
        try await store.flush()
        store = SwiftDataTripStore(container: try SwiftDataTripStore.makeContainer(sync: sync))
        syncEnabled = sync
    }

    func removeDuplicates() async throws { try await store.removeDuplicates() }
    func deduplicate() async throws { try await store.removeDuplicates() }

    func save(_ trip: Trip) async throws { try await store.save(trip) }
    func trip(id: UUID) async throws -> Trip? { try await store.trip(id: id) }
    func allTrips() async throws -> [Trip] { try await store.allTrips() }
    func activeTrip() async throws -> Trip? { try await store.activeTrip() }
    func append(_ points: [TrackPoint], toTripWithID id: UUID, updatedAt: Date) async throws {
        try await store.append(points, toTripWithID: id, updatedAt: updatedAt)
    }
    func delete(id: UUID) async throws { try await store.delete(id: id) }
    func flush() async throws { try await store.flush() }

    /// Safety net for sign-out (ADR 0005 §7): a local `TripArchive` in Application Support.
    func writeBackupArchive(appVersion: String) async throws {
        let trips = try await store.allTrips().filter { $0.status != .recording }
        let archive = TripArchive(exportedAt: Date(), appVersion: appVersion, trips: trips)
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        try archive.encoded().write(to: directory.appendingPathComponent("sync-backup.roadprint.json"), options: .atomic)
    }
}

/// Reads iCloud state and switches sync on or off. Only this file touches CloudKit.
actor CloudKitSyncService: SyncService {
    private let store: SwitchableTripStore
    private var enabled: Bool
    private var lastIssue: SyncStatus?
    private var observers: [NSObjectProtocol] = []
    private let hub = SyncChangeHub()

    init(store: SwitchableTripStore, enabled: Bool) {
        self.store = store
        self.enabled = enabled
        Task { await self.startObserving() }
    }

    nonisolated func changes() -> AsyncStream<Void> { hub.stream() }

    func status() async -> SyncStatus {
        guard enabled else { return .off }
        let account: CKAccountStatus
        do { account = try await CKContainer(identifier: SwiftDataTripStore.cloudContainerID).accountStatus() } catch {
            return .error
        }
        guard account == .available else { return .noAccount }
        return lastIssue ?? .available
    }

    func setEnabled(_ enabled: Bool) async throws {
        try await store.rebuild(sync: enabled)
        self.enabled = enabled
        lastIssue = nil
        UserDefaults.standard.set(enabled, forKey: AppSettings.iCloudSyncKey)
        if enabled { await startObserving() } else { stopObserving() }
    }

    func didEnterBackground(appVersion: String) async {
        guard enabled else { return }
        try? await store.writeBackupArchive(appVersion: appVersion)
    }

    private func stopObserving() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    /// Maps a CloudKit error, looking inside `.partialFailure` for `quotaExceeded`.
    nonisolated static func issue(for error: Error) -> SyncStatus {
        guard let error = error as? CKError else { return .error }
        switch error.code {
        case .quotaExceeded: return .quotaFull
        case .notAuthenticated: return .noAccount
        case .partialFailure:
            let inner = (error.partialErrorsByItemID ?? [:]).values.compactMap { $0 as? CKError }
            if inner.contains(where: { $0.code == .quotaExceeded }) { return .quotaFull }
            if inner.contains(where: { $0.code == .notAuthenticated }) { return .noAccount }
            return .error
        default: return .error
        }
    }

    private func startObserving() async {
        guard enabled, observers.isEmpty else { return }
        let center = NotificationCenter.default
        let store = self.store
        let hub = self.hub
        observers.append(center.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: nil) { _ in
            Task {
                try? await store.removeDuplicates()
                hub.send()
            }
        })
        observers.append(center.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: nil
        ) { [weak self] note in
            let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event
            guard let event, event.endDate != nil else { return }
            let issue: SyncStatus? = event.error.map { CloudKitSyncService.issue(for: $0) }
            Task {
                await self?.record(issue)
                hub.send()
            }
        })
        observers.append(center.addObserver(forName: .CKAccountChanged, object: nil, queue: nil) { [weak self] _ in
            Task {
                await self?.record(nil)
                hub.send()
            }
        })
        try? await store.removeDuplicates()
    }

    private func record(_ issue: SyncStatus?) {
        lastIssue = issue
    }
}
