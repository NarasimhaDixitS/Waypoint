import Foundation
import CoreData

extension GoalEntity {
    var planningModeValue: PlanningMode {
        get { PlanningMode(rawValue: planningMode ?? "manual") ?? .manual }
        set { planningMode = newValue.rawValue }
    }

    /// `createdAt`/`targetDate` are generated as `Date?` by Core Data codegen regardless of
    /// the model's "Optional" flag; every goal is created with both, so these are safe
    /// fallbacks, not real degenerate cases.
    var resolvedCreatedAt: Date {
        createdAt ?? .now
    }

    var resolvedTargetDate: Date {
        targetDate ?? .now
    }

    var sortedTasks: [TaskEntity] {
        let set = tasks as? Set<TaskEntity> ?? []
        return set.sorted { $0.resolvedStartTime < $1.resolvedStartTime }
    }

    var totalDayCount: Int {
        let start = Calendar.current.startOfDay(for: resolvedCreatedAt)
        let end = Calendar.current.startOfDay(for: resolvedTargetDate)
        return max(Calendar.current.dateComponents([.day], from: start, to: end).day ?? 1, 1)
    }

    var currentDayNumber: Int {
        let start = Calendar.current.startOfDay(for: resolvedCreatedAt)
        let today = Calendar.current.startOfDay(for: .now)
        return min(max((Calendar.current.dateComponents([.day], from: start, to: today).day ?? 0) + 1, 1), totalDayCount)
    }

    var daysRemaining: Int {
        let today = Calendar.current.startOfDay(for: .now)
        let target = Calendar.current.startOfDay(for: resolvedTargetDate)
        return max(Calendar.current.dateComponents([.day], from: today, to: target).day ?? 0, 0)
    }

    var completionFraction: Double {
        let all = sortedTasks
        guard !all.isEmpty else { return 0 }
        let done = all.filter(\.isDone).count
        return Double(done) / Double(all.count)
    }

    var doneTaskCount: Int {
        sortedTasks.filter(\.isDone).count
    }

    private var completedTaskDays: Set<Date> {
        Set(sortedTasks.filter(\.isDone).compactMap { $0.completedAt.map { Calendar.current.startOfDay(for: $0) } })
    }

    var dayStreak: Int {
        let doneDates = completedTaskDays
        var streak = 0
        var cursor = Calendar.current.startOfDay(for: .now)
        while doneDates.contains(cursor) {
            streak += 1
            cursor = Calendar.current.date(byAdding: .day, value: -1, to: cursor)!
        }
        return streak
    }

    /// Whether at least one task under this goal was completed on each of the trailing
    /// `count` days, oldest first, ending today — the Today banner's week ring-strip. Shows
    /// the real shape of a week (missed days stay visible) rather than a streak count that
    /// only ever goes up or silently resets.
    func recentCompletion(days count: Int = 7, now: Date = .now) -> [(date: Date, done: Bool)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let doneDates = completedTaskDays
        return (0..<count).reversed().map { offset in
            let day = cal.date(byAdding: .day, value: -offset, to: today)!
            return (day, doneDates.contains(day))
        }
    }

    var upcomingTasks: [TaskEntity] {
        sortedTasks.filter { !$0.isDone && $0.resolvedDate >= Calendar.current.startOfDay(for: .now) }
    }

    @discardableResult
    static func create(
        in context: NSManagedObjectContext,
        name: String,
        targetDate: Date,
        planningMode: PlanningMode,
        notes: String? = nil
    ) -> GoalEntity {
        let goal = GoalEntity(context: context)
        goal.id = UUID()
        goal.name = name
        goal.targetDate = targetDate
        goal.createdAt = .now
        goal.planningModeValue = planningMode
        goal.notes = notes
        return goal
    }
}
