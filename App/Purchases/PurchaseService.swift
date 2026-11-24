import Foundation
import Observation
import RoadPrintCore

/// One thing the driver can buy. Prices come from the store as localized text: never hard-coded.
struct PurchaseOffer: Identifiable, Equatable, Sendable {
    enum Period: Sendable { case yearly, monthly }

    let id: String
    let period: Period
    /// "$39.99", localized by the store.
    let priceString: String
    let hasFreeTrial: Bool
}

enum PurchaseProducts {
    /// The two auto-renewing subscriptions in one group (plan §8). Also in `RoadPrint.storekit`.
    static let yearlyID = "com.rimasbac.roadprint.pro.yearly"
    static let monthlyID = "com.rimasbac.roadprint.pro.monthly"
    /// The RevenueCat entitlement (AGENTS.md §7.4). Feature code never checks products.
    static let entitlementID = "pro"
    static let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")
    /// Apple's standard EULA, until the board writes custom terms (plan §11).
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
    static let privacyURL = URL(string: "https://rimasbac.github.io/roadprint/privacy.html")
}

/// Everything the app knows about purchases. Feature code talks to this and to `ProStore`,
/// never to StoreKit or RevenueCat.
protocol PurchaseService: Sendable {
    var manageSubscriptionsURL: URL? { get }
    func currentEntitlement() async -> Entitlement
    /// Emits whenever the entitlement may have changed (renewal, expiry, a purchase on another device).
    func entitlementUpdates() -> AsyncStream<Entitlement>
    func offers() async throws -> [PurchaseOffer]
    /// The new entitlement, or nil when the driver cancelled.
    func purchase(_ offer: PurchaseOffer) async throws -> Entitlement?
    func restore() async throws -> Entitlement
}

/// No store: everyone is `free` and nothing can be bought. Used when no RevenueCat key is set
/// and the store configuration has no products.
struct OfflinePurchaseService: PurchaseService {
    var fixed: Entitlement = .free
    var manageSubscriptionsURL: URL? { PurchaseProducts.manageSubscriptionsURL }
    func currentEntitlement() async -> Entitlement { fixed }
    func entitlementUpdates() -> AsyncStream<Entitlement> { AsyncStream { $0.finish() } }
    func offers() async throws -> [PurchaseOffer] { [] }
    func purchase(_ offer: PurchaseOffer) async throws -> Entitlement? { fixed }
    func restore() async throws -> Entitlement { fixed }
}

#if DEBUG
/// UI tests (`-RPFakeStore YES`): the two `RoadPrint.storekit` offers at their test prices.
/// `xcodebuild test` doesn't apply the scheme's StoreKit configuration (XcodeGen writes it only
/// on the Run action), so the UI tests use this instead. A purchase persists across launches like
/// a StoreKit test session; a new launch starts `free` until Restore finds it.
struct FakePurchaseService: PurchaseService {
    private static let purchasedKey = "RPFakeStorePurchased"
    var manageSubscriptionsURL: URL? { PurchaseProducts.manageSubscriptionsURL }
    func currentEntitlement() async -> Entitlement { .free }
    func entitlementUpdates() -> AsyncStream<Entitlement> { AsyncStream { $0.finish() } }
    func offers() async throws -> [PurchaseOffer] {
        [PurchaseOffer(id: PurchaseProducts.yearlyID, period: .yearly, priceString: "$39.99", hasFreeTrial: true),
         PurchaseOffer(id: PurchaseProducts.monthlyID, period: .monthly, priceString: "$4.99", hasFreeTrial: false)]
    }
    func purchase(_ offer: PurchaseOffer) async throws -> Entitlement? {
        UserDefaults.standard.set(true, forKey: Self.purchasedKey)
        return .pro
    }
    func restore() async throws -> Entitlement {
        UserDefaults.standard.bool(forKey: Self.purchasedKey) ? .pro : .free
    }
}
#endif

/// The entitlement and the offers, observed by the views. Created once by `AppEnvironment`.
@Observable
final class ProStore: @unchecked Sendable {
    private(set) var entitlement: Entitlement = .free
    private(set) var offers: [PurchaseOffer] = []
    private(set) var isWorking = false
    private(set) var offersFailed = false
    var errorMessage: String?
    let service: any PurchaseService

    init(service: any PurchaseService) {
        self.service = service
    }

    var isPro: Bool { entitlement == .pro }
    var manageSubscriptionsURL: URL? { service.manageSubscriptionsURL }

    /// Reads the entitlement and then follows its changes for the life of the app.
    @MainActor
    func start() async {
        entitlement = await service.currentEntitlement()
        for await update in service.entitlementUpdates() {
            entitlement = update
        }
    }

    @MainActor
    func loadOffers() async {
        offersFailed = false
        do {
            offers = try await service.offers()
            offersFailed = offers.isEmpty
        } catch {
            offersFailed = true
        }
    }

    /// True when the purchase made the driver Pro.
    @MainActor
    @discardableResult
    func purchase(_ offer: PurchaseOffer) async -> Bool {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            if let result = try await service.purchase(offer) { entitlement = result }
        } catch {
            errorMessage = error.localizedDescription
        }
        return isPro
    }

    /// True when the restore found Pro.
    @MainActor
    @discardableResult
    func restore() async -> Bool {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            entitlement = try await service.restore()
            if !isPro {
                errorMessage = String(localized: "No purchases to restore on this Apple Account.",
                                      comment: "Shown after Restore purchases finds nothing.")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        return isPro
    }

    /// The service for this build: RevenueCat when the key is set, else the local StoreKit service
    /// (which sees only the `RoadPrint.storekit` products in tests and sells nothing in a release).
    static func live() -> ProStore {
        #if DEBUG
        if let forced = UserDefaults.standard.string(forKey: "RPEntitlement") {
            return ProStore(service: OfflinePurchaseService(fixed: forced == "pro" ? .pro : .free))
        }
        if UserDefaults.standard.bool(forKey: "RPFakeStore") {
            return ProStore(service: FakePurchaseService())
        }
        #endif
        let key = (Bundle.main.object(forInfoDictionaryKey: "RevenueCatPublicKey") as? String) ?? ""
        let store: any PurchaseService = key.isEmpty || key.hasPrefix("$(")
            ? StoreKitPurchaseService() : RevenueCatPurchaseService(apiKey: key)
        if TesterProPurchaseService.isEnabledInBuild {
            return ProStore(service: TesterProPurchaseService(store: store))
        }
        return ProStore(service: store)
    }
}

extension PaywallTrigger: Identifiable {
    public var id: Self { self }
}
