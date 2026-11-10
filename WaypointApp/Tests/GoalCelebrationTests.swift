import XCTest
import CoreData
@testable import Waypoint

/// Finishing a goal is celebrated once, by the tick that finished it, and never again.
///
/// Worth testing rather than eyeballing because every interesting case is a *silence*: the
/// demo fixture loading, a task auto-completing, re-ticking something already celebrated.
/// A bug in any of those shows up as a full-screen takeover at a moment nobody did anything
/// to earn, which is exactly the sort of thing that reaches a user before it reaches a test.
@MainActor
final class GoalCelebrationTests: XCTestCase {
    var context: NSManagedObjectContext!

    override func setUp() {
        super.setUp()
        context = PersistenceController(inMemory: true).container.viewContext
        GoalCelebrations.shared.forgetAll()
        GoalCelebrations.shared.pending = nil
    }

    override func tearDown() {
        GoalCelebrations.shared.forgetAll()
        GoalCelebrations.shared.pending = nil
        super.tearDown()
    }

    private func makeGoal(name: String = "Learn Spanish", taskCount: Int) -> (GoalEntity, [TaskEntity]) {
        let goal = GoalEntity.create(
            in: context,
            name: name,
            targetDate: Calendar.current.date(byAdding: .day, value: 45, to: .now)!,
            planningMode: .manual
        )
        let tasks = (0..<taskCount).map { i in
            TaskEntity.create(
                in: context,
                title: "Task \(i)",
                date: .now,
                startTime: .now,
                durationMinutes: 30,
                priority: .medium,
                goal: goal
            )
        }
        return (goal, tasks)
    }

    func testNothingHappensUntilTheLastTaskIsTicked() {
        let (_, tasks) = makeGoal(taskCount: 3)

        tasks[0].toggleDone(in: context)
        XCTAssertNil(GoalCelebrations.shared.pending)

        tasks[1].toggleDone(in: context)
        XCTAssertNil(GoalCelebrations.shared.pending)

        tasks[2].toggleDone(in: context)
        XCTAssertNotNil(GoalCelebrations.shared.pending)
    }

    func testTheCelebrationCarriesTheGoalsOwnNumbers() throws {
        let (_, tasks) = makeGoal(name: "Run a half marathon", taskCount: 2)
        tasks.forEach { $0.toggleDone(in: context) }

        let celebration = try XCTUnwrap(GoalCelebrations.shared.pending)
        XCTAssertEqual(celebration.name, "Run a half marathon")
        XCTAssertEqual(celebration.tasksDone, 2)
    }

    /// Un-ticking and re-ticking is not a second achievement.
    func testAGoalIsOnlyEverCelebratedOnce() {
        let (_, tasks) = makeGoal(taskCount: 2)
        tasks.forEach { $0.toggleDone(in: context) }
        XCTAssertNotNil(GoalCelebrations.shared.pending)

        GoalCelebrations.shared.pending = nil      // as if the screen were dismissed
        tasks[1].toggleDone(in: context)           // un-tick
        tasks[1].toggleDone(in: context)           // and tick again

        XCTAssertNil(GoalCelebrations.shared.pending)
    }

    /// `markAutoCompleted` is a task's window elapsing, not somebody finishing something.
    func testATaskCompletingItselfDoesNotCelebrate() {
        let (_, tasks) = makeGoal(taskCount: 2)
        tasks[0].toggleDone(in: context)
        tasks[1].markAutoCompleted()

        XCTAssertNil(GoalCelebrations.shared.pending)
    }

    /// The demo fixture sets `isDone` directly on forty-five days of history. If that
    /// reached the celebration, `-wpReseed` would open a party for a goal nobody has seen.
    func testSeedingHistoryDirectlyDoesNotCelebrate() {
        let (_, tasks) = makeGoal(taskCount: 2)
        tasks.forEach { $0.isDone = true }

        XCTAssertNil(GoalCelebrations.shared.pending)
    }

    func testAGoalWithNoTasksIsNotConsideredFinished() {
        let (goal, _) = makeGoal(taskCount: 0)
        GoalCelebrations.shared.noteCompletion(of: goal)

        XCTAssertNil(GoalCelebrations.shared.pending)
    }
}
