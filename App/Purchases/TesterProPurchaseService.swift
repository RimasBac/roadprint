import Foundation
import StoreKit
import RoadPrintCore

/// TestFlight testers get Pro without the paywall (board, ROA-124, 2026-11-24).
///
/// Two conditions, both required:
/// 1. The build was made with `RP_TESTER_PRO=YES` (the `testflight` workflow's `tester_pro` input;
///    tag releases always build with NO). Info.plist key `RPTesterPro`.
/// 2. The app runs in Apple's sandbox, which is TestFlight (and App Review). An App Store install
///    is `.production`, so even a flagged binary never unlocks Pro for paying customers.
///
/// App Review also runs in the sandbox, so the build submitted for review must be made with
/// `tester_pro` off: reviewers have to see and test the paywall.
struct TesterProPurchaseService: PurchaseService {
    let store: any PurchaseService

    static var isEnabledInBuild: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "RPTesterPro") as? String)?.uppercased() == "YES"
    }

    /// True when Apple signed this install for the sandbox (TestFlight).
    static func isSandbox() async -> Bool {
        guard let result = try? await AppTransaction.shared, case .verified(let transaction) = result else { return false }
        return transaction.environment == .sandbox
    }

    var manageSubscriptionsURL: URL? { store.manageSubscriptionsURL }

    func currentEntitlement() async -> Entitlement {
        if await Self.isSandbox() { return .pro }
        return await store.currentEntitlement()
    }

    func entitlementUpdates() -> AsyncStream<Entitlement> {
        let store = self.store
        return AsyncStream { continuation in
            let task = Task {
                let tester = await Self.isSandbox()
                for await update in store.entitlementUpdates() {
                    continuation.yield(tester ? .pro : update)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func offers() async throws -> [PurchaseOffer] { try await store.offers() }

    func purchase(_ offer: PurchaseOffer) async throws -> Entitlement? {
        let result = try await store.purchase(offer)
        if await Self.isSandbox() { return .pro }
        return result
    }

    func restore() async throws -> Entitlement {
        if await Self.isSandbox() { return .pro }
        return try await store.restore()
    }
}
