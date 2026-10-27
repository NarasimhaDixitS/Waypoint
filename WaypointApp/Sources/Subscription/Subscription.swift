import Foundation

/// The one thing there is to buy.
///
/// **Waypoint sold a monthly and an annual subscription until Oct 2026, and now sells a single
/// one-time unlock.** The reasoning was partly commercial and partly honest: there is no server
/// and no account here, so there is no recurring cost to fund and nothing a renewal pays for.
/// Charging rent for software that runs entirely on someone's own phone is the objection that
/// gets levelled at local-first apps, and it is a fair one.
///
/// It also deleted a whole category of bug. A subscription can lapse, be cancelled, be refunded,
/// or sit in a retry loop behind a declined card, and each of those is a state the app has to
/// detect, name and draw — six bugs came out of exactly that in a single afternoon. A thing you
/// own has one state.
///
/// The type names here still say "subscription" because the folder, the manager and every gate
/// are named that way and renaming them is churn with no behaviour change. What they mean is
/// *entitlement to the paid features*.
enum WaypointPro {
    /// The identifier App Store Connect, RevenueCat and this app must all agree on exactly.
    /// Fixed for the life of the product — Apple does not allow it to be changed once created,
    /// and a purchase is tied to it.
    static let productID = "waypoint.pro.lifetime"

    /// Shown wherever the product has to be named, and deliberately a constant rather than a
    /// literal in a view: Apple requires the product's title at the point of purchase, and
    /// build 5 was rejected because the paywall named the *lengths* ("Monthly", "Annual") and
    /// never the product. One source for it means that cannot recur.
    static let name = "Waypoint Pro"
}

/// The two links the paid screens need, in one place so they cannot drift apart.
///
/// Guideline 3.1.2's checklist — title, length, price and both links at the point of purchase —
/// applies to *auto-renewable* subscriptions, so a one-time unlock is not bound by it. Both
/// links stay anyway: the privacy policy is the one claim this app makes about itself that a
/// person might reasonably want to read before paying, and removing something a reviewer has
/// already been shown invites the question of why.
enum AppLinks {
    /// Apple's standard EULA. There is no custom one in App Store Connect; if one is ever
    /// added, this changes.
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")

    static let privacy = URL(string: "https://narasimhadixits.github.io/privacy.html")
}

/// Where someone stands right now.
enum SubscriptionStatus: Equatable {
    case trial(daysLeft: Int)
    /// Bought, permanently. **No date and no renewal state, and that absence is the point.**
    /// The old `.subscribed(plan:until:renewal:)` carried an end date and whether it would roll
    /// over, because a subscription has both and the app got it wrong when it tried to carry
    /// only one of them. A purchase has neither.
    case purchased
    /// The trial ended and nothing was bought. Not "expired" — the app still works, with less
    /// of it. The name matters because the old one described a lockout, and a lockout is what
    /// this deliberately isn't.
    case free

    var isTrial: Bool { if case .trial = self { true } else { false } }
    var isPurchased: Bool { if case .purchased = self { true } else { false } }

    /// The single question every gate in the app asks.
    ///
    /// **No override any more.** `BetaAccess` held every gate open while the purchase path was
    /// a mock, so testers met the app rather than a paywall quoting prices for products that
    /// didn't exist. Purchases are real now, so the honest thing is the thing that ships: the
    /// same trial and the same paywall for testers as for everybody else. A backdoor kept past
    /// the moment it was needed is just a backdoor.
    var hasFullAccess: Bool {
        switch self {
        case .trial, .purchased: return true
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
/// **Untouched by the move from subscriptions to a one-time purchase**, which is the whole
/// reason the store sits behind a seam: these read `hasFullAccess` and have never known what
/// was being sold.
///
/// The shape of the free tier, in one sentence: **you can always look back, and today is always
/// yours; paying is what lets you plan forward and see the patterns.**
extension SubscriptionStatus {
    /// Nothing is ever hidden retroactively. Work already finished belongs to the person who
    /// did it, and holding their own history behind glass to sell an upgrade is the move that
    /// earns refund requests and one-star reviews.
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
    ///
    /// Kept after the move to a one-time purchase, and worth more now than it was: a person who
    /// has used the app for a fortnight is not buying on faith, which is what makes asking for
    /// a single payment at the end of it reasonable. It is a local clock in the Keychain, not a
    /// StoreKit introductory offer, so Apple has no part in it and nothing has to be disclosed.
    static let trialDays = 14

    static let freeGoalLimit = 1

    /// Pure, and given the clock rather than reading it, so the boundaries are testable.
    ///
    /// Days left rounds **up**: someone six hours from the end is told "1 day left", not "0".
    /// Zero is a number that means the trial is over, and showing it while the app still works
    /// reads as a bug.
    ///
    /// **A purchase outranks the trial and can never expire.** The old signature took a plan,
    /// an end date and a renewal state and had to decide whether the date was still in the
    /// future; getting that wrong in either direction either locked out a payer or gave the app
    /// away. There is nothing left to get wrong.
    static func resolve(
        trialStartedAt: Date?,
        hasPurchased: Bool,
        now: Date = .now
    ) -> SubscriptionStatus {
        if hasPurchased { return .purchased }
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
