import SwiftUI
import RoadPrintCore

struct HomeView: View {
    @Environment(\.appEnvironment) private var environment
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var model: RecordingModel?
    @State private var showLoading = false

    var body: some View {
        Group {
            if let model {
                content(model)
            } else if showLoading {
                ProgressView("Loading trips…")
                    .font(RPType.body)
                    .accessibilityIdentifier("homeLoading")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.clear
            }
        }
        .task {
            let model = model ?? RecordingModel(environment: environment)
            let loading = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                if !Task.isCancelled { showLoading = true }
            }
            await model.bootstrap()
            loading.cancel()
            showLoading = false
            self.model = model
        }
    }

    @ViewBuilder
    private func content(_ model: RecordingModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RPSpace.xxl) {
                Text("Drive").font(RPType.screenTitle)
                if model.isRecording {
                    recording(model)
                } else {
                    idle(model)
                }
                #if DEBUG
                if AppEnvironment.isReplay, model.replayFinished {
                    Text("Replay finished")
                        .font(RPType.axis)
                        .foregroundStyle(Color.RP.textSecondary)
                        .accessibilityIdentifier("replayFinished")
                }
                if AppEnvironment.isReplay, let ms = model.lastFlushMilliseconds {
                    Text(String(format: "flush %.1f ms, worst append %.1f ms", ms, model.worstAppendMilliseconds))
                        .font(RPType.axis)
                        .accessibilityIdentifier("flushTiming")
                }
                #endif
            }
            .padding(RPSpace.screenMargin)
            .padding(.bottom, RPSpace.s)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: model.startFeedback)
        .sensoryFeedback(.impact(weight: .medium), trigger: model.endFeedback)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.locationAccess.refresh() }
        }
        .alert(LocalizedStringKey(model.permissionAlert == .locationOff ? "Location is off for RoadPrint" : "Precise location is off"),
               isPresented: Binding(
                get: { model.permissionAlert != nil },
                set: { if !$0 { model.permissionAlert = nil } }
               ), presenting: model.permissionAlert) { alert in
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            if alert == .locationOff {
                Button("Not now", role: .cancel) {}
            } else {
                Button("Start anyway") { Task { await model.startAnyway() } }
            }
        } message: { alert in
            if alert == .locationOff {
                Text("Allow location in Settings to record your next trip.")
            } else {
                Text("Turn on Precise Location for a more accurate route, or start with approximate location.")
            }
        }
        .alert("End it at the stop?", isPresented: Binding(
            get: { model.pendingStop != nil },
            set: { if !$0 { model.pendingStop = nil } }
        )) {
            Button("End at the stop") { Task { await model.endAtPendingStop() } }
            Button("Keep recording", role: .cancel) {}
        } message: {
            Text("This trip has been parked for hours. End it where you stopped?")
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private func recording(_ model: RecordingModel) -> some View {
        VStack(alignment: .leading, spacing: RPSpace.xl) {
            Text("Recording · tap End when parked.")
                .font(RPType.body)
                .accessibilityIdentifier("recordingLabel")
            if let start = model.startedAt {
                Text(timerInterval: start...Date.distantFuture, countsDown: false)
                    .font(RPType.statNumber)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityLabel(Text("Elapsed time"))
                    .accessibilityIdentifier("elapsedTime")
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if model.locationAccess.state == .blocked {
                    Text("Location is off. Your trip is still open. Enable location in Settings when parked.")
                        .font(RPType.statLabel)
                        .foregroundStyle(Color.RP.textSecondary)
                } else if model.waitingForGPS(at: context.date) {
                    Text("Waiting for GPS. Recording will continue when a signal is available.")
                        .font(RPType.statLabel)
                        .foregroundStyle(Color.RP.textSecondary)
                        .accessibilityIdentifier("waitingForGPS")
                }
            }
            Button {
                Task { await model.end() }
            } label: {
                Text("End Trip")
            }
            .buttonStyle(.rpPrimary)
            .disabled(model.isBusy)
            .accessibilityIdentifier("endTrip")
        }
    }

    private func idle(_ model: RecordingModel) -> some View {
        VStack(alignment: .leading, spacing: RPSpace.xl) {
            Button {
                Task { await model.start() }
            } label: {
                Text("Start Trip")
            }
            .buttonStyle(.rpPrimary)
            .disabled(model.isBusy)
            .accessibilityIdentifier("startTrip")
            if model.locationAccess.state == .blocked {
                Text("Location is off. Allow location in Settings to record a trip.")
                    .font(RPType.body)
                    .foregroundStyle(Color.RP.textSecondary)
            } else {
                Text("GPS connects after you start.")
                    .font(RPType.statLabel)
                    .foregroundStyle(Color.RP.textSecondary)
            }
            if let last = model.rows.first {
                VStack(alignment: .leading, spacing: RPSpace.m) {
                    Text("Last trip").font(RPType.subtitle)
                    TripListView(rows: [last], unit: environment.profile.distanceUnit)
                }
            } else {
                Text("No trips yet. Tap Start Trip before you roll.")
                    .font(RPType.body)
                    .foregroundStyle(Color.RP.textSecondary)
                    .accessibilityIdentifier("homeEmpty")
            }
            Text("Career · \(TripFormatting.distance(meters: environment.profile.startingCareerDistanceMeters + model.rows.reduce(0) { $0 + $1.distanceMeters }, unit: environment.profile.distanceUnit))")
                .font(RPType.body)
                .monospacedDigit()
                .contentTransition(.numericText())
                .accessibilityIdentifier("careerLine")
        }
    }
}

struct TripListView: View {
    let rows: [TripRowData]
    let unit: DistanceUnit

    var body: some View {
        LazyVStack(alignment: .leading, spacing: RPSpace.m) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: RPSpace.xs) {
                    HStack {
                        Text(row.date, format: .dateTime.year().month().day().hour().minute())
                            .font(RPType.statLabel)
                            .foregroundStyle(Color.RP.textSecondary)
                        Spacer()
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: RPSpace.l) { stats(row) }
                        VStack(alignment: .leading, spacing: RPSpace.s) { stats(row) }
                    }
                    if let places = row.placesLine {
                        Text(places)
                            .font(RPType.statLabel)
                            .foregroundStyle(Color.RP.textSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("tripRow")
            }
        }
    }

    @ViewBuilder
    private func stats(_ row: TripRowData) -> some View {
        Text(TripFormatting.distance(meters: row.distanceMeters, unit: unit))
            .font(RPType.statNumber).monospacedDigit().contentTransition(.numericText())
        Text(TripFormatting.duration(seconds: row.movingTimeSeconds))
            .font(RPType.statNumber).monospacedDigit().contentTransition(.numericText())
    }
}

#Preview {
    HomeView()
}
