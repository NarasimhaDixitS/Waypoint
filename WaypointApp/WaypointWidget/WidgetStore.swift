import Foundation
import CoreData

/// Reads today's tasks straight out of the shared store.
///
/// Read-only and short-lived: the widget process opens the store, takes what it needs and lets
/// go. It never writes, so it can't conflict with the app holding the same file.
enum WidgetStore {
    static func todaySnapshot(now: Date = .now) -> DaySnapshot {
        let context = PersistenceController.shared.container.viewContext
        let request = TaskEntity.fetchRequest(on: now, context: context)
        let tasks = (try? context.fetch(request)) ?? []
        let items = tasks
            .sorted { $0.resolvedStartTime < $1.resolvedStartTime }
            .compactMap { task -> DaySnapshot.Item? in
                guard let id = task.id else { return nil }
                return DaySnapshot.Item(
                    id: id,
                    title: task.title ?? "Untitled",
                    start: task.resolvedStartTime,
                    end: task.endTime,
                    isDone: task.isDone
                )
            }
        return DaySnapshot(date: Calendar.current.startOfDay(for: now), items: items)
    }
}
