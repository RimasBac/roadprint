import Foundation
import StoreKit
import RoadPrintCore

/// Used when the build has no RevenueCat key: StoreKit 2 against the products of the scheme's
/// `RoadPrint.storekit` (tests) or the App Store. With no products everyone is `free`. Feature
/// code still sees only `PurchaseService`.
final class StoreKitPurchaseService: PurchaseService, @unchecked Sendable {
    private let lock = NSLock()
    private var products: [String: Product] = [:]
    private let ids = [PurchaseProducts.yearlyID, PurchaseProducts.monthlyID]

    var manageSubscriptionsURL: URL? { PurchaseProducts.manageSubscriptionsURL }

    func currentEntitlement() async -> Entitlement {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, ids.contains(transaction.productID),
               transaction.revocationDate == nil {
                return .pro
            }
        }
        return .free
    }

    func entitlementUpdates() -> AsyncStream<Entitlement> {
        AsyncStream { continuation in
            let task = Task {
                for await result in Transaction.updates {
                    if case .verified(let transaction) = result { await transaction.finish() }
                    continuation.yield(await self.currentEntitlement())
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func offers() async throws -> [PurchaseOffer] {
        let loaded = try await Product.products(for: ids)
        var byID: [String: Product] = [:]
        var result: [PurchaseOffer] = []
        for product in loaded {
            byID[product.id] = product
            let trial = product.subscription?.introductoryOffer?.paymentMode == .freeTrial
            result.append(PurchaseOffer(id: product.id,
                                        period: product.id == PurchaseProducts.yearlyID ? .yearly : .monthly,
                                        priceString: product.displayPrice, hasFreeTrial: trial))
        }
        lock.lock()
        products = byID
        lock.unlock()
        return result
    }

    func purchase(_ offer: PurchaseOffer) async throws -> Entitlement? {
        lock.lock()
        let product = products[offer.id]
        lock.unlock()
        guard let product else { return nil }
        switch try await product.purchase() {
        case .success(let verification):
            if case .verified(let transaction) = verification {
                await transaction.finish()
                return .pro
            }
            return nil
        case .userCancelled, .pending:
            return nil
        @unknown default:
            return nil
        }
    }

    func restore() async throws -> Entitlement {
        try await AppStore.sync()
        return await currentEntitlement()
    }
}
