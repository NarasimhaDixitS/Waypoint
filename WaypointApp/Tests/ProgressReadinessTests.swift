import XCTest
import CoreData
@testable import Waypoint

/// The badge promises a chart. If readiness disagrees with what the card does, the promise is
/// broken — the user taps through to a blank page, which is worse than never being told.
@MainActor
final class ProgressReadinessTests: XCTestCase {
    var context: NSManagedObjectContext!

    override func setUp() {
        super.setUp()
        context = PersistenceController(inMemory: true).container.viewContext
        ProgressNews.reset()
    }

    override func tearDown() {
        ProgressNews.reset()
        super.tearDown()
    }

    private let today = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 8))!

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: today)!
    }

    @discardableResult
    private func task(_ title: String, _ offset: Int, done: Bool = false, hour: Int = 9) -> TaskEntity {
        let d = day(offset)
        let t = TaskEntity.create(
            in: context, title: title, date: d,
            startTime: Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: d)!,
            durationMinutes: 30, priority: .medium
        )
        t.isDone = done
        // `hasObservedCompletionTime` wants a real timestamp and no auto-completion — ticking
        // `isDone` alone leaves the time-of-day chart with nothing to plot, which is correct
        // and was my test's mistake, not the code's.
        if done { t.completedAt = Calendar.current.date(bySettingHour: hour, minute: 10, second: 0, of: d) }
        return t
    }

    private func ready(_ tasks: [TaskEntity] = [], events: [TaskEventEntity] = []) -> Set<ProgressChart> {
        ProgressReadiness.ready(
            tasks: tasks, events: events, sessions: [], goal: nil, effortWeeks: 6
        )
    }

    // MARK: - A brand-new account

    func testAnEmptyAccountHasNothingReady() {
        XCTAssertTrue(ready().isEmpty, "day one is a pitch, not a dashboard")
    }

    func testOneScheduledDayIsEnoughForTheWeekdayChart() {
        let t = task("Gym", -1, done: true)

        let out = ready([t])

        XCTAssertTrue(out.contains(.weekday))
        XCTAssertFalse(out.contains(.timeOfDay), "eight completions is that card's own threshold")
    }

    func testTimeOfDayNeedsEightObservedCompletions() {
        var tasks: [TaskEntity] = []
        for i in 1...7 { tasks.append(task("t\(i)", -i, done: true, hour: 9)) }
        XCTAssertFalse(ready(tasks).contains(.timeOfDay))

        tasks.append(task("t8", -8, done: true, hour: 9))
        XCTAssertTrue(ready(tasks).contains(.timeOfDay))
    }

    // MARK: - News

    func testEverythingReadyIsNewsUntilProgressIsOpened() {
        let t = task("Gym", -1, done: true)
        let out = ready([t])

        XCTAssertEqual(ProgressNews.unseen(in: out), out, "nothing has been shown yet")

        ProgressNews.markSeen(out)
        XCTAssertTrue(ProgressNews.unseen(in: out).isEmpty)
    }

    func testAChartThatBecomesReadyLaterStillGetsItsMoment() {
        let first = task("Gym", -1, done: true)
        let early = ready([first])
        ProgressNews.markSeen(early)
        XCTAssertTrue(ProgressNews.unseen(in: early).isEmpty)

        // Enough completions arrive for the time-of-day card.
        var tasks = [first]
        for i in 2...9 { tasks.append(task("t\(i)", -i, done: true, hour: 14)) }
        let later = ready(tasks)

        XCTAssertTrue(later.contains(.timeOfDay))
        XCTAssertEqual(ProgressNews.unseen(in: later), [.timeOfDay],
                       "marking the early ones seen must not silence the one that arrives later")
    }

    func testSeenChartsStaySeenAcrossRecomputation() {
        let t = task("Gym", -1, done: true)
        ProgressNews.markSeen(ready([t]))

        XCTAssertTrue(ProgressNews.unseen(in: ready([t])).isEmpty)
    }

    // MARK: - Every chart has a promise to show on day one

    func testEveryChartCanDescribeItselfBeforeItHasData() {
        for chart in ProgressChart.allCases {
            XCTAssertFalse(chart.promise.isEmpty, "\(chart) has nothing to promise a new user")
            XCTAssertFalse(chart.promise.hasSuffix("."), "promises are joined into a sentence")
        }
    }
}
