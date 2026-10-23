import AppKit
import Observation
import PerMyLastCore
import StoreKit

/// Buying, restoring and checking out (FR-P1 to P4, FR-A15, FR-A18). The Mac App Store build sells with StoreKit 2;
/// the direct build opens a Lemon Squeezy checkout. Either way the backend grants the plan, never the app.
@MainActor
@Observable
final class PurchaseService {
    static let shared = PurchaseService()

    private(set) var products: [PaywallProduct: Product] = [:]
    /// Days of free trial each subscription offers this Apple ID (set up as an introductory offer in App Store Connect).
    private(set) var freeTrialDaysByProduct: [PaywallProduct: Int] = [:]
    var message: String?
    var messageIsError = false
    var isBusy = false
    private var updatesTask: Task<Void, Never>?

    private init() {}

    var channel: AppConfig.Channel { AppConfig.channel }

    /// Whether this product can be bought right now in this build.
    func isAvailable(_ product: PaywallProduct) -> Bool {
        guard AppConfig.paymentsLive else { return false }
        switch channel {
        case .appStore: return products[product] != nil
        case .direct: return !(AppConfig.checkoutLinks[product] ?? "").isEmpty
        }
    }

    /// The store's own price string (App Store build); nil in the direct build, where the checkout page shows it.
    func price(_ product: PaywallProduct) -> String? { products[product]?.displayPrice }

    /// The free trial this person can still get on a product, if any. Apple allows a trial once per subscription group.
    func freeTrialDays(_ product: PaywallProduct) -> Int? { freeTrialDaysByProduct[product] }

    // MARK: StoreKit

    func loadProducts() async {
        guard channel == .appStore else { return }
        do {
            let found = try await Product.products(for: PaywallProduct.allCases.map(\.storeKitID))
            products = Dictionary(uniqueKeysWithValues: found.compactMap { p in PaywallProduct(storeKitID: p.id).map { ($0, p) } })
            var trials: [PaywallProduct: Int] = [:]
            for (kind, product) in products {
                guard let sub = product.subscription, let offer = sub.introductoryOffer, offer.paymentMode == .freeTrial,
                      await sub.isEligibleForIntroOffer else { continue }
                let unitDays: Int
                switch offer.period.unit {
                case .day: unitDays = 1
                case .week: unitDays = 7
                case .month: unitDays = 30
                case .year: unitDays = 365
                @unknown default: unitDays = 1
                }
                trials[kind] = offer.period.value * unitDays
            }
            freeTrialDaysByProduct = trials
        } catch {
            show(L("Couldn't load the store: \(error.localizedDescription)"), error: true)
        }
    }

    /// Handles purchases that finish outside the paywall: renewals, Ask to Buy approvals, other devices.
    func startListening() {
        guard channel == .appStore, updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates { await self?.handle(update) }
        }
    }

    func buy(_ product: PaywallProduct) async {
        let account = AccountModel.shared
        guard let userID = account.session?.userID else { show(L("Sign in first, then choose a plan."), error: true); return }
        guard AppConfig.paymentsLive else { show(L("Plans aren't open yet."), error: true); return }

        switch channel {
        case .direct:
            guard let base = AppConfig.checkoutLinks[product].flatMap(URL.init(string:)) else { return }
            NSWorkspace.shared.open(checkoutURL(base: base, userID: userID))
            show(L("Finish your purchase in the browser. This window updates when it arrives."), error: false)
            Task { await account.waitForPurchase() }
        case .appStore:
            guard let storeProduct = products[product], let token = UUID(uuidString: userID) else { show(L("This purchase isn't available right now."), error: true); return }
            isBusy = true; defer { isBusy = false }
            do {
                // appAccountToken ties the purchase to this account (FR-P2); the backend rejects it for anyone else.
                switch try await storeProduct.purchase(options: [.appAccountToken(token)]) {
                case .success(let result): await handle(result)
                case .pending: show(L("Your purchase is waiting for approval."), error: false)
                case .userCancelled: break
                @unknown default: break
                }
            } catch {
                show(error.localizedDescription, error: true)
            }
        }
    }

    /// "Restore purchases" (FR-A18).
    func restore() async {
        let account = AccountModel.shared
        guard account.signedIn else { show(L("Sign in first to restore purchases."), error: true); return }
        isBusy = true; defer { isBusy = false }
        switch channel {
        case .direct:
            await account.refreshEntitlement()
            show(L("Checked for purchases. If you bought before signing in, enter your license key below."), error: false)
        case .appStore:
            do { try await AppStore.sync() } catch { show(error.localizedDescription, error: true); return }
            var sent = 0
            for await result in Transaction.currentEntitlements { if await handle(result, quiet: true) { sent += 1 } }
            await account.refreshEntitlement()
            show(sent == 0 ? L("No purchases to restore.") : L("Purchases restored."), error: false)
        }
    }

    @discardableResult
    private func handle(_ result: VerificationResult<Transaction>, quiet: Bool = false) async -> Bool {
        guard case .verified(let transaction) = result else { if !quiet { show(L("That purchase couldn't be verified."), error: true) }; return false }
        guard PaywallProduct(storeKitID: transaction.productID) != nil else { return false }
        do {
            try await AccountModel.shared.submitStoreKit(jws: result.jwsRepresentation)
            await transaction.finish()   // only after the backend has it
            if !quiet { show(L("Thank you! Your plan is active."), error: false) }
            return true
        } catch let error as BackendError {
            // Leave the transaction unfinished so StoreKit offers it again later.
            if !quiet { show(error.kind == .wrongAccount ? L("This purchase belongs to a different account.") : AccountModel.shared.friendly(error), error: true) }
            return false
        } catch {
            if !quiet { show(error.localizedDescription, error: true) }
            return false
        }
    }

    private func show(_ text: String, error: Bool) { message = text; messageIsError = error }
}
