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
    /// interrupting with a prompt per day — the caller shows one summary afterward.
    @discardableResult
    static func repeatWeekly(
        _ task: TaskEntity,
        onWeekdays weekdaySymbols: Set<String>,
        forWeeks weeks: Int,
        context: NSManagedObjectContext
    ) -> (created: Int, skipped: Int) {
        let cal = Calendar.current
        let timeOfDay = cal.dateComponents([.hour, .minute], from: task.resolvedStartTime)
        // Links every occurrence created together (plus the source task itself) so they can
        // later be bulk-deleted as "this and all future occurrences" — see `TaskEntity`'s
        // `seriesID`. Reuses an existing series ID if this task is already part of one.
        let seriesID = task.seriesID ?? UUID()
        task.seriesID = seriesID
        var created = 0
        var skipped = 0

        for offset in 1...(weeks * 7) {
            guard let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: task.resolvedDate)) else { continue }
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
        }
        try? context.save()
        return (created, skipped)
    }
}
