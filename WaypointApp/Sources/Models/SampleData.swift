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
        seedRepeatSeries(in: context, goals: goals)
        seedEventHistory(in: context, goals: goals, rng: &rng)
        seedFocusSessions(in: context, rng: &rng)
        backdateCreationStamps(in: context)

        do {
            try context.save()
        } catch {
            assertionFailure("Demo seed failed: \(error)")
        }
    }

    // MARK: - Clearing

    private static func clearContent(in context: NSManagedObjectContext) {
        // Deleting the goals cascades to their tasks; the ungoaled ones and the side tables have
        // to be swept separately.
        //
        // Focus sessions and milestones are in here because both are *derived from* the content
        // being replaced. Left behind, the sessions would point at task ids that no longer exist
        // — which reads as an empty estimate card, the exact thing this seed is meant to fill —
        // and the milestones would be awards for a history that has been deleted, which also
        // stops them ever being awarded again. `AppSessionEntity` is deliberately not swept: an
        // app-open log is a record of the real person at the keyboard, not demo content.
        for entity in ["TaskEntity", "GoalEntity", "TaskEventEntity", "FocusSessionEntity", "MilestoneEntity"] {
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: entity)
            guard let objects = try? context.fetch(request) as? [NSManagedObject] else { continue }
            objects.forEach(context.delete)
        }
    }

