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

/// TEMPORARY: why the test-trip tool could not add a trip (see `TestTripView`).
enum TestTripError: Error, Equatable, Sendable {
    case unknownPlace(String)
    case samePlace
    case failed
}

/// UI state for Home. All recording logic lives in the core `TripRecorder`.
@MainActor
@Observable
final class RecordingModel {
    private(set) var isRecording = false
    private(set) var isBusy = false
    private(set) var startFeedback = 0
    private(set) var endFeedback = 0
    private(set) var startedAt: Date?
    private(set) var gpsUnavailableSince: Date?
    let locationAccess = LocationAccess()
    enum PermissionAlert: String, Identifiable {
        case locationOff, preciseOff
        var id: String { rawValue }
    }
    var permissionAlert: PermissionAlert?

    func waitingForGPS(at date: Date) -> Bool {
        guard isRecording, let since = gpsUnavailableSince else { return false }
        return date.timeIntervalSince(since) >= 15
    }
    private(set) var rows: [TripRowData] = []
    private(set) var replayFinished = false
    /// What to offer after a relaunch with an unfinished trip (S5, S6). Nil when nothing is pending.
    var recovery: Recovery?
    /// Set after a trip ends: `MainTabView` opens its trip screen and clears this.
    var openTripID: UUID?
    enum Recovery: Equatable, Identifiable {
        case forgotToEnd(stop: LongStop, stopStart: Date, duration: TimeInterval)
        case interrupted(gapStart: Date, gapEnd: Date)
        var id: String {
            switch self {
            case .forgotToEnd: "forgotToEnd"
            case .interrupted: "interrupted"
            }
        }
    }
    private var recoveryEndDate: Date?
    var errorMessage: String?
    /// Debug: how long the final flush took on End, in milliseconds.
    private(set) var lastFlushMilliseconds: Double?
    private(set) var worstAppendMilliseconds: Double = 0

    private let now: @Sendable () -> Date
    private let store: any TripStore
    private let recorder: TripRecorder
    private let makeSource: @Sendable () -> any LocationSource
    private let analyzer = TripAnalyzer()
    private let processing: TripProcessingService
    private var source: (any LocationSource)?
    private var consumer: Task<Void, Never>?
    private var lastTimestamp: Date?
    private var didBootstrap = false

    init(environment: AppEnvironment, now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
        store = environment.tripStore
        recorder = TripRecorder(store: environment.tripStore, clock: now)
        processing = TripProcessingService(store: environment.tripStore)
        makeSource = environment.makeLocationSource
    }

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        #if DEBUG
        // Hold the real bootstrap path long enough to capture the delayed loading state.
        if UserDefaults.standard.bool(forKey: "RPDebugSlowStorage") {
            try? await Task.sleep(for: .seconds(3))
        }
        #endif
        do {
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "RPResetStore") {
                for trip in try await store.allTrips() { try await store.delete(id: trip.id) }
            }
            #endif
            #if DEBUG
            // UI tests: leave an unfinished trip behind, as if iOS had killed the app (S5, S6).
            if let kind = UserDefaults.standard.string(forKey: "RPSeedUnfinished") {
                try await store.save(Self.seedUnfinished(kind, now: now()))
            }
            #endif
            if let trip = try await recorder.resumeIfNeeded() {
                lastTimestamp = trip.points.last?.timestamp
                startedAt = trip.createdAt
                beginCapture()
                recoveryEndDate = trip.points.last?.timestamp
                switch analyzer.unfinishedTripAction(points: trip.points, now: now()) {
                case .none: break
                case .forgotToEnd(let start, let duration):
                    if let stop = analyzer.unfinishedStop(points: trip.points, now: now()) {
                        recovery = .forgotToEnd(stop: stop, stopStart: start, duration: duration)
                    }
                case .interrupted(let start, let end):
                    recovery = .interrupted(gapStart: start, gapEnd: end)
                }
            }
            // Retry trips whose processing failed earlier or was interrupted. Raw points are kept until it works.
            await processing.processPending()
            try await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    #if DEBUG
    private static func seedUnfinished(_ kind: String, now: Date) -> Trip {
        func point(_ lon: Double, _ t: Date) -> TrackPoint {
            TrackPoint(latitude: 40.76, longitude: lon, timestamp: t, horizontalAccuracy: 5)
        }
        let forgot = kind == "forgot"
        let last = forgot ? now.addingTimeInterval(-9 * 3600) : now.addingTimeInterval(-60)
        let points = [point(-111.90, last.addingTimeInterval(-400)),
                      point(-111.89, last.addingTimeInterval(-200)),
                      point(forgot ? -111.889 : -111.80, last)]
        return Trip(createdAt: points[0].timestamp, status: .recording, points: points)
    }
    #endif

