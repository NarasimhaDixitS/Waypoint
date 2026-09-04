import XCTest
import CoreData
@testable import Waypoint

@MainActor
final class TaskReplicatorTests: XCTestCase {
    var context: NSManagedObjectContext!

    override func setUp() {
        super.setUp()
        context = PersistenceController(inMemory: true).container.viewContext
        // Keep replicated occurrences well clear of the sleep window regardless of when
        // the test suite happens to run.
        SleepSettings.shared.startTimeOfDay = time(23, 0)
        SleepSettings.shared.durationMinutes = 7 * 60
    }

    private func time(_ hour: Int, _ minute: Int, on day: Date = .now) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func weekdaySymbol(for date: Date) -> String {
        let index = (Calendar.current.component(.weekday, from: date) + 5) % 7
        return CommitmentEntity.weekdaySymbols[index]
    }

    func testRepeatWeekly_createsOccurrenceOnEachMatchingWeek() {
        let start = time(10, 0)
        let task = TaskEntity.create(in: context, title: "Gym", date: start, startTime: start, durationMinutes: 30, priority: .medium)

        let result = TaskReplicator.repeatWeekly(task, onWeekdays: [weekdaySymbol(for: start)], forWeeks: 2, context: context)

        XCTAssertEqual(result.created, 2) // same weekday, one and two weeks out
        XCTAssertEqual(result.skipped, 0)
    }

    func testRepeatWeekly_skipsAnOccurrenceThatWouldCollide() {
        let start = time(10, 0)
        let task = TaskEntity.create(in: context, title: "Gym", date: start, startTime: start, durationMinutes: 30, priority: .medium)

        let nextWeek = Calendar.current.date(byAdding: .day, value: 7, to: start)!
        TaskEntity.create(in: context, title: "Blocker", date: nextWeek, startTime: nextWeek, durationMinutes: 30, priority: .medium)

        let result = TaskReplicator.repeatWeekly(task, onWeekdays: [weekdaySymbol(for: start)], forWeeks: 2, context: context)

        XCTAssertEqual(result.created, 1)
        XCTAssertEqual(result.skipped, 1)
    }

    /// `weeksUntil` rounds up so a repeat always *reaches* the goal, which means the week count
    /// it produces overshoots the target date by up to six days. The replicator has to hold the
    /// real line — otherwise a goal-linked series quietly outlives the goal it belongs to, which
    /// is exactly what shipped: a Mon/Thu repeat toward a Feb 28 goal created Mar 1 and Mar 4.
    func testRepeatWeekly_goalLinkedTask_createsNothingPastGoalTargetDate() {
        let cal = Calendar.current
        let start = time(10, 0)
        // 30 days out lands mid-week, so the rounded-up week count runs past it.
        let target = cal.date(byAdding: .day, value: 30, to: start)!
        let goal = GoalEntity.create(in: context, name: "Weight Loss", targetDate: target, planningMode: .manual)
        let task = TaskEntity.create(in: context, title: "Gym", date: start, startTime: start, durationMinutes: 30, priority: .medium, goal: goal)

        let weeks = TaskReplicator.weeksUntil(target, from: start)
        let result = TaskReplicator.repeatWeekly(task, onWeekdays: [weekdaySymbol(for: start)], forWeeks: weeks, context: context)

        XCTAssertGreaterThan(result.created, 0, "the repeat should still reach the goal, not be cancelled by the cap")
        let lastDay = try! XCTUnwrap(result.lastDate)
        XCTAssertLessThanOrEqual(cal.startOfDay(for: lastDay), cal.startOfDay(for: target))

        let request = TaskEntity.fetchRequest()
        let all = (try? context.fetch(request)) ?? []
        let past = all.filter { cal.startOfDay(for: $0.resolvedDate) > cal.startOfDay(for: target) }
        XCTAssertTrue(past.isEmpty, "no occurrence may fall past the goal's target date")
    }

    /// The boundary itself: the goal is still live on its target date, so an occurrence landing
    /// exactly on it is kept rather than trimmed off by an off-by-one.
    func testRepeatWeekly_occurrenceExactlyOnGoalTargetDate_isKept() {
        let cal = Calendar.current
        let start = time(10, 0)
        let target = cal.date(byAdding: .day, value: 14, to: start)! // same weekday, two weeks out
        let goal = GoalEntity.create(in: context, name: "Weight Loss", targetDate: target, planningMode: .manual)
        let task = TaskEntity.create(in: context, title: "Gym", date: start, startTime: start, durationMinutes: 30, priority: .medium, goal: goal)

        let result = TaskReplicator.repeatWeekly(task, onWeekdays: [weekdaySymbol(for: start)], forWeeks: 2, context: context)

        XCTAssertEqual(result.created, 2)
        let lastDay = try! XCTUnwrap(result.lastDate)
        XCTAssertTrue(cal.isDate(lastDay, inSameDayAs: target))
    }

