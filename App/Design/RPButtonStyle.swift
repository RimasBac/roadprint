import SwiftUI

struct RPButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }
    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(RPButtonSurface(kind: kind, isPressed: configuration.isPressed))
    }
}

extension ButtonStyle where Self == RPButtonStyle {
    static var rpPrimary: RPButtonStyle { RPButtonStyle(kind: .primary) }
    static var rpSecondary: RPButtonStyle { RPButtonStyle(kind: .secondary) }
}

// The DEBUG gallery uses this same surface to hold the transient pressed state for a screenshot.
struct RPButtonSurface: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    let kind: RPButtonStyle.Kind
    let isPressed: Bool

    func body(content: Content) -> some View {
        content
            .font(RPType.button)
            .padding(.horizontal, RPSpace.l)
            .padding(.vertical, RPSpace.s)
            .frame(maxWidth: .infinity, minHeight: RPSize.buttonHeight)
            .foregroundStyle(kind == .primary ? Color.RP.buttonPrimaryLabel : Color.RP.text)
            .background(kind == .primary ? Color.RP.buttonPrimary : Color.RP.card,
                        in: RoundedRectangle(cornerRadius: RPRadius.button))
            .overlay {
                if kind == .secondary && RPTheme.draw(for: colorScheme).cardBorder {
                    RoundedRectangle(cornerRadius: RPRadius.button)
                        .strokeBorder(Color.RP.border, lineWidth: RPSize.hairline(displayScale: displayScale))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: RPRadius.button))
            .scaleEffect(isPressed && isEnabled && !reduceMotion ? RPButton.pressedScale : 1)
            .opacity(!isEnabled ? RPOpacity.disabled : isPressed ? RPButton.pressedOpacity : 1)
            .animation(RPMotion.fast, value: isPressed)
    }
}
