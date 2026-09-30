import Foundation
import CoreData

/// Works out which milestones are true, from the history.
///
/// **Derived, never incremented.** A counter that drifts is wrong forever and nothing tells you
/// — a crash mid-write, a restore, a migration, and the number is quietly a lie you can't
/// detect. Every figure here is recomputed from the events and tasks that are already stored,
/// so a milestone can be re-evaluated after any of those and still be right.
///
/// Pure, and given the clock rather than reading it, because every one of these turns on a date
/// boundary and boundaries are where this sort of thing goes wrong unseen.
enum MilestoneEvaluator {

    struct Earned {
        let kind: MilestoneKind
        /// Whatever number the milestone is about — a count, a streak length, a percentage.
        let value: Int
        /// A short human phrase naming the specific thing, where there is one.
        let context: String?
        /// When it actually became true, which is rarely when it was noticed.
        let achievedAt: Date
    }

    struct Input {
        var tasks: [TaskEntity] = []
        var events: [TaskEventEntity] = []
        var sessions: [FocusSessionEntity] = []
        var goals: [GoalEntity] = []
        var alreadyEarned: Set<String> = []
        var now: Date = .now
    }

    static func newlyEarned(_ input: Input) -> [Earned] {
        var out: [Earned] = []
        func consider(_ earned: Earned?) {
            guard let earned, !input.alreadyEarned.contains(earned.kind.rawValue) else { return }
            out.append(earned)
        }

        consider(volume(input))
        consider(focusHours(input))
        consider(firstGoalCompleted(input))
        consider(longHaulGoal(input))
        consider(finallyDidIt(input))
        consider(perfectWeek(input))
        consider(zeroDeferralWeek(input))
        consider(cleanMonth(input))
        consider(thirtyDayStreak(input))
        consider(knowsOwnPace(input))
        consider(hardThingsFirst(input))
        return out
    }

    // MARK: - Volume

    /// Only the highest tier not yet earned, so passing a thousand doesn't hand over three at
    /// once — the smaller ones stopped being news a long time before.
    private static func volume(_ input: Input) -> Earned? {
        let done = input.tasks.filter(\.isDone)
        let count = done.count
        let tiers: [(Int, MilestoneKind)] = [(1000, .thousandTasks), (500, .fiveHundredTasks), (100, .hundredTasks)]
        for (threshold, kind) in tiers where count >= threshold {
            guard !input.alreadyEarned.contains(kind.rawValue) else { return nil }
            let at = done.compactMap(\.completedAt).sorted().dropFirst(threshold - 1).first
            return Earned(kind: kind, value: count, context: nil, achievedAt: at ?? input.now)
        }
        return nil
    }

    /// Measured focus only. Estimates don't count towards a milestone about hours actually spent.
    private static func focusHours(_ input: Input) -> Earned? {
        let seconds = input.sessions.reduce(0) { $0 + Int($1.actualSeconds) }
        let hours = seconds / 3600
        guard hours >= 100 else { return nil }
        return Earned(kind: .hundredFocusHours, value: hours, context: nil, achievedAt: input.now)
    }

    // MARK: - Follow-through

    private static func firstGoalCompleted(_ input: Input) -> Earned? {
        let completions = input.events
            .filter { $0.kindValue == .goalCompleted }
            .sorted { ($0.occurredAt ?? .distantPast) < ($1.occurredAt ?? .distantPast) }
        guard let first = completions.first else { return nil }
        return Earned(
            kind: .firstGoalCompleted,
            value: Int(first.toValue),
            context: first.title,
            achievedAt: first.occurredAt ?? input.now
        )
    }

    private static func longHaulGoal(_ input: Input) -> Earned? {
        let cal = Calendar.current
        for goal in input.goals {
            guard let started = goal.createdAt else { continue }
            let days = cal.dateComponents([.day], from: started, to: input.now).day ?? 0
            // Still being worked, not merely still existing — an abandoned goal left on the
            // shelf for three months is not ninety days of anything.
            guard days >= 90, goal.completionFraction > 0, goal.completionFraction < 1 else { continue }
            let at = cal.date(byAdding: .day, value: 90, to: started) ?? input.now
            return Earned(kind: .longHaulGoal, value: days, context: goal.name, achievedAt: at)
        }
        return nil
    }

