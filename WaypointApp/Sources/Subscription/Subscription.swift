import Foundation

/// What the user is entitled to, and the plans on offer.
///
/// Purchases are real: `Store` talks to RevenueCat, which talks to StoreKit. What lives here is
/// only what the app itself must know about a plan — its identifier, its name, how it reads.
/// Prices are deliberately not among them: they come from the App Store at runtime, already
/// converted and formatted for the viewer's storefront.
enum SubscriptionPlan: String, CaseIterable, Identifiable {
    case monthly
    case annual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monthly: "Monthly"
        case .annual: "Annual"
        }
    }

    /// The identifier this plan has in App Store Connect.
    ///
    /// Fixed for the life of the product — Apple does not allow it to be changed once created,
    /// and a subscriber's purchase is tied to it. This is the one string the app and App Store
    /// Connect must agree on exactly.
    var productID: String {
        switch self {
        case .monthly: "waypoint.pro.monthly"
        case .annual: "waypoint.pro.annual"
        }
    }

    /// Only so the mock paywall has something to draw.
    ///
    /// There is no introductory offer: the launch price *is* the price. An introductory offer
    /// in Apple's sense is "pay this for N periods, then the standard price", and it needs a
    /// standard price to revert to — so a low launch price with nothing above it is simply a
    /// low price, which is also the version that leaves every option open. Raising it later
    /// can preserve existing subscribers at what they signed up for.
    ///
    /// Dies with the mock. Real prices arrive from Apple at runtime, already converted and
    /// formatted for the viewer's storefront — a hardcoded "$1.99" shown to someone in India is
    /// both wrong and a review rejection.
    var mockPrice: String {
        switch self {
        case .monthly: "$1.99"
        case .annual: "$19.99"
        }
    }

    var cadence: String {
        switch self {
        case .monthly: "per month"
        case .annual: "per year"
        }
    }

    /// Deliberately not a number.
    ///
    /// This said "4 months free", which is true of the *standard* prices — $39.99 against twelve
    /// months at $4.99. Sitting beside "$19.99, introductory offer" it reads as a claim about
    /// the introductory price instead, and that one isn't true. Two prices on a row can only
    /// carry one comparison before the reader has to guess which, and a savings claim nobody can
    /// resolve is exactly what paywalls get rejected and complained about for.
    ///
    /// The row already states both numbers plainly. This only has to point at the better one.
    var savingNote: String? {
        switch self {
        case .monthly: nil
        case .annual: "Best value"
        }
    }

    var renewalInterval: DateComponents {
        switch self {
        case .monthly: DateComponents(month: 1)
        case .annual: DateComponents(year: 1)
        }
    }
}

/// What happens when the paid period ends.
///
/// **This is the fact the app used to throw away.** RevenueCat reports both when a period ends
/// and whether it will roll over; keeping only the date made a cancelled subscription and a
/// renewing one identical. So Settings told somebody who had just cancelled that their
/// subscription "Renews 10 Nov" — contradicting, on the screen they opened to check it had
/// worked, a decision they had just made about money. The predictable results are a second
/// cancellation, a support email, and a refund request.
///
/// All three states keep full access. Cancelling is not a punishment: the period is paid for.
enum Renewal: Equatable {
    /// Rolls over on the date, and is charged again.
    case renewing
    /// Auto-renew is off. Access runs to the date and then stops.
    case cancelled
    /// Apple cannot take payment and is retrying. Access continues while it does — taking the
    /// app away the moment a card expires punishes a customer for their bank's timing, and
    /// Apple recovers a good share of these on its own.
    case billingProblem
}

extension Renewal {
    /// Derived from the two facts Apple reports about a live subscription.
    ///
    /// A free function rather than inline in `Store` so it can be tested: `CustomerInfo` can't
    /// reasonably be constructed in a unit test, and this decision — the one the old code got
    /// wrong by not making it at all — is the part worth pinning down.
    ///
    /// Order matters. A declined card and a cancellation can coexist on a record, and the
    /// actionable one must win the label: telling somebody "won't renew" when the truth is
    /// "your card was declined" sends them to the wrong screen to fix it.
    static func from(willRenew: Bool, billingIssueDetectedAt: Date?) -> Renewal {
        if billingIssueDetectedAt != nil { return .billingProblem }
        return willRenew ? .renewing : .cancelled
    }
}

/// The three links the subscription screens need, in one place so they cannot drift apart.
enum AppLinks {
    /// Apple's standard EULA.
    ///
    /// **Guideline 3.1.2 requires a functional link to the terms of use and to the privacy
    /// policy at the point of purchase, inside the binary** — not only in the App Store
    /// listing. The paywall carried the renewal disclosure but neither link, which is one of
    /// the most common reasons a subscription app is rejected. This is the standard EULA
    /// because no custom one was supplied in App Store Connect; if one ever is, this changes.
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")

