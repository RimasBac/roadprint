import SwiftUI

extension View {
    /// Forces the night theme for one screen, whatever the phone's setting (the paywall).
    func rpNight() -> some View { preferredColorScheme(.dark) }
}
