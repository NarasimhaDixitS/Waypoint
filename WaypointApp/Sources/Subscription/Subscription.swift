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

    var mockPrice: String {
        switch self {
        case .monthly: "$4.99"
        case .annual: "$29.99"
        }
    }

    var cadence: String {
        switch self {
        case .monthly: "per month"
        case .annual: "per year"
        }
    }

    /// Annual is priced at ten months of monthly, so this is a fact rather than a sales line.
    var savingNote: String? {
        switch self {
        case .monthly: nil
        case .annual: "2 months free"
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
    case expired

    /// The single question the rest of the app asks. Creating work is what a lapsed user loses;
    /// reading, completing and editing what they already made stays open, always. Locking
    /// someone out of data they created earns refund requests and one-star reviews, and it isn't
    /// what they agreed to when they typed it in.
    var canCreate: Bool {
        switch self {
        case .trial, .subscribed: true
        case .expired: false
        }
    }
}

enum SubscriptionPolicy {
    static let trialDays = 7

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
            return .expired
        }
        guard ends > now else { return .expired }
        let seconds = ends.timeIntervalSince(now)
        return .trial(daysLeft: max(1, Int((seconds / 86_400).rounded(.up))))
    }
}
