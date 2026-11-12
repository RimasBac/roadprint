import SwiftUI

/// The card surface from the feel standard (§2a): `card` fill, with a hairline border in the day theme.
struct RPCardSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        content
            .background(Color.RP.card, in: RoundedRectangle(cornerRadius: RPRadius.card))
            .overlay {
                if RPTheme.draw(for: colorScheme).cardBorder {
                    RoundedRectangle(cornerRadius: RPRadius.card)
                        .strokeBorder(Color.RP.border, lineWidth: RPSize.hairline(displayScale: displayScale))
                }
            }
    }
}

extension View {
    func rpCard() -> some View { modifier(RPCardSurface()) }
}

/// A small grey label above a bold value (DESIGN_PLAN §2a).
struct RPStat: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: RPSpace.xs) {
            Text(label)
                .font(RPType.statLabel)
                .foregroundStyle(Color.RP.textSecondary)
            Text(value)
                .font(RPType.statNumber)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
    }
}

/// The uppercase kicker above a card ("SETTINGS").
struct RPSectionTitle: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(RPType.cardTitle)
            .tracking(RPType.cardTitleTracking)
            .textCase(RPType.cardTitleCase)
            .foregroundStyle(Color.RP.textSecondary)
            .accessibilityAddTraits(.isHeader)
    }
}