    func start() async {
        guard !isRecording, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        switch await locationAccess.request() {
        case .blocked, .unknown: permissionAlert = .locationOff; return
        case .approximate: permissionAlert = .preciseOff; return
        case .precise: break
        }
        await startAuthorized()
    }

    func startAnyway() async {
        guard !isRecording, !isBusy else { return }
        // Recheck after returning from Settings, or if permission changed while the alert was open.
        locationAccess.refresh()
        guard locationAccess.state == .precise || locationAccess.state == .approximate else { permissionAlert = .locationOff; return }
        isBusy = true
        defer { isBusy = false }
        await startAuthorized()
    }

    private func startAuthorized() async {
        do {
            let trip = try await recorder.start()
            startedAt = trip.createdAt
            lastTimestamp = nil
            replayFinished = false
            beginCapture()
            startFeedback += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func end() async {
        guard isRecording, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        endFeedback += 1
        do {
            try await finishCapture()
            try await timedFlush()
            let endedAt = AppEnvironment.isReplay ? (lastTimestamp ?? now()) : now()
            let trip = try await recorder.end(at: endedAt)
            await processing.process(trip)
            try await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// S5 "End at the stop": cut the trip at the start of the long stop.
    func endAtRecoveryStop() async {
        guard case .forgotToEnd(let stop, _, _)? = recovery else { return }
        recovery = nil
        do {
            try await finishCapture()
            try await timedFlush()
            let trip = try await recorder.endAtStop(stop)
            await processing.process(trip)
            try await reload()
            openTripID = trip.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// S6 "End trip here": end at the last recorded point. The trip keeps its gap and is stored as partial.
    func endInterruptedTrip() async {
        guard case .interrupted? = recovery else { return }
        recovery = nil
        do {
            try await finishCapture()
            try await timedFlush()
            let trip = try await recorder.end(at: recoveryEndDate ?? lastTimestamp ?? now())
            await processing.process(trip)
            try await reload()
            openTripID = trip.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Deletes a finished trip and refreshes the list.
    func deleteTrip(id: UUID) async {
        do {
            try await store.delete(id: id)
            try await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// TEMPORARY test tool: stores a made-up drive between two cities as a processed trip that
    /// counts like a recorded one. Remove with `TestTripView` and the core `TestRoute`.
    func addTestTrip(from fromName: String, to toName: String) async -> Result<UUID, TestTripError> {
        let end = now()
        let seed = (fromName + ">" + toName).lowercased().unicodeScalars
            .reduce(UInt64(0)) { ($0 &* 31) &+ UInt64($1.value) }
        let built = await Task.detached(priority: .userInitiated) { () -> Result<[TrackPoint], TestTripError> in
            guard let namer = try? AreaNamer.bundled() else { return .failure(.failed) }
            guard let a = namer.place(named: fromName) else { return .failure(.unknownPlace(fromName)) }
            guard let b = namer.place(named: toName) else { return .failure(.unknownPlace(toName)) }
            let points = TestRoute.points(from: a.coordinate, to: b.coordinate, endingAt: end, seed: seed)
            return points.isEmpty ? .failure(.samePlace) : .success(points)
        }.value
        switch built {
        case .failure(let error):
            return .failure(error)
        case .success(let points):
            let trip = Trip(createdAt: points[0].timestamp, status: .completed, points: points, endedAt: end)
            do {
                try await store.save(trip)
                guard await processing.process(trip) else {
                    try? await store.delete(id: trip.id)
                    return .failure(.failed)
                }
                try await reload()
                return .success(trip.id)
            } catch {
                return .failure(.failed)
            }
        }
    }

    private func beginCapture() {
        let source = makeSource()
        self.source = source
        let fixPolicy = LocationFixPolicy(sessionStartedAt: now())
        gpsUnavailableSince = fixPolicy.sessionStartedAt
        if let live = source as? CoreLocationSource {
            live.setSignalHandler { [weak self] available in
                Task { @MainActor in
                    guard let self, self.isRecording else { return }
                    if available { self.gpsUnavailableSince = nil }
                    else if self.gpsUnavailableSince == nil { self.gpsUnavailableSince = self.now() }
                }
            }
        }
        isRecording = true
        let stream = source.points()
        consumer = Task { [recorder] in
            for await point in stream {
                lastTimestamp = point.timestamp
                if fixPolicy.accepts(timestamp: point.timestamp, horizontalAccuracy: point.horizontalAccuracy),
                   fixPolicy.isRecent(timestamp: point.timestamp, receivedAt: now()) {
                    gpsUnavailableSince = nil
                }
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
            .sorted { ($0.startedAt ?? $0.createdAt) > ($1.startedAt ?? $1.createdAt) }
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
