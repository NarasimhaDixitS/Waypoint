import XCTest
import CoreData
@testable import Waypoint

/// A wrong bar is still a bar. Every figure on the Progress tab is checked here against input
/// with a known answer, because the one place a bad number is invisible is a chart.
@MainActor
final class ProgressAnalyticsTests: XCTestCase {
    var context: NSManagedObjectContext!

    override func setUp() {
        super.setUp()
        context = PersistenceController(inMemory: true).container.viewContext
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d))!
    }

    @discardableResult
    private func task(
        on date: Date, done: Bool = false, minutes: Int = 60,
        priority: Priority = .medium, goal: GoalEntity? = nil,
        seriesID: UUID? = nil, completedAt: Date? = nil, auto: Bool = false
    ) -> TaskEntity {
        let start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: date)!
        let t = TaskEntity.create(
            in: context, title: "Task", date: date, startTime: start,
            durationMinutes: minutes, priority: priority, goal: goal, seriesID: seriesID
        )
        t.isDone = done
        t.completedAt = completedAt
        t.autoCompleted = auto
        return t
    }

    private func event(kind: TaskEventKind, title: String, from: Date, to: Date, at when: Date) -> TaskEventEntity {
        let e = TaskEventEntity(context: context)
        e.id = UUID()
        e.kind = kind.rawValue
        e.title = title
        e.fromDate = from
        e.toDate = to
        e.occurredAt = when
        return e
    }

    // MARK: - Weekday

    /// 2026-09-07 is a Monday.
    func testWeekdayCompletionCountsOnlyDaysThatHaveArrived() {
        let now = day(2026, 9, 9)
        task(on: day(2026, 9, 7), done: true)
        task(on: day(2026, 9, 7), done: false)
        // Next Monday: scheduled but not yet reached, so it must not drag Monday down.
        task(on: day(2026, 9, 14), done: false)

        let monday = ProgressAnalytics.completionByWeekday(Array(fetchTasks()), now: now)
            .first { $0.label == "Mon" }

        XCTAssertEqual(monday?.total, 2)
        XCTAssertEqual(monday?.done, 1)
        XCTAssertEqual(monday?.fraction, 0.5)
    }

    func testEveryWeekdayIsRepresentedEvenWithNoWork() {
        XCTAssertEqual(ProgressAnalytics.completionByWeekday([], now: day(2026, 9, 9)).count, 7)
    }

    // MARK: - Deferrals

    func testDeferralsGroupByTitleAndSumTheDaysLost() {
        event(kind: .deferred, title: "Gym", from: day(2026, 9, 1), to: day(2026, 9, 3), at: day(2026, 9, 1))
        event(kind: .deferred, title: "Gym", from: day(2026, 9, 3), to: day(2026, 9, 4), at: day(2026, 9, 3))
        event(kind: .deferred, title: "Taxes", from: day(2026, 9, 1), to: day(2026, 9, 2), at: day(2026, 9, 1))

        let board = ProgressAnalytics.deferralLeaderboard(Array(fetchEvents()))

        XCTAssertEqual(board.first?.title, "Gym", "the biggest slip should lead")
        XCTAssertEqual(board.first?.times, 2)
        XCTAssertEqual(board.first?.totalDays, 3)
    }

    func testAbandonmentsAreNotCountedAsDeferrals() {
        event(kind: .abandoned, title: "Gym", from: day(2026, 9, 1), to: day(2026, 9, 1), at: day(2026, 9, 1))
        XCTAssertTrue(ProgressAnalytics.deferralLeaderboard(Array(fetchEvents())).isEmpty)
    }

    func testSlipsLandInTheRightBuckets() {
        event(kind: .deferred, title: "A", from: day(2026, 9, 1), to: day(2026, 9, 2), at: day(2026, 9, 1))
        event(kind: .deferred, title: "B", from: day(2026, 9, 1), to: day(2026, 9, 4), at: day(2026, 9, 1))
        event(kind: .deferred, title: "C", from: day(2026, 9, 1), to: day(2026, 9, 20), at: day(2026, 9, 1))

        let buckets = ProgressAnalytics.slipDistribution(Array(fetchEvents()))

        XCTAssertEqual(buckets.first { $0.id == "1 day" }?.count, 1)
        XCTAssertEqual(buckets.first { $0.id == "2–3" }?.count, 1)
        XCTAssertEqual(buckets.first { $0.id == "Over a week" }?.count, 1)
    }

    // MARK: - Effort

    /// The number task counts can't give you: two tasks, one finished, but only a fifth of the
    /// planned time actually spent.
    func testEffortMeasuresMinutesNotTaskCounts() {
        let now = day(2026, 9, 9)
        task(on: day(2026, 9, 8), done: true, minutes: 30)
        task(on: day(2026, 9, 8), done: false, minutes: 120)

        let week = ProgressAnalytics.effortByWeek(Array(fetchTasks()), weeks: 1, now: now).first

        XCTAssertEqual(week?.plannedMinutes, 150)
        XCTAssertEqual(week?.completedMinutes, 30)
    }

    // MARK: - Priority

    func testPriorityFollowThroughSplitsByPriority() {
        let now = day(2026, 9, 9)
        task(on: day(2026, 9, 8), done: false, priority: .high)
        task(on: day(2026, 9, 8), done: true, priority: .low)
        task(on: day(2026, 9, 8), done: true, priority: .low)

        let rows = ProgressAnalytics.priorityFollowThrough(Array(fetchTasks()), now: now)

        XCTAssertEqual(rows.first { $0.id == "high" }?.fraction, 0)
        XCTAssertEqual(rows.first { $0.id == "low" }?.fraction, 1)
    }

    // MARK: - Goal split

    func testEffortByGoalDividesCompletedHoursAndNamesTheRest() {
        let goal = GoalEntity.create(in: context, name: "Marathon", targetDate: day(2026, 12, 1), planningMode: .manual)
        task(on: day(2026, 9, 1), done: true, minutes: 120, goal: goal)
        task(on: day(2026, 9, 2), done: true, minutes: 60)
        task(on: day(2026, 9, 3), done: false, minutes: 600, goal: goal)

        let slices = ProgressAnalytics.effortByGoal(Array(fetchTasks()))

        XCTAssertEqual(slices.first { $0.label == "Marathon" }?.value, 2, "unfinished work must not count")
        XCTAssertEqual(slices.first { $0.label == "Unassigned" }?.value, 1)
    }

    // MARK: - Time of day

    /// The reason `autoCompleted` exists: an auto-completed task's timestamp is the schedule
    /// restated, not an observation, and letting it through invents a peak.
    func testTimeOfDayIgnoresAutoCompletedTasks() {
        let stamp = Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: day(2026, 9, 8))!
        task(on: day(2026, 9, 8), done: true, completedAt: stamp, auto: true)

        XCTAssertEqual(ProgressAnalytics.observedCompletionCount(Array(fetchTasks())), 0)
        XCTAssertTrue(ProgressAnalytics.completionsByTimeOfDay(Array(fetchTasks())).allSatisfy { $0.count == 0 })
    }

    func testTimeOfDayBucketsAManualCompletionIntoItsBand() {
        let stamp = Calendar.current.date(bySettingHour: 21, minute: 30, second: 0, of: day(2026, 9, 8))!
        task(on: day(2026, 9, 8), done: true, completedAt: stamp, auto: false)

        let cells = ProgressAnalytics.completionsByTimeOfDay(Array(fetchTasks()))
        let hit = cells.first { $0.count > 0 }

        XCTAssertEqual(hit?.bandLabel, "Night", "21:30 falls in the 20:00–24:00 band")
        XCTAssertEqual(cells.count, 42, "seven days by six bands, including the empty ones")
    }

    // MARK: - Burndown

    func testBurndownFallsAsWorkIsCompletedAndTracksAnIdealLine() {
        let goal = GoalEntity.create(in: context, name: "Ship", targetDate: day(2026, 9, 11), planningMode: .manual)
        goal.createdAt = day(2026, 9, 1)
        for offset in 0..<10 {
            task(on: day(2026, 9, 1 + offset), goal: goal)
        }
        let first = goal.sortedTasks[0]
        first.isDone = true
        first.completedAt = day(2026, 9, 2)

        let points = ProgressAnalytics.burndown(for: goal, now: day(2026, 9, 3))

        XCTAssertEqual(points.first?.remaining, 10, "nothing done on day zero")
        XCTAssertEqual(points.last?.remaining, 9)
        XCTAssertEqual(points.first?.idealRemaining, 10)
        XCTAssertEqual(points.last!.idealRemaining, 8, accuracy: 0.001, "two of ten days elapsed")
    }

    func testBurndownIsEmptyForAGoalWithNoTasks() {
        let goal = GoalEntity.create(in: context, name: "Empty", targetDate: day(2026, 12, 1), planningMode: .manual)
        XCTAssertTrue(ProgressAnalytics.burndown(for: goal, now: day(2026, 9, 3)).isEmpty)
    }

    // MARK: - Estimate accuracy

    private func session(taskID: UUID?, title: String, actualSeconds: Int, planned: Int = 1500) {
        FocusSessionLog.record(
            taskID: taskID, taskTitle: title,
            startedAt: day(2026, 9, 8), endedAt: day(2026, 9, 8),
            plannedSeconds: planned, actualSeconds: actualSeconds,
            ranToCompletion: true, in: context
        )
    }

    /// The point of the whole feature: a 60-minute booking that actually took 90.
    func testEstimateAccuracyComparesBookedTimeAgainstTimeSpent() {
        let t = task(on: day(2026, 9, 8), minutes: 60)
        session(taskID: t.id, title: "Task", actualSeconds: 90 * 60)

        let rows = ProgressAnalytics.estimateAccuracy(sessions: fetchSessions(), tasks: fetchTasks())

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.plannedMinutes, 60)
        XCTAssertEqual(rows.first?.actualMinutes, 90)
        XCTAssertEqual(rows.first?.overrunMinutes, 30)
    }

    /// Several sittings on one task are one estimate, not several. Scoring each against the
    /// whole booking would call a well-estimated task three severe under-runs.
    func testMultipleSessionsOnOneTaskAreSummed() {
        let t = task(on: day(2026, 9, 8), minutes: 60)
        session(taskID: t.id, title: "Task", actualSeconds: 25 * 60)
        session(taskID: t.id, title: "Task", actualSeconds: 35 * 60)

        let rows = ProgressAnalytics.estimateAccuracy(sessions: fetchSessions(), tasks: fetchTasks())

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.actualMinutes, 60)
        XCTAssertEqual(rows.first?.ratio, 1)
    }

    /// A task nobody timed is not evidence that the estimate was right.
    func testTasksWithNoSessionsAreExcluded() {
        task(on: day(2026, 9, 8), minutes: 60)
        XCTAssertTrue(ProgressAnalytics.estimateAccuracy(sessions: fetchSessions(), tasks: fetchTasks()).isEmpty)
    }

    /// One timer left running all afternoon shouldn't decide what the typical estimate looks
    /// like — which is why the headline figure is a median.
    func testMedianRatioIsNotThrownByASingleOutlier() {
        let normal = (0..<4).map { _ -> ProgressAnalytics.Estimate in
            ProgressAnalytics.Estimate(id: UUID().uuidString, title: "t", plannedMinutes: 60, actualMinutes: 60)
        }
        let outlier = ProgressAnalytics.Estimate(id: "x", title: "left running", plannedMinutes: 60, actualMinutes: 600)

        let median = ProgressAnalytics.medianEstimateRatio(normal + [outlier])

        XCTAssertEqual(median ?? 0, 1, accuracy: 0.001)
    }

    /// Opening the timer and closing it again isn't data; a pile of such rows would drag every
    /// average down while looking like evidence.
    func testVeryShortSessionsAreNotRecorded() {
        let written = FocusSessionLog.record(
            taskID: UUID(), taskTitle: "Blip",
            startedAt: day(2026, 9, 8), endedAt: day(2026, 9, 8),
            plannedSeconds: 1500, actualSeconds: 9,
            ranToCompletion: false, in: context
        )
        XCTAssertNil(written)
        XCTAssertTrue(fetchSessions().isEmpty)
    }

    /// An abandoned session still says something about how long work takes.
    func testAnAbandonedSessionIsStillRecorded() {
        let written = FocusSessionLog.record(
            taskID: UUID(), taskTitle: "Gave up",
            startedAt: day(2026, 9, 8), endedAt: day(2026, 9, 8),
            plannedSeconds: 1500, actualSeconds: 400,
            ranToCompletion: false, in: context
        )
        XCTAssertNotNil(written)
        XCTAssertEqual(written?.ranToCompletion, false)
    }

    // MARK: - Helpers

    private func fetchSessions() -> [FocusSessionEntity] {
        (try? context.fetch(FocusSessionEntity.fetchRequest(since: nil))) ?? []
    }

    private func fetchTasks() -> [TaskEntity] { (try? context.fetch(TaskEntity.fetchRequest())) ?? [] }
    private func fetchEvents() -> [TaskEventEntity] { (try? context.fetch(TaskEventEntity.fetchRequest())) ?? [] }
}
