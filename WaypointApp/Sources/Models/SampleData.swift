import Foundation
import CoreData

/// Fills the app with a realistic month-and-a-half of activity so every screen has something to
/// show — the goal carousel needs more than one goal, the analytics bars need weeks that differ
/// from each other, the streak needs consecutive completed days ending today, and the Week tab
/// needs history *and* future to browse through.
///
/// Deterministic on purpose. It runs off a fixed seed rather than `Double.random`, so the demo
/// state is the same every time you load it — you can compare a design change against the screen
/// you were looking at a minute ago instead of against a different set of tasks.
enum SampleData {
    /// Replaces all tasks, goals and history. Leaves commitments and every preference alone —
    /// those are the user's own setup, and blowing away a configured Work/Gym schedule to look
    /// at some demo tasks would be a bad trade.
    static func loadDemo(into context: NSManagedObjectContext) {
        var rng = SeededGenerator(seed: 0x5A_FE_D0_0D)
        clearContent(in: context)
        seedCommitmentsIfEmpty(in: context)

        let goals = seedGoals(in: context)
        seedHistory(in: context, goals: goals, rng: &rng)
        seedStreak(in: context, goal: goals[0])
        seedToday(in: context, goals: goals)
        seedUpcoming(in: context, goals: goals, rng: &rng)
        seedRepeatSeries(in: context, goal: goals[0])
        seedEventHistory(in: context, goals: goals, rng: &rng)

        do {
            try context.save()
        } catch {
            assertionFailure("Demo seed failed: \(error)")
        }
    }

    // MARK: - Clearing

