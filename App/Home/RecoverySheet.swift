import SwiftUI

/// S5 "Forgot to end" and S6 "Recording was interrupted", shown over either tab at launch.
struct RecoverySheet: View {
    let recovery: RecordingModel.Recovery
    let model: RecordingModel

    var body: some View {
        VStack(alignment: .leading, spacing: RPSpace.xl) {
            Text(title)
                .font(RPType.screenTitle)
                .foregroundStyle(Color.RP.text)
                .accessibilityIdentifier("recoveryTitle")
            Text(message)
                .font(RPType.body)
                .foregroundStyle(Color.RP.textSecondary)
            Spacer(minLength: 0)
            Button(primaryTitle) { Task { await primary() } }
                .buttonStyle(.rpPrimary)
                .accessibilityIdentifier("recoveryPrimary")
            Button(secondaryTitle) { Task { await secondary() } }
                .buttonStyle(.rpSecondary)
                .accessibilityIdentifier("recoverySecondary")
        }
        .padding(RPSpace.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.RP.background)
    }

    private var title: String {
        switch recovery {
        case .forgotToEnd: String(localized: "Forgot to end?")
        case .interrupted: String(localized: "Recording was interrupted")
        }
    }

    private var message: String {
        switch recovery {
        case .forgotToEnd(_, _, let duration):
            let hours = TripFormatting.duration(seconds: duration)
            return String(localized: "This trip includes a \(hours) stop. End it there?")
        case .interrupted:
            return String(localized: "This trip was only partly recorded: iOS stopped the app while you were driving. Continue it, or end it here. The gap will be drawn dotted.")
        }
    }

    private var primaryTitle: String {
        switch recovery {
        case .forgotToEnd: String(localized: "End at the stop")
        case .interrupted: String(localized: "Continue trip")
        }
    }

    private var secondaryTitle: String {
        switch recovery {
        case .forgotToEnd: String(localized: "Keep recording")
        case .interrupted: String(localized: "End trip here")
        }
    }

    private func secondary() async {
        switch recovery {
        case .forgotToEnd: model.recovery = nil
        case .interrupted: await model.endInterruptedTrip()
        }
    }

    private func primary() async {
        switch recovery {
        case .forgotToEnd: await model.endAtRecoveryStop()
        case .interrupted: model.recovery = nil
        }
    }
}
