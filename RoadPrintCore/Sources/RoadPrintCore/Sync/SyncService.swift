import Foundation

/// What iCloud sync is doing right now (ADR 0005). Trips are always kept on the phone first,
/// so every state other than `available` still means "your trips are safe here".
public enum SyncStatus: String, Sendable, Codable, Equatable, CaseIterable {
    /// Sync is on and the iCloud account can be used.
    case available
    /// The user turned sync off, or this build has sync disabled.
    case off
    /// Not signed in to iCloud, or iCloud is off for the app.
    case noAccount
    /// The user's iCloud storage is full.
    case quotaFull
    /// Any other sync failure; trips stay local and sync retries by itself.
    case error

    /// The banner to show on You and Settings (docs/design/SCREENS.md A8, A9), if any.
    public var banner: SyncBanner? {
        switch self {
        case .noAccount: .iCloudUnavailable
        case .quotaFull: .storageFull
        case .available, .off, .error: nil
        }
    }
}

public enum SyncBanner: String, Sendable, Equatable {
    /// A8 "iCloud is not available".
    case iCloudUnavailable
    /// A9 "iCloud storage is full".
    case storageFull
}

/// iCloud sync behind a protocol (AGENTS.md §7.2). Feature code sees only this; the
/// CloudKit-backed implementation lives in `App/Storage/`.
public protocol SyncService: Sendable {
    func status() async -> SyncStatus
    /// Turning sync off keeps every trip on the phone and leaves the iCloud copy as it is.
    func setEnabled(_ enabled: Bool) async throws
}

/// For tests, previews and builds where sync is not on yet.
public actor LocalOnlySyncService: SyncService {
    public init() {}
    public func status() -> SyncStatus { .off }
    public func setEnabled(_ enabled: Bool) {}
}
