#if DEBUG
import SwiftUI

/// Applies `-RPDebugTheme night|day` to a debug screen; follows the system when absent.
/// Lives in App/Design because it is the one place allowed to force a colour scheme.
extension View {
    func rpDebugAppearance() -> some View {
        let scheme: ColorScheme? = switch UserDefaults.standard.string(forKey: "RPDebugTheme") {
        case "night": .dark
        case "day": .light
        default: nil
        }
        return preferredColorScheme(scheme)
    }
}
#endif
