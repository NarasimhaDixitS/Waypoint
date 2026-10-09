import Foundation
import RevenueCat

/// Everything that talks to RevenueCat, in one place.
///
/// **Why a seam rather than calling `Purchases` from the view model.** The gates
/// (`canViewDay`, `canUseProgress`, and the rest) are the part of this that has to keep working
/// whatever happens to the billing layer, and they are tested against `SubscriptionStatus`
/// rather than against a network. Keeping the SDK behind one small type means the tests never
/// need a store, and swapping the store later never touches a gate.
enum Store {
    /// The public SDK key. Safe to ship — it identifies the app to RevenueCat and authorises
    /// nothing on its own; the secret key lives in the dashboard and never leaves it.
    private static let apiKey = "appl_HLgGkGhbEfEAtlWZxXpLEUTjQMu"

    /// Must match the entitlement identifier in the RevenueCat dashboard exactly.
    static let entitlementID = "pro"

    /// **Prices are `nil` on the simulator, always.** There's no App Store account signed into
    /// it, so StoreKit returns no products however correct the RevenueCat dashboard is — which
    /// means the simulator cannot answer "is the store wired up", and a paywall showing "—"
    /// there is not evidence of anything. That question needs a real device with a sandbox
    /// Apple ID signed in under Settings → App Store → Sandbox Account.
    static func configure() {
        #if DEBUG
        Purchases.logLevel = .debug
        #else
        Purchases.logLevel = .error
        #endif
        Purchases.configure(withAPIKey: apiKey)
    }

    /// What RevenueCat currently believes, translated into the app's own vocabulary.
    ///
    /// `nil` means "no active subscription", not "something went wrong" — a lapsed subscriber
    /// and an unreachable network look identical from here, which is deliberate: the caller
    /// falls back to the trial clock either way, and the trial clock is local. A person offline
    /// on a plane does not lose access they paid for, because `CustomerInfo` is cached by the
    /// SDK and served from disk.
    static func activeSubscription(from info: CustomerInfo) -> (plan: SubscriptionPlan, renewsAt: Date)? {
        guard let entitlement = info.entitlements[entitlementID], entitlement.isActive else { return nil }

        // Matched on the product identifier rather than on the package type: the identifier is
        // the one string App Store Connect, RevenueCat and this app all have to agree on, and
        // it's the one `SubscriptionPlan` already owns.
        let plan = SubscriptionPlan.allCases.first { $0.productID == entitlement.productIdentifier }

        return (
            plan ?? .monthly,
            // No expiry on a lifetime or a sandbox grant. Far-future rather than `nil` so the
            // status enum doesn't need a third case for a situation nobody will meet.
            entitlement.expirationDate ?? Date.distantFuture
        )
    }

    /// What the store actually said, in one line, for a screen a human can read.
    ///
    /// **This separates two failures that look identical from the paywall.** Offerings come
    /// over plain HTTP from RevenueCat and work anywhere; only the per-product StoreKit prices
    /// need an App Store account, which a simulator doesn't have. So "no offering at all" means
    /// the dashboard is wrong and is worth fixing now, while "offering present, prices missing"
    /// means the configuration is fine and only a real device can finish the check.
    static func diagnosis() async -> String {
        do {
            let offerings = try await Purchases.shared.offerings()
            guard let current = offerings.current else {
                let names = offerings.all.keys.sorted().joined(separator: ", ")
                return names.isEmpty
                    ? "No offerings at all. Nothing configured in the dashboard."
                    : "No *current* offering. Found: \(names). One must be marked current."
            }
            let packages = current.availablePackages
            guard !packages.isEmpty else {
                return "Offering '\(current.identifier)' exists but has no packages StoreKit could load — expected on a simulator."
            }
            let lines = packages.map {
                "\($0.storeProduct.productIdentifier) → \($0.storeProduct.localizedPriceString)"
            }
            return "Offering '\(current.identifier)': \(lines.joined(separator: " · "))"
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    static func customerInfo() async throws -> CustomerInfo {
        try await Purchases.shared.customerInfo()
    }

    /// The package for a plan, from the current offering.
    ///
    /// Looked up by product identifier rather than by `.monthly` / `.annual` package type,
    /// because the package type depends on how the offering was configured in a dashboard and
    /// the product identifier doesn't.
    static func package(for plan: SubscriptionPlan) async throws -> Package? {
        let offerings = try await Purchases.shared.offerings()
        guard let current = offerings.current else { return nil }
        return current.availablePackages.first { $0.storeProduct.productIdentifier == plan.productID }
    }

    /// Localised price, straight from the App Store.
    ///
    /// This is what replaces `mockPrice`. The paywall used to hardcode "$1.99", which is both
    /// wrong everywhere outside the US and wrong here the moment a price changes in App Store
    /// Connect — the one number on that screen a person is deciding on, written down in Swift.
    /// Every plan's price, from **one** fetch.
    ///
    /// This was a loop calling `offerings()` once per plan — two network round trips for one
    /// answer, and the second one didn't always land: the paywall showed a real price for
    /// Monthly and an em dash for Annual, while a single fetch could see both. Asking twice
    /// for the same thing and believing whichever reply arrived is not a race worth having.
    static func allPrices() async -> [SubscriptionPlan: String] {
        guard let current = try? await Purchases.shared.offerings().current else { return [:] }
        var prices: [SubscriptionPlan: String] = [:]
        for package in current.availablePackages {
            guard let plan = SubscriptionPlan.allCases.first(
                where: { $0.productID == package.storeProduct.productIdentifier }
            ) else { continue }
            prices[plan] = package.storeProduct.localizedPriceString
        }
        return prices
    }

    enum PurchaseOutcome {
        case bought(CustomerInfo)
        case cancelled
        case unavailable
    }

    static func purchase(_ plan: SubscriptionPlan) async throws -> PurchaseOutcome {
        guard let package = try await package(for: plan) else { return .unavailable }
        let result = try await Purchases.shared.purchase(package: package)
        // Cancelling is not an error and must not be shown as one. It's the single most common
        // outcome of opening a paywall.
        return result.userCancelled ? .cancelled : .bought(result.customerInfo)
    }

    static func restore() async throws -> CustomerInfo {
        try await Purchases.shared.restorePurchases()
    }
}
