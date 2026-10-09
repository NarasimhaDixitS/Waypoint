import Foundation
import SwiftUI

/// Holds the entitlement and stands in for StoreKit.
///
/// The trial is stamped on first run rather than at install, because there's no install hook to
/// hang it on — and stamping it lazily means someone who downloads the app and opens it a month
/// later still gets their seven days.
@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    @Published private(set) var status: SubscriptionStatus = .free

    /// The trial start deliberately isn't here — see `TrialRecord`. `UserDefaults` is deleted
    /// with the app, so storing it there handed out a fresh trial on every reinstall.
    ///
    /// The purchase keys can stay: an actual subscription is tied to the Apple ID, and
    /// "Restore purchases" brings it back on a new install or a new phone without the app
    /// having to remember anything. Only the trial — which Apple knows nothing about — needs
    /// somewhere durable of its own.
    private enum Keys {
        static let plan = "subscription.plan"
        static let renewsAt = "subscription.renewsAt"
    }

    /// Set once RevenueCat has answered. `nil` before the first reply, and after a failure —
    /// the same thing from here, deliberately: both mean "no confirmed subscription", and both
    /// fall through to the trial clock, which is local and always available.
    private var entitled: (plan: SubscriptionPlan, renewsAt: Date)?

    /// Real prices, once the store has sent them. The paywall reads these and falls back to
    /// nothing rather than to an invented number — a wrong price is worse than a missing one.
    @Published private(set) var prices: [SubscriptionPlan: String] = [:]

    private init() {
        refresh()
        Task { await syncWithStore() }
    }

    /// Asks RevenueCat what it knows, then recomputes.
    ///
    /// Not on a timer: an entitlement changes when somebody buys, cancels or renews, and the
    /// SDK's cached `CustomerInfo` already survives being offline — polling would add network
    /// traffic to answer a question whose answer is usually already on disk.
    func syncWithStore() async {
        if let info = try? await Store.customerInfo() {
            entitled = Store.activeSubscription(from: info)
            refresh()
        }
        let fetched = await Store.allPrices()
        // Only overwrite when the store actually answered. An empty reply is "ask again
        // later", not "these products have no price" — blanking a price already on screen
        // because one request timed out is strictly worse than showing the last true one.
        if !fetched.isEmpty { prices = fetched }
    }

    /// Recomputed rather than stored: a trial ends by the clock moving, and nothing fires an
    /// event when that happens. Anything showing entitlement has to ask again, not remember.
    func refresh(now: Date = .now) {
        let defaults = UserDefaults.standard
        let trialStartedAt = TrialRecord.startOrBegin(now: now)
        #if DEBUG
        // `-wpFree` forces the lapsed state, same family as `-wpTab`. The Settings toggle for
        // this writes to UserDefaults and needs a tap; a launch argument can be used from a
        // script, which is the difference between looking at the free tier and not.
        if ProcessInfo.processInfo.arguments.contains("-wpFree") {
            status = .free
            return
        }
        #endif
        // **The store wins when it has an answer.** A confirmed entitlement is a fact about
        // money that changed hands; the trial clock is a local guess about someone who hasn't
        // paid. When RevenueCat hasn't replied — offline, first launch, an error — `entitled`
        // is nil and the trial decides, which is the right way to fail: it can only ever be
        // more generous than the truth, never less.
        status = SubscriptionPolicy.resolve(
            trialStartedAt: trialStartedAt,
            plan: entitled?.plan ?? (defaults.string(forKey: Keys.plan)).flatMap(SubscriptionPlan.init(rawValue:)),
            renewsAt: entitled?.renewsAt ?? defaults.object(forKey: Keys.renewsAt) as? Date,
            now: now
        )
    }

    enum PurchaseResult: Equatable { case bought, cancelled, failed(String) }

    /// Buys through RevenueCat, which buys through StoreKit.
    ///
    /// Cancelling is returned, not thrown. It is the most common way a paywall ends, and
    /// showing it as an error tells someone their deliberate choice went wrong.
    func purchase(_ plan: SubscriptionPlan) async -> PurchaseResult {
        do {
            switch try await Store.purchase(plan) {
            case .bought(let info):
                entitled = Store.activeSubscription(from: info)
                refresh()
                return .bought
            case .cancelled:
                return .cancelled
            case .unavailable:
                // No package for this product in the current offering — a dashboard problem,
                // not the customer's, and worth saying rather than failing silently.
                return .failed("That plan isn't available right now.")
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Replays Apple's transaction history for this Apple ID.
    ///
    /// Required by Apple on any app selling a subscription, and genuinely needed here: the
    /// entitlement lives with the Apple ID and nothing in this app is synced.
    func restore() async -> PurchaseResult {
        do {
            entitled = Store.activeSubscription(from: try await Store.restore())
            refresh()
            return entitled != nil ? .bought : .failed("No previous purchase found on this Apple ID.")
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Developer affordance so the lapsed state can actually be looked at — a seven-day wait is
    /// not a testing strategy.
    func expireNow() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Keys.plan)
        defaults.removeObject(forKey: Keys.renewsAt)
        TrialRecord.setStart(
            Calendar.current.date(byAdding: .day, value: -(SubscriptionPolicy.trialDays + 1), to: .now) ?? .now
        )
        refresh()
    }

    func resetTrial() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Keys.plan)
        defaults.removeObject(forKey: Keys.renewsAt)
        TrialRecord.setStart(.now)
        refresh()
    }
}
