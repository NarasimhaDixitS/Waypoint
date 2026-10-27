import Foundation
import SwiftUI

/// Holds the entitlement and stands in for StoreKit.
///
/// The trial is stamped on first run rather than at install, because there's no install hook to
/// hang it on — and stamping it lazily means someone who downloads the app and opens it a month
/// later still gets their fourteen days.
@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    @Published private(set) var status: SubscriptionStatus = .free

    /// Whether RevenueCat has confirmed a purchase.
    ///
    /// `false` before the first reply and after a failure — the same thing from here,
    /// deliberately: both mean "no confirmed purchase", and both fall through to the trial
    /// clock, which is local and always available.
    private var owned = false

    /// The real price, once the store has sent it. The paywall reads this and falls back to
    /// nothing rather than to an invented number — a wrong price is worse than a missing one.
    @Published private(set) var price: String?

    private init() {
        #if DEBUG
        // `-wpTrial` restarts the fourteen days, the mirror of `-wpFree`.
        //
        // Needed because the trial deliberately survives everything: it lives in the Keychain
        // so that deleting the app can't buy a second one, which also means nothing outside the
        // app can put it back. The only other route is the Settings button, and reaching that
        // is a tap. Capturing unlocked screens, or looking at any gated tab, otherwise means
        // either waiting out a real fortnight or wiping the device and losing the data that
        // made the screen worth looking at.
        if ProcessInfo.processInfo.arguments.contains("-wpTrial") {
            TrialRecord.setStart(.now)
        }
        #endif
        refresh()
        Task { await syncWithStore() }
        observeStore()
    }

    /// Keeps `owned` current for the life of the process.
    ///
    /// **This mattered more when Waypoint sold subscriptions**, which could be cancelled in iOS
    /// Settings, renew overnight, or fall into a card-declined retry loop without the app being
    /// involved at all. A purchase cannot lapse on its own, so the remaining cases are narrow:
    /// a refund Apple grants, and a purchase made on another device under the same Apple ID.
    /// Both are real, and the SDK already holds this connection open for its own cache, so
    /// listening costs nothing and needs no timer.
    private func observeStore() {
        Task { [weak self] in
            for await owns in Store.ownershipUpdates {
                guard let self else { return }
                self.owned = owns
                self.refresh()
            }
        }
    }

    /// Asks RevenueCat what it knows, then recomputes.
    func syncWithStore() async {
        if let info = try? await Store.customerInfo() {
            owned = Store.owns(from: info)
            refresh()
        }
        // Only overwrite when the store actually answered. A nil reply is "ask again later",
        // not "this product has no price" — blanking a price already on screen because one
        // request timed out is strictly worse than showing the last true one.
        if let fetched = await Store.price() { price = fetched }
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
        #endif
        // **The store wins when it has an answer.** A confirmed purchase is a fact about money
        // that changed hands; the trial clock is a local guess about someone who hasn't paid.
        // When RevenueCat hasn't replied — offline, first launch, an error — `owned` is false
        // and the trial decides, which is the right way to fail: it can only ever be more
        // generous than the truth, never less.
        status = SubscriptionPolicy.resolve(
            trialStartedAt: trialStartedAt,
            hasPurchased: owned,
            now: now
        )
    }

    enum PurchaseResult: Equatable { case bought, cancelled, failed(String) }

    /// Buys through RevenueCat, which buys through StoreKit.
    ///
    /// Cancelling is returned, not thrown. It is the most common way a paywall ends, and
    /// showing it as an error tells someone their deliberate choice went wrong.
    func purchase() async -> PurchaseResult {
        do {
            switch try await Store.purchase() {
            case .bought(let info):
                owned = Store.owns(from: info)
                refresh()
                return .bought
            case .cancelled:
                return .cancelled
            case .unavailable:
                // No package for this product in the current offering — a dashboard problem,
                // not the customer's, and worth saying rather than failing silently.
                return .failed("Waypoint Pro isn't available right now.")
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Replays Apple's transaction history for this Apple ID.
    ///
    /// Required by Apple on any app selling a purchase, and it carries more weight here than it
    /// used to. A one-time unlock is the kind of thing somebody buys once and expects on every
    /// phone they ever own, and there is no account in this app to look them up by — the Apple
    /// ID is the only thread connecting a new device to a purchase made years earlier.
    func restore() async -> PurchaseResult {
        do {
            owned = Store.owns(from: try await Store.restore())
            refresh()
            return owned ? .bought : .failed("No previous purchase found on this Apple ID.")
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Developer affordance so the lapsed state can actually be looked at — a fourteen-day wait
    /// is not a testing strategy.
    func expireNow() {
        // Must drop the purchase too, or a real one on the device simply overrules the button
        // and the lapsed state stays unlookable — which was the whole complaint this affordance
        // exists to answer. The next push from the store puts it back.
        owned = false
        TrialRecord.setStart(
            Calendar.current.date(byAdding: .day, value: -(SubscriptionPolicy.trialDays + 1), to: .now) ?? .now
        )
        refresh()
    }

    func resetTrial() {
        owned = false
        TrialRecord.setStart(.now)
        refresh()
    }
}