    /// A task with no goal has no end date to respect — the cap must not leak into that case.
    func testRepeatWeekly_ungoaledTask_isNotCapped() {
        let start = time(10, 0)
        let task = TaskEntity.create(in: context, title: "Gym", date: start, startTime: start, durationMinutes: 30, priority: .medium)

        let result = TaskReplicator.repeatWeekly(task, onWeekdays: [weekdaySymbol(for: start)], forWeeks: 6, context: context)

        XCTAssertEqual(result.created, 6)
    }

    // MARK: - Seed day alignment

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// The exact case that shipped: creating a Mon/Thu repeat while looking at a Friday filed
    /// the task itself on that Friday, so the series came out as 27 Mondays, 27 Thursdays and
    /// one stray Friday.
    func testFirstDay_startWeekdayNotInPattern_movesToFirstMatchingDay() {
        let friday = day(2026, 8, 28)
        XCTAssertEqual(weekdaySymbol(for: friday), "Fri", "fixture sanity: 28 Aug 2026 is a Friday")

        let seed = TaskReplicator.firstDay(onOrAfter: friday, matching: ["Mon", "Thu"])

        XCTAssertTrue(Calendar.current.isDate(seed, inSameDayAs: day(2026, 8, 31)), "should move to Monday 31 Aug")
        XCTAssertEqual(weekdaySymbol(for: seed), "Mon")
    }

    /// Already on the pattern — the task must stay exactly where it is, not jump a week.
    func testFirstDay_startWeekdayAlreadyInPattern_staysPut() {
        let monday = day(2026, 8, 31)
        XCTAssertEqual(weekdaySymbol(for: monday), "Mon")

        let seed = TaskReplicator.firstDay(onOrAfter: monday, matching: ["Mon", "Thu"])

        XCTAssertTrue(Calendar.current.isDate(seed, inSameDayAs: monday))
    }

    /// No repeat pattern at all means no realignment — a one-off task belongs on the day the
    /// user picked, whatever weekday that is.
    func testFirstDay_emptyPattern_staysPut() {
        let friday = day(2026, 8, 28)

        let seed = TaskReplicator.firstDay(onOrAfter: friday, matching: [])

        XCTAssertTrue(Calendar.current.isDate(seed, inSameDayAs: friday))
    }

    /// End to end: seeding on the pattern and then replicating must yield occurrences on the
    /// requested weekdays only — no stray day, from either end of the process.
    func testSeededRepeat_producesOnlyRequestedWeekdays() {
        let cal = Calendar.current
        let friday = day(2026, 8, 28)
        let pattern: Set<String> = ["Mon", "Thu"]
        let seedDay = TaskReplicator.firstDay(onOrAfter: friday, matching: pattern)
        let start = cal.date(bySettingHour: 10, minute: 0, second: 0, of: seedDay)!
        let task = TaskEntity.create(in: context, title: "Gym", date: seedDay, startTime: start, durationMinutes: 30, priority: .medium)

        TaskReplicator.repeatWeekly(task, onWeekdays: pattern, forWeeks: 4, context: context)

        let all = (try? context.fetch(TaskEntity.fetchRequest())) ?? []
        XCTAssertFalse(all.isEmpty)
        let weekdays = Set(all.map { weekdaySymbol(for: $0.resolvedDate) })
        XCTAssertEqual(weekdays, pattern, "every task — the seed included — must land on a requested weekday")
    }

    func testDraftForTomorrow_preservesTimeOfDayAndAdvancesOneDay() {
        let start = time(9, 0)
        let task = TaskEntity.create(in: context, title: "Standup", date: start, startTime: start, durationMinutes: 15, priority: .medium)

        let draft = TaskReplicator.draftForTomorrow(task)

        let cal = Calendar.current
        XCTAssertEqual(cal.dateComponents([.hour, .minute], from: draft.startTime), cal.dateComponents([.hour, .minute], from: start))
        let expectedDate = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: start))!
        XCTAssertTrue(cal.isDate(draft.date, inSameDayAs: expectedDate))
    }
}
