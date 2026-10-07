import XCTest
import CoreData
@testable import Waypoint

@MainActor
final class GoalCenterTests: XCTestCase {
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
        on date: Date,
        title: String = "Task",
        done: Bool = false,
        hour: Int = 10,
        goal: GoalEntity? = nil
    ) -> TaskEntity {
        let start = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: date)!
        let t = TaskEntity.create(
            in: context, title: title, date: date, startTime: start,
            durationMinutes: 30, priority: .medium, goal: goal
        )
        t.isDone = done
        return t
    }

    private func makeGoal(from: Date, to: Date) -> GoalEntity {
        let goal = GoalEntity.create(in: context, name: "Learn Spanish", targetDate: to, planningMode: .manual)
        goal.createdAt = from
        return goal
    }

    // MARK: - Grouping

    func testTasksSplitIntoOverdueTodayUpcomingAndDone() {
        let now = day(2026, 10, 7)
        let tasks = [
            task(on: day(2026, 10, 5), title: "missed"),
            task(on: day(2026, 10, 7), title: "now"),
            task(on: day(2026, 10, 9), title: "later"),
            task(on: day(2026, 10, 4), title: "finished", done: true),
        ]

        let groups = TaskGroup.grouped(tasks, now: now)

        XCTAssertEqual(groups.map(\.kind), [.overdue, .today, .upcoming, .done])
        XCTAssertEqual(groups[0].tasks.first?.title, "missed")
        XCTAssertEqual(groups[3].tasks.first?.title, "finished")
    }

    func testAFinishedPastTaskIsDoneRatherThanOverdue() {
        let now = day(2026, 10, 7)
        let tasks = [task(on: day(2026, 10, 1), title: "done last week", done: true)]

        let groups = TaskGroup.grouped(tasks, now: now)

        XCTAssertEqual(groups.map(\.kind), [.done],
                       "Something you finished is a record, not a miss.")
    }

    func testEmptyGroupsAreLeftOutEntirely() {
        let now = day(2026, 10, 7)
        let tasks = [task(on: day(2026, 10, 9), title: "later")]

        XCTAssertEqual(TaskGroup.grouped(tasks, now: now).map(\.kind), [.upcoming])
    }

    func testOverdueReadsNewestFirstAndUpcomingSoonestFirst() {
        let now = day(2026, 10, 7)
        let tasks = [
            task(on: day(2026, 10, 1), title: "old miss"),
            task(on: day(2026, 10, 6), title: "recent miss"),
            task(on: day(2026, 10, 20), title: "far"),
            task(on: day(2026, 10, 8), title: "soon"),
        ]

        let groups = TaskGroup.grouped(tasks, now: now)

        XCTAssertEqual(groups.first(where: { $0.kind == .overdue })?.tasks.map(\.title), ["recent miss", "old miss"])
        XCTAssertEqual(groups.first(where: { $0.kind == .upcoming })?.tasks.map(\.title), ["soon", "far"])
    }

    // MARK: - Heatmap

    func testHeatmapCoversEveryDayIncludingOnesWithNoTasks() {
        let goal = makeGoal(from: day(2026, 10, 1), to: day(2026, 10, 10))
        task(on: day(2026, 10, 3), goal: goal)

        let days = ProgressAnalytics.heatmap(for: goal, now: day(2026, 10, 5))

        XCTAssertEqual(days.count, 5, "A gap in the middle is the thing worth seeing, not a row to skip.")
        XCTAssertEqual(days.first?.date, day(2026, 10, 1))
        XCTAssertEqual(days.last?.date, day(2026, 10, 5))
    }

    func testHeatmapStopsAtTodayRatherThanRunningToTheTarget() {
        let goal = makeGoal(from: day(2026, 10, 1), to: day(2027, 1, 30))
        task(on: day(2026, 10, 2), goal: goal)
        task(on: day(2026, 11, 20), goal: goal)

        let days = ProgressAnalytics.heatmap(for: goal, now: day(2026, 10, 5))

        XCTAssertEqual(days.last?.date, day(2026, 10, 5),
                       "Future days drawn as scheduled-but-not-done read as months of failure.")
    }

    func testADayWithNoTasksHasNoFractionRatherThanZero() {
        let goal = makeGoal(from: day(2026, 10, 1), to: day(2026, 10, 3))
        task(on: day(2026, 10, 2), goal: goal)

        let days = ProgressAnalytics.heatmap(for: goal, now: day(2026, 10, 3))

        XCTAssertNil(days[0].fraction, "A day the goal asked nothing of you isn't a day you failed.")
        XCTAssertEqual(days[1].fraction, 0.0, "A day with work you didn't do is a real zero.")
    }

    func testHeatmapFractionCountsDoneOverTotal() {
        let goal = makeGoal(from: day(2026, 10, 1), to: day(2026, 10, 2))
        task(on: day(2026, 10, 1), title: "a", done: true, hour: 9, goal: goal)
        task(on: day(2026, 10, 1), title: "b", done: true, hour: 11, goal: goal)
        task(on: day(2026, 10, 1), title: "c", done: false, hour: 13, goal: goal)

        let days = ProgressAnalytics.heatmap(for: goal, now: day(2026, 10, 2))

        XCTAssertEqual(days[0].total, 3)
        XCTAssertEqual(days[0].done, 2)
        XCTAssertEqual(days[0].fraction ?? 0, 2.0 / 3.0, accuracy: 0.0001)
    }

    func testHeatmapRunsPastTheTargetDateWhenWorkContinued() {
        let goal = makeGoal(from: day(2026, 10, 1), to: day(2026, 10, 5))
        task(on: day(2026, 10, 8), goal: goal)

        let days = ProgressAnalytics.heatmap(for: goal, now: day(2026, 10, 9))

        XCTAssertEqual(days.last?.date, day(2026, 10, 8),
                       "A goal still being worked past its deadline keeps its overrun.")
    }

    func testAFinishedGoalIsNotTrailedByEmptyWeeks() {
        let goal = makeGoal(from: day(2026, 8, 1), to: day(2026, 8, 20))
        task(on: day(2026, 8, 18), done: true, goal: goal)

        let days = ProgressAnalytics.heatmap(for: goal, now: day(2026, 10, 7))

        XCTAssertEqual(days.last?.date, day(2026, 8, 20),
                       "A goal that ended in August shouldn't drag six empty weeks behind it.")
    }

    func testAVeryLongGoalIsTrimmedToItsMostRecentDays() {
        let goal = makeGoal(from: day(2025, 1, 1), to: day(2026, 12, 31))

        let days = ProgressAnalytics.heatmap(for: goal, now: day(2026, 10, 7), maxDays: 30)

        XCTAssertEqual(days.count, 30)
        XCTAssertEqual(days.last?.date, day(2026, 10, 7), "Trimmed from the start, keeping the recent end.")
    }
}