/// Makes the fixture claim a plausible history rather than an impossible one.
    ///
    /// `TaskEntity.create` stamps `createdAt` with the current moment, which is right for a
    /// real user — the app won't let anyone schedule work in the past, so the earliest thing
    /// they created is genuinely when they started. It's wrong for a fixture, where forty-five
    /// days of history all get stamped with the second the seeder ran.
    ///
    /// Anything reading "when did this person start" then concludes *today*, and the last seven
    /// days render as days that predate them — a week of history drawn as if it never happened.
    /// Backdating to each task's own day makes the fixture describe someone who has been using
    /// the app for weeks, which is the whole point of it.
    private static func backdateCreationStamps(in context: NSManagedObjectContext) {
        let tasks = (try? context.fetch(TaskEntity.fetchRequest())) ?? []
        let now = Date.now
        for task in tasks {
            // Work already in the past was created no later than the day it was due; work still
            // ahead was created by now. Either way `createdAt` never lands in the future.
            task.createdAt = min(task.resolvedDate, now)
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
            ("Ship Waypoint v1", -25, 70, .manual, "Week and Today polished, analytics landed, on the App Store."),
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

    /// **No title here may also be a series title.** `seedRepeatSeries` creates its
    /// occurrences with a `seriesID`; these are created without one. Share a title between the
    /// two and the fixture grows a task that looks exactly like a repeat, isn't one, and so
    /// correctly refuses the series-delete choice its twin three rows down offers — which
    /// reads as a bug in the app rather than a collision in the data. It cost an afternoon.
    private static let historyTitles = [
        "Half marathon": ["Easy 5k", "Hill repeats", "Long run", "Recovery jog", "Strength — legs", "Foam roll and stretch"],
        "Ship Waypoint v1": ["Fix scheduling edge case", "Write release notes", "Review PR backlog", "Polish the Week tab", "Screenshot pass for the store", "Triage crash reports"],
        "Read 12 books": ["Read — 30 pages", "Finish current chapter", "Write up notes", "Pick the next book"],
        "Learn Spanish": ["Flashcards — 15 min", "Listening practice", "Speak with tutor", "Review verb tenses"],
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
                    // Scattered rather than pinned to "one hour after the start". The
                    // time-of-day card buckets these into four-hour bands, so a fixture that
                    // always finished on schedule would draw one hard stripe and look like a
                    // rendering bug rather than a habit.
                    task.completedAt = at(hour: hour, on: date)
                        .addingTimeInterval(Double.random(in: 900...9000, using: &rng))
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
            // Deterministic spread rather than an rng this function doesn't carry — the fixture
            // has to stay byte-identical across loads, which is what makes it useful for
            // comparing a design change against the run before it.
            task.completedAt = at(hour: 6, on: date).addingTimeInterval(Double((abs(offset) * 13) % 55) * 60 + 2100)
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

        // **Placed around the running task, not blindly after it.** These used to be
        // `laterToday(hours:fallbackHour:)` — now plus an offset, falling back to a fixed hour
        // when that overflowed the day. Run the fixture at nine in the evening and every
        // fallback landed on top of the in-progress task, so the demo showed two things
        // running at once: the app failing at the one thing it exists to prevent, in the
        // screenshots used to sell it.
        //
        // `freeHours` walks a list of sensible slots and skips any that collide with the
        // window above, so the seeded day is honest whatever time it's generated at.
        let busy = (
            start: Date.now.addingTimeInterval(-20 * 60),
            end: Date.now.addingTimeInterval(40 * 60)
        )
        let remaining: [(title: String, minutes: Int, goal: GoalEntity, notes: String?)] = [
            ("Review PR backlog", 45, goals[1], nil),
            ("Read — 30 pages", 30, goals[2], "Chapter 7 onward; skim the appendix."),
            // Not "Vocab drill — 20 min": that title belongs to `seedRepeatSeries`, and a
            // loose copy beside its own repeating twin is the collision that
            // `testNoTitleIsBothARepeatAndNotARepeat` exists to prevent.
            ("Listening practice", 20, goals[3], nil),
        ]
        var slots = freeHours(avoiding: busy, on: today, count: remaining.count).makeIterator()
        for item in remaining {
            guard let start = slots.next() else { continue }
            TaskEntity.create(
                in: context, title: item.title, date: today,
                startTime: start, durationMinutes: item.minutes,
                priority: item.title == "Review PR backlog" ? .high : (item.minutes == 30 ? .low : .medium),
                goal: item.goal, notes: item.notes
            )
        }
    }

    /// Start times on `day` that don't overlap `avoiding`, drawn from ordinary working hours.
    ///
    /// Deliberately a fixed candidate list rather than arithmetic on `now`: the fixture has to
    /// produce the same shape of day whether it runs at 7am or 11pm, and anything anchored to
    /// the current hour drifts off the end of the day and lands back on top of itself.
    private static func freeHours(
        avoiding busy: (start: Date, end: Date),
        on day: Date,
        count: Int
    ) -> [Date] {
        let candidates = [9, 11, 13, 15, 17, 19, 21, 8, 10, 12, 14, 16, 18, 20]
        var chosen: [Date] = []
        for hour in candidates where chosen.count < count {
            let start = at(hour: hour, on: day)
            // An hour's clearance either side, so nothing seeded butts up against the running
            // task and reads as a collision even when it technically isn't one.
            let end = start.addingTimeInterval(3600)
            guard end <= busy.start || start >= busy.end else { continue }
            guard !chosen.contains(where: { abs($0.timeIntervalSince(start)) < 3600 }) else { continue }
            chosen.append(start)
        }
        return chosen.sorted()
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

    /// Two repeat series, not one.
    ///
    /// One is enough for "delete this and future occurrences" to have something to act on, which
    /// is why it was one. The habit card compares series *against each other* and names the one
    /// slipping most — with a single row there's nothing to compare, so it falls back to a
    /// caption that just restates its own title. The second series is deliberately the
    /// worse-kept of the two for the same reason: if every habit runs at the same rate there is
    /// no "slipping most" to name.
    private static func seedRepeatSeries(in context: NSManagedObjectContext, goals: [GoalEntity]) {
        // `days` are Monday-relative (0 = Mon), matching the shift below. `missEvery` is how
        // often a past occurrence goes unticked.
        let specs: [(title: String, goal: GoalEntity?, hour: Int, days: [Int], minutes: Int, missEvery: Int)] = [
            ("Interval session", goals[0], 18, [2, 5], 50, 6),
            ("Vocab drill — 20 min", goals[3], 21, [0, 3], 20, 3),
            // Deliberately goal-less. Every series in the fixture used to hang off a goal, so
            // the No-goal list could never show one — and the series-delete choice was
            // unreachable there however hard anyone tapped. A repeat with no goal is an
            // ordinary thing to have, and the fixture should contain one.
            ("Rubbish out", nil, 20, [6], 10, 5),
        ]
        let cal = Calendar.current
        for spec in specs {
            let seriesID = UUID()
            var occurrence = 0
            for offset in stride(from: -45, through: 28, by: 1) {
                let date = day(offset: offset)
                let weekday = (cal.component(.weekday, from: date) + 5) % 7
                guard spec.days.contains(weekday) else { continue }
                let task = TaskEntity.create(
                    in: context,
                    title: spec.title,
                    date: date,
                    startTime: at(hour: spec.hour, on: date),
                    durationMinutes: spec.minutes,
                    priority: .high,
                    goal: spec.goal,
                    seriesID: seriesID
                )
                occurrence += 1
                // Deterministic spread and deterministic misses rather than an rng this function
                // doesn't carry — the fixture has to stay byte-identical across loads, which is
                // what makes it useful for comparing a design change against the run before it.
                guard offset < 0, !occurrence.isMultiple(of: spec.missEvery) else { continue }
                task.isDone = true
                task.completedAt = at(hour: spec.hour + 1, on: date)
                    .addingTimeInterval(Double((abs(offset) * 23) % 80) * 60)
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

        // Work pulled forward. Without these the replanning card counts only slips, which is
        // both half the picture and the demoralising half.
        for _ in 0..<7 {
            let when = day(offset: -Int.random(in: 1...44, using: &rng))
            let goal = pickGoal(goals, rng: &rng)
            let event = TaskEventEntity(context: context)
            event.id = UUID()
            event.kind = TaskEventKind.rescheduledEarlier.rawValue
            event.occurredAt = when
            event.taskID = UUID()
            event.goalID = goal?.id
            event.title = pickTitle(for: goal, rng: &rng)
            event.fromDate = Calendar.current.date(byAdding: .day, value: 3, to: when)
            event.toDate = when
        }

        // Two things whose time budget kept climbing, each raised more than once — the shape
        // the underestimate card exists to show, and one the fixture can't produce by accident
        // because nothing in it ever edits a task.
        let creep: [(String, [(Int, Int)])] = [
            ("Listening practice", [(30, 45), (45, 60), (60, 90)]),
            ("Polish the Week tab", [(45, 60), (60, 90)]),
            ("Deep work — Week tab polish", [(60, 90), (90, 120)])
        ]
        for (title, steps) in creep {
            for (index, step) in steps.enumerated() {
                let event = TaskEventEntity(context: context)
                event.id = UUID()
                event.kind = TaskEventKind.durationChanged.rawValue
                event.occurredAt = day(offset: -30 + index * 7)
                event.taskID = UUID()
                event.title = title
                event.fromValue = Int32(step.0)
                event.toValue = Int32(step.1)
            }
        }

        // Goals seen through, and goals given up on. Without the first kind the outcome tiles are
        // a zero beside a failure count, which is the imbalance `goalCompleted` was added to fix.
        //
        // Every name here is a goal that no longer exists, which is the normal case and the whole
        // reason the event carries its own copy of the title. It also has to be true of the
        // finished ones specifically: the earlier fixture credited "Read 12 books", a goal still
        // sitting in the carousel twenty-five per cent done with its target date ahead of it, so
        // the log and the screen flatly contradicted each other.
        let finished: [(String, Int, Int, Int)] = [
            ("Couch to 5k", -120, -12, 34),
            ("Rebuild the website", -95, -41, 19),
        ]
        for (name, started, ended, tasks) in finished {
            let event = TaskEventEntity(context: context)
            event.id = UUID()
            event.kind = TaskEventKind.goalCompleted.rawValue
            event.occurredAt = day(offset: ended)
            event.goalID = UUID()
            event.title = name
            event.fromDate = day(offset: started)
            event.toDate = day(offset: ended)
            event.toValue = Int32(tasks)
        }

        // One of each kind inside the last four weeks, which is the window the page opens on.
        // Both abandonments used to sit further back than that, so the default view drew the
        // finished tile beside a zero — the exact "column of failures" shape inverted, and just
        // as misleading about what the app has recorded.
        let dropped: [(String, Int, Int, Int)] = [
            ("Wake at 5am", -50, -22, 30),
            ("Learn the guitar", -102, -47, -8),
        ]
        for (name, started, quit, target) in dropped {
            let event = TaskEventEntity(context: context)
            event.id = UUID()
            event.kind = TaskEventKind.goalAbandoned.rawValue
            event.occurredAt = day(offset: quit)
            event.goalID = UUID()
            event.title = name
            event.fromDate = day(offset: started)
            event.toDate = day(offset: target)
        }

        seedAvoidanceStreak(in: context)
        seedEditHistory(in: context)
    }

    /// One thing put off over and over, and then actually done.
    ///
    /// The deferral leaderboard's top row is the most-read thing on the Friction tab, and a
    /// fixture whose worst offender was pushed twice makes it look like nothing much happens
    /// here. Random scatter won't produce this on purpose: sixteen deferrals spread over four
    /// titles and forty days lands at three or four apiece.
    ///
    /// The completed task belongs with the events rather than in `seedHistory` because the two
    /// are one story — six pushes and then a tick is the shape `finallyDidIt` exists to find,
    /// and it only reads as that story if both halves carry the same title.
    private static func seedAvoidanceStreak(in context: NSManagedObjectContext) {
        let title = "Book the dentist"
        for step in 0..<6 {
            let when = day(offset: -34 + step * 5)
            let event = TaskEventEntity(context: context)
            event.id = UUID()
            event.kind = TaskEventKind.deferred.rawValue
            event.occurredAt = when
            event.taskID = UUID()
            event.title = title
            event.fromDate = when
            event.toDate = Calendar.current.date(byAdding: .day, value: 5, to: when)
        }

        let date = day(offset: -3)
        let settled = TaskEntity.create(
            in: context, title: title, date: date,
            startTime: at(hour: 11, on: date), durationMinutes: 15,
            priority: .low, notes: "A month late, but booked."
        )
        settled.isDone = true
        settled.completedAt = at(hour: 11, on: date).addingTimeInterval(720)
    }

    /// Edits and un-ticks — the two kinds of record the app writes that nothing else in this
    /// fixture can produce, because nothing here ever changes a task after creating it.
    ///
    /// Neither has a card of its own yet. They're seeded anyway: an empty table is
    /// indistinguishable from a broken writer, and the next thing built on this log should be
    /// built against rows that look like real ones.
    private static func seedEditHistory(in context: NSManagedObjectContext) {
        let reprioritised: [(String, Priority, Priority, Int)] = [
            ("Triage crash reports", .medium, .high, -18),
            ("Screenshot pass for the store", .low, .high, -9),
            ("Pick the next book", .medium, .low, -25),
            ("Pay the electricity bill", .low, .high, -6),
        ]
        for (title, from, to, offset) in reprioritised {
            let event = TaskEventEntity(context: context)
            event.id = UUID()
            event.kind = TaskEventKind.priorityChanged.rawValue
            event.occurredAt = day(offset: offset)
            event.taskID = UUID()
            event.title = title
            event.fromText = from.rawValue
            event.toText = to.rawValue
        }

        // `fromDate` is the completion being withdrawn, which is the only thing about it worth
        // keeping — the task itself forgets it was ever done.
        let undone: [(String, Int)] = [("Meal prep", -21), ("Review PR backlog", -13)]
        for (title, offset) in undone {
            let event = TaskEventEntity(context: context)
            event.id = UUID()
            event.kind = TaskEventKind.completionUndone.rawValue
            event.occurredAt = day(offset: offset).addingTimeInterval(20 * 3600)
            event.taskID = UUID()
            event.title = title
            event.fromDate = day(offset: offset).addingTimeInterval(15 * 3600)
        }
    }

    // MARK: - Focus sessions

    /// How long each of these actually takes, as a multiple of what was booked for it.
    ///
    /// Attached to titles rather than drawn at random, because the estimate card's job is to say
    /// *what* you misjudge. Random ratios produce six rows of noise with a different six every
    /// reload; a table produces "listening practice always runs nearly double" — a sentence, and
    /// one that stays put between screenshots.
    ///
    /// Two of these names are the same two whose booked duration keeps climbing in the behaviour
    /// log, which is the point: the estimate rising and the work still overrunning is one story
    /// told by two cards, and it only holds together if both cards name the same task.
    private static let paceByTitle: [String: Double] = [
        "Listening practice": 1.85,
        "Triage crash reports": 1.7,
        "Polish the Week tab": 1.55,
        "Long run": 1.34,
        "Write up notes": 1.22,
        "Foam roll and stretch": 0.55,
        "Write release notes": 0.62,
        "Inbox to zero": 0.71,
    ]

    /// Timed work, which nothing in the fixture had before this.
    ///
    /// Two things needed it and neither could fake it: the estimate card is the one analysis in
    /// the app that can't be computed from tasks alone — a `durationMinutes` is a guess and an
    /// `isDone` doesn't check it — so with no sessions it drew its empty state no matter how much
    /// history sat behind it. The pace milestone has the same dependency.
    ///
    /// Sessions hang off tasks that already exist, by id, so this has to run after everything
    /// that creates one. Fetching rather than threading the tasks through: the context hasn't
    /// been saved yet, and a fetch on a main-queue context includes pending inserts.
    private static func seedFocusSessions(in context: NSManagedObjectContext, rng: inout SeededGenerator) {
        let request = TaskEntity.fetchRequest()
        request.predicate = NSPredicate(format: "isDone == YES AND date < %@", day(offset: 0) as NSDate)
        // Sorted so the subset picked below is the same one every load — a fetch's order isn't
        // promised, and an rng consumed in a different order is a different fixture.
        request.sortDescriptors = [
            NSSortDescriptor(key: "date", ascending: true),
            NSSortDescriptor(key: "startTime", ascending: true),
            NSSortDescriptor(key: "title", ascending: true)
        ]
        let finished = (try? context.fetch(request)) ?? []

        for task in finished {
            let named = paceByTitle[task.title ?? ""]
            // Everything the table names gets timed; about half of the rest does. Somebody who
            // ran the timer on every single task would be a stranger to every real user of this
            // app, and a fixture where the measured set *is* the finished set can't show the
            // difference between "this estimate was wrong" and "nobody checked".
            guard named != nil || Double.random(in: 0...1, using: &rng) < 0.45 else { continue }
            // A narrow band around 1 for everything unnamed. Most estimates are roughly right,
            // and a fixture where every task is a disaster leaves the chart with no baseline to
            // read the disasters against.
            let ratio = named ?? Double.random(in: 0.86...1.19, using: &rng)
            let planned = Int(task.durationMinutes) * 60
            let actual = max(60, Int((Double(planned) * ratio).rounded()))
            let started = task.resolvedStartTime
            FocusSessionLog.record(
                taskID: task.id,
                taskTitle: task.title,
                startedAt: started,
                endedAt: started.addingTimeInterval(Double(actual)),
                plannedSeconds: planned,
                actualSeconds: actual,
                // Overrunning means the timer was still going when the booked time ran out, so
                // it was stopped by hand rather than reaching its own end.
                ranToCompletion: ratio <= 1,
                in: context
            )
        }
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
