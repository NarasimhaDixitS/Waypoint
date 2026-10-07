import XCTest
import CoreData
@testable import Waypoint

/// The day's row order. Small, and it has now broken twice without anything failing.
@MainActor
final class TimelineOrderTests: XCTestCase {
    var context: NSManagedObjectContext!

    override func setUp() {
        super.setUp()
        context = PersistenceController(inMemory: true).container.viewContext
    }

    private let day = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 7))!

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func task(_ title: String, _ hour: Int, _ priority: Priority) -> TimelineItem {
        .task(TaskEntity.create(
            in: context, title: title, date: day, startTime: at(hour),
            durationMinutes: 30, priority: priority
        ))
    }

    private func titles(_ items: [TimelineItem]) -> [String] {
        items.compactMap { $0.taskEntity?.title }
    }

    // MARK: - Nothing is lost or doubled

    func testEveryTaskAppearsExactlyOnceWhateverTheSortAndWhateverElseIsOnTheDay() {
        let items: [TimelineItem] = [
            .sleep(at(0), at(6)),
            task("Morning miles", 7, .low),
            task("Deep work", 10, .high),
            .sleep(at(23), at(23, 59)),
            task("Review PR backlog", 13, .medium),
        ]

        for mode in [TaskSortMode.time, .priority] {
            let out = TimelineItem.ordered(items, by: mode)
            XCTAssertEqual(
                titles(out).sorted(), ["Deep work", "Morning miles", "Review PR backlog"],
                "sorting by \(mode) must not duplicate or drop a task"
            )
            XCTAssertEqual(out.count, items.count)
        }
    }

    func testSleepRowsSurvivePrioritySort() {
        let items: [TimelineItem] = [
            .sleep(at(0), at(6)),
            task("Deep work", 10, .high),
            .sleep(at(23), at(23, 59)),
        ]

        let out = TimelineItem.ordered(items, by: .priority)

        XCTAssertEqual(out.filter(\.isFixed).count, 2,
                       "a sleep row swallowed by the task queue is how both of them vanished")
    }

    // MARK: - Fixed rows don't move

    func testFixedRowsHoldTheirPositionsWhenTheSortChanges() {
        let commitment = CommitmentEntity(context: context)
        commitment.id = UUID()
        commitment.name = "Work"

        let items: [TimelineItem] = [
            task("Early low", 7, .low),
            .block(commitment, at(9), at(17)),
            task("Late high", 18, .high),
            .sleep(at(23), at(23, 59)),
        ]

        let byTime = TimelineItem.ordered(items, by: .time)
        let byPriority = TimelineItem.ordered(items, by: .priority)

        XCTAssertEqual(byTime.map(\.isFixed), byPriority.map(\.isFixed),
                       "a fixed row is not the user's to reorder; only which task fills each task slot changes")
    }

    func testPrioritySortPutsTheHighestPriorityTaskInTheEarliestTaskSlot() {
        let items: [TimelineItem] = [
            task("Early low", 7, .low),
            task("Mid medium", 12, .medium),
            task("Late high", 18, .high),
        ]

        XCTAssertEqual(titles(TimelineItem.ordered(items, by: .time)),
                       ["Early low", "Mid medium", "Late high"])
        XCTAssertEqual(titles(TimelineItem.ordered(items, by: .priority)),
                       ["Late high", "Mid medium", "Early low"])
    }

    func testEqualPrioritiesKeepTheirTimeOrder() {
        let items: [TimelineItem] = [
            task("Nine", 9, .medium),
            task("Eight", 8, .medium),
            task("Ten", 10, .medium),
        ]

        XCTAssertEqual(titles(TimelineItem.ordered(items, by: .priority)), ["Eight", "Nine", "Ten"])
    }

    func testADayOfNothingButFixedRowsIsLeftAlone() {
        let items: [TimelineItem] = [.sleep(at(0), at(6)), .sleep(at(23), at(23, 59))]

        XCTAssertEqual(TimelineItem.ordered(items, by: .priority).count, 2)
    }
}