    // MARK: - Self-knowledge

    /// A task pushed back five times or more, and then finished.
    ///
    /// Grouped by title, the same way the deferral leaderboard is: the thing you keep avoiding
    /// is the *thing*, not a particular row, and a task deleted and recreated would otherwise
    /// slip the count.
    private static func finallyDidIt(_ input: Input) -> Earned? {
        let deferrals = input.events.filter { $0.kindValue == .deferred }
        let counts = Dictionary(grouping: deferrals) { $0.title ?? "" }.mapValues(\.count)
        let heavy = counts.filter { $0.value >= 5 }
        guard !heavy.isEmpty else { return nil }

        let finished = input.tasks.filter { $0.isDone }
        for task in finished.sorted(by: { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }) {
            guard let title = task.title, let times = heavy[title] else { continue }
            return Earned(
                kind: .finallyDidIt,
                value: times,
                context: title,
                achievedAt: task.completedAt ?? input.now
            )
        }
        return nil
    }

    /// A week where what work took landed within a tenth of what was budgeted.
    ///
    /// Needs at least three timed tasks — two could agree by luck, and a milestone handed out
    /// on a coincidence is worth nothing.
    private static func knowsOwnPace(_ input: Input) -> Earned? {
        let cal = Calendar.current
        let byWeek = Dictionary(grouping: input.sessions.filter { $0.endedAt != nil }) {
            cal.dateInterval(of: .weekOfYear, for: $0.endedAt!)?.start ?? .distantPast
        }
        for (weekStart, sessions) in byWeek.sorted(by: { $0.key < $1.key }) {
            var actualByTask: [UUID: Int] = [:]
            for session in sessions {
                guard let id = session.taskID else { continue }
                actualByTask[id, default: 0] += Int(session.actualSeconds)
            }
            let planned = Dictionary(
                input.tasks.compactMap { task in task.id.map { ($0, Int(task.durationMinutes)) } },
                uniquingKeysWith: { first, _ in first }
            )
            let ratios = actualByTask.compactMap { id, seconds -> Double? in
                guard let minutes = planned[id], minutes > 0 else { return nil }
                return (Double(seconds) / 60) / Double(minutes)
            }
            guard ratios.count >= 3 else { continue }
            let median = ratios.sorted()[ratios.count / 2]
            guard abs(median - 1) <= 0.1 else { continue }
            let end = cal.date(byAdding: .day, value: 7, to: weekStart) ?? input.now
            return Earned(kind: .knowsOwnPace, value: Int(median * 100), context: nil, achievedAt: min(end, input.now))
        }
        return nil
    }

    /// A month where the important work got done at a better rate than the easy work.
    ///
    /// Most people's numbers run the other way round, which is what makes this worth marking.
    private static func hardThingsFirst(_ input: Input) -> Earned? {
        let cal = Calendar.current
        let elapsed = input.tasks.filter { cal.startOfDay(for: $0.resolvedDate) <= cal.startOfDay(for: input.now) }
        let byMonth = Dictionary(grouping: elapsed) { cal.dateInterval(of: .month, for: $0.resolvedDate)?.start ?? .distantPast }
        for (monthStart, tasks) in byMonth.sorted(by: { $0.key < $1.key }) {
            let high = tasks.filter { $0.priorityValue == .high }
            let low = tasks.filter { $0.priorityValue == .low }
            guard high.count >= 5, low.count >= 5 else { continue }
            let highRate = Double(high.filter(\.isDone).count) / Double(high.count)
            let lowRate = Double(low.filter(\.isDone).count) / Double(low.count)
            guard highRate > lowRate else { continue }
            let end = cal.date(byAdding: .month, value: 1, to: monthStart) ?? input.now
            return Earned(kind: .hardThingsFirst, value: Int(highRate * 100), context: nil, achievedAt: min(end, input.now))
        }
        return nil
    }

