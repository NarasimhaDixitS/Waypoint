import XCTest
import CoreData
@testable import Waypoint

@MainActor
final class TaskEventLogTests: XCTestCase {
    var context: NSManagedObjectContext!

    override func setUp() {
        super.setUp()
        context = PersistenceController(inMemory: true).container.viewContext
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func makeTask(on date: Date, done: Bool = false, goal: GoalEntity? = nil) -> TaskEntity {
        let start = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: date)!
        let task = TaskEntity.create(
            in: context, title: "Gym", date: date, startTime: start,
            durationMinutes: 30, priority: .medium, goal: goal
        )
        task.isDone = done
        return task
    }

    private func events(_ kind: TaskEventKind? = nil) -> [TaskEventEntity] {
        (try? context.fetch(TaskEventEntity.fetchRequest(kind: kind))) ?? []
    }

    // MARK: - Deferral

    func testApplyingADraftThatMovesTheTaskLater_recordsADeferral() {
        let task = makeTask(on: day(2026, 8, 31))
        let target = day(2026, 9, 3)

        task.apply(draft(for: task, on: target), in: context)

        let logged = events(.deferred)
        XCTAssertEqual(logged.count, 1)
        XCTAssertEqual(logged.first?.slipInDays, 3)
        XCTAssertEqual(logged.first?.taskID, task.id)
    }

    /// Pulling work *forward* isn't a slip. Counting it would make the deferral number
    /// measure "date edits" rather than "times I put something off."
    func testApplyingADraftThatMovesTheTaskEarlier_recordsNothing() {
        let task = makeTask(on: day(2026, 9, 3))

        task.apply(draft(for: task, on: day(2026, 8, 31)), in: context)

        XCTAssertTrue(events(.deferred).isEmpty)
    }

    func testEditingATaskWithoutChangingItsDay_recordsNothing() {
        let task = makeTask(on: day(2026, 8, 31))
        var edit = draft(for: task, on: day(2026, 8, 31))
        edit = TaskDraft(
            title: "Gym — heavier", date: edit.date, startTime: edit.startTime,
            durationMinutes: 90, priority: .high, notes: edit.notes, goal: edit.goal
        )

        task.apply(edit, in: context)

        XCTAssertEqual(task.title, "Gym — heavier", "the edit itself must still apply")
        XCTAssertTrue(events(.deferred).isEmpty)
    }

    /// The log has to outlive the thing it describes, which is why it holds a raw `taskID`
    /// rather than a relationship — a relationship would cascade the record away with the task.
    func testDeferralSurvivesDeletingTheTaskItDescribes() {
        let task = makeTask(on: day(2026, 8, 31))
        let id = task.id
        task.apply(draft(for: task, on: day(2026, 9, 7)), in: context)
        try? context.save()

        context.delete(task)
        try? context.save()

        let logged = events(.deferred)
        XCTAssertEqual(logged.count, 1)
        XCTAssertEqual(logged.first?.taskID, id)
        XCTAssertEqual(logged.first?.title, "Gym", "a deleted task still has to be legible")
    }

    func testDeferralCarriesTheGoalItBelongsTo() {
        let goal = GoalEntity.create(in: context, name: "Weight Loss", targetDate: day(2026, 12, 1), planningMode: .manual)
        let task = makeTask(on: day(2026, 8, 31), goal: goal)

        task.apply(draft(for: task, on: day(2026, 9, 1)), in: context)

        XCTAssertEqual(events(.deferred).first?.goalID, goal.id)
    }

    // MARK: - Abandonment

    func testDeletingAnUnfinishedTaskWhoseDayHasPassed_isAbandonment() {
        let task = makeTask(on: day(2026, 8, 25))

        TaskEventLog.recordAbandonmentIfNeeded(task: task, in: context, now: day(2026, 8, 31))

        XCTAssertEqual(events(.abandoned).count, 1)
    }

    /// The boundary: a task due today that you delete today counts — its day has arrived.
    func testDeletingAnUnfinishedTaskDueToday_isAbandonment() {
        let task = makeTask(on: day(2026, 8, 31))

        TaskEventLog.recordAbandonmentIfNeeded(task: task, in: context, now: day(2026, 8, 31))

        XCTAssertEqual(events(.abandoned).count, 1)
    }

