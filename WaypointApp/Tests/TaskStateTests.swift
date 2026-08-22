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
}
