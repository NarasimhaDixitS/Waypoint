import XCTest
import CoreData
@testable import Waypoint

@MainActor
final class ScheduleEngineTests: XCTestCase {
    var context: NSManagedObjectContext!

    override func setUp() {
        super.setUp()
        context = PersistenceController(inMemory: true).container.viewContext
        SleepSettings.shared.startTimeOfDay = time(23, 0)
        SleepSettings.shared.durationMinutes = 7 * 60
    }

    private func time(_ hour: Int, _ minute: Int, on day: Date = .now) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    @discardableResult
    private func makeTask(
        title: String,
        start: Date,
        duration: Int,
        priority: Priority = .medium
    ) -> TaskEntity {
        TaskEntity.create(in: context, title: title, date: start, startTime: start, durationMinutes: duration, priority: priority)
    }

    private func assertNone(_ resolution: EditResolution, file: StaticString = #filePath, line: UInt = #line) {
        guard case .none = resolution else {
            return XCTFail("expected .none, got \(resolution)", file: file, line: line)
        }
    }

    private func assertNone(_ resolution: NewTaskResolution, file: StaticString = #filePath, line: UInt = #line) {
        guard case .none = resolution else {
            return XCTFail("expected .none, got \(resolution)", file: file, line: line)
        }
    }

    // MARK: - resolveTimeMove (new task / moved task collisions)

    func testTimeMove_intoEmptySlot_returnsNone() {
        let task = makeTask(title: "A", start: time(9, 0), duration: 30)
        let resolution = ScheduleEngine.resolveTimeMove(task: task, newStart: time(14, 0), newDurationMinutes: 30, context: context)
        assertNone(resolution)
    }

    func testTimeMove_ontoAnotherTask_returnsHardBumpWithThatTask() {
        let a = makeTask(title: "A", start: time(9, 0), duration: 30)
        let b = makeTask(title: "B", start: time(14, 0), duration: 30)

        let resolution = ScheduleEngine.resolveTimeMove(task: a, newStart: time(14, 15), newDurationMinutes: 30, context: context)
        guard case .hardBump(let candidates, _) = resolution else {
            return XCTFail("expected hardBump, got \(resolution)")
        }
        XCTAssertEqual(candidates.map(\.objectID), [b.objectID])
    }

    func testTimeMove_intoSleepWindow_returnsHardBumpBlockedBySleep() {
        let task = makeTask(title: "Late task", start: time(9, 0), duration: 30)
        let resolution = ScheduleEngine.resolveTimeMove(task: task, newStart: time(23, 30), newDurationMinutes: 30, context: context)
        guard case .hardBump(_, let blockedBy) = resolution else {
            return XCTFail("expected hardBump, got \(resolution)")
        }
        XCTAssertEqual(blockedBy, "sleep")
    }

    func testTimeMove_ontoNextTask_cascadesItLater() {
        let a = makeTask(title: "A", start: time(9, 0), duration: 30)
        let b = makeTask(title: "B", start: time(10, 0), duration: 30)

        // Dragging A to 9:45 (ending 10:15) now overlaps B — push B later instead of bumping.
        let resolution = ScheduleEngine.resolveTimeMove(task: a, newStart: time(9, 45), newDurationMinutes: 30, context: context)
        guard case .cascade(let shifts) = resolution else {
            return XCTFail("expected cascade, got \(resolution)")
        }
        XCTAssertEqual(shifts.map(\.task.objectID), [b.objectID])
        XCTAssertEqual(shifts.first?.newStart, time(10, 15))
    }

    func testTimeMove_cascadeChainRunsIntoSleep_returnsHardBump() {
        let a = makeTask(title: "A", start: time(9, 0), duration: 30)
        let b = makeTask(title: "B", start: time(22, 40), duration: 15) // 22:40-22:55

        // Moving A to 22:30-22:50 pushes B to start at 22:50; B's 15-min slot would then end
        // at 23:05, past the 23:00 sleep boundary — no room even with cascading.
        let resolution = ScheduleEngine.resolveTimeMove(task: a, newStart: time(22, 30), newDurationMinutes: 20, context: context)
        guard case .hardBump(let candidates, let blockedBy) = resolution else {
            return XCTFail("expected hardBump, got \(resolution)")
        }
        XCTAssertEqual(candidates.map(\.objectID), [b.objectID])
        XCTAssertEqual(blockedBy, "sleep")
    }