    // MARK: - Consistency

    /// A week where every day that had work finished something.
    ///
    /// Days with nothing scheduled don't count against it — a Sunday off is not a gap, and
    /// treating it as one would make this unearnable for anybody who rests.
    private static func perfectWeek(_ input: Input) -> Earned? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: input.now)
        let byWeek = Dictionary(grouping: input.tasks) {
            cal.dateInterval(of: .weekOfYear, for: $0.resolvedDate)?.start ?? .distantPast
        }
        for (weekStart, tasks) in byWeek.sorted(by: { $0.key < $1.key }) {
            guard let end = cal.date(byAdding: .day, value: 7, to: weekStart), end <= today else { continue }
            let byDay = Dictionary(grouping: tasks) { cal.startOfDay(for: $0.resolvedDate) }
            guard byDay.count >= 4 else { continue }
            guard byDay.values.allSatisfy({ $0.contains(where: \.isDone) }) else { continue }
            return Earned(kind: .perfectWeek, value: byDay.count, context: nil, achievedAt: end)
        }
        return nil
    }

    /// A full week with nothing pushed to a later day.
    private static func zeroDeferralWeek(_ input: Input) -> Earned? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: input.now)
        let deferrals = Set(input.events.filter { $0.kindValue == .deferred }.compactMap { event in
            event.occurredAt.flatMap { cal.dateInterval(of: .weekOfYear, for: $0)?.start }
        })
        let weeks = Set(input.tasks.compactMap { cal.dateInterval(of: .weekOfYear, for: $0.resolvedDate)?.start })
        for weekStart in weeks.sorted() {
            guard let end = cal.date(byAdding: .day, value: 7, to: weekStart), end <= today else { continue }
            guard !deferrals.contains(weekStart) else { continue }
            // A week with almost nothing in it isn't restraint, it's an empty week.
            let count = input.tasks.filter { cal.dateInterval(of: .weekOfYear, for: $0.resolvedDate)?.start == weekStart }.count
            guard count >= 5 else { continue }
            return Earned(kind: .zeroDeferralWeek, value: count, context: nil, achievedAt: end)
        }
        return nil
    }

    /// A calendar month with nothing abandoned.
    private static func cleanMonth(_ input: Input) -> Earned? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: input.now)
        let abandoned = Set(input.events.filter { $0.kindValue == .abandoned || $0.kindValue == .goalAbandoned }
            .compactMap { event in event.occurredAt.flatMap { cal.dateInterval(of: .month, for: $0)?.start } })
        let months = Set(input.tasks.compactMap { cal.dateInterval(of: .month, for: $0.resolvedDate)?.start })
        for monthStart in months.sorted() {
            guard let end = cal.date(byAdding: .month, value: 1, to: monthStart), end <= today else { continue }
            guard !abandoned.contains(monthStart) else { continue }
            let count = input.tasks.filter { cal.dateInterval(of: .month, for: $0.resolvedDate)?.start == monthStart }.count
            guard count >= 15 else { continue }
            return Earned(kind: .cleanMonth, value: count, context: nil, achievedAt: end)
        }
        return nil
    }

    /// Thirty consecutive days with at least one completion.
    private static func thirtyDayStreak(_ input: Input) -> Earned? {
        let cal = Calendar.current
        let doneDays = Set(input.tasks.filter(\.isDone).map { task in
            cal.startOfDay(for: task.completedAt ?? task.resolvedDate)
        })
        guard !doneDays.isEmpty else { return nil }

        var run = 0
        for day in doneDays.sorted() {
            let previous = cal.date(byAdding: .day, value: -1, to: day)
            run = (previous.map(doneDays.contains) ?? false) ? run + 1 : 1
            if run >= 30 {
                return Earned(kind: .thirtyDayStreak, value: run, context: nil, achievedAt: day)
            }
        }
        return nil
    }
}
