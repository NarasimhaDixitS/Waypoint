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

    private var sessions: [FocusSessionEntity] {
        (try? context.fetch(FocusSessionEntity.fetchRequest())) ?? []
    }

    private var estimates: [ProgressAnalytics.Estimate] {
        ProgressAnalytics.estimateAccuracy(sessions: sessions, tasks: tasks, limit: .max)
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

    /// A title is either a repeat or it isn't — never both.
    ///
    /// `historyTitles` once shared two titles with `seedRepeatSeries`, so the fixture held a
    /// "Vocab drill — 20 min" at 9pm that was part of a series and another at 4:41pm that
    /// wasn't. Selecting the second and deleting it correctly offered no series choice, while
    /// its twin three rows up did — which looks exactly like a broken feature and isn't one.
    func testNoTitleIsBothARepeatAndNotARepeat() {
        let byTitle = Dictionary(grouping: tasks, by: { $0.title ?? "" })

        for (title, group) in byTitle {
            let repeating = group.filter { $0.seriesID != nil }
            let oneOffs = group.filter { $0.seriesID == nil }
            XCTAssertTrue(
                repeating.isEmpty || oneOffs.isEmpty,
                "\"\(title)\" exists both as a series (\(repeating.count)) and as loose tasks (\(oneOffs.count)) — identical rows that behave differently read as a bug in the app"
            )
        }
    }

    /// The No-goal list has its own series-delete path, which needs something to act on.
    func testAtLeastOneRepeatSeriesHasNoGoal() {
        let goalless = tasks.filter { $0.seriesID != nil && $0.goal == nil }
        XCTAssertFalse(goalless.isEmpty, "the No-goal list could never show a repeat to delete")
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

    /// Every card that reads the log needs a shape to draw. A kind with no rows is a screen
    /// that can't be looked at, which is the one thing this fixture exists to prevent.
    func testTheBehaviourLogCoversEveryKindTheAppRecords() {
        let kinds = Set(events.compactMap(\.kindValue))
        XCTAssertEqual(
            kinds,
            [
                .deferred, .abandoned, .goalAbandoned, .goalCompleted,
                .rescheduledEarlier, .durationChanged, .priorityChanged, .completionUndone
            ]
        )
        XCTAssertTrue(
            events.contains { $0.kindValue == .durationChanged && $0.toValue > $0.fromValue },
            "the underestimate card needs a budget that actually went up"
        )
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

    /// Everything that draws a run of days asks when this person started, and answers it from
    /// the earliest `createdAt`. A fixture that stamps all of it with the seeding moment claims
    /// the user started today — which renders its own forty-five days of history as days that
    /// predate them.
    func testHistoryIsNotAllStampedWithTheMomentItWasSeeded() {
        let context = self.context!
        guard let start = TaskEntity.firstActivityDate(in: context) else {
            return XCTFail("no tasks were seeded")
        }
        let daysBack = Calendar.current.dateComponents([.day], from: start, to: .now).day ?? 0
        XCTAssertGreaterThan(daysBack, 30, "the fixture should look like weeks of use, not day one")
        XCTAssertLessThanOrEqual(
            start, tasks.map(\.resolvedDate).min() ?? .now,
            "history starts no later than the earliest work in it"
        )
        XCTAssertTrue(
            tasks.allSatisfy { ($0.createdAt ?? .distantPast) <= .now },
            "nothing can claim to have been created in the future"
        )
    }

    // MARK: - Measured work

    /// The estimate card is the one analysis that can't be computed from tasks alone: a booked
    /// duration is a guess and a tick doesn't check it. With no sessions it drew its empty state
    /// however much history sat behind it, which is what this fixture existed to prevent.
    func testTimedWorkIsSeededSoTheEstimateCardHasSomethingToDraw() {
        XCTAssertGreaterThan(sessions.count, 20, "a handful of sessions makes for a chart of noise")
        XCTAssertTrue(
            sessions.allSatisfy { $0.taskID != nil && $0.plannedSeconds > 0 },
            "a session with no task or no booking can't be scored against an estimate"
        )
        XCTAssertFalse(estimates.isEmpty)
    }

    /// Both directions, because the card colours overruns differently from under-runs and a
    /// fixture that only ever ran long would leave half of its own legend unexplained.
    func testMeasuredWorkRunsBothLongAndShortOfItsEstimate() {
        XCTAssertTrue(estimates.contains { $0.ratio > 1.2 }, "nothing overran badly enough to notice")
        XCTAssertTrue(estimates.contains { $0.ratio < 0.85 }, "nothing came in under its booking")
    }

    /// One bar per title on the vertical axis, so two rows sharing a title are drawn on top of
    /// each other. Repeated titles are the norm — every occurrence of a repeating task shares
    /// one — so this is the fixture proving the grouping, not a quirk of the fixture.
    func testNoTwoEstimateRowsShareATitle() {
        let titles = estimates.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count)
        XCTAssertTrue(estimates.contains { $0.occurrences > 1 }, "nothing was measured more than once")
    }

    /// Sessions point at task ids. Leaving them behind on a reload would orphan every one of
    /// them, which reads on screen as the empty estimate card again.
    func testReloadingReplacesTimedWorkRatherThanOrphaningIt() {
        let before = sessions.count
        SampleData.loadDemo(into: context)
        XCTAssertEqual(sessions.count, before)
        XCTAssertFalse(estimates.isEmpty, "every session now points at a task that no longer exists")
    }

    // MARK: - Friction

    /// The habit card names the series slipping most, which needs more than one series and needs
    /// them kept at different rates.
    func testTwoHabitsAreSeededAndOneIsKeptWorseThanTheOther() {
        let habits = ProgressAnalytics.seriesAdherence(tasks)
        XCTAssertGreaterThanOrEqual(habits.count, 2)
        XCTAssertGreaterThan(
            Set(habits.map { Int($0.fraction * 100) }).count, 1,
            "identical adherence gives the card no habit to single out"
        )
        XCTAssertTrue(habits.contains { $0.fraction < 1 }, "a habit kept perfectly has nothing to show")
    }

    /// Something pushed off again and again and then actually done — the leaderboard's top row,
    /// and a shape random scatter won't produce: sixteen deferrals over four titles lands at
    /// three or four apiece.
    func testSomethingIsPutOffRepeatedlyAndThenFinished() {
        guard let worst = ProgressAnalytics.deferralLeaderboard(events).first else {
            return XCTFail("nothing was deferred")
        }
        XCTAssertGreaterThanOrEqual(worst.times, 5)
        XCTAssertTrue(
            tasks.contains { $0.title == worst.title && $0.isDone },
            "\(worst.title) was pushed \(worst.times) times and never done, so the story has no ending"
        )
    }

    /// Goals finished against goals given up on. The app recorded only the second of those for a
    /// long time, which made the pair read as a scoreboard of failure.
    func testGoalOutcomesAreSeededInBothDirections() {
        let outcomes = ProgressAnalytics.goalOutcomes(events)
        XCTAssertGreaterThan(outcomes.finished, 0)
        XCTAssertGreaterThan(outcomes.abandoned, 0)

        // And both inside the window the page opens on. Seeded further back, the tiles draw a
        // count beside a zero on first look, whatever the whole log says.
        let fourWeeksAgo = Calendar.current.date(byAdding: .day, value: -28, to: .now)!
        let recent = ProgressAnalytics.goalOutcomes(events.filter { ($0.occurredAt ?? .distantPast) >= fourWeeksAgo })
        XCTAssertGreaterThan(recent.finished, 0)
        XCTAssertGreaterThan(recent.abandoned, 0)
    }

    /// A completed goal still sitting in the carousel, part-done and with its target date ahead
    /// of it, means the log and the screen contradict each other.
    func testNoFinishedGoalInTheLogIsStillLiveAndUnfinished() {
        let live = Set(goals.filter { $0.completionFraction < 1 }.compactMap(\.name))
        for event in events where event.kindValue == .goalCompleted {
            XCTAssertFalse(live.contains(event.title ?? ""), "\(event.title ?? "") is both finished and in progress")
        }
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