    // MARK: - resolveNewTask (brand-new, not-yet-persisted task)

    func testNewTask_intoEmptySlot_returnsNone() {
        let resolution = ScheduleEngine.resolveNewTask(start: time(9, 0), end: time(9, 30), on: time(9, 0), context: context)
        assertNone(resolution)
    }

    func testNewTask_overlappingFixedCommitment_returnsNone() {
        // Fixed commitments (Work, Gym, Team meeting, ...) are informational only and never
        // block scheduling — only sleep and other tasks do.
        _ = CommitmentEntity.create(
            in: context,
            name: "Gym",
            icon: "gym",
            days: CommitmentEntity.weekdaySymbols,
            startTime: time(7, 0),
            endTime: time(8, 0)
        )
        let resolution = ScheduleEngine.resolveNewTask(start: time(7, 30), end: time(8, 30), on: time(7, 30), context: context)
        assertNone(resolution)
    }

    func testNewTask_ontoAnotherTask_choosesEarliestGapInWholeDay() {
        // Free 7:00-9:00 gap between "Early" and "Existing" should win over just appending
        // after whatever the new task happened to collide with.
        makeTask(title: "Early", start: time(6, 0), duration: 60) // 6:00-7:00
        let existing = makeTask(title: "Existing", start: time(9, 0), duration: 30) // 9:00-9:30
        let resolution = ScheduleEngine.resolveNewTask(start: time(9, 15), end: time(9, 45), on: time(9, 15), context: context)
        guard case .appendable(let appendStart, let candidates, _) = resolution else {
            return XCTFail("expected appendable, got \(resolution)")
        }
        XCTAssertEqual(candidates.map(\.objectID), [existing.objectID])
        XCTAssertEqual(appendStart, time(7, 0)) // the gap between Early and Existing, not 9:30
    }

    func testNewTask_ontoAnotherTask_withNoRoomAnywhereInDay_returnsHardBump() {
        // Occupies the entire day, leaving only a 30-minute tail before sleep — too small
        // for the 60-minute task being requested, and there's no gap anywhere else either.
        let existing = makeTask(title: "Existing", start: time(6, 0), duration: 16 * 60 + 30) // 6:00-22:30
        let resolution = ScheduleEngine.resolveNewTask(start: time(22, 0), end: time(23, 0), on: time(22, 0), context: context)
        guard case .hardBump(let candidates, _) = resolution else {
            return XCTFail("expected hardBump, got \(resolution)")
        }
        XCTAssertEqual(candidates.map(\.objectID), [existing.objectID])
    }

    // MARK: - resolveDurationIncrease (cascade vs. hard bump)

    func testDurationIncrease_noDownstreamTask_returnsNone() {
        let task = makeTask(title: "Solo", start: time(9, 0), duration: 30)
        let resolution = ScheduleEngine.resolveDurationIncrease(task: task, newDurationMinutes: 60, context: context)
        assertNone(resolution)
    }

    func testDurationIncrease_overlapsNextTask_cascadesItLater() {
        let a = makeTask(title: "A", start: time(9, 0), duration: 30) // 9:00-9:30
        let b = makeTask(title: "B", start: time(9, 30), duration: 30) // 9:30-10:00, back-to-back

        // Grow A to 9:00-10:00, which now needs to push B to 10:00
        let resolution = ScheduleEngine.resolveDurationIncrease(task: a, newDurationMinutes: 60, context: context)
        guard case .cascade(let shifts) = resolution else {
            return XCTFail("expected cascade, got \(resolution)")
        }
        XCTAssertEqual(shifts.count, 1)
        XCTAssertEqual(shifts.first?.task.objectID, b.objectID)
        XCTAssertEqual(shifts.first?.newStart, time(10, 0))
    }

