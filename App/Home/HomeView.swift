import SwiftUI
import RoadPrintCore

struct HomeView: View {
    @Environment(\.appEnvironment) private var environment
    @State private var model: RecordingModel?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                Color.clear
            }
        }
        .task {
            let model = model ?? RecordingModel(environment: environment)
            self.model = model
            await model.bootstrap()
        }
    }

    @ViewBuilder
    private func content(_ model: RecordingModel) -> some View {
        VStack(spacing: 24) {
            Text("RoadPrint").font(.largeTitle.bold())
            if model.isRecording {
                recording(model)
            } else {
                idle(model)
            }
            #if DEBUG
            if model.replayFinished {
                Text("Replay finished")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("replayFinished")
            }
            #endif
        }
        .padding()
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
        VStack(spacing: 24) {
            Text("Recording · tap End when parked.")
                .font(.headline)
                .accessibilityIdentifier("recordingLabel")
            Button {
                Task { await model.end() }
            } label: {
                Text("End Trip").font(.title2.bold()).frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .accessibilityIdentifier("endTrip")
        }
    }

    private func idle(_ model: RecordingModel) -> some View {
        VStack(spacing: 24) {
            Button {
                Task { await model.start() }
            } label: {
                Text("Start Trip").font(.title.bold()).frame(maxWidth: .infinity, minHeight: 88)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("startTrip")
            TripListView(rows: model.rows)
        }
    }
}

struct TripListView: View {
    let rows: [TripRowData]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(rows) { row in
                    HStack {
                        Text(row.date, format: .dateTime.year().month().day().hour().minute())
                        Spacer()
                        Text(TripFormatting.distance(meters: row.distanceMeters))
                        Text(TripFormatting.duration(seconds: row.movingTimeSeconds))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("tripRow")
                }
            }
        }
    }
}

#Preview {
    HomeView()
}
