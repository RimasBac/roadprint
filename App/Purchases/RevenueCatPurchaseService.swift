import Foundation
import RevenueCat
import RoadPrintCore

/// RevenueCat, used anonymously: no account, no user id of ours (plan §6, §8).
final class RevenueCatPurchaseService: PurchaseService, @unchecked Sendable {
    private let lock = NSLock()
    private var packages: [String: Package] = [:]

    init(apiKey: String) {
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: apiKey)
    }

    var manageSubscriptionsURL: URL? { PurchaseProducts.manageSubscriptionsURL }

    private static func entitlement(_ info: CustomerInfo) -> Entitlement {
        info.entitlements[PurchaseProducts.entitlementID]?.isActive == true ? .pro : .free
    }

    func currentEntitlement() async -> Entitlement {
        guard let info = try? await Purchases.shared.customerInfo() else { return .free }
        return Self.entitlement(info)
    }

    func entitlementUpdates() -> AsyncStream<Entitlement> {
        AsyncStream { continuation in
            let task = Task {
                for await info in Purchases.shared.customerInfoStream {
                    continuation.yield(Self.entitlement(info))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func offers() async throws -> [PurchaseOffer] {
        let offerings = try await Purchases.shared.offerings()
        let available = offerings.current?.availablePackages ?? []
        var result: [PurchaseOffer] = []
        var byID: [String: Package] = [:]
        for package in available {
            let period: PurchaseOffer.Period
            switch package.packageType {
            case .annual: period = .yearly
            case .monthly: period = .monthly
            default: continue
            }
            let product = package.storeProduct
            let trial = product.introductoryDiscount?.paymentMode == .freeTrial
            result.append(PurchaseOffer(id: package.identifier, period: period,
                                        priceString: product.localizedPriceString, hasFreeTrial: trial))
            byID[package.identifier] = package
        }
        lock.withLock { packages = byID }
        return result
    }

    func purchase(_ offer: PurchaseOffer) async throws -> Entitlement? {
        let package = lock.withLock { packages[offer.id] }
        guard let package else { return nil }
        let result = try await Purchases.shared.purchase(package: package)
        if result.userCancelled { return nil }
        return Self.entitlement(result.customerInfo)
    }

    func restore() async throws -> Entitlement {
        Self.entitlement(try await Purchases.shared.restorePurchases())
    }
}
