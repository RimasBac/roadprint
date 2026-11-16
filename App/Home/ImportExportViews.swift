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
    private(set) var isWorking = false

    /// Export all trips: writes both files off the main thread, then the share sheet opens.
    func export(model: RecordingModel, profile: UserProfile) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            exported = try await model.dataTransfer.export(profile: profile)
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
            self.plan = nil
            await model.refreshTrips()
        } catch let error as ImportExportService.TransferError {
            self.plan = nil
            alertMessage = error.message
        } catch {
            self.plan = nil
            alertMessage = ImportExportService.TransferError.saveFailed.message
        }
    }
}

extension View {
    /// The system pieces behind "Your data": share sheet, file picker, preview sheet, alert.
    func dataTransferPresentations(_ transfer: DataTransferModel, model: RecordingModel, profile: UserProfile) -> some View {
        @Bindable var transfer = transfer
        return self
            .sheet(item: $transfer.exported) { files in
                ActivitySheet(items: files.urls).presentationDetents([.medium, .large])
            }
            .fileImporter(isPresented: $transfer.pickingFile,
                          allowedContentTypes: [.json, UTType(filenameExtension: "gpx") ?? .xml],
                          allowsMultipleSelection: false) { result in
                Task { await transfer.picked(result, model: model, profile: profile) }
            }
            .sheet(isPresented: Binding(get: { transfer.plan != nil }, set: { if !$0 { transfer.plan = nil } })) {
                if let plan = transfer.plan {
                    ImportPreviewSheet(plan: plan, isWorking: transfer.isWorking) {
                        Task { await transfer.confirmImport(model: model) }
                    } cancel: { transfer.plan = nil }
                    .presentationDetents([.medium, .large])
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
            Text("Import trips").font(RPType.screenTitle)
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
            Button(action: confirm) {
                Text("Import").font(RPType.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: RPSize.minTouch)
            }
            .buttonStyle(.borderedProminent)
            .disabled(plan.importCount == 0 || isWorking)
            .accessibilityIdentifier("importConfirmButton")
            Button("Cancel", role: .cancel, action: cancel)
                .frame(maxWidth: .infinity, minHeight: RPSize.minTouch)
                .accessibilityIdentifier("importCancelButton")
        }
        .padding(RPSpace.screenMargin)
        .background(Color.RP.background.ignoresSafeArea())
        .accessibilityIdentifier("importPreviewSheet")
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
