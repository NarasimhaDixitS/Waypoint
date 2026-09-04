import XCTest
import CoreData
@testable import Waypoint

/// The demo set exists to make every screen showable at once, so these assert *coverage* rather
/// than exact numbers — the point of the fixture is that nothing is missing, and a shape that
/// isn't represented is a screen you can't look at.
@MainActor
final class SampleDataTests: XCTestCase {
    var context: NSManagedObjectContext!

    override func setUp() {
        super.setUp()
        context = PersistenceController(inMemory: true).container.viewContext
        SampleData.loadDemo(into: context)
    }

    private var tasks: [TaskEntity] {
        (try? context.fetch(TaskEntity.fetchRequest())) ?? []
    }

    private var goals: [GoalEntity] {
        (try? context.fetch(GoalEntity.fetchRequest())) ?? []
    }

    private var events: [TaskEventEntity] {
        (try? context.fetch(TaskEventEntity.fetchRequest())) ?? []
    }

    func testProducesASubstantialAmountOfWork() {
        XCTAssertGreaterThan(tasks.count, 100)
    }

    /// Today's carousel only proves it's a carousel with more than one goal in it.
    func testSeedsSeveralGoalsAtDifferentStagesIncludingAnAIPlannedOne() {
        XCTAssertGreaterThanOrEqual(goals.count, 3)
        XCTAssertTrue(goals.contains { $0.planningModeValue == .ai })

        let fractions = goals.map(\.completionFraction)
        XCTAssertGreaterThan(
            Set(fractions.map { Int($0 * 10) }).count, 1,
            "goals should sit at visibly different progress, not all at the same percentage"
        )
    }

    /// Every row treatment on Today needs a task in that state to render it — `inProgress` in
    /// particular can't be staged after the fact, since it depends on the clock right now.
    func testEveryTaskStateIsRepresented() {
        let states = Set(tasks.map(\.state))
        for state in [TaskState.done, .overdue, .future, .inProgress, .pending] {
            XCTAssertTrue(states.contains(state), "no task is in the \(state) state, so that row can't be seen")
        }
    }

    func testTodayHasWorkInBothDirectionsOfTheDay() {
        let cal = Calendar.current
        let todays = tasks.filter { cal.isDateInToday($0.resolvedDate) }
        XCTAssertGreaterThanOrEqual(todays.count, 4)
        XCTAssertTrue(todays.contains { $0.isDone }, "the done-row treatment needs a done task today")
        XCTAssertTrue(todays.contains { !$0.isDone }, "and something still outstanding")
    }

    func testThereIsALiveStreak() {
        let streak = goals.map(\.dayStreak).max() ?? 0
        XCTAssertGreaterThan(streak, 1, "the streak counter reads zero without consecutive completed days")
    }

    /// "Delete this and future occurrences" needs a real series to act on.
    func testARepeatSeriesExistsSpanningPastAndFuture() {
        let series = Dictionary(grouping: tasks.compactMap { task -> (UUID, TaskEntity)? in
            task.seriesID.map { ($0, task) }
        }, by: \.0)
        guard let biggest = series.values.max(by: { $0.count < $1.count }) else {
            return XCTFail("no repeat series in the demo set")
        }
        XCTAssertGreaterThan(biggest.count, 4)
        let today = Calendar.current.startOfDay(for: .now)
        XCTAssertTrue(biggest.contains { $0.1.resolvedDate < today }, "series should have history")
        XCTAssertTrue(biggest.contains { $0.1.resolvedDate > today }, "and future occurrences")
    }

    func testPriorityAndNotesAreBothExercised() {
        XCTAssertEqual(Set(tasks.map(\.priorityValue)).count, Priority.allCases.count)
        XCTAssertTrue(tasks.contains { !($0.notes ?? "").isEmpty })
    }

    /// The Week tab browses months, so a month either side of this one has to have something in
    /// it — otherwise stepping back lands on an empty screen.
    func testHistoryAndFutureSpanMoreThanOneMonth() {
        let dates = tasks.map(\.resolvedDate)
        guard let earliest = dates.min(), let latest = dates.max() else { return XCTFail("no tasks") }
        let span = Calendar.current.dateComponents([.day], from: earliest, to: latest).day ?? 0
        XCTAssertGreaterThan(span, 45)
    }

    func testTheBehaviourLogHasAllThreeKinds() {
        let kinds = Set(events.compactMap(\.kindValue))
        XCTAssertEqual(kinds, [.deferred, .abandoned, .goalAbandoned])
        XCTAssertTrue(
            events.contains { ($0.slipInDays ?? 0) > 1 },
            "deferrals need varying slip lengths to be worth charting"
        )
    }

    /// Two loads should leave the same set, not two stacked sets — and the fixed seed should
    /// produce identical content, which is what makes it usable for comparing design changes.
    func testLoadingTwiceReplacesRatherThanAccumulates() {
        let firstCount = tasks.count
        let firstTitles = tasks.map { $0.title ?? "" }.sorted()

        SampleData.loadDemo(into: context)

        XCTAssertEqual(tasks.count, firstCount)
        XCTAssertEqual(tasks.map { $0.title ?? "" }.sorted(), firstTitles)
    }

    /// A configured Work/Gym schedule is the user's own setup, not demo content.
    func testExistingCommitmentsAreLeftAlone() {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "CommitmentEntity")
        let before = (try? context.count(for: request)) ?? 0
        XCTAssertGreaterThan(before, 0, "an empty install should still get a starting schedule")

        SampleData.loadDemo(into: context)

        XCTAssertEqual((try? context.count(for: request)) ?? 0, before, "commitments must not be duplicated or wiped")
    }
}
