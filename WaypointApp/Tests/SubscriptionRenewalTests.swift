import XCTest
@testable import Waypoint

/// What happens at the end of the paid period — the fact the app used to discard.
///
/// A tester bought the annual plan, cancelled it, and the app went on telling her it would
/// renew. `Store` was keeping only the expiry date from Apple's answer and throwing `willRenew`
/// away, so "renewing" and "cancelled" were the same value all the way through the app. The
/// screen somebody opens to confirm their cancellation worked was the screen that denied it.
final class SubscriptionRenewalTests: XCTestCase {

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d))!
    }

    // MARK: - Reading Apple's answer

    func testARenewingSubscriptionIsRenewing() {
        XCTAssertEqual(Renewal.from(willRenew: true, billingIssueDetectedAt: nil), .renewing)
    }

    func testAutoRenewOffMeansCancelled() {
        XCTAssertEqual(Renewal.from(willRenew: false, billingIssueDetectedAt: nil), .cancelled)
    }

    /// The one the customer can actually do something about wins the label.
    func testADeclinedCardOutranksEverythingElse() {
        XCTAssertEqual(
            Renewal.from(willRenew: true, billingIssueDetectedAt: .now), .billingProblem)
        XCTAssertEqual(
            Renewal.from(willRenew: false, billingIssueDetectedAt: .now), .billingProblem,
            "sending somebody to 'resubscribe' when their card was declined is the wrong screen")
    }

    // MARK: - Cancelling takes nothing away early

    /// She paid for the year. Cancelling is a decision about the *next* payment.
    func testCancellingKeepsEverythingUntilTheDate() {
        let status = SubscriptionPolicy.resolve(
            trialStartedAt: day(2026, 1, 1),   // long expired
            plan: .annual,
            until: day(2027, 10, 10),
            renewal: .cancelled,
            now: day(2026, 10, 12)
        )

        XCTAssertTrue(status.hasFullAccess)
        XCTAssertTrue(status.canUseWeekTab)
        XCTAssertTrue(status.canUseProgress)
        XCTAssertTrue(status.canEditDay(day(2026, 12, 25), now: day(2026, 10, 12)))
        XCTAssertTrue(status.canCreateGoal(existingCount: 99))
    }

    func testEveryLiveSubscriptionHasFullAccessWhateverHappensNext() {
        for renewal in [Renewal.renewing, .cancelled, .billingProblem] {
            let status = SubscriptionStatus.subscribed(
                plan: .monthly, until: day(2026, 11, 10), renewal: renewal)
            XCTAssertTrue(status.hasFullAccess, "\(renewal) must not cost anyone access they paid for")
        }
    }

    /// The bug itself. Access was never the problem — the *label* was.
    func testTheStatusSaysCancelledRatherThanRenewing() {
        let status = SubscriptionPolicy.resolve(
            trialStartedAt: day(2026, 1, 1), plan: .monthly,
            until: day(2026, 11, 10), renewal: .cancelled, now: day(2026, 10, 12)
        )

        XCTAssertEqual(status, .subscribed(plan: .monthly, until: day(2026, 11, 10), renewal: .cancelled))
        guard case .subscribed(_, _, let renewal) = status else { return XCTFail("not subscribed") }
        XCTAssertNotEqual(renewal, .renewing, "this is what told her the subscription she had just cancelled would renew")
    }

    // MARK: - And then it ends

    func testOnceTheDatePassesAccessDrops() {
        let status = SubscriptionPolicy.resolve(
            trialStartedAt: day(2026, 1, 1), plan: .monthly,
            until: day(2026, 11, 10), renewal: .cancelled, now: day(2026, 11, 11)
        )

        XCTAssertEqual(status, .free)
        XCTAssertFalse(status.canUseProgress)
        XCTAssertTrue(status.canViewDay(day(2026, 10, 1), now: day(2026, 11, 11)),
                      "history is never taken back")
    }

    /// A declined card is not an expiry. Apple retries for weeks and usually succeeds.
    func testABillingProblemDoesNotLockAnyoneOut() {
        let status = SubscriptionPolicy.resolve(
            trialStartedAt: day(2026, 1, 1), plan: .annual,
            until: day(2027, 10, 10), renewal: .billingProblem, now: day(2026, 10, 12)
        )

        XCTAssertTrue(status.hasFullAccess)
        guard case .subscribed(_, _, let renewal) = status else { return XCTFail("not subscribed") }
        XCTAssertEqual(renewal, .billingProblem, "they need telling, but not locking out")
    }

    // MARK: - A subscription still outranks the trial clock

    func testSubscribingDuringTheTrialReplacesIt() {
        let status = SubscriptionPolicy.resolve(
            trialStartedAt: day(2026, 10, 1),   // 5 days into a 14-day trial
            plan: .monthly, until: day(2026, 11, 5), renewal: .renewing,
            now: day(2026, 10, 5)
        )

        XCTAssertEqual(status, .subscribed(plan: .monthly, until: day(2026, 11, 5), renewal: .renewing),
                       "a paying customer is not on trial")
    }
}
