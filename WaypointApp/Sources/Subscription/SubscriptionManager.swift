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

    /// Set once RevenueCat has answered. `nil` before the first reply, and after a failure —
    /// the same thing from here, deliberately: both mean "no confirmed subscription", and both
    /// fall through to the trial clock, which is local and always available.
    private var entitled: Store.Entitlement?

    /// Real prices, once the store has sent them. The paywall reads these and falls back to
    /// nothing rather than to an invented number — a wrong price is worse than a missing one.
    @Published private(set) var prices: [SubscriptionPlan: String] = [:]

    #if DEBUG
    /// A forced renewal state, so the cancelled and payment-problem screens can be looked at.
    ///
    /// Reaching them for real takes a purchase, a trip to iOS Settings and, for the second one,
    /// a card that declines on demand. Copy that can't be looked at is copy that ships unread —
    /// which is exactly how "Renews 10 Nov" ended up in front of somebody who had just
    /// cancelled. Set by `-wpRenewal` or the Settings developer panel; a real push from the
    /// store clears it.
    private var previewRenewal: Renewal?

    func preview(_ renewal: Renewal?) {
        previewRenewal = renewal
        refresh()
    }

    /// Whether the panel is currently forcing this state — marked so it's obvious which button
    /// you already pressed. Reads the status rather than the override, so a real subscription
    /// lights the matching button too.
    func isPreviewing(_ renewal: Renewal) -> Bool {
        if case .subscribed(_, _, let current) = status { return current == renewal }
        return false
    }
    #endif

    private init() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-wpRenewal"), i + 1 < args.count {
            switch args[i + 1] {
            case "cancelled": previewRenewal = .cancelled
            case "billing": previewRenewal = .billingProblem
            case "renewing": previewRenewal = .renewing
            default: break
            }
        }
        #endif
        refresh()
        Task { await syncWithStore() }
        observeStore()
    }

    /// Keeps `entitled` current for the life of the process.
    ///
    /// A subscription changes without the app being involved at all — it is cancelled in iOS
    /// Settings, it renews overnight, a card is declined, Apple grants a refund. None of those
    /// pass through any code here, so an app that only asks at launch is wrong from the first
    /// one onward. The SDK already holds this connection open for its own cache; this listens
    /// to it rather than adding a timer.
    private func observeStore() {
        Task { [weak self] in
            for await entitlement in Store.entitlementUpdates {
                guard let self else { return }
                #if DEBUG
                // Only a *real* entitlement overrules a preview. The stream yields its cached
                // answer the instant you subscribe to it, and on a simulator that answer is
                // "no subscription" — which was wiping the forced state a few milliseconds
                // after launch and making `-wpRenewal` look like it did nothing.
                if entitlement != nil { self.previewRenewal = nil }
                #endif
                self.entitled = entitlement
                self.refresh()
            }
        }
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
        let trialStartedAt = TrialRecord.startOrBegin(now: now)
        #if DEBUG
        // `-wpFree` forces the lapsed state, same family as `-wpTab`. The Settings toggle for
        // this writes to UserDefaults and needs a tap; a launch argument can be used from a
        // script, which is the difference between looking at the free tier and not.
        if ProcessInfo.processInfo.arguments.contains("-wpFree") {
            status = .free
            return
        }
        if let previewRenewal {
            status = .subscribed(
                plan: .annual,
                until: Calendar.current.date(byAdding: .day, value: 300, to: now) ?? now,
                renewal: previewRenewal
            )
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
            plan: entitled?.plan,
            until: entitled?.until,
            renewal: entitled?.renewal ?? .renewing,
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
        #if DEBUG
        previewRenewal = nil
        #endif
        // Must drop the entitlement too, or a real subscription on the device simply overrules
        // the button and the lapsed state stays unlookable — which was the whole complaint
        // this affordance exists to answer. The next push from the store puts it back.
        entitled = nil
        TrialRecord.setStart(
            Calendar.current.date(byAdding: .day, value: -(SubscriptionPolicy.trialDays + 1), to: .now) ?? .now
        )
        refresh()
    }

    func resetTrial() {
        #if DEBUG
        previewRenewal = nil
        #endif
        entitled = nil
        TrialRecord.setStart(.now)
        refresh()
    }
}
