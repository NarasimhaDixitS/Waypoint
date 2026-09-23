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
    func toggleDone(now: Date = .now) {
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
        let previousDate = resolvedDate
        title = draft.title
        date = Calendar.current.startOfDay(for: draft.date)
        startTime = draft.startTime
        durationMinutes = Int32(draft.durationMinutes)
        priorityValue = draft.priority
        goal = draft.goal
        notes = draft.notes
        TaskEventLog.recordDeferralIfNeeded(task: self, from: previousDate, to: draft.date, in: context, now: now)
    }
}
