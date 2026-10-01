import XCTest
import CoreData
@testable import Waypoint

/// The reminder rules, tested because every one of them fails *invisibly*.
///
/// iOS accepts an over-budget notification request and silently drops it; a reminder that was
/// never scheduled looks exactly like a reminder that was scheduled and didn't matter. Nothing
/// on screen goes wrong, so the only place a mistake here can be caught is in here.
@MainActor
final class NotificationSchedulingTests: XCTestCase {
    var context: NSManagedObjectContext!
    let now = Date(timeIntervalSince1970: 1_790_000_000) // a fixed, arbitrary instant

    override func setUp() {
        super.setUp()
        context = PersistenceController(inMemory: true).container.viewContext
    }

    @discardableResult
    private func task(
        hoursFromNow: Double,
        priority: Priority = .medium,
        reminder: Bool = true,
        lead: Int32 = TaskEntity.reminderLeadFollowsPriority,
        done: Bool = false
    ) -> TaskEntity {
        let start = now.addingTimeInterval(hoursFromNow * 3600)
        let task = TaskEntity.create(
            in: context, title: "T\(hoursFromNow)", date: start, startTime: start,
            durationMinutes: 30, priority: priority,
            reminderEnabled: reminder, reminderLeadMinutes: lead
        )
        task.isDone = done
        return task
    }

    private func all() -> [TaskEntity] { (try? context.fetch(TaskEntity.fetchRequest())) ?? [] }

    // MARK: - Opt-in

    /// The whole point of the change: a task nobody armed must not produce a notification,
    /// however important it is or however on the master switch is.
    func testOnlyTasksWithAReminderAreScheduled() {
        task(hoursFromNow: 2, reminder: true)
        task(hoursFromNow: 3, priority: .high, reminder: false)

        let due = NotificationManager.remindableTasks(from: all(), now: now)

        XCTAssertEqual(due.count, 1)
        XCTAssertEqual(due.first?.title, "T2.0")
    }

    /// A task finished early still has a start time in the future. Reminding someone about work
    /// they've already done is the fastest way to teach them to ignore the next one.
    func testFinishedWorkIsNotRemindedAbout() {
        task(hoursFromNow: 2, done: true)
        XCTAssertTrue(NotificationManager.remindableTasks(from: all(), now: now).isEmpty)
    }

    /// A reminder whose moment has already passed is not a reminder.
    func testAReminderAlreadyDueIsNotScheduled() {
        task(hoursFromNow: 0.05) // starts in 3 minutes, so a 10-minute lead fired 7 minutes ago
        XCTAssertTrue(NotificationManager.remindableTasks(from: all(), now: now).isEmpty)
    }

    // MARK: - Lead time

    func testLeadFollowsPriorityUntilSomebodyPinsOne() {
        let high = task(hoursFromNow: 5, priority: .high)
        let low = task(hoursFromNow: 6, priority: .low)
        let pinned = task(hoursFromNow: 7, priority: .low, lead: 45)

        XCTAssertEqual(high.resolvedReminderLeadMinutes, 15)
        XCTAssertEqual(low.resolvedReminderLeadMinutes, 5)
        XCTAssertEqual(pinned.resolvedReminderLeadMinutes, 45, "a pinned lead must survive its priority")
    }

    /// Zero is a real choice — "tell me as it starts" — so it can't double as the unset value.
    func testZeroIsAPinnedLeadNotAnUnsetOne() {
        let atStart = task(hoursFromNow: 5, priority: .high, lead: 0)
        XCTAssertEqual(atStart.resolvedReminderLeadMinutes, 0)
        XCTAssertEqual(atStart.reminderFireDate(now: now), atStart.resolvedStartTime)
    }

    // MARK: - Window

    /// Nothing wakes the app in the background to schedule these, so the window has to outlast a
    /// day nobody opens the app. It also has to stop: a nudge about next Thursday is not a
    /// reminder.
    func testTheWindowReachesPastTomorrowButNotIndefinitely() {
        task(hoursFromNow: 40)
        task(hoursFromNow: 100)

        let due = NotificationManager.remindableTasks(from: all(), now: now)

        XCTAssertEqual(due.map(\.title), ["T40.0"])
    }

