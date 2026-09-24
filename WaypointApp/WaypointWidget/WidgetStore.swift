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
        return DaySnapshot(
            date: Calendar.current.startOfDay(for: now),
            items: items,
            week: weekCompletion(context: context, now: now)
        )
    }

    /// One fetch across the whole week rather than seven day-fetches — the widget process is
    /// woken briefly and killed, so the work it does at launch is the work that matters.
    private static func weekCompletion(context: NSManagedObjectContext, now: Date) -> [Bool] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        guard let start = cal.date(byAdding: .day, value: -6, to: today),
              let end = cal.date(byAdding: .day, value: 1, to: today) else {
            return Array(repeating: false, count: 7)
        }
        let request = TaskEntity.fetchRequest(from: start, to: end)
        let tasks = (try? context.fetch(request)) ?? []
        let doneDays = Set(tasks.filter(\.isDone).map { cal.startOfDay(for: $0.resolvedDate) })
        return (0..<7).reversed().compactMap { offset in
            cal.date(byAdding: .day, value: -offset, to: today).map { doneDays.contains($0) }
        }
    }
}
