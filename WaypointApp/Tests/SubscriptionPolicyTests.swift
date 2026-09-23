import XCTest
@testable import Waypoint

/// The trial boundary is the one piece of this that can be wrong silently and expensively: too
/// generous and nobody pays, too strict and a paying customer gets locked out of their own work.
/// `resolve` takes the clock rather than reading it, so the edges can actually be checked.
final class SubscriptionPolicyTests: XCTestCase {
    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 9) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    private var trialStart: Date { date(2026, 9, 1) }

    func testAFreshTrialHasTheFullRun() {
        let status = SubscriptionPolicy.resolve(
            trialStartedAt: trialStart, plan: nil, renewsAt: nil, now: trialStart
        )
        XCTAssertEqual(status, .trial(daysLeft: SubscriptionPolicy.trialDays))
    }

    /// Days left rounds up: six hours from the end is "1 day left", never "0". Zero means over,
    /// and showing it while the app still works reads as a bug.
    func testTheLastHoursStillReadAsOneDay() {
        let status = SubscriptionPolicy.resolve(
            trialStartedAt: trialStart, plan: nil, renewsAt: nil,
            now: date(2026, 9, 8, hour: 3)
        )
        XCTAssertEqual(status, .trial(daysLeft: 1))
    }

    func testTheTrialIsStillLiveOneSecondBeforeItEnds() {
        let status = SubscriptionPolicy.resolve(
            trialStartedAt: trialStart, plan: nil, renewsAt: nil,
            now: date(2026, 9, 8).addingTimeInterval(-1)
        )
        XCTAssertEqual(status, .trial(daysLeft: 1))
        XCTAssertTrue(status.canCreate)
    }

    func testTheTrialIsOverExactlyOnTheBoundary() {
        let status = SubscriptionPolicy.resolve(
            trialStartedAt: trialStart, plan: nil, renewsAt: nil, now: date(2026, 9, 8)
        )
        XCTAssertEqual(status, .expired)
        XCTAssertFalse(status.canCreate)
    }

    /// The whole point of the gate: what's already there stays usable.
    func testALapsedUserCannotCreateButIsNeverLockedOut() {
        XCTAssertFalse(SubscriptionStatus.expired.canCreate)
        XCTAssertTrue(SubscriptionStatus.trial(daysLeft: 3).canCreate)
        XCTAssertTrue(SubscriptionStatus.subscribed(plan: .annual, renewsAt: .now).canCreate)
    }

    func testAnActiveSubscriptionOutranksAnExpiredTrial() {
        let renews = date(2027, 9, 1)
        let status = SubscriptionPolicy.resolve(
            trialStartedAt: trialStart, plan: .annual, renewsAt: renews,
            now: date(2026, 12, 1)
        )
        XCTAssertEqual(status, .subscribed(plan: .annual, renewsAt: renews))
    }

    /// A lapsed subscription falls back to the trial rules rather than staying entitled —
    /// otherwise a cancelled subscriber keeps everything forever.
    func testALapsedSubscriptionExpires() {
        let status = SubscriptionPolicy.resolve(
            trialStartedAt: trialStart, plan: .monthly, renewsAt: date(2026, 10, 1),
            now: date(2026, 11, 1)
        )
        XCTAssertEqual(status, .expired)
    }

    /// No trial stamped yet means it hasn't started, not that it's over. Defaulting to expired
    /// here would lock out a fresh install that reached this before the stamp was written.
    func testAMissingTrialStampIsTreatedAsNotStarted() {
        let status = SubscriptionPolicy.resolve(
            trialStartedAt: nil, plan: nil, renewsAt: nil, now: .now
        )
        XCTAssertEqual(status, .trial(daysLeft: SubscriptionPolicy.trialDays))
    }

    /// Annual is ten months of monthly, so "2 months free" is a fact rather than a sales line.
    func testAnnualPricingMatchesTheSavingItClaims() {
        XCTAssertEqual(SubscriptionPlan.annual.savingNote, "2 months free")
        XCTAssertNil(SubscriptionPlan.monthly.savingNote)
        XCTAssertEqual(SubscriptionPlan.monthly.mockPrice, "$4.99")
        XCTAssertEqual(SubscriptionPlan.annual.mockPrice, "$29.99")
    }
}
