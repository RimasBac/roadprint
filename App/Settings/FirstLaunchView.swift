import SwiftUI

struct FirstLaunchView: View {
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RPSpace.xl) {
                VStack(alignment: .leading, spacing: RPSpace.m) {
                    Image(decorative: "BrandMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: RPSize.buttonHeight)
                        .clipShape(RoundedRectangle(cornerRadius: RPRadius.button))
                    Text("RoadPrint")
                        .font(RPType.screenTitle)
                        .accessibilityIdentifier("firstLaunchTitle")
                    Text("Record your drives and build a map of the roads you’ve travelled.")
                        .font(RPType.body)
                        .foregroundStyle(Color.RP.textSecondary)
                }
                VStack(alignment: .leading, spacing: RPSpace.s) {
                    RPSectionTitle(title: "Before you drive")
                    Text("Start before rolling. End after parking. Never use your phone while driving.")
                        .font(RPType.body)
                }
                .padding(RPSpace.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .rpCard()

                Text("RoadPrint records your route only between Start Trip and End Trip. Your trips stay on this iPhone.")
                    .font(RPType.body)
                    .foregroundStyle(Color.RP.textSecondary)

                Button("Continue", action: onContinue)
                    .buttonStyle(.rpPrimary)
                    .accessibilityIdentifier("firstLaunchContinue")
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(RPSpace.screenMargin)
            .padding(.top, RPSpace.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
