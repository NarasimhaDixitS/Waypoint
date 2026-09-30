import Foundation
import CoreData

/// What actually happened to a task, recorded as it happens.
///
/// Deliberately an append-only *log*, not a counter on `TaskEntity`. Behavioural history can't
/// be backfilled: a tally answers "how many times", and nothing else, forever. Keeping the
/// before/after dates and the moment of the decision is what makes "how far do things slip",
/// "which weekday do I defer on", and "which goal bleeds" answerable later, without having to
/// go back in time and collect them.
enum TaskEventKind: String {
    /// The user pushed a task to a later day. Recorded wherever the move came from.
    case deferred
    /// The user deleted a task they hadn't finished, on or after the day it was due. Deleting
    /// something still in the future is planning, not failure — see `shouldRecordAbandonment`.
    case abandoned
    /// The user deleted a goal they hadn't finished. Deliberately its own kind rather than one
    /// `abandoned` row per task: deleting a goal with 130 tasks under it is a single decision,
    /// and recording it as 130 separate failures would bury the signal it actually carries.
    case goalAbandoned
    /// A goal finished end to end.
    ///
    /// The missing half of `goalAbandoned`. Without it the app remembered every goal you gave
    /// up on and forgot every one you saw through — the wrong half to keep, and it left the
    /// single largest achievement in the app with no trace at all.
    case goalCompleted
    /// Work pulled *forward* to an earlier day. The counterpart to `deferred`: recording only
    /// the slips makes every history a record of failure, when moving something up is the same
    /// decision made well.
    case rescheduledEarlier
    /// The time budgeted for a task changed. `fromValue`/`toValue` are minutes.
    ///
    /// Cannot be derived after the fact — the task only ever holds its current duration — and
    /// it is the one edit that reveals a real pattern: the thing you keep having to double.
    case durationChanged
    /// How important a task was called changed. `fromText`/`toText` carry the priority.
    case priorityChanged
    /// A task ticked off and then un-ticked. Flags optimistic ticking, and is gone the instant
    /// it happens since the task keeps no memory of having been done.
    case completionUndone
}

enum TaskEventLog {
    /// Records a move to a later day. A no-op for same-day edits and for moves *earlier* —
    /// pulling work forward isn't a slip, and counting it would make the number meaningless.
    ///
    /// Called from `TaskEntity.apply(draft:)` rather than from any button, so that every route
    /// that can move a task — the quick action, the edit sheet, a cascade resolution — lands
    /// here. Instrumenting the affordance instead of the mutation leaves silent loopholes and
    /// quietly undercounts.
    ///
    /// Its opposite, `recordPullForwardIfNeeded`, sits beside it for the same reason.
    @discardableResult
    static func recordDeferralIfNeeded(
        task: TaskEntity,
        from oldDate: Date,
        to newDate: Date,
        in context: NSManagedObjectContext,
        now: Date = .now
    ) -> TaskEventEntity? {
        let cal = Calendar.current
        let from = cal.startOfDay(for: oldDate)
        let to = cal.startOfDay(for: newDate)
        guard to > from else { return nil }
        return record(.deferred, task: task, from: from, to: to, in: context, now: now)
    }

    /// Records giving up on a task. Call this at the point the delete actually commits, never
    /// when it's merely requested — Today's delete sits behind a 4-second undo window, and an
    /// undone delete is a decision the user reversed, not one they made.
    @discardableResult
    static func recordAbandonmentIfNeeded(
        task: TaskEntity,
        in context: NSManagedObjectContext,
        now: Date = .now
    ) -> TaskEventEntity? {
        guard shouldRecordAbandonment(task: task, now: now) else { return nil }
        return record(.abandoned, task: task, from: task.resolvedDate, to: nil, in: context, now: now)
    }

    /// Only an unfinished task whose day has already arrived counts. Deleting a finished task
    /// is housekeeping, and deleting one scheduled for next week is a plan changing — neither
    /// is a failure, and folding them in would leave the abandonment count measuring nothing
    /// in particular.
    static func shouldRecordAbandonment(task: TaskEntity, now: Date = .now) -> Bool {
        guard !task.isDone else { return false }
        let cal = Calendar.current
        return cal.startOfDay(for: task.resolvedDate) <= cal.startOfDay(for: now)
    }

    /// Records giving up on a goal, as one row. `fromDate`/`toDate` carry the goal's own span
    /// — created-on and aimed-at — so `occurredAt` against them answers "how far in did they
    /// quit," which is the question worth asking, without needing fields of its own.
    ///
    /// A goal whose tasks were all finished isn't abandoned; deleting that is housekeeping,
    /// the same rule tasks follow.
    @discardableResult
    static func recordGoalAbandonmentIfNeeded(
        goal: GoalEntity,
        in context: NSManagedObjectContext,
        now: Date = .now
    ) -> TaskEventEntity? {
        guard goal.completionFraction < 1 else { return nil }
        let event = TaskEventEntity(context: context)
        event.id = UUID()
        event.kind = TaskEventKind.goalAbandoned.rawValue
        event.occurredAt = now
        event.goalID = goal.id
        event.title = goal.name
        event.fromDate = goal.createdAt
        event.toDate = goal.resolvedTargetDate
        return event
    }

/// Work pulled forward to an earlier day.
    static func recordPullForwardIfNeeded(
        task: TaskEntity,
        from oldDate: Date,
        to newDate: Date,
        in context: NSManagedObjectContext,
        now: Date = .now
    ) -> TaskEventEntity? {
        let cal = Calendar.current
        let from = cal.startOfDay(for: oldDate)
        let to = cal.startOfDay(for: newDate)
        guard to < from else { return nil }
        return record(.rescheduledEarlier, task: task, from: from, to: to, in: context, now: now)
    }