    private static func clearContent(in context: NSManagedObjectContext) {
        // Deleting the goals cascades to their tasks; the ungoaled ones and the event log have
        // to be swept separately.
        for entity in ["TaskEntity", "GoalEntity", "TaskEventEntity"] {
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: entity)
            guard let objects = try? context.fetch(request) as? [NSManagedObject] else { continue }
            objects.forEach(context.delete)
        }
    }

    private static func seedCommitmentsIfEmpty(in context: NSManagedObjectContext) {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "CommitmentEntity")
        let existing = (try? context.count(for: request)) ?? 0
        guard existing == 0 else { return }
        let weekdays = CommitmentEntity.weekdaySymbols.filter { $0 != "Sat" && $0 != "Sun" }
        _ = CommitmentEntity.create(in: context, name: "Work", icon: "work", days: weekdays, startTime: time(9, 0), endTime: time(17, 0))
        _ = CommitmentEntity.create(in: context, name: "Gym", icon: "gym", days: ["Mon", "Wed", "Fri"], startTime: time(7, 0), endTime: time(8, 30))
    }

    // MARK: - Goals

    /// Four, spread deliberately across the states a goal can be in: one nearly finished and
    /// nearly out of time, one mid-flight, one just started, and one AI-planned so that mode is
    /// visible without having to make one.
    private static func seedGoals(in context: NSManagedObjectContext) -> [GoalEntity] {
        let specs: [(String, Int, Int, PlanningMode, String?)] = [
            ("Half marathon", -40, 44, .manual, "Sub-2:00 at the city run. Long run Sundays, intervals Wednesdays."),
            ("Ship Waypoint v1", -25, 70, .manual, "Free tier polished, Pro trends behind a paywall, on the App Store."),
            ("Read 12 books", -60, 18, .manual, nil),
            ("Learn Spanish", -10, 110, .ai, "Conversational by spring — 20 minutes a day, no excuses."),
        ]
        return specs.map { name, createdOffset, targetOffset, mode, notes in
            let goal = GoalEntity.create(
                in: context,
                name: name,
                targetDate: day(offset: targetOffset),
                planningMode: mode,
                notes: notes
            )
            goal.createdAt = day(offset: createdOffset)
            return goal
        }
    }

    // MARK: - History

    private static let historyTitles = [
        "Half marathon": ["Easy 5k", "Interval session", "Long run", "Recovery jog", "Strength — legs", "Foam roll and stretch"],
        "Ship Waypoint v1": ["Fix scheduling edge case", "Write release notes", "Review PR backlog", "Polish the Week tab", "Screenshot pass for the store", "Triage crash reports"],
        "Read 12 books": ["Read — 30 pages", "Finish current chapter", "Write up notes", "Pick the next book"],
        "Learn Spanish": ["Vocab drill — 20 min", "Listening practice", "Speak with tutor", "Review verb tenses"],
    ]

    private static let looseTitles = [
        "Grocery run", "Call Mum", "Inbox to zero", "Meal prep", "Pay the electricity bill",
        "Tidy the desk", "Book the dentist", "Water the plants", "Laundry",
    ]

    private static let noteSamples = [
        "Felt harder than it should have — check sleep.",
        "Blocked on the API key, ask about it tomorrow.",
        "Bring the resistance bands.",
        "Chapter 7 onward; skim the appendix.",
    ]

    /// Forty-five days back. Completion rate is stepped per week rather than uniform, so the
    /// analytics bars actually differ from one another — a flat 75% everywhere makes the chart
    /// look broken rather than calm.
    private static let weeklyCompletionRate: [Double] = [0.92, 0.55, 0.81, 0.44, 0.76, 0.68, 0.85]

    private static func seedHistory(
        in context: NSManagedObjectContext,
        goals: [GoalEntity],
        rng: inout SeededGenerator
    ) {
        for offset in stride(from: -45, through: -1, by: 1) {
            let date = day(offset: offset)
            let week = min(abs(offset) / 7, weeklyCompletionRate.count - 1)
            let rate = weeklyCompletionRate[week]
            let count = Int.random(in: 1...4, using: &rng)

            for slot in 0..<count {
                let goal = pickGoal(goals, rng: &rng)
                let title = pickTitle(for: goal, rng: &rng)
                let hour = [7, 9, 11, 14, 17, 19][slot % 6]
                let task = TaskEntity.create(
                    in: context,
                    title: title,
                    date: date,
                    startTime: at(hour: hour, on: date),
                    durationMinutes: [30, 45, 60, 90].randomElement(using: &rng)!,
                    priority: Priority.allCases.randomElement(using: &rng)!,
                    goal: goal,
                    notes: Double.random(in: 0...1, using: &rng) < 0.18 ? noteSamples.randomElement(using: &rng) : nil
                )
                // Anything left undone on a past day reads as overdue, which is exactly the
                // state we want represented — just not on every other row.
                if Double.random(in: 0...1, using: &rng) < rate {
                    task.isDone = true
                    task.completedAt = at(hour: hour + 1, on: date)
                }
            }
        }
    }

    /// `dayStreak` counts back from today and stops at the first day with nothing completed, so
    /// a streak has to be built explicitly — random history almost never produces one.
    private static func seedStreak(in context: NSManagedObjectContext, goal: GoalEntity) {
        for offset in stride(from: -8, through: -1, by: 1) {
            let date = day(offset: offset)
            let task = TaskEntity.create(
                in: context,
                title: "Morning miles",
                date: date,
                startTime: at(hour: 6, on: date),
                durationMinutes: 40,
                priority: .medium,
                goal: goal
            )
            task.isDone = true
            task.completedAt = at(hour: 7, on: date)
        }
    }

    // MARK: - Today

    /// Today carries one of everything the row can show: a finished task, one running *right
    /// now* so the waterline animates, a high-priority pending one, and a couple still to come.
    private static func seedToday(in context: NSManagedObjectContext, goals: [GoalEntity]) {
        let today = day(offset: 0)

        let done = TaskEntity.create(
            in: context, title: "Morning miles", date: today,
            startTime: at(hour: 6, on: today), durationMinutes: 40,
            priority: .medium, goal: goals[0]
        )
        done.isDone = true
        done.completedAt = at(hour: 7, on: today)

        // Started twenty minutes ago and running for another forty — the one state you can't
        // stage after the fact, since it depends on the clock at the moment you look.
        TaskEntity.create(
            in: context, title: "Deep work — Week tab polish", date: today,
            startTime: Date.now.addingTimeInterval(-20 * 60), durationMinutes: 60,
            priority: .high, goal: goals[1],
            notes: "Agenda layout for the expanded card."
        )

        TaskEntity.create(
            in: context, title: "Review PR backlog", date: today,
            startTime: laterToday(hours: 2, fallbackHour: 19), durationMinutes: 45,
            priority: .high, goal: goals[1]
        )
        TaskEntity.create(
            in: context, title: "Read — 30 pages", date: today,
            startTime: laterToday(hours: 4, fallbackHour: 20), durationMinutes: 30,
            priority: .low, goal: goals[2],
            notes: "Chapter 7 onward; skim the appendix."
        )
        TaskEntity.create(
            in: context, title: "Vocab drill — 20 min", date: today,
            startTime: laterToday(hours: 6, fallbackHour: 21), durationMinutes: 20,
            priority: .medium, goal: goals[3]
        )
    }

    private static func seedUpcoming(
        in context: NSManagedObjectContext,
        goals: [GoalEntity],
        rng: inout SeededGenerator
    ) {
        for offset in 1...21 {
            let date = day(offset: offset)
            for slot in 0..<Int.random(in: 1...3, using: &rng) {
                let goal = pickGoal(goals, rng: &rng)
                TaskEntity.create(
                    in: context,
                    title: pickTitle(for: goal, rng: &rng),
                    date: date,
                    startTime: at(hour: [8, 12, 16, 18][slot % 4], on: date),
                    durationMinutes: [30, 45, 60].randomElement(using: &rng)!,
                    priority: Priority.allCases.randomElement(using: &rng)!,
                    goal: goal
                )
            }
        }
    }

    /// One real repeat series, so "delete this and future occurrences" has something to act on.
    private static func seedRepeatSeries(in context: NSManagedObjectContext, goal: GoalEntity) {
        let seriesID = UUID()
        let cal = Calendar.current
        for offset in stride(from: -21, through: 28, by: 1) {
            let date = day(offset: offset)
            let weekday = (cal.component(.weekday, from: date) + 5) % 7
            guard weekday == 2 || weekday == 5 else { continue } // Wed and Sat
            let task = TaskEntity.create(
                in: context,
                title: "Interval session",
                date: date,
                startTime: at(hour: 18, on: date),
                durationMinutes: 50,
                priority: .high,
                goal: goal,
                seriesID: seriesID
            )
            if offset < 0 {
                task.isDone = true
                task.completedAt = at(hour: 19, on: date)
            }
        }
    }

    // MARK: - Behaviour log

    /// Deferrals and abandonments across the same window, so the Pro trends work has real shapes
    /// to be built against rather than an empty table. The goal-level row deliberately names a
    /// goal that no longer exists — that's the normal case, and it's what the denormalized title
    /// on the event is for.
    private static func seedEventHistory(
        in context: NSManagedObjectContext,
        goals: [GoalEntity],
        rng: inout SeededGenerator
    ) {
        for _ in 0..<16 {
            let when = day(offset: -Int.random(in: 1...44, using: &rng))
            let slip = Int.random(in: 1...5, using: &rng)
            let goal = pickGoal(goals, rng: &rng)
            let event = TaskEventEntity(context: context)
            event.id = UUID()
            event.kind = TaskEventKind.deferred.rawValue
            event.occurredAt = when
            event.taskID = UUID()
            event.goalID = goal?.id
            event.title = pickTitle(for: goal, rng: &rng)
            event.fromDate = when
            event.toDate = Calendar.current.date(byAdding: .day, value: slip, to: when)
        }

        for _ in 0..<5 {
            let when = day(offset: -Int.random(in: 1...44, using: &rng))
            let goal = pickGoal(goals, rng: &rng)
            let event = TaskEventEntity(context: context)
            event.id = UUID()
            event.kind = TaskEventKind.abandoned.rawValue
            event.occurredAt = when
            event.taskID = UUID()
            event.goalID = goal?.id
            event.title = pickTitle(for: goal, rng: &rng)
            event.fromDate = when
        }

        let quit = TaskEventEntity(context: context)
        quit.id = UUID()
        quit.kind = TaskEventKind.goalAbandoned.rawValue
        quit.occurredAt = day(offset: -30)
        quit.goalID = UUID()
        quit.title = "Wake at 5am"
        quit.fromDate = day(offset: -58)
        quit.toDate = day(offset: 30)
    }

    // MARK: - Helpers

    private static func pickGoal(_ goals: [GoalEntity], rng: inout SeededGenerator) -> GoalEntity? {
        // A quarter of everything belongs to no goal — a to-do list isn't all project work, and
        // the ungoaled rows are the ones that prove the goal chip is optional.
        Double.random(in: 0...1, using: &rng) < 0.25 ? nil : goals.randomElement(using: &rng)
    }

    private static func pickTitle(for goal: GoalEntity?, rng: inout SeededGenerator) -> String {
        guard let name = goal?.name, let pool = historyTitles[name] else {
            return looseTitles.randomElement(using: &rng)!
        }
        return pool.randomElement(using: &rng)!
    }

    private static func day(offset: Int) -> Date {
        let cal = Calendar.current
        return cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: .now))!
    }

    private static func at(hour: Int, on date: Date) -> Date {
        let cal = Calendar.current
        return cal.date(bySettingHour: min(hour, 23), minute: 0, second: 0, of: date) ?? date
    }

    /// Kept inside today so a late-evening load doesn't push "later today" past midnight, where
    /// the tasks would land on tomorrow and today would look half-empty.
    ///
    /// `fallbackHour` rather than a shared 22:00 ceiling: clamping every offset to one cutoff
    /// collapsed all three of today's remaining tasks onto the same minute, which is both
    /// unrealistic and useless for looking at a list.
    private static func laterToday(hours: Int, fallbackHour: Int) -> Date {
        let candidate = Date.now.addingTimeInterval(Double(hours) * 3600)
        let cutoff = at(hour: 22, on: day(offset: 0))
        return candidate <= cutoff ? candidate : at(hour: fallbackHour, on: day(offset: 0))
    }

    private static func time(_ hour: Int, _ minute: Int) -> Date {
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.date(from: comps)!
    }
}

/// SplitMix64 — small, fast, and identical across runs and platforms, which the system generator
/// deliberately isn't. The point is a demo you can load twice and get the same screen.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
