import SwiftUI
import RoadPrintCore

/// The Pro paywall (plan §8, SCREENS.md): the art first, a few benefits, Yearly preselected, then
/// the buy button, Restore, Terms and Privacy, and the renewal line Apple requires. Always night.
struct PaywallSheet: View {
    let trigger: PaywallTrigger
    /// The trips drawn as the art. Loaded from the store when nil.
    var artTrips: [HeatTrip]?

    @Environment(\.appEnvironment) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var selected: PurchaseOffer.Period = .yearly
    @State private var loadedTrips: [HeatTrip] = []

    private var pro: ProStore { environment.pro }
    private var art: [HeatTrip] { artTrips ?? loadedTrips }

    private var yearly: PurchaseOffer? { pro.offers.first { $0.period == .yearly } }
    private var monthly: PurchaseOffer? { pro.offers.first { $0.period == .monthly } }
    private var chosen: PurchaseOffer? { selected == .yearly ? (yearly ?? monthly) : (monthly ?? yearly) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RPSpace.l) {
                header
                benefits
                if pro.offers.isEmpty {
                    unavailable
                } else {
                    plans
                    buyButton
                }
                if let message = pro.errorMessage {
                    Text(message)
                        .font(RPType.statLabel)
                        .foregroundStyle(Color.RP.textSecondary)
                        .accessibilityIdentifier("paywallError")
                }
                footer
            }
            .padding(.horizontal, RPSpace.screenMargin)
            .padding(.bottom, RPSpace.xl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color.RP.background.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(RPType.body.weight(.semibold))
                    .foregroundStyle(Color.RP.text)
                    .frame(width: RPSize.minTouch, height: RPSize.minTouch)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(RPSpace.m)
            .accessibilityLabel(Text("Close"))
            .accessibilityIdentifier("paywallClose")
        }
        .rpNight()
        .accessibilityIdentifier("paywall")
        .task { await pro.loadOffers() }
        .task {
            guard artTrips == nil else { return }
            let stored = (try? await environment.tripStore.allTrips()) ?? []
            loadedTrips = stored.compactMap { HeatTrip($0) }
        }
        .onChange(of: pro.isPro) { _, isPro in
            if isPro { dismiss() }
        }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: RPSpace.m) {
            Group {
                if art.isEmpty {
                    ZStack {
                        Color.RP.card
                        Image(systemName: "map.fill")
                            .font(RPType.screenTitle).imageScale(.large)
                            .foregroundStyle(Color.RP.accentText)
                    }
                } else {
                    HeatMapView(trips: art)
                }
            }
            .frame(height: 240)
            .clipped()
            .padding(.horizontal, -RPSpace.screenMargin)
            .accessibilityHidden(true)
            Text("RoadPrint Pro").font(RPType.screenTitle)
            Text("Every road you've driven, on one map.")
                .font(RPType.subtitle)
                .foregroundStyle(Color.RP.textSecondary)
        }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: RPSpace.s) {
            benefit("map", "Your map, all time. Free shows the last 30 days.")
            benefit("line.3.horizontal.decrease.circle", "Filter by year, place and road.")
            benefit("rectangle.stack", "Every trip card style.")
            benefit("seal", "No watermark on your cards.")
        }
    }

    private func benefit(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: RPSpace.m) {
            Image(systemName: symbol)
                .foregroundStyle(Color.RP.accentText)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text).font(RPType.body)
        }
    }

    private var plans: some View {
        VStack(spacing: RPSpace.s) {
            if let yearly {
                planRow(yearly, title: "Yearly", detail: yearly.hasFreeTrial ? "7-day free trial" : nil,
                        badge: "Best value", identifier: "paywallYearly")
            }
            if let monthly {
                planRow(monthly, title: "Monthly", detail: nil, badge: nil, identifier: "paywallMonthly")
            }
        }
    }

    private func planRow(_ offer: PurchaseOffer, title: LocalizedStringKey, detail: LocalizedStringKey?,
                         badge: LocalizedStringKey?, identifier: String) -> some View {
        let isSelected = chosen?.id == offer.id
        return Button {
            selected = offer.period
        } label: {
            HStack(spacing: RPSpace.m) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.RP.accentText : Color.RP.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: RPSpace.s) {
                        Text(title).font(RPType.body.weight(.semibold))
                        if let badge {
                            Text(badge)
                                .font(RPType.statLabel.weight(.semibold))
                                .foregroundStyle(Color.RP.buttonPrimaryLabel)
                                .padding(.horizontal, RPSpace.s)
                                .padding(.vertical, 2)
                                .background(Color.RP.buttonPrimary, in: Capsule())
                        }
                    }
                    if let detail {
                        Text(detail).font(RPType.statLabel).foregroundStyle(Color.RP.textSecondary)
                    }
                }
                Spacer(minLength: RPSpace.s)
                Text(verbatim: "\(offer.priceString) / \(offer.period == .yearly ? String(localized: "year") : String(localized: "month"))")
                    .font(RPType.body)
            }
            .padding(RPSpace.l)
            .frame(minHeight: RPSize.minTouch)
            .background(Color.RP.card, in: RoundedRectangle(cornerRadius: RPRadius.card))
            .overlay(RoundedRectangle(cornerRadius: RPRadius.card)
                .strokeBorder(isSelected ? Color.RP.accentText : Color.RP.border, lineWidth: isSelected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    private var buyButton: some View {
        Button {
            guard let chosen else { return }
            Task { await pro.purchase(chosen) }
        } label: {
            if pro.isWorking {
                ProgressView()
            } else if chosen?.hasFreeTrial == true {
                Text("Start 7-day free trial")
            } else {
                Text("Continue")
            }
        }
        .buttonStyle(.rpPrimary)
        .disabled(pro.isWorking || chosen == nil)
        .accessibilityIdentifier("paywallBuy")
    }

    private var unavailable: some View {
        Text(pro.offersFailed
             ? "Pro isn't available right now. Check your connection and try again."
             : "Loading prices…")
            .font(RPType.body)
            .foregroundStyle(Color.RP.textSecondary)
            .accessibilityIdentifier("paywallUnavailable")
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: RPSpace.m) {
            Button("Restore purchases") { Task { await pro.restore() } }
                .font(RPType.body)
                .frame(minHeight: RPSize.minTouch)
                .accessibilityIdentifier("paywallRestore")
            Text("Payment is charged to your Apple Account at confirmation of purchase. The subscription renews automatically unless it is cancelled at least 24 hours before the end of the current period. Your account is charged for renewal within 24 hours before the end of the period. Manage or cancel any time in your Apple Account settings. Any free trial ends when you subscribe.")
                .font(RPType.statLabel)
                .foregroundStyle(Color.RP.textSecondary)
                .accessibilityIdentifier("paywallLegal")
            HStack(spacing: RPSpace.xl) {
                if let url = PurchaseProducts.termsURL { Link("Terms of Use", destination: url) }
                if let url = PurchaseProducts.privacyURL { Link("Privacy Policy", destination: url) }
            }
            .font(RPType.statLabel)
        }
    }
}
