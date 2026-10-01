import Foundation
import CoreData

/// Every figure the Progress tab draws, computed as pure functions over already-fetched arrays.
///
/// Kept out of the views deliberately. A chart is the one place a bug is invisible — a wrong
/// bar is still a bar, and it looks authoritative — so the arithmetic lives somewhere it can be
/// tested against known input instead of being eyeballed on a screen. Every entry point takes
/// `now` rather than reading the clock, for the same reason.
enum ProgressAnalytics {

    // MARK: - Shared shapes

    struct Ratio: Identifiable {
        let id: String
        let label: String
        let done: Int
        let total: Int
        var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
    }

    struct Slice: Identifiable {
        let id: String
        let label: String
        let value: Double
    }

    struct Bucket: Identifiable {
        let id: String
        let label: String
        let count: Int
    }

    // MARK: - 1. Completion by weekday

    /// Weekday names are hardcoded English rather than pulled from `Calendar`: the device region
    /// here is `en_IN`, whose short-weekday data has already produced blank labels elsewhere in
    /// this app, and a chart axis is a bad place to discover that.
    static let weekdayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    /// Only days that have actually arrived. A Friday still in the future has nothing to say
    /// about your Fridays, and counting it as 0-of-n would drag every forward-looking weekday
    /// toward zero — the chart would show you getting worse the further ahead you plan.
    static func completionByWeekday(_ tasks: [TaskEntity], now: Date = .now) -> [Ratio] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let elapsed = tasks.filter { cal.startOfDay(for: $0.resolvedDate) <= today }
        return (1...7).map { weekday in
            let onDay = elapsed.filter { cal.component(.weekday, from: $0.resolvedDate) == weekday }
            return Ratio(
                id: "weekday-\(weekday)",
                label: weekdayNames[weekday - 1],
                done: onDay.filter(\.isDone).count,
                total: onDay.count
            )
        }
    }

    // MARK: - 2. Deferral leaderboard

    struct Deferral: Identifiable {
        let id: String
        let title: String
        let times: Int
        let totalDays: Int
    }

    /// Grouped by title rather than by task id: the point is the *thing* you keep putting off,
    /// and a task deleted and recreated, or a repeat series, would otherwise scatter across
    /// several ids and hide the pattern that matters.
    static func deferralLeaderboard(_ events: [TaskEventEntity], limit: Int = 6) -> [Deferral] {
        let deferrals = events.filter { $0.kindValue == .deferred }
        let grouped = Dictionary(grouping: deferrals) { $0.title ?? "Untitled" }
        return grouped
            .map { title, rows in
                Deferral(
                    id: title,
                    title: title,
                    times: rows.count,
                    totalDays: rows.reduce(0) { $0 + ($1.slipInDays ?? 0) }
                )
            }
            .sorted { ($0.totalDays, $0.times) > ($1.totalDays, $1.times) }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - 3. Slip distribution

    /// Buckets, not a raw histogram of day counts. Twelve one-day slips and one twelve-day slip
    /// are the same total and completely different behaviour; the bucket edges are chosen so
    /// that difference is the thing you see.
    static func slipDistribution(_ events: [TaskEventEntity]) -> [Bucket] {
        let slips = events.filter { $0.kindValue == .deferred }.compactMap(\.slipInDays)
        let edges: [(String, ClosedRange<Int>)] = [
            ("1 day", 1...1),
            ("2–3", 2...3),
            ("4–7", 4...7),
            ("Over a week", 8...Int.max)
        ]
        return edges.map { label, range in
            Bucket(id: label, label: label, count: slips.filter { range.contains($0) }.count)
        }
    }

    // MARK: - 4. Planned vs completed effort

    struct EffortWeek: Identifiable {
        let id: Date
        let weekStart: Date
        let plannedMinutes: Int
        let completedMinutes: Int
        /// The week currently being lived, whose completed figure is a running total rather than
        /// a result. On a Tuesday it is two days of work against seven days of plan, so drawn
        /// like every other week it reads as a collapse — and it reads that way six days out of
        /// seven, which makes the newest and most-looked-at bar the least trustworthy one.
        var isPartial: Bool = false
        var plannedHours: Double { Double(plannedMinutes) / 60 }
        var completedHours: Double { Double(completedMinutes) / 60 }
    }

    /// Hours, not task counts. A completion ratio treats a 15-minute errand and a two-hour block
    /// as equals, so it can read 80% while you drop every substantial thing on the list — this
    /// is the number that catches that.
    static func effortByWeek(_ tasks: [TaskEntity], weeks: Int = 6, now: Date = .now) -> [EffortWeek] {
        let cal = Calendar.current
        let thisMonday = mondayOfWeek(containing: now)
        // Weeks before the first task aren't zero hours, they're weeks this person wasn't here.
        // Plotting them draws a long flat run along the baseline that reads as months of doing
        // nothing, and squashes the part of the chart that has anything in it.
        let firstWeek = tasks.map(\.resolvedDate).min().map(mondayOfWeek(containing:))
        return (0..<weeks).reversed().compactMap { offset in
            guard let start = cal.date(byAdding: .day, value: -7 * offset, to: thisMonday),
                  let end = cal.date(byAdding: .day, value: 7, to: start) else { return nil }
            if let firstWeek, start < firstWeek { return nil }
            let inWeek = tasks.filter { $0.resolvedDate >= start && $0.resolvedDate < end }
            return EffortWeek(
                id: start,
                weekStart: start,
                plannedMinutes: inWeek.reduce(0) { $0 + Int($1.durationMinutes) },
                completedMinutes: inWeek.filter(\.isDone).reduce(0) { $0 + Int($1.durationMinutes) },
                isPartial: start == thisMonday
            )
        }
    }

    // MARK: - 5. Priority follow-through

    static func priorityFollowThrough(_ tasks: [TaskEntity], now: Date = .now) -> [Ratio] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let elapsed = tasks.filter { cal.startOfDay(for: $0.resolvedDate) <= today }
        return Priority.allCases.map { priority in
            let matching = elapsed.filter { $0.priorityValue == priority }
            return Ratio(
                id: priority.rawValue,
                label: priority.label,
                done: matching.filter(\.isDone).count,
                total: matching.count
            )
        }
    }

    // MARK: - 6. Effort split by goal

    /// Completed minutes only. Where the time *went*, not where it was promised — a plan tells
    /// you about intent, and this card is the one that answers what actually happened.
    static func effortByGoal(_ tasks: [TaskEntity], limit: Int = 5) -> [Slice] {
        let done = tasks.filter(\.isDone)
        var grouped: [String: Int] = [:]
        for task in done {
            grouped[task.goal?.name ?? "Unassigned", default: 0] += Int(task.durationMinutes)
        }
        let sorted = grouped.sorted { $0.value > $1.value }
        let head = sorted.prefix(limit)
        let tail = sorted.dropFirst(limit).reduce(0) { $0 + $1.value }
        var slices = head.map { Slice(id: $0.key, label: $0.key, value: Double($0.value) / 60) }
        if tail > 0 { slices.append(Slice(id: "Other", label: "Other", value: Double(tail) / 60)) }
        return slices
    }

    // MARK: - 7. Habit adherence

    /// Repeat series only — a one-off task has no adherence to measure, and including them would
    /// bury the handful of genuine habits under a list of everything ever scheduled.
    static func seriesAdherence(_ tasks: [TaskEntity], now: Date = .now, limit: Int = 6) -> [Ratio] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let elapsed = tasks.filter { $0.seriesID != nil && cal.startOfDay(for: $0.resolvedDate) <= today }
        let grouped = Dictionary(grouping: elapsed) { $0.seriesID! }
        return grouped
            .compactMap { _, rows -> Ratio? in
                guard let title = rows.first?.title, !rows.isEmpty else { return nil }
                return Ratio(id: title, label: title, done: rows.filter(\.isDone).count, total: rows.count)
            }
            .sorted { $0.total > $1.total }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - 8. Time of day

    struct HeatCell: Identifiable {
        let id: String
        let weekday: Int
        let hourBand: Int
        let count: Int
        var bandLabel: String { ProgressAnalytics.bandLabels[hourBand] }
    }

    static let bandLabels = ["Early", "Morning", "Midday", "Afternoon", "Evening", "Night"]

    /// Four-hour bands rather than 24 columns: at a phone's width, 24 × 7 cells are two pixels
    /// each and legible to nobody.
    ///
    /// Auto-completed tasks are excluded — their `completedAt` is the scheduled end time, not an
    /// observation, so including them would draw a confident spike at whatever hour you tend to
    /// schedule things to finish. See `TaskEntity.hasObservedCompletionTime`.
    static func completionsByTimeOfDay(_ tasks: [TaskEntity]) -> [HeatCell] {
        let cal = Calendar.current
        let observed = tasks.filter(\.hasObservedCompletionTime)
        var counts: [String: Int] = [:]
        for task in observed {
            guard let at = task.completedAt else { continue }
            let weekday = cal.component(.weekday, from: at)
            let band = min(cal.component(.hour, from: at) / 4, 5)
            counts["\(weekday)-\(band)", default: 0] += 1
        }
        return (1...7).flatMap { weekday in
            (0..<6).map { band in
                HeatCell(
                    id: "\(weekday)-\(band)",
                    weekday: weekday,
                    hourBand: band,
                    count: counts["\(weekday)-\(band)"] ?? 0
                )
            }
        }
    }

    /// How many completions carry a real timestamp. The time-of-day card is meaningless below a
    /// handful, and silently drawing an empty grid would read as "you never finish anything".
    static func observedCompletionCount(_ tasks: [TaskEntity]) -> Int {
        tasks.filter(\.hasObservedCompletionTime).count
    }

    // MARK: - 9. Goal burn-down

    struct BurndownPoint: Identifiable {
        let id: Date
        let date: Date
        /// Tasks still outstanding at the end of this day.
        let remaining: Int
        /// Where an even pace from the goal's start would have put you.
        let idealRemaining: Double
    }

    /// Actual against the straight line from "all of it" on the start date to "none of it" on
    /// the target date. The gap between the two curves is the whole point: it says whether the
    /// deadline is still reachable, which no count of finished tasks can.
    static func burndown(for goal: GoalEntity, now: Date = .now) -> [BurndownPoint] {
        let cal = Calendar.current
        let tasks = goal.sortedTasks
        guard !tasks.isEmpty else { return [] }
        let start = cal.startOfDay(for: goal.createdAt ?? tasks.map(\.resolvedDate).min() ?? now)
        let end = cal.startOfDay(for: goal.resolvedTargetDate)
        guard end > start else { return [] }
        let totalDays = cal.dateComponents([.day], from: start, to: end).day ?? 1
        let today = cal.startOfDay(for: now)
        let lastPlotted = min(today, end)
        let elapsedDays = max(cal.dateComponents([.day], from: start, to: lastPlotted).day ?? 0, 0)
        let total = tasks.count

        return (0...elapsedDays).compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: offset, to: start) else { return nil }
            // Completed *by the end of* this day, using the real completion stamp where there is
            // one and the scheduled day otherwise — a task ticked late still counts on the day
            // it was actually ticked, which is what makes the curve honest.
            let completed = tasks.filter { task in
                guard task.isDone else { return false }
                let when = task.completedAt.map { cal.startOfDay(for: $0) } ?? cal.startOfDay(for: task.resolvedDate)
                return when <= day
            }.count
            let ideal = Double(total) * (1 - Double(offset) / Double(totalDays))
            return BurndownPoint(id: day, date: day, remaining: total - completed, idealRemaining: max(ideal, 0))
        }
    }

    // MARK: - 10. Estimate accuracy

    struct Estimate: Identifiable {
        let id: String
        let title: String
        let plannedMinutes: Int
        let actualMinutes: Int
        /// How many separate tasks carrying this title went into the two figures above.
        var occurrences: Int = 1
        /// >1 means it took longer than planned.
        var ratio: Double { plannedMinutes == 0 ? 0 : Double(actualMinutes) / Double(plannedMinutes) }
        var overrunMinutes: Int { actualMinutes - plannedMinutes }
    }

    /// How long work actually takes against how long it was booked for.
    ///
    /// Sessions are summed per task, not compared one at a time: a two-hour task worked in three
    /// sittings is one estimate that was roughly right, and scoring each sitting against the
    /// whole booking would call it three severe under-runs.
    ///
    /// Only tasks with a real session attached appear. An untouched task has no evidence either
    /// way, and assuming it took exactly as long as planned would quietly pull the whole average
    /// towards "you estimate perfectly".
    static func estimateAccuracy(
        sessions: [FocusSessionEntity],
        tasks: [TaskEntity],
        limit: Int = 6
    ) -> [Estimate] {
        var actualByTask: [UUID: Int] = [:]
        var titleByTask: [UUID: String] = [:]
        for session in sessions {
            guard let id = session.taskID else { continue }
            actualByTask[id, default: 0] += Int(session.actualSeconds)
            if let title = session.taskTitle { titleByTask[id] = title }
        }
        let plannedByTask = Dictionary(
            tasks.compactMap { task -> (UUID, TaskEntity)? in task.id.map { ($0, task) } },
            uniquingKeysWith: { first, _ in first }
        )
        // Grouped by title, not by task. The same piece of work comes round again and again —
        // every occurrence of a repeating task shares one title — and six rows all called "Long
        // run" are one fact about how long a long run takes, not six. Per task they also collide
        // on the way out: the chart puts one bar per title on its vertical axis, so same-named
        // rows would be drawn on top of each other.
        var grouped: [String: (planned: Int, actual: Int, count: Int)] = [:]
        for (id, seconds) in actualByTask {
            guard let planned = plannedByTask[id].map({ Int($0.durationMinutes) }), planned > 0 else { continue }
            let title = plannedByTask[id]?.title ?? titleByTask[id] ?? "Untitled"
            var row = grouped[title] ?? (planned: 0, actual: 0, count: 0)
            row.planned += planned
            row.actual += Int((Double(seconds) / 60).rounded())
            row.count += 1
            grouped[title] = row
        }

        return grouped.map { title, row in
            // Averaged per occurrence rather than totalled, so both numbers stay in the unit the
            // estimate was made in. "You book 45 minutes and it takes 70" is something you can
            // act on next time; "you booked nine hours and spent fourteen" is not.
            Estimate(
                id: title,
                title: title,
                plannedMinutes: Int((Double(row.planned) / Double(row.count)).rounded()),
                actualMinutes: Int((Double(row.actual) / Double(row.count)).rounded()),
                occurrences: row.count
            )
        }
        .sorted { abs($0.overrunMinutes) > abs($1.overrunMinutes) }
        .prefix(limit)
        .map { $0 }
    }

    /// One number for the headline: how far off the typical estimate is. Median rather than mean
    /// — a single forgotten timer left running produces an outlier that drags an average to
    /// nonsense, and this figure has to survive one bad day.
    static func medianEstimateRatio(_ estimates: [Estimate]) -> Double? {
        let ratios = estimates.map(\.ratio).filter { $0 > 0 }.sorted()
        guard !ratios.isEmpty else { return nil }
        let mid = ratios.count / 2
        return ratios.count.isMultiple(of: 2) ? (ratios[mid - 1] + ratios[mid]) / 2 : ratios[mid]
    }

    // MARK: - 11. What you keep underestimating

    struct Underestimate: Identifiable {
        let id: String
        let title: String
        let originalMinutes: Int
        let currentMinutes: Int
        /// How many separate times the budget was raised.
        let raises: Int
        var growth: Double { originalMinutes == 0 ? 0 : Double(currentMinutes) / Double(originalMinutes) }
    }

    /// Work whose time budget kept going up.
    ///
    /// Only answerable because the change is logged: a task holds one duration, the current
    /// one, so the forty-five minutes you originally thought it would take is gone the moment
    /// you correct it. Grouped by title for the same reason the deferral board is — the thing
    /// you keep misjudging is the *thing*, and a task deleted and recreated would otherwise
    /// scatter across ids.
    ///
    /// Increases only. A budget revised *down* is a correction in the other direction and a
    /// different, less useful story.
    static func underestimates(_ events: [TaskEventEntity], limit: Int = 5) -> [Underestimate] {
        let changes = events
            .filter { $0.kindValue == .durationChanged }
            .sorted { ($0.occurredAt ?? .distantPast) < ($1.occurredAt ?? .distantPast) }
        let grouped = Dictionary(grouping: changes) { $0.title ?? "Untitled" }
        return grouped
            .compactMap { title, rows -> Underestimate? in
                guard let first = rows.first, let last = rows.last else { return nil }
                let original = Int(first.fromValue)
                let current = Int(last.toValue)
                guard original > 0, current > original else { return nil }
                return Underestimate(
                    id: title,
                    title: title,
                    originalMinutes: original,
                    currentMinutes: current,
                    raises: rows.filter { $0.toValue > $0.fromValue }.count
                )
            }
            .sorted { $0.currentMinutes - $0.originalMinutes > $1.currentMinutes - $1.originalMinutes }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - 12. Replanning

    /// Work moved to a later day against work pulled forward.
    ///
    /// Shown as a pair because only recording the slips makes every history a record of
    /// failure. Moving something up is the same decision taken well, and a month where both
    /// numbers are high is a month of active replanning rather than one of avoidance.
    static func replanBalance(_ events: [TaskEventEntity]) -> (pushed: Int, pulled: Int) {
        (
            events.filter { $0.kindValue == .deferred }.count,
            events.filter { $0.kindValue == .rescheduledEarlier }.count
        )
    }

    // MARK: - 13. Goal outcomes

    /// Goals seen through against goals given up on. The app recorded only the second of these
    /// until recently, which made the whole picture a scoreboard of failure.
    static func goalOutcomes(_ events: [TaskEventEntity]) -> (finished: Int, abandoned: Int) {
        (
            events.filter { $0.kindValue == .goalCompleted }.count,
            events.filter { $0.kindValue == .goalAbandoned }.count
        )
    }

    // MARK: - Helpers

    static func mondayOfWeek(containing date: Date) -> Date {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        let weekday = cal.component(.weekday, from: day)
        return cal.date(byAdding: .day, value: -((weekday + 5) % 7), to: day)!
    }
}