    func testDurationIncrease_withGapAfterNextTask_doesNotCascadeBeyondIt() {
        let a = makeTask(title: "A", start: time(9, 0), duration: 30)
        let b = makeTask(title: "B", start: time(9, 30), duration: 15) // 9:30-9:45
        makeTask(title: "C", start: time(11, 0), duration: 30) // far enough away, has a gap

        let resolution = ScheduleEngine.resolveDurationIncrease(task: a, newDurationMinutes: 45, context: context) // 9:00-9:45
        guard case .cascade(let shifts) = resolution else {
            return XCTFail("expected cascade, got \(resolution)")
        }
        // Only B needs to move (to 9:45); C already has room and shouldn't be touched.
        XCTAssertEqual(shifts.map(\.task.objectID), [b.objectID])
    }

    func testDurationIncrease_wouldRunIntoHighPriorityTask_returnsHardBump() {
        let a = makeTask(title: "A", start: time(9, 0), duration: 30, priority: .medium)
        let protectedTask = makeTask(title: "Protected", start: time(9, 30), duration: 30, priority: .high)

        let resolution = ScheduleEngine.resolveDurationIncrease(task: a, newDurationMinutes: 60, context: context)
        guard case .hardBump(_, let blockedBy) = resolution else {
            return XCTFail("expected hardBump, got \(resolution)")
        }
        XCTAssertEqual(blockedBy, protectedTask.title)
    }

    func testDurationIncrease_pastEndOfDayIntoSleep_returnsHardBump() {
        let task = makeTask(title: "Evening", start: time(22, 30), duration: 20) // 22:30-22:50
        let resolution = ScheduleEngine.resolveDurationIncrease(task: task, newDurationMinutes: 60, context: context) // would end 23:30, into sleep at 23:00
        guard case .hardBump(_, let blockedBy) = resolution else {
            return XCTFail("expected hardBump, got \(resolution)")
        }
        XCTAssertEqual(blockedBy, "sleep")
    }

    // MARK: - earliestOpenSlot (new-task smart defaults)

    func testEarliestOpenSlot_emptyDay_startsRightAfterMorningSleep() {
        let slot = ScheduleEngine.earliestOpenSlot(on: time(12, 0), context: context)
        XCTAssertEqual(slot?.start, time(6, 0)) // sleep is 23:00-06:00
        XCTAssertEqual(slot?.availableMinutes, 17 * 60) // 06:00 to 23:00
    }

    func testEarliestOpenSlot_withTaskLater_returnsGapBeforeIt() {
        makeTask(title: "Standup", start: time(9, 0), duration: 30)
        let slot = ScheduleEngine.earliestOpenSlot(on: time(12, 0), context: context)
        XCTAssertEqual(slot?.start, time(6, 0))
        XCTAssertEqual(slot?.availableMinutes, 3 * 60) // 06:00 to 09:00
    }

    func testEarliestOpenSlot_respectsNotBefore_forToday() {
        let slot = ScheduleEngine.earliestOpenSlot(on: time(12, 0), notBefore: time(10, 0), context: context)
        XCTAssertEqual(slot?.start, time(10, 0))
        XCTAssertEqual(slot?.availableMinutes, 13 * 60) // 10:00 to 23:00
    }

    func testEarliestOpenSlot_noRoomLeftBeforeSleep_returnsNil() {
        let slot = ScheduleEngine.earliestOpenSlot(on: time(12, 0), notBefore: time(23, 30), context: context)
        XCTAssertNil(slot)
    }

    func testEarliestOpenSlot_backToBackTasksAllDay_returnsGapAfterLast() {
        makeTask(title: "Morning block", start: time(6, 0), duration: 60) // 06:00-07:00
        makeTask(title: "Next block", start: time(7, 0), duration: 60) // 07:00-08:00
        let slot = ScheduleEngine.earliestOpenSlot(on: time(12, 0), context: context)
        XCTAssertEqual(slot?.start, time(8, 0))
        XCTAssertEqual(slot?.availableMinutes, 15 * 60) // 08:00 to 23:00
    }
}
