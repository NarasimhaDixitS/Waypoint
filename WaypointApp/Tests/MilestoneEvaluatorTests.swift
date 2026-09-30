import XCTest
import CoreData
@testable import Waypoint

/// Milestones turn true at date boundaries with nobody present, and a wrong one is awarded
/// silently and permanently. These check the edges rather than the happy path.
@MainActor
final class MilestoneEvaluatorTests: XCTestCase {
    var context: NSManagedObjectContext!

    override func setUp() {
        super.setUp()
        context = PersistenceController(inMemory: true).container.viewContext
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: 9))!
    }

    @discardableResult
    private func task(
        on date: Date, done: Bool = true, minutes: Int = 60,
        priority: Priority = .medium, title: String = "Task", completedAt: Date? = nil
    ) -> TaskEntity {
        let t = TaskEntity.create(
            in: context, title: title, date: date, startTime: date,
            durationMinutes: minutes, priority: priority
        )
        t.isDone = done
        t.completedAt = done ? (completedAt ?? date) : nil
        return t
    }

    private func event(_ kind: TaskEventKind, title: String = "Task", at when: Date) {
        let e = TaskEventEntity(context: context)
        e.id = UUID()
        e.kind = kind.rawValue
        e.title = title
        e.occurredAt = when
    }

    private func evaluate(now: Date, already: Set<String> = []) -> [MilestoneEvaluator.Earned] {
        MilestoneEvaluator.newlyEarned(.init(
            tasks: (try? context.fetch(TaskEntity.fetchRequest())) ?? [],
            events: (try? context.fetch(TaskEventEntity.fetchRequest())) ?? [],
            sessions: (try? context.fetch(FocusSessionEntity.fetchRequest(since: nil))) ?? [],
            goals: (try? context.fetch(GoalEntity.fetchRequest())) ?? [],
            alreadyEarned: already,
            now: now
        ))
    }

    // MARK: - Nothing is given away

    func testAnEmptyHistoryEarnsNothing() {
        XCTAssertTrue(evaluate(now: day(2026, 9, 30)).isEmpty)
    }

    /// Something already recorded is never handed out twice.
    func testAnAlreadyEarnedMilestoneIsNotRepeated() {
        for i in 0..<100 { task(on: day(2026, 8, 1).addingTimeInterval(Double(i) * 3600)) }
        let first = evaluate(now: day(2026, 9, 30))
        XCTAssertTrue(first.contains { $0.kind == .hundredTasks })

        let second = evaluate(now: day(2026, 9, 30), already: ["hundredTasks"])
        XCTAssertFalse(second.contains { $0.kind == .hundredTasks })
    }

    /// Passing a thousand shouldn't hand over three at once — the smaller tiers stopped being
    /// news long before.
    func testOnlyTheHighestUnearnedVolumeTierIsAwarded() {
        for i in 0..<520 { task(on: day(2026, 8, 1).addingTimeInterval(Double(i) * 600)) }
        let volume = evaluate(now: day(2026, 9, 30)).filter {
            [.hundredTasks, .fiveHundredTasks, .thousandTasks].contains($0.kind)
        }
        XCTAssertEqual(volume.count, 1)
        XCTAssertEqual(volume.first?.kind, .fiveHundredTasks)
    }

    // MARK: - Consistency

    /// A day with nothing scheduled is not a gap. Counting it as one would make this
    /// unearnable for anyone who takes a day off.
    func testAPerfectWeekIgnoresDaysWithNoWork() {
        for offset in [0, 1, 3, 4] {
            task(on: Calendar.current.date(byAdding: .day, value: offset, to: day(2026, 9, 7))!)
        }
        XCTAssertTrue(evaluate(now: day(2026, 9, 20)).contains { $0.kind == .perfectWeek })
    }

    func testAWeekWithAnUnfinishedDayIsNotPerfect() {
        for offset in [0, 1, 2, 3] {
            task(on: Calendar.current.date(byAdding: .day, value: offset, to: day(2026, 9, 7))!,
                 done: offset != 2)
        }
        XCTAssertFalse(evaluate(now: day(2026, 9, 20)).contains { $0.kind == .perfectWeek })
    }

    /// A week still in progress can't have been perfect yet.
    func testTheCurrentWeekIsNeverAwarded() {
        for offset in 0..<3 {
            task(on: Calendar.current.date(byAdding: .day, value: offset, to: day(2026, 9, 28))!)
        }
        XCTAssertFalse(evaluate(now: day(2026, 9, 30)).contains { $0.kind == .perfectWeek })
    }

    /// An empty week isn't restraint.
    func testAQuietWeekDoesNotCountAsZeroDeferrals() {
        task(on: day(2026, 9, 8))
        task(on: day(2026, 9, 9))
        XCTAssertFalse(evaluate(now: day(2026, 9, 30)).contains { $0.kind == .zeroDeferralWeek })
    }

    func testAFullWeekWithNoDeferralsIsAwarded() {
        for offset in 0..<6 {
            task(on: Calendar.current.date(byAdding: .day, value: offset, to: day(2026, 9, 7))!)
        }
        XCTAssertTrue(evaluate(now: day(2026, 9, 30)).contains { $0.kind == .zeroDeferralWeek })
    }

    func testADeferralInThatWeekBlocksIt() {
        for offset in 0..<6 {
            task(on: Calendar.current.date(byAdding: .day, value: offset, to: day(2026, 9, 7))!)
        }
        event(.deferred, at: day(2026, 9, 9))
        XCTAssertFalse(evaluate(now: day(2026, 9, 30)).contains { $0.kind == .zeroDeferralWeek })
    }

    /// A gap of one day resets it — that's what "consecutive" means.
    func testAStreakNeedsConsecutiveDays() {
        for offset in 0..<40 where offset != 20 {
            let d = Calendar.current.date(byAdding: .day, value: offset, to: day(2026, 8, 1))!
            task(on: d, completedAt: d)
        }
        XCTAssertFalse(evaluate(now: day(2026, 9, 30)).contains { $0.kind == .thirtyDayStreak })

        for offset in 0..<31 {
            let d = Calendar.current.date(byAdding: .day, value: offset, to: day(2026, 6, 1))!
            task(on: d, completedAt: d)
        }
        XCTAssertTrue(evaluate(now: day(2026, 9, 30)).contains { $0.kind == .thirtyDayStreak })
    }

    // MARK: - Self-knowledge

    /// The distinctive one: it needs the deferral log, which is the thing no other app has.
    func testFinallyDidItNeedsFiveDeferralsAndThenCompletion() {
        for i in 0..<5 { event(.deferred, title: "Taxes", at: day(2026, 9, 1 + i)) }
        XCTAssertFalse(evaluate(now: day(2026, 9, 30)).contains { $0.kind == .finallyDidIt },
                       "five deferrals alone is avoidance, not the milestone")

        task(on: day(2026, 9, 20), title: "Taxes")
        let earned = evaluate(now: day(2026, 9, 30)).first { $0.kind == .finallyDidIt }
        XCTAssertNotNil(earned)
        XCTAssertEqual(earned?.context, "Taxes")
        XCTAssertEqual(earned?.value, 5)
    }

    func testFourDeferralsIsNotEnough() {
        for i in 0..<4 { event(.deferred, title: "Taxes", at: day(2026, 9, 1 + i)) }
        task(on: day(2026, 9, 20), title: "Taxes")
        XCTAssertFalse(evaluate(now: day(2026, 9, 30)).contains { $0.kind == .finallyDidIt })
    }

    /// Most people's numbers run the other way, which is what makes this worth marking.
    func testHardThingsFirstNeedsHighToBeatLow() {
        for i in 0..<6 { task(on: day(2026, 8, 1 + i), done: true, priority: .high) }
        for i in 0..<6 { task(on: day(2026, 8, 10 + i), done: i < 2, priority: .low) }
        XCTAssertTrue(evaluate(now: day(2026, 9, 30)).contains { $0.kind == .hardThingsFirst })
    }

    func testHardThingsFirstIsNotAwardedWhenEasyWorkWins() {
        for i in 0..<6 { task(on: day(2026, 8, 1 + i), done: i < 2, priority: .high) }
        for i in 0..<6 { task(on: day(2026, 8, 10 + i), done: true, priority: .low) }
        XCTAssertFalse(evaluate(now: day(2026, 9, 30)).contains { $0.kind == .hardThingsFirst })
    }
}
