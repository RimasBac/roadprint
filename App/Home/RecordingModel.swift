import Foundation
import Observation
import OSLog
import RoadPrintCore

struct TripRowData: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let distanceMeters: Double
    let movingTimeSeconds: TimeInterval
    /// Regions (or countries) crossed, e.g. "Utah · Nevada · California". Nil until processed.
    let placesLine: String?
}

/// UI state for Home. All recording logic lives in the core `TripRecorder`.
@MainActor
@Observable
final class RecordingModel {
    private(set) var isRecording = false
    private(set) var rows: [TripRowData] = []
    private(set) var replayFinished = false
    /// Set when a resumed trip has been parked for hours: offer to end it at the stop.
    var pendingStop: LongStop?
    var errorMessage: String?
    /// Debug: how long the final flush took on End, in milliseconds.
    private(set) var lastFlushMilliseconds: Double?
    private(set) var worstAppendMilliseconds: Double = 0

    private let store: any TripStore
    private let recorder: TripRecorder
    private let makeSource: @Sendable () -> any LocationSource
    private let analyzer = TripAnalyzer()
    private let processing: TripProcessingService
    private var source: (any LocationSource)?
    private var consumer: Task<Void, Never>?
    private var lastTimestamp: Date?
    private var didBootstrap = false

    init(environment: AppEnvironment) {
        store = environment.tripStore
        recorder = TripRecorder(store: environment.tripStore)
        processing = TripProcessingService(store: environment.tripStore)
        makeSource = environment.makeLocationSource
    }

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        do {
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "RPResetStore") {
                for trip in try await store.allTrips() { try await store.delete(id: trip.id) }
            }
            #endif
            if let trip = try await recorder.resumeIfNeeded() {
                lastTimestamp = trip.points.last?.timestamp
                beginCapture()
                pendingStop = analyzer.trailingStop(of: trip, now: Date())
            }
            // Retry trips whose processing failed earlier or was interrupted. Raw points are kept until it works.
            await processing.processPending()
            try await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func start() async {
        guard !isRecording else { return }
        do {
            _ = try await recorder.start()
            lastTimestamp = nil
            replayFinished = false
            beginCapture()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func end() async {
        guard isRecording else { return }
        do {
            try await finishCapture()
            try await timedFlush()
            let endedAt = AppEnvironment.isReplay ? (lastTimestamp ?? Date()) : Date()
            let trip = try await recorder.end(at: endedAt)
            await processing.process(trip)
            try await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Alert action: end the resumed trip at the start of the long stop.
    func endAtPendingStop() async {
        guard let stop = pendingStop else { return }
        pendingStop = nil
        do {
            try await finishCapture()
            try await timedFlush()
            let trip = try await recorder.endAtStop(stop)
            await processing.process(trip)
            try await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func beginCapture() {
        let source = makeSource()
        self.source = source
        isRecording = true
        let stream = source.points()
        consumer = Task { [recorder] in
            for await point in stream {
                lastTimestamp = point.timestamp
                let began = ContinuousClock.now
                do { try await recorder.record([point]) } catch { errorMessage = error.localizedDescription }
                worstAppendMilliseconds = max(worstAppendMilliseconds, Self.milliseconds(since: began))
            }
            if AppEnvironment.isReplay { replayFinished = true }
        }
    }

    /// Stops the source and waits until every emitted point is written.
    private func finishCapture() async throws {
        source?.stop()
        await consumer?.value
        consumer = nil
        source = nil
        isRecording = false
    }

    private func timedFlush() async throws {
        let began = ContinuousClock.now
        try await store.flush()
        let ms = Self.milliseconds(since: began)
        lastFlushMilliseconds = ms
        AppEnvironment.log.info("End flush \(ms, privacy: .public) ms; worst append \(self.worstAppendMilliseconds, privacy: .public) ms")
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let d = start.duration(to: .now).components
        return Double(d.seconds) * 1000 + Double(d.attoseconds) / 1e15
    }

    private func reload() async throws {
        rows = try await store.allTrips()
            .filter { $0.status != .recording }
            .map { trip in
                // Processed trips carry their stored summary; unprocessed ones fall back to the raw points.
                let stats = trip.summary ?? analyzer.stats(for: trip)
                return TripRowData(
                    id: trip.id,
                    date: trip.startedAt ?? trip.createdAt,
                    distanceMeters: stats.distanceMeters,
                    movingTimeSeconds: stats.movingTimeSeconds,
                    placesLine: TripFormatting.placesLine(trip.places)
                )
            }
    }
}
