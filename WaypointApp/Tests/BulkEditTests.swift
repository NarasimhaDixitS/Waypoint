import XCTest
import CoreData
@testable import Waypoint

/// Covers the two pieces of bulk edit that can break silently: the forward-only rule, and the
/// fact that a bulk change still goes through the one instrumented write.
@MainActor
final class BulkEditTests: XCTestCase {
    var context: NSManagedObjectContext!

    override func setUp() {
        super.setUp()
        context = PersistenceController(inMemory: true).container.viewContext
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func makeTask(
        on date: Date,
        title: String = "Gym",
        priority: Priority = .medium,
        goal: GoalEntity? = nil
    ) -> TaskEntity {
        let start = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: date)!
        return TaskEntity.create(
            in: context, title: title, date: date, startTime: start,
            durationMinutes: 45, priority: priority, goal: goal
        )
    }

    private func events(_ kind: TaskEventKind? = nil) -> [TaskEventEntity] {
        (try? context.fetch(TaskEventEntity.fetchRequest(kind: kind))) ?? []
    }

    // MARK: - Forward only

    func testBulkEditingIsRefusedOnAPastDay() {
        let now = day(2026, 10, 7)

        XCTAssertFalse(
            BulkEditPolicy.allowsBulkEditing(on: day(2026, 10, 6), canEditDay: true, now: now),
            "Selecting a past day's tasks and deleting them in one tap is the move this app doesn't offer."
        )
    }

    func testBulkEditingIsAllowedTodayAndForward() {
        let now = day(2026, 10, 7)

        XCTAssertTrue(BulkEditPolicy.allowsBulkEditing(on: day(2026, 10, 7), canEditDay: true, now: now))
        XCTAssertTrue(BulkEditPolicy.allowsBulkEditing(on: day(2026, 10, 8), canEditDay: true, now: now))
        XCTAssertTrue(BulkEditPolicy.allowsBulkEditing(on: day(2026, 12, 25), canEditDay: true, now: now))
    }

    func testTodayCountsAsForwardAtAnyHour() {
        // The rule compares days, not instants. At 23:59 today is still today.
        let lateToday = Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: day(2026, 10, 7))!

        XCTAssertTrue(
            BulkEditPolicy.allowsBulkEditing(on: day(2026, 10, 7), canEditDay: true, now: lateToday)
        )
    }

    func testBulkEditingCannotRouteAroundTheFreeTier() {
        let now = day(2026, 10, 7)

        XCTAssertFalse(
            BulkEditPolicy.allowsBulkEditing(on: day(2026, 10, 9), canEditDay: false, now: now),
            "A day the subscription gate has closed stays closed, whatever the date says."
        )
    }

    // MARK: - currentDraft

    func testCurrentDraftRoundTripsTheTasksOwnValues() {
        let goal = GoalEntity.create(in: context, name: "Learn Spanish", targetDate: day(2026, 12, 1), planningMode: .manual)
        let task = makeTask(on: day(2026, 10, 9), title: "Verb drills", priority: .high, goal: goal)
        task.notes = "chapter 4"

        let draft = task.currentDraft

        XCTAssertEqual(draft.title, "Verb drills")
        XCTAssertEqual(draft.durationMinutes, 45)
        XCTAssertEqual(draft.priority, .high)
        XCTAssertEqual(draft.goal, goal)
        XCTAssertEqual(draft.notes, "chapter 4")
        XCTAssertEqual(Calendar.current.startOfDay(for: draft.date), day(2026, 10, 9))
    }

    func testCurrentDraftNeverCarriesRepeatOrSeriesInstructions() {
        let task = makeTask(on: day(2026, 10, 9))

        let draft = task.currentDraft

        // Both are instructions rather than stored values. Round-tripping them would make a
        // bulk priority change manufacture a second series, or silently rewrite every
        // sibling's reminder.
        XCTAssertTrue(draft.repeatWeekdays.isEmpty)
        XCTAssertFalse(draft.reminderAppliesToSeries)
    }

    // MARK: - Bulk changes stay instrumented

    func testChangingPriorityViaCurrentDraftStillLogsThePriorityChange() {
        let task = makeTask(on: day(2026, 10, 9), priority: .low)

        var draft = task.currentDraft
        draft.priority = .high
        task.apply(draft, in: context)

        XCTAssertEqual(events(.priorityChanged).count, 1,
                       "Bulk priority must not be the one route that writes priorityValue unlogged.")
        XCTAssertEqual(task.priorityValue, .high)
    }

    func testChangingGoalViaCurrentDraftMovesTheTaskWithoutLoggingADeferral() {
        let goal = GoalEntity.create(in: context, name: "Run a 10k", targetDate: day(2026, 12, 1), planningMode: .manual)
        let task = makeTask(on: day(2026, 10, 9))

        var draft = task.currentDraft
        draft.goal = goal
        task.apply(draft, in: context)

        XCTAssertEqual(task.goal, goal)
        XCTAssertTrue(events(.deferred).isEmpty, "Reassigning a goal doesn't move the task in time.")
    }

    func testBulkPriorityLeavesEveryOtherFieldAlone() {
        let goal = GoalEntity.create(in: context, name: "Learn Spanish", targetDate: day(2026, 12, 1), planningMode: .manual)
        let task = makeTask(on: day(2026, 10, 9), title: "Verb drills", priority: .low, goal: goal)
        let originalStart = task.resolvedStartTime

        var draft = task.currentDraft
        draft.priority = .high
        task.apply(draft, in: context)

        XCTAssertEqual(task.title, "Verb drills")
        XCTAssertEqual(task.resolvedStartTime, originalStart)
        XCTAssertEqual(Int(task.durationMinutes), 45)
        XCTAssertEqual(task.goal, goal)
    }
}
