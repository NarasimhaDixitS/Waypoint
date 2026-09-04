import Foundation
import CoreData

@MainActor
enum TaskReplicator {
    /// The simple, one-tap default: same time, tomorrow. Returns a draft rather than saving
    /// directly, so the caller can run it through the normal collision/bump flow — tomorrow
    /// might already be full.
    static func draftForTomorrow(_ task: TaskEntity) -> TaskDraft {
        let cal = Calendar.current
        return TaskDraft(
            title: task.title ?? "",
            date: cal.date(byAdding: .day, value: 1, to: task.resolvedDate) ?? task.resolvedDate,
            startTime: cal.date(byAdding: .day, value: 1, to: task.resolvedStartTime) ?? task.resolvedStartTime,
            durationMinutes: Int(task.durationMinutes),
            priority: task.priorityValue,
            notes: task.notes,
            goal: task.goal
        )
    }

    /// More control, still a single decision: repeat on the given weekdays for N weeks.
    /// Occurrences that would collide with something are silently skipped rather than
    /// interrupting with a prompt per day — the caller shows one summary afterward, which is
    /// why this also reports back the last date actually created: a collision-heavy tail can
    /// leave the real last occurrence short of the nominal N-week end, and the caller's
    /// summary should say what actually happened, not just what was asked for.
    ///
    /// A goal-linked task additionally stops at its goal's target date, whatever `weeks` says.
    /// That ceiling is enforced here, rather than left to each caller, because `weeks` can't
    /// express it on its own: `weeksUntil` deliberately rounds *up* so a repeat always reaches
    /// the goal, which means the requested week count routinely overshoots the target date by
    /// up to six days. Without this, a Mon/Thu repeat toward a Feb 28 goal really did create
    /// occurrences on Mar 1 and Mar 4 — while the creation screen was telling the user it had
    /// been "capped to the goal's end date".
    @discardableResult
    static func repeatWeekly(
        _ task: TaskEntity,
        onWeekdays weekdaySymbols: Set<String>,
        forWeeks weeks: Int,
        context: NSManagedObjectContext
    ) -> (created: Int, skipped: Int, lastDate: Date?) {
        let cal = Calendar.current
        let timeOfDay = cal.dateComponents([.hour, .minute], from: task.resolvedStartTime)
        // Compared against each candidate day's start, so an occurrence landing exactly *on*
        // the target date is kept — the goal is still live that day.
        let goalEnd = task.goal.map { cal.startOfDay(for: $0.resolvedTargetDate) }
        // Links every occurrence created together (plus the source task itself) so they can
        // later be bulk-deleted as "this and all future occurrences" — see `TaskEntity`'s
        // `seriesID`. Reuses an existing series ID if this task is already part of one.
        let seriesID = task.seriesID ?? UUID()
        task.seriesID = seriesID
        var created = 0
        var skipped = 0
        var lastDate: Date?

        for offset in 1...(weeks * 7) {
            guard let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: task.resolvedDate)) else { continue }
            // `day` only moves forward, so the first one past the goal ends the whole run.
            if let goalEnd, day > goalEnd { break }
            let weekdayIndex = (cal.component(.weekday, from: day) + 5) % 7
            guard weekdaySymbols.contains(CommitmentEntity.weekdaySymbols[weekdayIndex]) else { continue }
            guard let newStart = cal.date(byAdding: timeOfDay, to: day) else { continue }
            let newEnd = newStart.addingTimeInterval(TimeInterval(task.durationMinutes) * 60)

            if ScheduleEngine.wouldCollide(start: newStart, end: newEnd, on: day, context: context) {
                skipped += 1
                continue
            }
            TaskEntity.create(
                in: context,
                title: task.title ?? "",
                date: day,
                startTime: newStart,
                durationMinutes: Int(task.durationMinutes),
                priority: task.priorityValue,
                goal: task.goal,
                notes: task.notes,
                seriesID: seriesID
            )
            created += 1
            lastDate = day
        }
        try? context.save()
        return (created, skipped, lastDate)
    }

    /// The first day on or after `start` that falls on one of `weekdaySymbols` — where a task
    /// carrying that repeat pattern actually belongs.
    ///
    /// `repeatWeekly` only ever creates occurrences *after* the task it's given, so the task
    /// itself has to already sit on the pattern. It doesn't, by default: a new task is filed on
    /// whichever day the user happens to be looking at, which is how asking for "Mon/Thu"
    /// on a Friday produced 27 Mondays, 27 Thursdays — and one stray Friday.
    ///
    /// Returns `start` unchanged when the pattern is empty (no repeat at all) or already
    /// includes `start`'s own weekday. Never searches more than a week, since any non-empty set
    /// of weekdays must match within seven days.
    static func firstDay(onOrAfter start: Date, matching weekdaySymbols: Set<String>) -> Date {
        guard !weekdaySymbols.isEmpty else { return start }
        let cal = Calendar.current
        for offset in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: start) else { continue }
            let weekdayIndex = (cal.component(.weekday, from: day) + 5) % 7
            if weekdaySymbols.contains(CommitmentEntity.weekdaySymbols[weekdayIndex]) { return day }
        }
        return start
    }

    /// Whole weeks needed to cover `start` through `target`, rounded up so the last day is
    /// never short of `target` — e.g. 68 days rounds up to 10 weeks, not down to 9. Always at
    /// least 1, even if `target` is on or before `start`.
    static func weeksUntil(_ target: Date, from start: Date) -> Int {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: start), to: cal.startOfDay(for: target)).day ?? 0
        return max(1, Int(ceil(Double(days) / 7)))
    }

    /// The one place this gets turned into user-facing text, shared by every screen that can
    /// trigger a repeat (creating a task, editing one, adding one from a goal) so the message
    /// — and the fact that it always names the *actual* last date, not just the requested
    /// length — stays consistent everywhere.
    static func summaryText(created: Int, skipped: Int, lastDate: Date?) -> String {
        guard created > 0 else {
            return skipped > 0 ? "Nothing added — every day collided with something." : "Nothing added."
        }
        let through = lastDate.map { ", through \($0.formatted(.dateTime.month(.abbreviated).day()))" } ?? ""
        let base = "Added \(created) task\(created == 1 ? "" : "s")\(through)."
        guard skipped > 0 else { return base }
        return base + " \(skipped) skipped due to conflicts."
    }
}
