import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Observation
import RoadPrintCore

/// State for "Your data" on You: export, the file picker, the import preview and alerts.
@MainActor
@Observable
final class DataTransferModel {
    var exported: ImportExportService.ExportedFiles?
    var pickingFile = false
    var plan: ImportPlan?
    var alertMessage: String?
    /// An error from saving: shown once the preview sheet has finished dismissing.
    private var pendingAlert: String?
    private(set) var isWorking = false

    /// Called when the preview sheet is gone: now an alert can be presented.
    func previewDismissed() {
        guard let pendingAlert else { return }
        self.pendingAlert = nil
        alertMessage = pendingAlert
    }

    #if DEBUG
    private(set) var exportedFixture: URL?

    /// Test-only (`-RPImportFixture <name>`): plans a bundled JSON file as if it had been picked.
    func importFixture(named name: String, model: RecordingModel, profile: UserProfile) async {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            alertMessage = ImportExportService.TransferError.unreadable.message
            return
        }
        await picked(.success([url]), model: model, profile: profile)
    }

    func restoreExportedFixture(model: RecordingModel, profile: UserProfile) async {
        guard let exportedFixture else { return }
        await picked(.success([exportedFixture]), model: model, profile: profile)
        try? FileManager.default.removeItem(at: exportedFixture)
        self.exportedFixture = nil
    }

    /// Verify both export files and keep the JSON for the restore step without opening the system share sheet.
    private func stageExportedFixture(_ files: ImportExportService.ExportedFiles) throws {
        let fileManager = FileManager.default
        guard files.urls.allSatisfy({ fileManager.isReadableFile(atPath: $0.path) }) else {
            throw ImportExportService.TransferError.unreadable
        }
        let fixture = fileManager.temporaryDirectory
            .appendingPathComponent("RoadPrintImportFixture-\(UUID().uuidString).json")
        try fileManager.copyItem(at: files.json, to: fixture)
        if let exportedFixture { try? fileManager.removeItem(at: exportedFixture) }
        exportedFixture = fixture
    }
    #endif

    /// Export all trips: writes both files off the main thread, then the share sheet opens.
    func export(model: RecordingModel, profile: UserProfile) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let files = try await model.dataTransfer.export(profile: profile)
            #if DEBUG
            if UserDefaults.standard.string(forKey: "RPImportFixture") != nil {
                defer { ImportExportService.removeTemporaryExports() }
                try stageExportedFixture(files)
                return
            }
            #endif
            exported = files
        } catch let error as ImportExportService.TransferError {
            alertMessage = error.message
        } catch {
            alertMessage = ImportExportService.TransferError.writeFailed.message
        }
    }

    func picked(_ result: Result<[URL], Error>, model: RecordingModel, profile: UserProfile) async {
        guard case .success(let urls) = result, let url = urls.first else {
            if case .failure = result { alertMessage = ImportExportService.TransferError.unreadable.message }
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            plan = try await model.dataTransfer.plan(fileAt: url, profile: profile)
        } catch let error as ImportExportService.TransferError {
            alertMessage = error.message
        } catch {
            alertMessage = ImportExportService.TransferError.unreadable.message
        }
    }

    func confirmImport(model: RecordingModel) async {
        guard let plan else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await model.dataTransfer.apply(plan)
            await model.refreshTrips()
            self.plan = nil
        } catch let error as ImportExportService.TransferError {
            pendingAlert = error.message
            self.plan = nil
        } catch {
            pendingAlert = ImportExportService.TransferError.saveFailed.message
            self.plan = nil
        }
    }
}