    // MARK: - Budget

    /// iOS keeps 64 pending notifications per app and silently discards the rest, so the app has
    /// to do its own budgeting — there is no error to react to.
    func testTheQueueIsNeverFilledPastWhatIOSWillHold() {
        for index in 0..<90 { task(hoursFromNow: 1 + Double(index) * 0.1) }

        let due = NotificationManager.remindableTasks(from: all(), now: now)

        XCTAssertLessThanOrEqual(due.count, NotificationManager.maxPendingReminders)
        XCTAssertLessThan(due.count, 90, "the budget has to actually bite")
    }

    /// When there isn't room for everyone, importance decides who keeps a slot. Ordering by
    /// start time — which is what this did — drops the *latest* tasks, so a 9am errand would
    /// keep its reminder while a 10am interview silently lost one.
    func testWhenTheBudgetOverflowsImportanceWinsNotEarliness() {
        for index in 0..<80 { task(hoursFromNow: 1 + Double(index) * 0.1, priority: .low) }
        task(hoursFromNow: 47, priority: .high)

        let due = NotificationManager.remindableTasks(from: all(), now: now)

        XCTAssertEqual(due.first?.priorityValue, .high, "the one important task must come first")
        XCTAssertTrue(due.contains { $0.priorityValue == .high }, "and must not be the one dropped")
    }

    // MARK: - Series

    /// A habit reminder you have to re-arm every week is no reminder at all — but arming it must
    /// not rewrite history, which is what the Progress tab reads.
    func testApplyingToASeriesReachesFutureOccurrencesAndLeavesPastOnesAlone() {
        let seriesID = UUID()
        let cal = Calendar.current
        var made: [TaskEntity] = []
        for offset in [-7, 0, 7] {
            let day = cal.date(byAdding: .day, value: offset, to: now)!
            made.append(TaskEntity.create(
                in: context, title: "Habit", date: day, startTime: day,
                durationMinutes: 30, priority: .medium, seriesID: seriesID
            ))
        }
        let (past, today, future) = (made[0], made[1], made[2])

        var draft = TaskDraft(
            title: "Habit", date: today.resolvedDate, startTime: today.resolvedStartTime,
            durationMinutes: 30, priority: .medium
        )
        draft.reminderEnabled = true
        draft.reminderLeadMinutes = 30
        draft.reminderAppliesToSeries = true
        today.apply(draft, in: context, now: now)

        XCTAssertTrue(future.reminderEnabled)
        XCTAssertEqual(future.reminderLeadMinutes, 30)
        XCTAssertFalse(past.reminderEnabled, "a past occurrence is history, not plan")
    }

    /// Without the choice, editing one awkward occurrence would silently re-arm the whole habit.
    func testASingleOccurrenceCanBeArmedWithoutTouchingTheSeries() {
        let seriesID = UUID()
        let cal = Calendar.current
        let today = TaskEntity.create(
            in: context, title: "Habit", date: now, startTime: now,
            durationMinutes: 30, priority: .medium, seriesID: seriesID
        )
        let nextWeek = cal.date(byAdding: .day, value: 7, to: now)!
        let future = TaskEntity.create(
            in: context, title: "Habit", date: nextWeek, startTime: nextWeek,
            durationMinutes: 30, priority: .medium, seriesID: seriesID
        )

        var draft = TaskDraft(
            title: "Habit", date: today.resolvedDate, startTime: today.resolvedStartTime,
            durationMinutes: 30, priority: .medium
        )
        draft.reminderEnabled = true
        today.apply(draft, in: context, now: now)

        XCTAssertTrue(today.reminderEnabled)
        XCTAssertFalse(future.reminderEnabled)
    }

    // MARK: - Wording

    func testLeadWordingReadsAsEnglishAtEveryOfferedValue() {
        XCTAssertEqual(NotificationManager.leadDescription(minutes: 0), "Starting now")
        XCTAssertEqual(NotificationManager.leadDescription(minutes: 15), "Starts in 15 minutes")
        XCTAssertEqual(NotificationManager.leadDescription(minutes: 60), "Starts in an hour")
    }
}
