import SwiftUI
import RoadPrintCore

struct HomeView: View {
    @Environment(\.appEnvironment) private var environment
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
        VStack(spacing: RPSpace.xl) {
            Text("RoadPrint").font(RPType.screenTitle)
            if model.isRecording {
                recording(model)
            } else {
                idle(model)
            }
            #if DEBUG
            if model.replayFinished {
                Text("Replay finished")
                    .font(RPType.axis)
                    .foregroundStyle(Color.RP.textSecondary)
                    .accessibilityIdentifier("replayFinished")
            }
            if let ms = model.lastFlushMilliseconds {
                Text(String(format: "flush %.1f ms, worst append %.1f ms", ms, model.worstAppendMilliseconds))
                    .font(RPType.axis)
                    .foregroundStyle(Color.RP.textSecondary)
                    .accessibilityIdentifier("flushTiming")
            }
            #endif
        }
        .padding(RPSpace.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
        VStack(spacing: RPSpace.xl) {
            Text("Recording · tap End when parked.")
                .font(RPType.body)
                .accessibilityIdentifier("recordingLabel")
            Button {
                Task { await model.end() }
            } label: {
                Text("End Trip")
            }
            .buttonStyle(.rpPrimary)
            .accessibilityIdentifier("endTrip")
        }
    }

    private func idle(_ model: RecordingModel) -> some View {
        VStack(spacing: RPSpace.xl) {
            Button {
                Task { await model.start() }
            } label: {
                Text("Start Trip")
            }
            .buttonStyle(.rpPrimary)
            .accessibilityIdentifier("startTrip")
            if model.rows.isEmpty {
                Text("No trips yet. Tap Start Trip before you roll.")
                    .font(RPType.body)
                    .foregroundStyle(Color.RP.textSecondary)
                    .accessibilityIdentifier("homeEmpty")
            }
            TripListView(rows: model.rows, unit: environment.profile.distanceUnit)
        }
    }
}

struct TripListView: View {
    let rows: [TripRowData]
    let unit: DistanceUnit

    var body: some View {
        ScrollView {
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
                                .lineLimit(2)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("tripRow")
                }
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