extension View {
    /// The system pieces behind "Your data": share sheet, file picker, preview sheet, alert.
    func dataTransferPresentations(_ transfer: DataTransferModel, model: RecordingModel, profile: UserProfile) -> some View {
        @Bindable var transfer = transfer
        return self
            .sheet(item: $transfer.exported, onDismiss: { ImportExportService.removeTemporaryExports() }) { files in
                ActivitySheet(items: files.urls).presentationDetents([.medium, .large])
            }
            .fileImporter(isPresented: $transfer.pickingFile,
                          allowedContentTypes: [.json, UTType(importedAs: "com.topografix.gpx"), .xml],
                          allowsMultipleSelection: false) { result in
                Task { await transfer.picked(result, model: model, profile: profile) }
            }
            .sheet(isPresented: Binding(get: { transfer.plan != nil }, set: { if !$0 { transfer.plan = nil } }),
                   onDismiss: { transfer.previewDismissed() }) {
                if let plan = transfer.plan {
                    ImportPreviewSheet(plan: plan, isWorking: transfer.isWorking) {
                        Task { await transfer.confirmImport(model: model) }
                    } cancel: { transfer.plan = nil }
                    .presentationDetents([.medium, .large])
                    .interactiveDismissDisabled(transfer.isWorking)
                }
            }
            .alert("Couldn't finish", isPresented: Binding(
                get: { transfer.alertMessage != nil }, set: { if !$0 { transfer.alertMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(transfer.alertMessage ?? "")
            }
    }
}

extension ImportExportService.ExportedFiles: Identifiable {
    var id: URL { json }
}

/// The system share sheet with several files (Y6).
struct ActivitySheet: UIViewControllerRepresentable {
    let items: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Import preview (S10): what the file holds, before anything is saved.
struct ImportPreviewSheet: View {
    let plan: ImportPlan
    let isWorking: Bool
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: RPSpace.l) {
            Text("Import trips")
                .font(RPType.screenTitle)
                .accessibilityIdentifier("importPreviewSheet")
            VStack(alignment: .leading, spacing: RPSpace.s) {
                Text("\(plan.found) trips found")
                    .font(RPType.body)
                    .accessibilityIdentifier("importFoundText")
                if plan.alreadyHere > 0 {
                    Text("\(plan.alreadyHere) already here")
                        .font(RPType.body).foregroundStyle(Color.RP.textSecondary)
                }
                if plan.importCount > 0 {
                    Text("\(plan.importCount) will be added")
                        .font(RPType.body).foregroundStyle(Color.RP.textSecondary)
                }
                ForEach(Array(skippedLines.enumerated()), id: \.offset) { _, line in
                    Text(line).font(RPType.body).foregroundStyle(Color.RP.textSecondary)
                }
            }
            .padding(RPSpace.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .rpCard()
            Spacer(minLength: 0)
            Button("Import", action: confirm)
                .buttonStyle(.rpPrimary)
                .disabled(plan.importCount == 0 || isWorking)
                .accessibilityIdentifier("importConfirmButton")
            Button("Cancel", role: .cancel, action: cancel)
                .frame(maxWidth: .infinity, minHeight: RPSize.minTouch)
                .disabled(isWorking)
                .accessibilityIdentifier("importCancelButton")
        }
        .padding(RPSpace.screenMargin)
        .background(Color.RP.background.ignoresSafeArea())
    }

    private var skippedLines: [String] {
        var lines: [String] = []
        let noTimes = plan.skipped.filter { $0.reason == .noTimes }.count
        if noTimes > 0 {
            lines.append(String(localized: "\(noTimes) tracks have no times. To restore, choose the .json file",
                                comment: "Import preview: GPX tracks without timestamps."))
        }
        let short = plan.skipped.filter { $0.reason == .tooShort }.count
        if short > 0 {
            lines.append(String(localized: "\(short) tracks are too short to import",
                                comment: "Import preview: GPX tracks under 100 m."))
        }
        let recording = plan.skipped.filter { $0.reason == .recording }.count
        if recording > 0 {
            lines.append(String(localized: "\(recording) unfinished trips skipped",
                                comment: "Import preview: trips that were still recording."))
        }
        return lines
    }
}
