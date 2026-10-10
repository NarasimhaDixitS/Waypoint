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
            trialStartedAt: trialStart, plan: nil, until: nil, now: trialStart
        )
        XCTAssertEqual(status, .trial(daysLeft: SubscriptionPolicy.trialDays))
    }

    /// Days left rounds up: six hours from the end is "1 day left", never "0". Zero means over,
    /// and showing it while the app still works reads as a bug.
    /// Derived from `trialDays` rather than written as a date. These tests guard the *boundary*,
    /// and a literal date means changing the trial length silently moves them off the thing they
    /// were watching — which is exactly what happened at seven days to fourteen.
    private var trialEnds: Date {
        Calendar.current.date(byAdding: .day, value: SubscriptionPolicy.trialDays, to: trialStart)!
    }

    func testTheLastHoursStillReadAsOneDay() {
        let status = SubscriptionPolicy.resolve(
            trialStartedAt: trialStart, plan: nil, until: nil,
            now: trialEnds.addingTimeInterval(-6 * 3600)
        )
        XCTAssertEqual(status, .trial(daysLeft: 1))
    }

    func testTheTrialIsStillLiveOneSecondBeforeItEnds() {
        let status = SubscriptionPolicy.resolve(
            trialStartedAt: trialStart, plan: nil, until: nil,
            now: trialEnds.addingTimeInterval(-1)
        )
        XCTAssertEqual(status, .trial(daysLeft: 1))
        XCTAssertTrue(status.hasFullAccess)
    }

    func testTheTrialIsOverExactlyOnTheBoundary() {
        let status = SubscriptionPolicy.resolve(
            trialStartedAt: trialStart, plan: nil, until: nil, now: trialEnds
        )
        XCTAssertEqual(status, .free)
        XCTAssertFalse(status.hasFullAccess)
    }

    /// The whole point of the gate: what's already there stays usable.
    func testALapsedUserCannotCreateButIsNeverLockedOut() {
        XCTAssertFalse(SubscriptionStatus.free.hasFullAccess)
        XCTAssertTrue(SubscriptionStatus.trial(daysLeft: 3).hasFullAccess)
        XCTAssertTrue(SubscriptionStatus.subscribed(plan: .annual, until: .now, renewal: .renewing).hasFullAccess)
    }

    func testAnActiveSubscriptionOutranksAnExpiredTrial() {
        let renews = date(2027, 9, 1)
        let status = SubscriptionPolicy.resolve(
            trialStartedAt: trialStart, plan: .annual, until: renews,
            now: date(2026, 12, 1)
        )
        XCTAssertEqual(status, .subscribed(plan: .annual, until: renews, renewal: .renewing))
    }

    /// A lapsed subscription falls back to the trial rules rather than staying entitled —
    /// otherwise a cancelled subscriber keeps everything forever.
    func testALapsedSubscriptionExpires() {
        let status = SubscriptionPolicy.resolve(
            trialStartedAt: trialStart, plan: .monthly, until: date(2026, 10, 1),
            now: date(2026, 11, 1)
        )
        XCTAssertEqual(status, .free)
    }

    /// No trial stamped yet means it hasn't started, not that it's over. Defaulting to expired
    /// here would lock out a fresh install that reached this before the stamp was written.
    func testAMissingTrialStampIsTreatedAsNotStarted() {
        let status = SubscriptionPolicy.resolve(
            trialStartedAt: nil, plan: nil, until: nil, now: .now
        )
        XCTAssertEqual(status, .trial(daysLeft: SubscriptionPolicy.trialDays))
    }

    func testOnlyTheAnnualPlanClaimsASaving() {
        XCTAssertNil(SubscriptionPlan.monthly.savingNote)
        XCTAssertNotNil(SubscriptionPlan.annual.savingNote)
    }

    // MARK: - Free tier

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: 9))!
    }

    /// The line the whole tier rests on: look back for free, pay to plan forward.
    func testFreeTierCanLookBackAndAtTodayButNotForward() {
        let now = day(2026, 10, 1)
        let free = SubscriptionStatus.free

        XCTAssertTrue(free.canViewDay(day(2026, 9, 24), now: now), "finished work belongs to whoever did it")
        XCTAssertTrue(free.canViewDay(now, now: now))
        XCTAssertFalse(free.canViewDay(day(2026, 10, 2), now: now), "planning ahead is the thing being sold")
    }

    /// Readable is not editable. A past day stays legible so nobody's history is held hostage,
    /// but it can't be rewritten.
    func testFreeTierCanOnlyEditToday() {
        let now = day(2026, 10, 1)
        let free = SubscriptionStatus.free

        XCTAssertTrue(free.canEditDay(now, now: now))
        XCTAssertFalse(free.canEditDay(day(2026, 9, 30), now: now))
        XCTAssertFalse(free.canEditDay(day(2026, 10, 2), now: now))
    }

    /// Paying removes every one of these limits, and that has to be checked explicitly — a gate
    /// that accidentally applies to a subscriber is worse than one that leaks.
    func testPayingLiftsEveryDayLimit() {
        let now = day(2026, 10, 1)
        for status in [SubscriptionStatus.trial(daysLeft: 3),
                       .subscribed(plan: .annual, until: day(2027, 10, 1), renewal: .renewing)] {
            XCTAssertTrue(status.canViewDay(day(2026, 12, 25), now: now))
            XCTAssertTrue(status.canEditDay(day(2026, 12, 25), now: now))
            XCTAssertTrue(status.canUseWeekTab)
            XCTAssertTrue(status.canUseProgress)
            XCTAssertTrue(status.canCreateGoal(existingCount: 99))
        }
    }

    /// The bug this was found by: on the free tier an overdue task from yesterday could still be
    /// pushed to today, through the reschedule button an overdue row carries. The rule below was
    /// already right — what was wrong is that a row has three ways into its editor (tapping it,
    /// that button, and the goal page's list) and only one of them asked.
    ///
    /// Keyed on the task's own date rather than the day being browsed: those usually agree, and
    /// only one of them is the real question.
    func testYesterdaysOverdueWorkCannotBeRescheduledOnTheFreeTier() {
        let now = day(2026, 10, 1)
        let yesterday = day(2026, 9, 30)

        XCTAssertFalse(SubscriptionStatus.free.canEditDay(yesterday, now: now))
        XCTAssertTrue(SubscriptionStatus.free.canViewDay(yesterday, now: now), "but it must still be visible")
        XCTAssertTrue(SubscriptionStatus.free.canEditDay(now, now: now), "and today must stay fully editable")
    }

    func testFreeTierLosesTheWeekAndProgressTabs() {
        XCTAssertFalse(SubscriptionStatus.free.canUseWeekTab)
        XCTAssertFalse(SubscriptionStatus.free.canUseProgress)
    }

    /// The limit is on creating, never on having. Somebody who made four goals during the trial
    /// keeps four — choosing three of someone's goals to take away is the hostage problem in a
    /// different coat.
    func testFreeTierBlocksASecondGoalButNeverRemovesExistingOnes() {
        XCTAssertTrue(SubscriptionStatus.free.canCreateGoal(existingCount: 0))
        XCTAssertFalse(SubscriptionStatus.free.canCreateGoal(existingCount: 1))
        XCTAssertFalse(SubscriptionStatus.free.canCreateGoal(existingCount: 4))
    }

    /// Two weeks, not one. A planner is judged over a week of real use, and a trial ending
    /// before the second Monday never gets that chance.
    func testTrialRunsForFourteenDays() {
        XCTAssertEqual(SubscriptionPolicy.trialDays, 14)
        let started = day(2026, 10, 1)
        let onLastDay = SubscriptionPolicy.resolve(
            trialStartedAt: started, plan: nil, until: nil, now: day(2026, 10, 14)
        )
        let afterwards = SubscriptionPolicy.resolve(
            trialStartedAt: started, plan: nil, until: nil, now: day(2026, 10, 16)
        )
        XCTAssertEqual(onLastDay, .trial(daysLeft: 1))
        XCTAssertEqual(afterwards, .free)
    }

    /// There is no introductory offer any more, so there is no second price to disclose and
    /// nothing to be deceptive about. What has to stay true is the one claim the paywall still
    /// makes: that annual is the better value.
    func testTheAnnualPlanIsActuallyTheBetterValue() {
        let monthly = Double(SubscriptionPlan.monthly.mockPrice.dropFirst())!
        let annual = Double(SubscriptionPlan.annual.mockPrice.dropFirst())!
        XCTAssertLessThan(annual, monthly * 12, "a yearly plan costing more than paying monthly is not a plan")
    }

    /// Product identifiers cannot be changed once App Store Connect has them, and a subscriber's
    /// purchase is tied to the string. A typo here is unrecoverable, so it is pinned.
    func testProductIdentifiersMatchAppStoreConnect() {
        XCTAssertEqual(SubscriptionPlan.monthly.productID, "waypoint.pro.monthly")
        XCTAssertEqual(SubscriptionPlan.annual.productID, "waypoint.pro.annual")
        XCTAssertEqual(Set(SubscriptionPlan.allCases.map(\.productID)).count, SubscriptionPlan.allCases.count)
    }

}
