import XCTest
@testable import Waypoint

/// The trial clock, which has to outlive the app being deleted.
///
/// Each test uses its own keychain account and clears it afterwards, so these don't collide with
/// each other or with the real one the simulator's installed build is using.
final class TrialRecordTests: XCTestCase {
    private var account = ""

    override func setUp() {
        super.setUp()
        account = "test.\(UUID().uuidString)"
        TrialRecord.clear(account: account)
    }

    override func tearDown() {
        TrialRecord.clear(account: account)
        UserDefaults.standard.removeObject(forKey: "subscription.trialStartedAt")
        super.tearDown()
    }

    private let instant = Date(timeIntervalSince1970: 1_790_000_000)

    func testADateSurvivesARoundTrip() throws {
        XCTAssertTrue(TrialRecord.setStart(instant, account: account))
        let read = try XCTUnwrap(TrialRecord.start(account: account))
        XCTAssertEqual(read.timeIntervalSince1970, instant.timeIntervalSince1970, accuracy: 0.001)
    }

    /// Nothing recorded means the trial hasn't begun, never that it's over. A keychain that
    /// can't be read is a reason to let someone use the app, not to lock them out of it.
    func testAnAbsentRecordReadsAsNothingRatherThanAsExpired() {
        XCTAssertNil(TrialRecord.start(account: account))
    }

    /// `SecItemAdd` fails outright on a duplicate, so a write-once implementation would make
    /// every later write silently do nothing — and "Reset trial" would appear to work while
    /// changing not a thing.
    func testWritingTwiceOverwritesRatherThanFailing() throws {
        TrialRecord.setStart(instant, account: account)
        let later = instant.addingTimeInterval(86_400)

        XCTAssertTrue(TrialRecord.setStart(later, account: account))
        let read = try XCTUnwrap(TrialRecord.start(account: account))
        XCTAssertEqual(read.timeIntervalSince1970, later.timeIntervalSince1970, accuracy: 0.001)
    }

    /// The point of the whole change: this is the value a reinstall used to wipe. It must not be
    /// recoverable from `UserDefaults` alone, or it is exactly as fragile as it was before.
    func testTheTrialStartIsNotKeptOnlyInUserDefaults() {
        UserDefaults.standard.removeObject(forKey: "subscription.trialStartedAt")
        TrialRecord.setStart(instant, account: account)

        XCTAssertNotNil(TrialRecord.start(account: account))
        XCTAssertNil(UserDefaults.standard.object(forKey: "subscription.trialStartedAt"),
                     "a value only in UserDefaults is deleted with the app")
    }

    /// Somebody mid-trial when they update must not have their clock restarted by the upgrade
    /// that moved where it's stored.
    func testAnExistingUserDefaultsTrialIsCarriedOverRatherThanRestarted() throws {
        let started = instant.addingTimeInterval(-5 * 86_400)
        UserDefaults.standard.set(started, forKey: "subscription.trialStartedAt")

        let resolved = TrialRecord.startOrBegin(now: instant, account: account)

        XCTAssertEqual(resolved.timeIntervalSince1970, started.timeIntervalSince1970, accuracy: 0.001)
        let stored = try XCTUnwrap(TrialRecord.start(account: account), "it should have moved into the keychain")
        XCTAssertEqual(stored.timeIntervalSince1970, started.timeIntervalSince1970, accuracy: 0.001)
    }

    /// A fresh install stamps now, and every launch after that reads the same date back — a
    /// trial that restarts itself each time the app opens is worse than no trial at all.
    func testAFirstRunStampsNowAndThenStaysPut() {
        let first = TrialRecord.startOrBegin(now: instant, account: account)
        let second = TrialRecord.startOrBegin(now: instant.addingTimeInterval(3 * 86_400), account: account)

        XCTAssertEqual(first.timeIntervalSince1970, instant.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(second.timeIntervalSince1970, first.timeIntervalSince1970, accuracy: 0.001)
    }

    /// And the trial really does end, measured from the stored start.
    func testAStoredStartOlderThanTheTrialResolvesToTheFreeTier() {
        let longAgo = instant.addingTimeInterval(-Double(SubscriptionPolicy.trialDays + 2) * 86_400)
        TrialRecord.setStart(longAgo, account: account)

        let status = SubscriptionPolicy.resolve(
            trialStartedAt: TrialRecord.start(account: account),
            plan: nil, until: nil, now: instant
        )
        XCTAssertEqual(status, .free)
    }
}
