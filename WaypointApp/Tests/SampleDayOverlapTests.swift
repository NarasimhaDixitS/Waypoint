import XCTest
import CoreData
@testable import Waypoint

/// The seeded day must not contradict the app.
///
/// Waypoint's whole premise is that two things can't quietly sit on top of each other. The
/// fixture was placing today's tasks at "now plus an offset, or a fixed hour if that overflows
/// the day" — so generating it in the evening put every fallback inside the in-progress task,
/// and the demo showed two tasks running at once. That is the one thing the app claims to
/// prevent, shown on the screen used to sell it.
@MainActor
final class SampleDayOverlapTests: XCTestCase {
    var context: NSManagedObjectContext!

    override func setUp() {
        super.setUp()
        context = PersistenceController(inMemory: true).container.viewContext
    }

    private func todaysTasks() -> [TaskEntity] {
        let request = TaskEntity.fetchRequest(on: .now, context: context)
        return (try? context.fetch(request)) ?? []
    }

    func testNoTwoSeededTasksOverlapToday() {
        SampleData.loadDemo(into: context)

        let tasks = todaysTasks().sorted { $0.resolvedStartTime < $1.resolvedStartTime }
        for (a, b) in zip(tasks, tasks.dropFirst()) {
            XCTAssertLessThanOrEqual(
                a.endTime, b.resolvedStartTime,
                "\"\(a.title ?? "?")\" (\(a.resolvedStartTime)–\(a.endTime)) overlaps "
                + "\"\(b.title ?? "?")\" starting \(b.resolvedStartTime)"
            )
        }
    }

    /// The in-progress card is the fixture's most valuable state — it can't be staged, it
    /// depends on the clock at the moment you look. Exactly one, though: two is a collision.
    func testExactlyOneSeededTaskIsRunningRightNow() {
        SampleData.loadDemo(into: context)

        let running = todaysTasks().filter { $0.state(at: .now) == .inProgress }
        XCTAssertEqual(running.count, 1, "running now: \(running.compactMap(\.title))")
    }
}
