import Foundation
import RoadPrintCore

/// Export and import for the You tab (plan §4.7). All the logic is in the core
/// (`TripArchive`, `GPXWriter`, `TripImporter`); this only reads and writes the store and files.
struct ImportExportService: Sendable {
    let store: any TripStore
    let processing: TripProcessingService

    struct ExportedFiles: Equatable, Sendable {
        let json: URL
        let gpx: URL
        var urls: [URL] { [json, gpx] }
    }

    enum TransferError: Error, Equatable {
        case nothingToExport
        case diskFull
        case writeFailed
        case unreadable
        case importing(ImportError)
        case saveFailed

        /// Plain words for alerts A10 and A14.
        var message: String {
            switch self {
            case .nothingToExport:
                String(localized: "There are no trips to export yet.", comment: "Export alert: no finished trips.")
            case .diskFull:
                String(localized: "Your iPhone is out of space. Free some up and try again.", comment: "Export alert A14: disk full.")
            case .writeFailed:
                String(localized: "RoadPrint could not write the export files. Try again.", comment: "Export alert A10: writing failed.")
            case .unreadable:
                String(localized: "RoadPrint could not open that file.", comment: "Import alert: file could not be read.")
            case .importing(let error):
                error.message
            case .saveFailed:
                String(localized: "RoadPrint could not save the imported trips. Nothing was lost. Try again.", comment: "Import alert: saving failed.")
            }
        }
    }

    /// Writes `RoadPrint-YYYY-MM-DD.json` and `.gpx` into a fresh temp folder.
    func export(profile: UserProfile, now: Date = Date()) async throws -> ExportedFiles {
        let trips = try await store.allTrips().filter { $0.status != .recording }
        guard !trips.isEmpty else { throw TransferError.nothingToExport }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        return try await Task.detached(priority: .userInitiated) {
            let archive = TripArchive(exportedAt: now, appVersion: version, profile: profile, trips: trips)
            let json: Data
            do { json = try archive.encoded() } catch { throw TransferError.writeFailed }
            let gpx = GPXWriter.document(trips: archive.trips)
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("RoadPrintExport-\(UUID().uuidString)", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let jsonURL = folder.appendingPathComponent(ExportFileNames.json(on: now))
                let gpxURL = folder.appendingPathComponent(ExportFileNames.gpx(on: now))
                try json.write(to: jsonURL, options: .atomic)
                try gpx.write(to: gpxURL, options: .atomic)
                return ExportedFiles(json: jsonURL, gpx: gpxURL)
            } catch let error as NSError where error.code == NSFileWriteOutOfSpaceError {
                throw TransferError.diskFull
            } catch {
                throw TransferError.writeFailed
            }
        }.value
    }

    /// Reads a picked file and says what importing it would do.
    func plan(fileAt url: URL, profile: UserProfile) async throws -> ImportPlan {
        let existing = try await store.allTrips()
        return try await Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data: Data
            do { data = try Data(contentsOf: url) } catch { throw TransferError.unreadable }
            do {
                return try TripImporter.plan(data: data, fileName: url.lastPathComponent,
                                             existing: existing, localProfile: profile)
            } catch let error as ImportError {
                throw TransferError.importing(error)
            }
        }.value
    }

    /// Saves the new and newer trips, then processes imported GPX trips like recorded ones.
    func apply(_ plan: ImportPlan) async throws {
        do {
            for trip in plan.toInsert + plan.toReplace { try await store.save(trip) }
            try await store.flush()
        } catch {
            throw TransferError.saveFailed
        }
        if plan.needsProcessing {
            for trip in plan.toInsert + plan.toReplace { await processing.process(trip) }
        }
    }
}

extension ImportPlan {
    /// Trips that Import would write.
    var importCount: Int { toInsert.count + toReplace.count }
}
