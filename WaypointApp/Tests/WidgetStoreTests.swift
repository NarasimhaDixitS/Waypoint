import XCTest
import CoreData
@testable import Waypoint

/// The widget draws from a snapshot taken in one process and rendered in another, minutes
/// later. These cover the shape of that snapshot, because a widget failing is silent — it just
/// shows the wrong thing, and nobody sees a stack trace.
final class WidgetStoreTests: XCTestCase {
    private func item(_ title: String, start: Date, minutes: Int, done: Bool = false) -> DaySnapshot.Item {
        DaySnapshot.Item(
            id: UUID(), title: title, start: start,
            end: start.addingTimeInterval(Double(minutes) * 60), isDone: done
        )
    }

    private var nine: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 9))!
    }

    func testRemainingEffortCountsOnlyUnfinishedWork() {
        let snapshot = DaySnapshot(date: nine, items: [
            item("Done", start: nine, minutes: 60, done: true),
            item("Left", start: nine.addingTimeInterval(3600), minutes: 45)
        ])
        XCTAssertEqual(snapshot.remainingMinutes, 45)
        XCTAssertEqual(snapshot.remainingLabel, "45m of work left")
    }

    func testCompletionFractionMatchesWhatTheRingDraws() {
        let snapshot = DaySnapshot(date: nine, items: [
            item("A", start: nine, minutes: 30, done: true),
            item("B", start: nine, minutes: 30, done: true),
            item("C", start: nine, minutes: 30),
            item("D", start: nine, minutes: 30)
        ])
        XCTAssertEqual(snapshot.fraction, 0.5)
        XCTAssertEqual(snapshot.done, 2)
    }

    func testAnEmptyDayDoesNotDivideByZero() {
        let snapshot = DaySnapshot(date: nine, items: [])
        XCTAssertEqual(snapshot.fraction, 0)
        XCTAssertEqual(snapshot.remainingLabel, "Nothing left")
        XCTAssertNil(snapshot.focus)
    }

    /// The widget leads with what's running; failing that, the next thing still to come.
    func testFocusPrefersTheRunningTaskThenTheNextOne() {
        let running = item("Running", start: Date.now.addingTimeInterval(-600), minutes: 60)
        let later = item("Later", start: Date.now.addingTimeInterval(7200), minutes: 30)
        XCTAssertEqual(DaySnapshot(date: .now, items: [later, running]).focus?.title, "Running")
        XCTAssertEqual(DaySnapshot(date: .now, items: [later]).focus?.title, "Later")
    }

    func testFinishedWorkIsNeverOfferedAsTheFocus() {
        let done = item("Done", start: Date.now.addingTimeInterval(-600), minutes: 60, done: true)
        XCTAssertNil(DaySnapshot(date: .now, items: [done]).focus)
    }

    /// Refresh points come from the day's own shape, not a fixed interval — a widget gets a
    /// limited number of wake-ups a day and polling spends them on moments nothing changed.
    func testRefreshDatesLandOnTaskBoundariesAndMidnight() {
        let now = Date.now
        let soon = now.addingTimeInterval(1800)
        let snapshot = DaySnapshot(date: now, items: [
            item("Next", start: soon, minutes: 30)
        ])
        let dates = snapshot.refreshDates(now: now)

        XCTAssertTrue(dates.contains(soon), "a task starting is a moment the widget must redraw")
        XCTAssertTrue(dates.contains(soon.addingTimeInterval(1800)), "and when it ends")
        XCTAssertTrue(dates.allSatisfy { $0 > now }, "never schedules a wake-up in the past")
    }

    func testRefreshDatesAreCappedSoALongDayCannotFloodTheBudget() {
        let now = Date.now
        let items = (1...40).map { item("T\($0)", start: now.addingTimeInterval(Double($0) * 600), minutes: 5) }
        let dates = DaySnapshot(date: now, items: items).refreshDates(now: now, limit: 24)
        XCTAssertEqual(dates.count, 24)
        XCTAssertEqual(dates, dates.sorted(), "soonest first, so the cap drops the far future")
    }
}
