import Foundation
import CoreData

extension TaskEntity {
    var priorityValue: Priority {
        get { Priority(rawValue: priority ?? "medium") ?? .medium }
        set { priority = newValue.rawValue }
    }

    /// `startTime` is generated as `Date?` by Core Data codegen regardless of the model's
    /// "Optional" flag; every task is created with one, so this is a safe fallback, not a
    /// real degenerate case.
    var resolvedStartTime: Date {
        startTime ?? .now
    }

    /// Same rationale as `resolvedStartTime` — `date` is `Date?` per Core Data codegen.
    var resolvedDate: Date {
        date ?? .now
    }

    var endTime: Date {
        resolvedStartTime.addingTimeInterval(TimeInterval(durationMinutes * 60))
    }

    var state: TaskState { state(at: .now) }

    /// Takes the instant explicitly so a screen can resolve every row against one clock reading.
    /// Rows calling `.now` individually can straddle a minute boundary mid-render and disagree
    /// with each other about which task is running — and, more to the point, a view can't
    /// re-render on a clock it never observes. See `TodayView.clockTick`.
    func state(at now: Date) -> TaskState {
        TaskState.resolve(
            isDone: isDone,
            date: resolvedDate,
            startTime: resolvedStartTime,
            durationMinutes: Int(durationMinutes),
            now: now
        )
    }

    var timeRangeLabel: String {
        "\(resolvedStartTime.formatted(.dateTime.hour().minute()))–\(endTime.formatted(.dateTime.hour().minute()))"
    }

/// When this person's history starts.
    ///
    /// Everything that draws a run of days needs it, because a day before someone started is
    /// not a day they missed — and a chart that can't tell those apart greets a new user by
    /// reporting a week of failures that never happened.
    ///
    /// The earliest of *either* stamp, not just `createdAt`. Normally the two agree, since the
    /// app won't let work be scheduled in the past. But a store can hold rows written in bulk
    /// with a single creation stamp — the demo fixture did exactly that — and then `createdAt`
    /// says "started today" over six weeks of visible history. Taking the minimum keeps the
    /// answer right however the data arrived, rather than depending on every writer having been
    /// careful.
    ///
    /// `nil` means there's no history at all yet, which callers should treat as "everything is
    /// still ahead" rather than "everything was missed".
    static func firstActivityDate(in context: NSManagedObjectContext) -> Date? {
        func earliest(by key: String, read: (TaskEntity) -> Date?) -> Date? {
            let request = NSFetchRequest<TaskEntity>(entityName: "TaskEntity")
            request.sortDescriptors = [NSSortDescriptor(key: key, ascending: true)]
            request.fetchLimit = 1
            return (try? context.fetch(request))?.first.flatMap(read)
        }
        let stamps = [
            earliest(by: "createdAt") { $0.createdAt },
            earliest(by: "date") { $0.date }
        ]
        return stamps.compactMap { $0 }.min()
    }

    static func fetchRequest(on day: Date, context: NSManagedObjectContext) -> NSFetchRequest<TaskEntity> {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return fetchRequest(from: start, to: end)
    }

    static func fetchRequest(from start: Date, to end: Date) -> NSFetchRequest<TaskEntity> {
        let request = TaskEntity.fetchRequest()
        request.predicate = NSPredicate(format: "date >= %@ AND date < %@", start as NSDate, end as NSDate)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TaskEntity.startTime, ascending: true)]
        return request
    }

    @discardableResult
    static func create(
        in context: NSManagedObjectContext,
        title: String,
        date: Date,
        startTime: Date,
        durationMinutes: Int,
        priority: Priority,
        goal: GoalEntity? = nil,
        notes: String? = nil,
        seriesID: UUID? = nil
    ) -> TaskEntity {
        let task = TaskEntity(context: context)
        task.id = UUID()
        task.title = title
        task.date = Calendar.current.startOfDay(for: date)
        task.startTime = startTime
        task.durationMinutes = Int32(durationMinutes)
        task.priorityValue = priority
        task.isDone = false
        task.createdAt = .now
        task.goal = goal
        task.notes = notes
        task.seriesID = seriesID
        return task
    }

    /// `autoCompleted` records *how* a task got ticked, not just that it did.
    ///
    /// Auto-completion stamps `completedAt` with the task's scheduled end rather than the real
    /// instant — it has no other honest value to use. That makes `completedAt` two different
    /// measurements sharing one field: a real observation for manual ticks, and a restatement
    /// of the schedule for automatic ones. Any time-of-day analysis that mixes them shows a
    /// spike at every task's end time and reads as a genuine pattern, so anything drawing
    /// conclusions from *when* work happened has to filter on this first.
    ///
    /// - Parameter context: when given, un-ticking is logged. The task keeps no memory of
    ///   having been done — `isDone` flips back and `completedAt` is cleared — so that fact is
    ///   gone the instant it happens unless it's written down here.
    func toggleDone(now: Date = .now, in context: NSManagedObjectContext? = nil) {
        if isDone, let context {
            TaskEventLog.recordCompletionUndone(task: self, in: context, now: now)
        }
        isDone.toggle()
        completedAt = isDone ? now : nil
        autoCompleted = false
    }

    /// Marks a task finished because its window elapsed, not because anyone said so.
    func markAutoCompleted() {
        isDone = true
        completedAt = endTime
        autoCompleted = true
    }

    /// Completions whose timestamp is a real observation of when work stopped.
    var hasObservedCompletionTime: Bool { isDone && !autoCompleted && completedAt != nil }

    /// The single place an existing task takes on an edit. Lived as a verbatim copy in both
    /// `TodayView` and `GoalDetailView` before this; it's in the model now because deferral
    /// logging has to sit on the mutation, not on any one screen's button — a third caller
    /// added later would otherwise silently skip it.
    func apply(_ draft: TaskDraft, in context: NSManagedObjectContext, now: Date = .now) {
        // Read before the write. Everything logged below is a *change*, and the task holds only
        // its current values — once these are overwritten there's no way back to what they were.
        let previousDate = resolvedDate
        let previousMinutes = Int(durationMinutes)
        let previousPriority = priorityValue

        title = draft.title
        date = Calendar.current.startOfDay(for: draft.date)
        startTime = draft.startTime
        durationMinutes = Int32(draft.durationMinutes)
        priorityValue = draft.priority
        goal = draft.goal
        notes = draft.notes

        // All five sit on the mutation rather than on any button, so a route added later is
        // instrumented by construction instead of by somebody remembering.
        TaskEventLog.recordDeferralIfNeeded(task: self, from: previousDate, to: draft.date, in: context, now: now)
        TaskEventLog.recordPullForwardIfNeeded(task: self, from: previousDate, to: draft.date, in: context, now: now)
        TaskEventLog.recordDurationChangeIfNeeded(task: self, from: previousMinutes, to: draft.durationMinutes, in: context, now: now)
        TaskEventLog.recordPriorityChangeIfNeeded(task: self, from: previousPriority, to: draft.priority, in: context, now: now)
    }
}
