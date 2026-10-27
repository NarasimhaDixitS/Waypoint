import Foundation
import RevenueCat

/// Everything that talks to RevenueCat, in one place.
///
/// **Why a seam rather than calling `Purchases` from the view model.** The gates
/// (`canViewDay`, `canUseProgress`, and the rest) are the part of this that has to keep working
/// whatever happens to the billing layer, and they are tested against `SubscriptionStatus`
/// rather than against a network. Keeping the SDK behind one small type means the tests never
/// need a store, and swapping the store later never touches a gate.
///
/// That claim was tested for real in Oct 2026, when Waypoint stopped selling a monthly and an
/// annual subscription and started selling one permanent unlock. Six files changed. **Not one
/// gate did**, because none of them had ever known what was being sold.
enum Store {
    /// The public SDK key. Safe to ship — it identifies the app to RevenueCat and authorises
    /// nothing on its own; the secret key lives in the dashboard and never leaves it.
    private static let apiKey = "appl_HLgGkGhbEfEAtlWZxXpLEUTjQMu"

    /// Must match the entitlement identifier in the RevenueCat dashboard exactly.
    ///
    /// Deliberately still `pro` after the move to a one-time purchase. The lifetime product is
    /// attached to this same entitlement in the dashboard, so every gate in the app keeps
    /// asking the one question it always asked.
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

    /// Whether this customer owns Waypoint Pro.
    ///
    /// **A `Bool`, and the shrinking is the point.** This used to return an `Entitlement` with
    /// a plan, an end date and a renewal state derived from `willRenew` and
    /// `billingIssueDetectedAt` — three facts a subscription has and a purchase does not.
    ///
    /// Carrying that shape into a one-time product would have shipped a bug on day one: a
    /// lifetime entitlement arrives from RevenueCat with `willRenew == false` and
    /// `expirationDate == nil`, so the old derivation would have read it as *cancelled* and
    /// Settings would have told a paying customer "Ends 1 Jan 4001 · won't renew". The fix is
    /// the deletion, not a special case.
    ///
    /// `false` means "no purchase on record", not "something went wrong" — a customer who never
    /// bought and an unreachable network look identical from here, which is deliberate: the
    /// caller falls back to the trial clock either way, and the trial clock is local. Someone
    /// offline on a plane does not lose access they paid for, because `CustomerInfo` is cached
    /// by the SDK and served from disk.
    static func owns(from info: CustomerInfo) -> Bool {
        info.entitlements[entitlementID]?.isActive == true
    }

    /// Every change RevenueCat sees for this customer, pushed as it happens.
    ///
    /// **This is what replaces polling, and its absence was a real bug.** `syncWithStore` was
    /// the only thing that ever asked, and it ran once in `init` — so for the whole life of the
    /// process the app believed whatever had been true at launch. The SDK already maintains
    /// this connection for its own cache; listening to it costs nothing and no timer.
    ///
    /// It matters less than it did, because a purchase cannot lapse on its own the way a
    /// subscription could. It is kept for the cases that remain: a refund Apple grants, and a
    /// purchase made on another device under the same Apple ID.
    ///
    /// Yields `Bool` rather than `CustomerInfo` so that no RevenueCat type escapes this file —
    /// the seam this whole enum exists to maintain.
    static var ownershipUpdates: AsyncStream<Bool> {
        AsyncStream { continuation in
            let task = Task {
                for await info in Purchases.shared.customerInfoStream {
                    continuation.yield(owns(from: info))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
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

    /// The lifetime package from the current offering.
    ///
    /// Looked up by product identifier rather than by `.lifetime` package type, because the
    /// package type depends on how the offering was configured in a dashboard and the product
    /// identifier doesn't.
    static func package() async throws -> Package? {
        let offerings = try await Purchases.shared.offerings()
        guard let current = offerings.current else { return nil }
        return current.availablePackages.first {
            $0.storeProduct.productIdentifier == WaypointPro.productID
        }
    }

    /// The localised price, straight from the App Store.
    ///
    /// Never hardcoded. A price written down in Swift is wrong everywhere outside one
    /// storefront and wrong here the moment it changes in App Store Connect — and it is the one
    /// number on that screen a person is deciding on. `nil` means the store hasn't answered;
    /// the paywall shows nothing rather than a guess.
    static func price() async -> String? {
        guard let package = try? await package() else { return nil }
        return package.storeProduct.localizedPriceString
    }

    enum PurchaseOutcome {
        case bought(CustomerInfo)
        case cancelled
        case unavailable
    }

    static func purchase() async throws -> PurchaseOutcome {
        guard let package = try await package() else { return .unavailable }
        let result = try await Purchases.shared.purchase(package: package)
        // Cancelling is not an error and must not be shown as one. It's the single most common
        // outcome of opening a paywall.
        return result.userCancelled ? .cancelled : .bought(result.customerInfo)
    }

    static func restore() async throws -> CustomerInfo {
        try await Purchases.shared.restorePurchases()
    }
}
