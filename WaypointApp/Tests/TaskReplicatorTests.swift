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
