import XCTest
import CoreData
@testable import Waypoint

@MainActor
final class SearchResultsTests: XCTestCase {
    var context: NSManagedObjectContext!

    override func setUp() {
        super.setUp()
        context = PersistenceController(inMemory: true).container.viewContext
    }

    private let today = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 7))!

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: today)!
    }

    @discardableResult
    private func task(_ title: String, _ offset: Int, notes: String? = nil, goal: GoalEntity? = nil) -> TaskEntity {
        let d = day(offset)
        let t = TaskEntity.create(
            in: context, title: title, date: d,
            startTime: Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: d)!,
            durationMinutes: 30, priority: .medium, goal: goal, notes: notes
        )
        return t
    }

    private func goal(_ name: String, notes: String? = nil) -> GoalEntity {
        GoalEntity.create(in: context, name: name, targetDate: day(100), planningMode: .manual, notes: notes)
    }

    private func titles(_ ts: [TaskEntity]) -> [String] { ts.compactMap(\.title) }

    // MARK: - Ordering

    func testResultsStartNearestToTodayRatherThanOldestInTheDatabase() {
        task("Interval session", -42)
        task("Interval session", -1)
        task("Interval session", 3)

        let out = SearchResults.tasks(matching: "interval", in: fetchAll(), now: today)

        XCTAssertEqual(out.map { Calendar.current.dateComponents([.day], from: today, to: $0.resolvedDate).day },
                       [-1, 3, -42],
                       "the fetch is oldest-first, so without re-sorting the six-week-old one led")
    }

    func testAtEqualDistanceTheFutureComesFirst() {
        task("Gym", -2)
        task("Gym", 2)

        XCTAssertEqual(
            SearchResults.tasks(matching: "gym", in: fetchAll(), now: today)
                .map { $0.resolvedDate > today },
            [true, false],
            "tomorrow is more use than yesterday when both are the same distance away"
        )
    }

    // MARK: - What matches

    func testATaskIsNotAMatchBecauseItsGoalNameIs() {
        let spanish = goal("Learn Spanish")
        task("Vocab drill", 1, goal: spanish)
        task("Spanish podcast", 2)

        XCTAssertEqual(titles(SearchResults.tasks(matching: "spanish", in: fetchAll(), now: today)),
                       ["Spanish podcast"],
                       "membership of a matching goal is what the goal result is for")
    }

    func testTheGoalItselfIsAResult() {
        let spanish = goal("Learn Spanish")
        _ = goal("Half marathon")

        XCTAssertEqual(SearchResults.goals(matching: "spanish", in: [spanish]).count, 1)
        XCTAssertTrue(SearchResults.goals(matching: "marathon", in: [spanish]).isEmpty)
    }

    func testNotesAreSearched() {
        task("Call the bank", 1, notes: "ask about the API key")
        task("Unrelated", 1)

        // A task whose title says nothing useful is findable by what you wrote on it, which was
        // the point: "Call the bank" is not what anyone types when looking for this.
        XCTAssertEqual(titles(SearchResults.tasks(matching: "api key", in: fetchAll(), now: today)),
                       ["Call the bank"])
        XCTAssertEqual(titles(SearchResults.tasks(matching: "API", in: fetchAll(), now: today)),
                       ["Call the bank"])
    }

    func testMatchingIsSubstringRatherThanFuzzy() {
        task("Call the bank", 1, notes: "ask about the API key")

        XCTAssertTrue(
            SearchResults.tasks(matching: "key api", in: fetchAll(), now: today).isEmpty,
            "words out of order are not a match; this is contains, not a search engine"
        )
    }

    func testGoalNotesAreSearched() {
        let g = goal("Half marathon", notes: "Sub-2:00 at the city run")

        XCTAssertEqual(SearchResults.goals(matching: "city run", in: [g]).count, 1)
    }

    func testMatchingIsCaseInsensitive() {
        task("Morning MILES", 0)

        XCTAssertEqual(titles(SearchResults.tasks(matching: "miles", in: fetchAll(), now: today)),
                       ["Morning MILES"])
    }

    // MARK: - Nothing to match

    func testAnEmptyOrBlankQueryMatchesNothing() {
        task("Anything", 0)
        _ = goal("Anything")

        for q in ["", "   ", "\n"] {
            XCTAssertTrue(SearchResults.tasks(matching: q, in: fetchAll(), now: today).isEmpty)
            XCTAssertTrue(SearchResults.goals(matching: q, in: fetchAllGoals()).isEmpty)
        }
    }

    // MARK: -

    private func fetchAll() -> [TaskEntity] {
        let r = TaskEntity.fetchRequest()
        r.sortDescriptors = [NSSortDescriptor(keyPath: \TaskEntity.startTime, ascending: true)]
        return (try? context.fetch(r)) ?? []
    }

    private func fetchAllGoals() -> [GoalEntity] {
        (try? context.fetch(NSFetchRequest<GoalEntity>(entityName: "GoalEntity"))) ?? []
    }
}