    static let privacy = URL(string: "https://narasimhadixits.github.io/privacy.html")

    /// Apple's subscription management page. The only place a plan can actually be cancelled,
    /// resumed, or have its payment method replaced — none of which an app can do itself.
    static let manageSubscription = URL(string: "https://apps.apple.com/account/subscriptions")
}

/// Where someone stands right now.
enum SubscriptionStatus: Equatable {
    case trial(daysLeft: Int)
    /// `until` is the end of the paid period — a renewal date or an expiry date, depending on
    /// `renewal`. Deliberately no longer called `renewsAt`: that name admitted one meaning and
    /// was wrong in two of the three cases.
    case subscribed(plan: SubscriptionPlan, until: Date, renewal: Renewal)
    /// The trial ended and nothing was bought. Not "expired" — the app still works, with less
    /// of it. The name matters because the old one described a lockout, and a lockout is what
    /// this deliberately isn't.
    case free

    var isTrial: Bool { if case .trial = self { true } else { false } }
    var isSubscribed: Bool { if case .subscribed = self { true } else { false } }

    /// The single question every gate in the app asks.
    ///
    /// **No override any more.** `BetaAccess` held every gate open while the purchase path was
    /// a mock, so testers met the app rather than a paywall quoting prices for products that
    /// didn't exist. Purchases are real now, so the honest thing is the thing that ships: the
    /// same trial and the same paywall for testers as for everybody else. A backdoor kept past
    /// the moment it was needed is just a backdoor.
    var hasFullAccess: Bool {
        switch self {
        case .trial, .subscribed: return true
        case .free: return false
        }
    }
}

/// What the free tier can and can't do.
///
/// Every rule lives here rather than in the screens that enforce them. A gate spread across
/// five views is a gate with five slightly different opinions, and the one that drifts is the
/// one nobody tests — which on a paywall means either giving the product away or locking out
/// someone who paid.
///
/// The shape of the free tier, in one sentence: **you can always look back, and today is always
/// yours; paying is what lets you plan forward and see the patterns.**
extension SubscriptionStatus {
    /// Nothing is ever hidden retroactively. Work already finished belongs to the person who
    /// did it, and holding their own history behind glass to sell a subscription is the move
    /// that earns refund requests and one-star reviews.
    func canViewDay(_ day: Date, now: Date = .now) -> Bool {
        guard !hasFullAccess else { return true }
        let cal = Calendar.current
        return cal.startOfDay(for: day) <= cal.startOfDay(for: now)
    }

    /// Today only, on the free tier. A past day stays readable but can't be rewritten — which
    /// is also the honest behaviour, since completing work after the fact isn't completing it.
    func canEditDay(_ day: Date, now: Date = .now) -> Bool {
        guard !hasFullAccess else { return true }
        return Calendar.current.isDate(day, inSameDayAs: now)
    }

    var canUseWeekTab: Bool { hasFullAccess }
    var canUseProgress: Bool { hasFullAccess }

    /// One goal on the free tier — enough to use the feature properly rather than peer at it.
    ///
    /// Phrased as a limit on *creating*, never on having. Somebody who made four goals during
    /// the trial keeps all four; they just can't start a fifth. The alternative is choosing
    /// three of their goals to hide, which is the same hostage problem in a different coat.
    func canCreateGoal(existingCount: Int) -> Bool {
        hasFullAccess || existingCount < SubscriptionPolicy.freeGoalLimit
    }
}

enum SubscriptionPolicy {
    /// Two weeks rather than one. A planner is judged over a week of real use, and a trial that
    /// ends before the second Monday never gets the chance to be judged at all.
    static let trialDays = 14

    static let freeGoalLimit = 1

    /// Pure, and given the clock rather than reading it, so the boundaries are testable.
    ///
    /// Days left rounds **up**: someone six hours from the end is told "1 day left", not "0".
    /// Zero is a number that means the trial is over, and showing it while the app still works
    /// reads as a bug.
    static func resolve(
        trialStartedAt: Date?,
        plan: SubscriptionPlan?,
        until: Date?,
        renewal: Renewal = .renewing,
        now: Date = .now
    ) -> SubscriptionStatus {
        if let plan, let until, until > now {
            return .subscribed(plan: plan, until: until, renewal: renewal)
        }
        // No trial on record means it hasn't started yet, not that it's over — a fresh install
        // that somehow reaches this before the trial is stamped should not be locked out.
        guard let trialStartedAt else { return .trial(daysLeft: trialDays) }
        guard let ends = Calendar.current.date(byAdding: .day, value: trialDays, to: trialStartedAt) else {
            return .free
        }
        guard ends > now else { return .free }
        let seconds = ends.timeIntervalSince(now)
        return .trial(daysLeft: max(1, Int((seconds / 86_400).rounded(.up))))
    }
}
