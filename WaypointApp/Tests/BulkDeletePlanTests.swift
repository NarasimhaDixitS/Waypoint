import XCTest
import CoreData
@testable import Waypoint

/// The counts on the delete sheet are the entire safety argument — "are you sure?" is a
/// question anyone says yes to, where "41 tasks" is a number that stops them. So the counts
/// have to be right.
@MainActor
final class BulkDeletePlanTests: XCTestCase {
    var context: NSManagedObjectContext!

    override func setUp() {
        super.setUp()
        context = PersistenceController(inMemory: true).container.viewContext
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d))!
    }

    @discardableResult
    private func task(on date: Date, title: String = "Drill", series: UUID? = nil) -> TaskEntity {
        let start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: date)!
        return TaskEntity.create(
            in: context, title: title, date: date, startTime: start,
            durationMinutes: 30, priority: .medium, seriesID: series
        )
    }

    // MARK: - No series

    func testASelectionWithNoRepeatsOffersNoChoice() {
        let plan = BulkDeletePlan(
            selected: [task(on: day(2026, 10, 8)), task(on: day(2026, 10, 9))],
            context: context
        )

        XCTAssertFalse(plan.hasSeries)
        XCTAssertEqual(plan.seriesCount, 0)
        XCTAssertEqual(plan.seriesTasks.count, 2, "With nothing repeating, both paths remove the same thing.")
    }

    // MARK: - Forward only

    func testSeriesDeletionSweepsForwardAndLeavesThePastAlone() {
        let series = UUID()
        task(on: day(2026, 10, 1), series: series)
        task(on: day(2026, 10, 2), series: series)
        let picked = task(on: day(2026, 10, 3), series: series)
        task(on: day(2026, 10, 4), series: series)
        task(on: day(2026, 10, 5), series: series)

        let plan = BulkDeletePlan(selected: [picked], context: context)

        XCTAssertEqual(plan.seriesTasks.count, 3, "The 3rd onwards — never the two before it.")
        XCTAssertEqual(
            plan.seriesTasks.map { Calendar.current.startOfDay(for: $0.resolvedDate) },
            [day(2026, 10, 3), day(2026, 10, 4), day(2026, 10, 5)]
        )
    }

    func testTheSweepStartsAtTheEarliestSelectedOccurrence() {
        let series = UUID()
        task(on: day(2026, 10, 1), series: series)
        let early = task(on: day(2026, 10, 2), series: series)
        task(on: day(2026, 10, 3), series: series)
        let late = task(on: day(2026, 10, 4), series: series)

        // Picked out of order on purpose: the plan must not depend on selection order.
        let plan = BulkDeletePlan(selected: [late, early], context: context)

        XCTAssertEqual(plan.seriesTasks.count, 3, "From the 2nd onwards, not from the 4th.")
    }

    // MARK: - Counting

    func testThreeTasksFromOneRepeatAreOneSeriesNotThree() {
        let series = UUID()
        let a = task(on: day(2026, 10, 1), series: series)
        let b = task(on: day(2026, 10, 2), series: series)
        let c = task(on: day(2026, 10, 3), series: series)

        let plan = BulkDeletePlan(selected: [a, b, c], context: context)

        XCTAssertEqual(plan.seriesCount, 1, "One repeat, selected three times over.")
        XCTAssertEqual(plan.seriesTasks.count, 3, "And no task counted twice.")
    }

    func testTwoRepeatsAreCountedSeparatelyAndNotDoubleCounted() {
        let spanish = UUID()
        let running = UUID()
        let a = task(on: day(2026, 10, 1), title: "Verbs", series: spanish)
        task(on: day(2026, 10, 2), title: "Verbs", series: spanish)
        let b = task(on: day(2026, 10, 1), title: "Intervals", series: running)
        task(on: day(2026, 10, 3), title: "Intervals", series: running)

        let plan = BulkDeletePlan(selected: [a, b], context: context)

        XCTAssertEqual(plan.seriesCount, 2)
        XCTAssertEqual(plan.seriesTasks.count, 4)
    }

    func testAdditionalCountIsWhatTheUserDidNotPickByHand() {
        let series = UUID()
        let picked = task(on: day(2026, 10, 1), series: series)
        task(on: day(2026, 10, 2), series: series)
        task(on: day(2026, 10, 3), series: series)

        let plan = BulkDeletePlan(selected: [picked], context: context)

        XCTAssertEqual(plan.selected.count, 1)
        XCTAssertEqual(plan.seriesTasks.count, 3)
        XCTAssertEqual(plan.additionalCount, 2, "The number worth reading on the sheet.")
    }

    func testAOneOffSelectedAlongsideARepeatIsStillIncludedButAddsNoSeries() {
        let series = UUID()
        let repeating = task(on: day(2026, 10, 1), series: series)
        task(on: day(2026, 10, 2), series: series)
        let oneOff = task(on: day(2026, 10, 5), title: "Book a tutor")

        let plan = BulkDeletePlan(selected: [repeating, oneOff], context: context)

        XCTAssertEqual(plan.seriesCount, 1)
        XCTAssertEqual(plan.seriesTasks.count, 3, "Both repeat occurrences, plus the one-off that was ticked.")
    }

    func testTasksOfADifferentSeriesAreNeverSweptIn() {
        let mine = UUID()
        let other = UUID()
        let picked = task(on: day(2026, 10, 1), title: "Verbs", series: mine)
        task(on: day(2026, 10, 2), title: "Verbs", series: mine)
        task(on: day(2026, 10, 2), title: "Someone else's", series: other)

        let plan = BulkDeletePlan(selected: [picked], context: context)

        XCTAssertEqual(plan.seriesTasks.count, 2)
        XCTAssertFalse(plan.seriesTasks.contains { $0.title == "Someone else's" })
    }
}
