import XCTest
@testable import Waypoint

/// A session has to survive the sheet closing, the app being suspended, and the app being
/// killed — all of which it previously didn't.
final class ActiveFocusSessionTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ActiveFocusStore.clear()
    }

    override func tearDown() {
        ActiveFocusStore.clear()
        super.tearDown()
    }

    private func running(minutes: Int, remaining: Int, banked: Int = 0, task: UUID? = nil) -> ActiveFocusSession {
        ActiveFocusSession(
            taskID: task,
            taskTitle: "Deep work",
            selectedMinutes: minutes,
            endsAt: Date().addingTimeInterval(TimeInterval(remaining)),
            pausedRemaining: remaining,
            bankedSeconds: banked,
            startedAt: Date().addingTimeInterval(-TimeInterval(minutes * 60 - remaining))
        )
    }

    // MARK: - It comes back

    func testASessionSurvivesBeingWrittenAndReadBack() {
        let session = running(minutes: 40, remaining: 900, banked: 120)
        ActiveFocusStore.current = session

        let restored = ActiveFocusStore.current
        XCTAssertEqual(restored?.selectedMinutes, 40)
        XCTAssertEqual(restored?.bankedSeconds, 120)
        XCTAssertEqual(restored?.taskTitle, "Deep work")
    }

    /// The whole point of storing an end date rather than a tick count.
    func testRemainingIsReadFromTheClockNotFromTicks() {
        var session = running(minutes: 40, remaining: 600)
        session.endsAt = Date().addingTimeInterval(300)

        XCTAssertEqual(session.remaining(), 300, accuracy: 1,
                       "a suspended app fires no timer; the clock still moved")
    }

    func testAPausedSessionHoldsItsRemainingTime() {
        var session = running(minutes: 40, remaining: 600)
        session.endsAt = nil
        session.pausedRemaining = 600

        XCTAssertEqual(session.remaining(at: Date().addingTimeInterval(3600)), 600,
                       "an hour passing while paused must not drain a paused timer")
    }

    // MARK: - Focused time stays honest

    func testAPausedSessionBanksOnlyWhatWasActuallyRun() {
        var session = running(minutes: 40, remaining: 600, banked: 420)
        session.endsAt = nil

        XCTAssertEqual(session.focusedSeconds(totalMinutes: 40), 420,
                       "a timer left paused over lunch must not claim the lunch")
    }

    func testARunningSessionCountsTheLiveStretch() {
        // 40 minutes, 10 left, 5 minutes banked from before — so 25 of this stretch are live.
        let session = running(minutes: 40, remaining: 600, banked: 300)

        XCTAssertEqual(session.focusedSeconds(totalMinutes: 40), 1800, accuracy: 2)
    }

    // MARK: - Whose session is it

    func testASessionBelongsToOneTask() {
        let mine = UUID()
        let session = running(minutes: 40, remaining: 600, task: mine)

        XCTAssertTrue(session.matches(taskID: mine))
        XCTAssertFalse(session.matches(taskID: UUID()))
        XCTAssertFalse(session.matches(taskID: nil), "a free session is not every task's session")
    }

    func testClearingLeavesNothingBehind() {
        ActiveFocusStore.current = running(minutes: 25, remaining: 100)
        ActiveFocusStore.clear()

        XCTAssertNil(ActiveFocusStore.current)
    }
}
