import XCTest
@testable import Waypoint

final class TaskStateTests: XCTestCase {
    func testResolve_beforeWindow_isPending() {
        let start = Date.now.addingTimeInterval(3600)
        XCTAssertEqual(TaskState.resolve(isDone: false, date: .now, startTime: start, durationMinutes: 30, now: .now), .pending)
    }

    func testResolve_withinWindow_isInProgress() {
        let start = Date.now.addingTimeInterval(-600)
        XCTAssertEqual(TaskState.resolve(isDone: false, date: .now, startTime: start, durationMinutes: 30, now: .now), .inProgress)
    }

    func testResolve_afterWindow_staysPendingIfNotMarkedDone() {
        let start = Date.now.addingTimeInterval(-3600)
        XCTAssertEqual(TaskState.resolve(isDone: false, date: .now, startTime: start, durationMinutes: 30, now: .now), .pending)
    }

    func testResolve_isDone_alwaysWinsRegardlessOfTime() {
        let start = Date.now.addingTimeInterval(3600) // hasn't started yet
        XCTAssertEqual(TaskState.resolve(isDone: true, date: .now, startTime: start, durationMinutes: 30, now: .now), .done)
    }

    func testResolve_pastDay_isOverdueEvenIfNotDone() {
        let cal = Calendar.current
        let yesterday = cal.date(byAdding: .day, value: -1, to: .now)!
        XCTAssertEqual(TaskState.resolve(isDone: false, date: yesterday, startTime: yesterday, durationMinutes: 30, now: .now), .overdue)
    }

    func testResolve_pastDay_isDoneWinsOverOverdue() {
        let cal = Calendar.current
        let yesterday = cal.date(byAdding: .day, value: -1, to: .now)!
        XCTAssertEqual(TaskState.resolve(isDone: true, date: yesterday, startTime: yesterday, durationMinutes: 30, now: .now), .done)
    }

    func testResolve_futureDay_isFuture() {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: .now)!
        XCTAssertEqual(TaskState.resolve(isDone: false, date: tomorrow, startTime: tomorrow, durationMinutes: 30, now: .now), .future)
    }

    /// The clock is now an argument rather than something each row reads for itself — that's what
    /// lets Today re-render as time passes, and what lets a test sit at a chosen instant.
    func testStateAtAnExplicitInstantTracksTheTaskWindow() {
        let context = PersistenceController(inMemory: true).container.viewContext
        let cal = Calendar.current
        let day = cal.date(from: DateComponents(year: 2026, month: 9, day: 3))!
        let start = cal.date(bySettingHour: 10, minute: 0, second: 0, of: day)!
        let task = TaskEntity.create(
            in: context, title: "Deep work", date: day,
            startTime: start, durationMinutes: 60, priority: .medium
        )

        XCTAssertEqual(task.state(at: start.addingTimeInterval(-60)), .pending, "a minute before it starts")
        XCTAssertEqual(task.state(at: start), .inProgress, "the instant it starts")
        XCTAssertEqual(task.state(at: start.addingTimeInterval(59 * 60)), .inProgress, "a minute before it ends")
        XCTAssertEqual(task.state(at: start.addingTimeInterval(60 * 60)), .pending, "the instant it ends, back to pending")
    }

    /// Completing it takes it out of the running window immediately, whatever the clock says.
    func testACompletedTaskIsNeverInProgress() {
        let context = PersistenceController(inMemory: true).container.viewContext
        let cal = Calendar.current
        let day = cal.date(from: DateComponents(year: 2026, month: 9, day: 3))!
        let start = cal.date(bySettingHour: 10, minute: 0, second: 0, of: day)!
        let task = TaskEntity.create(
            in: context, title: "Deep work", date: day,
            startTime: start, durationMinutes: 60, priority: .medium
        )
        task.isDone = true

        XCTAssertEqual(task.state(at: start.addingTimeInterval(30 * 60)), .done)
    }
}
