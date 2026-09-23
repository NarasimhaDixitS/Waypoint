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

    @Published private(set) var status: SubscriptionStatus = .expired

    private enum Keys {
        static let trialStartedAt = "subscription.trialStartedAt"
        static let plan = "subscription.plan"
        static let renewsAt = "subscription.renewsAt"
    }

    private init() { refresh() }

    /// Recomputed rather than stored: a trial ends by the clock moving, and nothing fires an
    /// event when that happens. Anything showing entitlement has to ask again, not remember.
    func refresh(now: Date = .now) {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Keys.trialStartedAt) == nil {
            defaults.set(now, forKey: Keys.trialStartedAt)
        }
        status = SubscriptionPolicy.resolve(
            trialStartedAt: defaults.object(forKey: Keys.trialStartedAt) as? Date,
            plan: (defaults.string(forKey: Keys.plan)).flatMap(SubscriptionPlan.init(rawValue:)),
            renewsAt: defaults.object(forKey: Keys.renewsAt) as? Date,
            now: now
        )
    }

    /// Mock. A real one asks StoreKit, waits for Apple, and verifies the signed transaction —
    /// and can fail, be cancelled, or be deferred for parental approval, none of which this
    /// models. The states either side of it are real, which is the point.
    func purchase(_ plan: SubscriptionPlan, now: Date = .now) {
        let renewsAt = Calendar.current.date(byAdding: plan.renewalInterval, to: now) ?? now
        UserDefaults.standard.set(plan.rawValue, forKey: Keys.plan)
        UserDefaults.standard.set(renewsAt, forKey: Keys.renewsAt)
        refresh(now: now)
    }

    /// Mock. The real one replays Apple's transaction history for this Apple ID, which is how
    /// someone on a new phone gets back what they already bought.
    func restore() { refresh() }

    /// Developer affordance so the lapsed state can actually be looked at — a seven-day wait is
    /// not a testing strategy.
    func expireNow() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Keys.plan)
        defaults.removeObject(forKey: Keys.renewsAt)
        defaults.set(
            Calendar.current.date(byAdding: .day, value: -(SubscriptionPolicy.trialDays + 1), to: .now),
            forKey: Keys.trialStartedAt
        )
        refresh()
    }

    func resetTrial() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Keys.plan)
        defaults.removeObject(forKey: Keys.renewsAt)
        defaults.set(Date.now, forKey: Keys.trialStartedAt)
        refresh()
    }
}
