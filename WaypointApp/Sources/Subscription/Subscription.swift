import Foundation

/// What the user is entitled to, and the plans on offer.
///
/// **Mock.** No StoreKit, no payment, no receipt — `purchase` simply writes the result a real
/// purchase would have produced. That is deliberate: the gate, the paywall and every screen that
/// has to behave differently for a lapsed user can all be built and tested now, and swapping in
/// StoreKit later touches `purchase`, `restore` and nothing else.
///
/// Prices are stated here only so the mock paywall can show something. Real prices come from
/// App Store Connect at runtime and are localised per storefront — a hardcoded "$4.99" shown to
/// someone in India is both wrong and a review rejection, so these strings die with the mock.
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

    /// What someone pays for the first period. Introductory offers are an Apple feature: a real
    /// reduced price for a set time, after which the standard price applies. That distinction is
    /// the whole reason the crossed-out number below is allowed to exist — a "was" price nobody
    /// was ever charged is deceptive pricing, and in the UK and EU it is against consumer law.
    var mockIntroPrice: String {
        switch self {
        case .monthly: "$1.99"
        case .annual: "$19.99"
        }
    }

    /// The standard price, shown struck through. Real, and really charged once the intro period
    /// ends.
    var mockPrice: String {
        switch self {
        case .monthly: "$4.99"
        case .annual: "$39.99"
        }
    }

    /// How long the introductory price lasts.
    var introDuration: String {
        switch self {
        case .monthly: "for 3 months"
        case .annual: "for the first year"
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

/// Where someone stands right now.
enum SubscriptionStatus: Equatable {
    case trial(daysLeft: Int)
    case subscribed(plan: SubscriptionPlan, renewsAt: Date)
    /// The trial ended and nothing was bought. Not "expired" — the app still works, with less
    /// of it. The name matters because the old one described a lockout, and a lockout is what
    /// this deliberately isn't.
    case free

    var isTrial: Bool { if case .trial = self { true } else { false } }
    var isSubscribed: Bool { if case .subscribed = self { true } else { false } }

    /// The single question every gate in the app asks.
    ///
    /// `BetaAccess` short-circuits it while the purchase path is still a mock, so testers get
    /// the whole app rather than a paywall quoting prices for products that do not exist. The
    /// status itself stays truthful underneath — a lapsed trial still reports `.free`, so
    /// Settings can say so — only the gates open. See `BetaAccess` for why it is detected from
    /// the receipt rather than left as a flag somebody has to remember to turn off.
    var hasFullAccess: Bool {
        if BetaAccess.grantsFullAccess { return true }
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
        renewsAt: Date?,
        now: Date = .now
    ) -> SubscriptionStatus {
        if let plan, let renewsAt, renewsAt > now {
            return .subscribed(plan: plan, renewsAt: renewsAt)
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
