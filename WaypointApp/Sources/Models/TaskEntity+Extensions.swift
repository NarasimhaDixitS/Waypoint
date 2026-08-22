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

    var state: TaskState {
        TaskState.resolve(isDone: isDone, date: resolvedDate, startTime: resolvedStartTime, durationMinutes: Int(durationMinutes))
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

    func toggleDone() {
        isDone.toggle()
        completedAt = isDone ? .now : nil
    }
}
