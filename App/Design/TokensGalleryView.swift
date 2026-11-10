#if DEBUG
import SwiftUI

struct TokensGalleryView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RPSpace.xl) {
                Text("Tokens").font(RPType.screenTitle).accessibilityIdentifier("tokensGallery")
                Text("Colours").font(RPType.cardTitle).textCase(RPType.cardTitleCase).tracking(RPType.cardTitleTracking)
                ForEach(swatches, id: \.0) { name, color in
                    HStack(spacing: RPSpace.m) {
                        RoundedRectangle(cornerRadius: RPRadius.button)
                            .fill(color)
                            .frame(width: RPSize.minTouch, height: RPSize.minTouch)
                            .overlay(RoundedRectangle(cornerRadius: RPRadius.button).strokeBorder(Color.RP.border))
                            .accessibilityHidden(true)
                        Text(verbatim: name).font(RPType.statLabel)
                    }
                }
                Text("Typography").font(RPType.cardTitle).textCase(RPType.cardTitleCase).tracking(RPType.cardTitleTracking)
                ForEach(RPType.samples, id: \.name) { style in
                    VStack(alignment: .leading, spacing: RPSpace.xs) {
                        Text(verbatim: "type.\(style.name)").font(RPType.axis).foregroundStyle(Color.RP.textSecondary)
                        Text("RoadPrint 0123456789")
                            .font(style.font).tracking(style.tracking).textCase(style.textCase)
                    }
                }
                Text("Buttons").font(RPType.cardTitle).textCase(RPType.cardTitleCase).tracking(RPType.cardTitleTracking)
                buttonExamples(.primary)
                buttonExamples(.secondary)
                Text("End of tokens").font(RPType.axis).accessibilityIdentifier("tokensGalleryEnd")
            }
            .padding(RPSpace.screenMargin)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Color.RP.text)
        .background(Color.RP.background)
    }

    private func buttonExamples(_ kind: RPButtonStyle.Kind) -> some View {
        VStack(spacing: RPSpace.s) {
            Text(kind == .primary ? LocalizedStringKey("Primary") : LocalizedStringKey("Secondary")).font(RPType.body)
            Button("Normal") {}.buttonStyle(RPButtonStyle(kind: kind))
            Text("Pressed").modifier(RPButtonSurface(kind: kind, isPressed: true))
            Button("Disabled") {}.buttonStyle(RPButtonStyle(kind: kind)).disabled(true)
        }
    }

    private var swatches: [(String, Color)] {
        [
            ("accentText", .RP.accentText), ("background", .RP.background), ("border", .RP.border),
            ("buttonPrimary", .RP.buttonPrimary), ("buttonPrimaryLabel", .RP.buttonPrimaryLabel),
            ("card", .RP.card), ("heat1", .RP.heat1), ("heat2", .RP.heat2), ("heat3", .RP.heat3),
            ("heat4", .RP.heat4), ("heat5", .RP.heat5), ("land", .RP.land), ("route", .RP.route),
            ("routeEdge", .RP.routeEdge), ("text", .RP.text), ("textSecondary", .RP.textSecondary)
        ]
    }
}

// Launch-only test controls live in Design, are absent from Release, and never persist appearance.
private struct RPDebugAppearance: ViewModifier {
    func body(content: Content) -> some View {
        let defaults = UserDefaults.standard
        let theme: ColorScheme? = switch defaults.string(forKey: "RPDebugTheme") {
        case "night": .dark
        case "day": .light
        default: nil
        }
        if defaults.bool(forKey: "RPDebugAX3") {
            content.preferredColorScheme(theme).dynamicTypeSize(.accessibility3)
        } else {
            content.preferredColorScheme(theme)
        }
    }
}

extension View {
    func rpDebugAppearance() -> some View { modifier(RPDebugAppearance()) }
}
#endif
