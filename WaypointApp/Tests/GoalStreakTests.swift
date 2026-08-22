import XCTest
import CoreData
@testable import Waypoint

@MainActor
final class GoalStreakTests: XCTestCase {
    var context: NSManagedObjectContext!

    override func setUp() {
        super.setUp()
        context = PersistenceController(inMemory: true).container.viewContext
    }

    private func makeGoal() -> GoalEntity {
        GoalEntity.create(in: context, name: "Goal", targetDate: Date.now.addingTimeInterval(86400 * 30), planningMode: .manual)
    }

    private func completedTask(daysAgo: Int, goal: GoalEntity) {
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: -daysAgo, to: .now)!
        let task = TaskEntity.create(in: context, title: "T-\(daysAgo)", date: day, startTime: day, durationMinutes: 30, priority: .medium, goal: goal)
        task.isDone = true
        task.completedAt = day
    }

    func testDayStreak_consecutiveDays_countsAll() {
        let goal = makeGoal()
        completedTask(daysAgo: 0, goal: goal)
        completedTask(daysAgo: 1, goal: goal)
        completedTask(daysAgo: 2, goal: goal)
        XCTAssertEqual(goal.dayStreak, 3)
    }

    func testDayStreak_gapBreaksTheChain() {
        let goal = makeGoal()
        completedTask(daysAgo: 0, goal: goal)
        completedTask(daysAgo: 2, goal: goal) // yesterday missing
        XCTAssertEqual(goal.dayStreak, 1)
    }

    func testDayStreak_noCompletedTasks_isZero() {
        let goal = makeGoal()
        XCTAssertEqual(goal.dayStreak, 0)
    }

    func testDayStreak_missingToday_isZeroEvenWithPastStreak() {
        let goal = makeGoal()
        completedTask(daysAgo: 1, goal: goal)
        completedTask(daysAgo: 2, goal: goal)
        // Streak counts backward starting from today, so a gap today breaks it immediately.
        XCTAssertEqual(goal.dayStreak, 0)
    }
}