    /// A change to the time budgeted for a task, in minutes.
    ///
    /// The task only ever holds its current duration, so this is unrecoverable the moment it
    /// isn't written down — and it's the edit that reveals the pattern worth knowing: the thing
    /// you keep having to double.
    @discardableResult
    static func recordDurationChangeIfNeeded(
        task: TaskEntity,
        from oldMinutes: Int,
        to newMinutes: Int,
        in context: NSManagedObjectContext,
        now: Date = .now
    ) -> TaskEventEntity? {
        guard oldMinutes != newMinutes, oldMinutes > 0 else { return nil }
        let event = record(.durationChanged, task: task, from: nil, to: nil, in: context, now: now)
        event.fromValue = Int32(oldMinutes)
        event.toValue = Int32(newMinutes)
        return event
    }

    /// A change to how important a task was called.
    @discardableResult
    static func recordPriorityChangeIfNeeded(
        task: TaskEntity,
        from oldPriority: Priority,
        to newPriority: Priority,
        in context: NSManagedObjectContext,
        now: Date = .now
    ) -> TaskEventEntity? {
        guard oldPriority != newPriority else { return nil }
        let event = record(.priorityChanged, task: task, from: nil, to: nil, in: context, now: now)
        event.fromText = oldPriority.rawValue
        event.toText = newPriority.rawValue
        return event
    }

    /// A task un-ticked after being marked done.
    ///
    /// The task keeps no memory of having been finished — `isDone` flips back and `completedAt`
    /// is cleared — so this is gone the instant it happens unless it's written here.
    @discardableResult
    static func recordCompletionUndone(
        task: TaskEntity,
        in context: NSManagedObjectContext,
        now: Date = .now
    ) -> TaskEventEntity {
        record(.completionUndone, task: task, from: task.completedAt, to: nil, in: context, now: now)
    }

    /// A goal seen through to the end.
    ///
    /// Derived rather than hooked to a button. A goal becomes complete when its last task is
    /// ticked, and that can happen from several screens — but it can also become complete
    /// because a task was deleted, or un-complete because one was added. Detecting the state
    /// during a reconcile pass catches every route, including the ones nobody thought of, and
    /// `occurredAt` takes the moment of the last completion rather than the moment we noticed.
    @discardableResult
    static func recordGoalCompletionIfNeeded(
        goal: GoalEntity,
        alreadyRecorded: Set<UUID>,
        in context: NSManagedObjectContext,
        now: Date = .now
    ) -> TaskEventEntity? {
        guard let id = goal.id, !alreadyRecorded.contains(id) else { return nil }
        let tasks = goal.sortedTasks
        guard !tasks.isEmpty, tasks.allSatisfy(\.isDone) else { return nil }

        let finishedAt = tasks.compactMap(\.completedAt).max() ?? now
        let event = TaskEventEntity(context: context)
        event.id = UUID()
        event.kind = TaskEventKind.goalCompleted.rawValue
        event.occurredAt = finishedAt
        event.goalID = id
        event.title = goal.name
        event.fromDate = goal.createdAt
        event.toDate = finishedAt
        event.toValue = Int32(tasks.count)
        return event
    }

    private static func record(
        _ kind: TaskEventKind,
        task: TaskEntity,
        from: Date?,
        to: Date?,
        in context: NSManagedObjectContext,
        now: Date
    ) -> TaskEventEntity {
        let event = TaskEventEntity(context: context)
        event.id = UUID()
        event.kind = kind.rawValue
        event.occurredAt = now
        // Plain UUIDs, not Core Data relationships. A relationship to `TaskEntity` would either
        // cascade this record away with the task it describes — destroying precisely the
        // abandonment signal — or leave a dangling reference. The denormalized title is here for
        // the same reason: a deleted task still has to be legible in a trend view a year later.
        event.taskID = task.id
        event.seriesID = task.seriesID
        event.goalID = task.goal?.id
        event.title = task.title
        event.fromDate = from
        event.toDate = to
        return event
    }
}

extension TaskEventEntity {
    var kindValue: TaskEventKind? {
        kind.flatMap(TaskEventKind.init(rawValue:))
    }

    /// How many days a deferral pushed the task. `nil` for anything but a move.
    var slipInDays: Int? {
        guard let fromDate, let toDate else { return nil }
        return Calendar.current.dateComponents([.day], from: fromDate, to: toDate).day
    }

    static func fetchRequest(kind: TaskEventKind? = nil, since: Date? = nil) -> NSFetchRequest<TaskEventEntity> {
        let request = NSFetchRequest<TaskEventEntity>(entityName: "TaskEventEntity")
        var predicates: [NSPredicate] = []
        if let kind {
            predicates.append(NSPredicate(format: "kind == %@", kind.rawValue))
        }
        if let since {
            predicates.append(NSPredicate(format: "occurredAt >= %@", since as NSDate))
        }
        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TaskEventEntity.occurredAt, ascending: false)]
        return request
    }
}