    /// Deleting something scheduled for next week is a plan changing, not a failure.
    func testDeletingATaskStillInTheFuture_recordsNothing() {
        let task = makeTask(on: day(2026, 9, 7))

        TaskEventLog.recordAbandonmentIfNeeded(task: task, in: context, now: day(2026, 8, 31))

        XCTAssertTrue(events(.abandoned).isEmpty)
    }

    /// Deleting a task you actually finished is housekeeping.
    func testDeletingACompletedTask_recordsNothing() {
        let task = makeTask(on: day(2026, 8, 25), done: true)

        TaskEventLog.recordAbandonmentIfNeeded(task: task, in: context, now: day(2026, 8, 31))

        XCTAssertTrue(events(.abandoned).isEmpty)
    }

    // MARK: - Goal abandonment

    func testDeletingAnUnfinishedGoal_recordsOneRowNotOnePerTask() {
        let goal = GoalEntity.create(in: context, name: "Weight Loss", targetDate: day(2026, 12, 1), planningMode: .manual)
        for offset in 0..<20 {
            _ = makeTask(on: day(2026, 9, 1 + offset), goal: goal)
        }

        TaskEventLog.recordGoalAbandonmentIfNeeded(goal: goal, in: context, now: day(2026, 9, 15))

        let logged = events(.goalAbandoned)
        XCTAssertEqual(logged.count, 1, "one decision, one row — not one per task")
        XCTAssertEqual(logged.first?.goalID, goal.id)
        XCTAssertEqual(logged.first?.title, "Weight Loss")
    }

    /// The goal's own span rides along, so "how far in did they quit" is answerable later
    /// without the log needing fields of its own.
    func testGoalAbandonmentCarriesTheGoalsSpan() {
        let goal = GoalEntity.create(in: context, name: "Weight Loss", targetDate: day(2026, 12, 1), planningMode: .manual)
        _ = makeTask(on: day(2026, 9, 1), goal: goal)

        TaskEventLog.recordGoalAbandonmentIfNeeded(goal: goal, in: context, now: day(2026, 9, 15))

        let logged = try! XCTUnwrap(events(.goalAbandoned).first)
        XCTAssertNotNil(logged.fromDate)
        XCTAssertEqual(
            Calendar.current.startOfDay(for: try! XCTUnwrap(logged.toDate)),
            Calendar.current.startOfDay(for: day(2026, 12, 1))
        )
    }

    /// Deleting a goal you actually finished is housekeeping, the same rule tasks follow.
    func testDeletingAFullyCompletedGoal_recordsNothing() {
        let goal = GoalEntity.create(in: context, name: "Weight Loss", targetDate: day(2026, 12, 1), planningMode: .manual)
        for offset in 0..<3 {
            _ = makeTask(on: day(2026, 9, 1 + offset), done: true, goal: goal)
        }

        TaskEventLog.recordGoalAbandonmentIfNeeded(goal: goal, in: context, now: day(2026, 9, 15))

        XCTAssertTrue(events(.goalAbandoned).isEmpty)
    }

    // MARK: - Fetching

    func testFetchRequestFiltersByKindAndWindow() {
        let old = makeTask(on: day(2026, 8, 25))
        TaskEventLog.recordAbandonmentIfNeeded(task: old, in: context, now: day(2026, 8, 1))
        let recent = makeTask(on: day(2026, 8, 25))
        TaskEventLog.recordAbandonmentIfNeeded(task: recent, in: context, now: day(2026, 8, 30))

        let request = TaskEventEntity.fetchRequest(kind: .abandoned, since: day(2026, 8, 15))
        let found = (try? context.fetch(request)) ?? []

        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.taskID, recent.id)
    }

    private func draft(for task: TaskEntity, on date: Date) -> TaskDraft {
        let cal = Calendar.current
        let timeOfDay = cal.dateComponents([.hour, .minute], from: task.resolvedStartTime)
        return TaskDraft(
            title: task.title ?? "",
            date: date,
            startTime: cal.date(byAdding: timeOfDay, to: cal.startOfDay(for: date)) ?? date,
            durationMinutes: Int(task.durationMinutes),
            priority: task.priorityValue,
            notes: task.notes,
            goal: task.goal
        )
    }
}
