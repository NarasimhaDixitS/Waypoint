import Foundation
import CoreData

/// Catches up the record: derives what can be derived, and writes down what's newly true.
///
/// Two jobs that look different and aren't. A goal becomes complete when its last task is
/// ticked — but it can also become complete because a task was *deleted*, or stop being
/// complete because one was added, and no button fires for either. A milestone turns true at a
/// date boundary, with nobody present at all. Hooking either to a tap would miss the routes
/// nobody thought of, so both are detected by looking at the data as it actually stands.
///
/// Runs on launch and on foreground. Everything it does is idempotent — a milestone already
/// recorded is skipped, a goal already marked complete isn't marked twice — so running it more
/// often than necessary costs a fetch and nothing else.
enum HistoryReconciler {

    @MainActor
    static func run(in context: NSManagedObjectContext, now: Date = .now) {
        let events = fetch(TaskEventEntity.fetchRequest(kind: nil, since: nil), in: context)
        let goals = fetch(NSFetchRequest<GoalEntity>(entityName: "GoalEntity"), in: context)

        // Goal completions first: a milestone reads them, so they have to exist by then.
        let alreadyCompleted = Set(events.filter { $0.kindValue == .goalCompleted }.compactMap(\.goalID))
        for goal in goals {
            TaskEventLog.recordGoalCompletionIfNeeded(
                goal: goal, alreadyRecorded: alreadyCompleted, in: context, now: now
            )
        }

        let refreshedEvents = fetch(TaskEventEntity.fetchRequest(kind: nil, since: nil), in: context)
        let milestones = fetch(MilestoneEntity.fetchRequest(), in: context)
        let earned = MilestoneEvaluator.newlyEarned(
            .init(
                tasks: fetch(NSFetchRequest<TaskEntity>(entityName: "TaskEntity"), in: context),
                events: refreshedEvents,
                sessions: fetch(FocusSessionEntity.fetchRequest(since: nil), in: context),
                goals: goals,
                alreadyEarned: Set(milestones.compactMap(\.kind)),
                now: now
            )
        )

        for milestone in earned {
            let row = MilestoneEntity(context: context)
            row.id = UUID()
            row.kind = milestone.kind.rawValue
            row.achievedAt = milestone.achievedAt
            row.value = Int32(milestone.value)
            row.context = milestone.context
        }

        guard context.hasChanges else { return }
        try? context.save()
    }

    private static func fetch<T: NSFetchRequestResult>(
        _ request: NSFetchRequest<T>, in context: NSManagedObjectContext
    ) -> [T] {
        (try? context.fetch(request)) ?? []
    }
}
