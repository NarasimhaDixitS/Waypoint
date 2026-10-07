import Foundation
import CoreData

/// What a bulk delete would actually remove, worked out before anything is shown.
///
/// **Why this is computed up front.** The whole safety argument for series deletion is the
/// number: "are you sure?" is a question anyone can answer yes to without thinking, where
/// "this removes 41 tasks" is a number that stops them. That means the count has to be known
/// before the sheet opens, not discovered after it's confirmed.
///
/// **Series means this occurrence and every later one, never the whole history.** It takes the
/// earliest *selected* date in each series and sweeps forward from there. Past occurrences are
/// left exactly where they are, for the same reason bulk editing is forward-only at all: a
/// repeat you kept for six weeks and then abandoned is a record, and deleting the record is
/// not the same as stopping the repeat. This matches what the single-task editor has always
/// done — see `GoalDetailView.deleteSeries(from:)`.
struct BulkDeletePlan: Identifiable {
    let id = UUID()
    /// Exactly what the user ticked.
    let selected: [TaskEntity]
    /// The selection, plus every later occurrence of any series it touches.
    let seriesTasks: [TaskEntity]
    /// How many distinct series the selection reaches into.
    let seriesCount: Int

    var hasSeries: Bool { seriesCount > 0 }

    /// How many tasks series deletion would remove *beyond* the ones already ticked. This is
    /// the number worth reading, because it's the part the user didn't choose one by one.
    var additionalCount: Int { max(0, seriesTasks.count - selected.count) }

    var plainTitle: String {
        selected.count == 1
            ? "\u{201C}\(selected[0].title ?? "Task")\u{201D}"
            : "\(selected.count) tasks"
    }

    var seriesTitle: String { "\(seriesTasks.count) tasks" }

    init(selected: [TaskEntity], context: NSManagedObjectContext, calendar: Calendar = .current) {
        self.selected = selected

        // One sweep per series, from the earliest selected occurrence in it. Selecting three
        // tasks from the same repeat is still one series and one sweep, not three overlapping
        // ones — which is what would have double-counted the total on the sheet.
        var earliestBySeries: [UUID: Date] = [:]
        for task in selected {
            guard let seriesID = task.seriesID else { continue }
            let day = calendar.startOfDay(for: task.resolvedDate)
            if let existing = earliestBySeries[seriesID] {
                earliestBySeries[seriesID] = min(existing, day)
            } else {
                earliestBySeries[seriesID] = day
            }
        }

        self.seriesCount = earliestBySeries.count

        var collected: [NSManagedObjectID: TaskEntity] = [:]
        for task in selected { collected[task.objectID] = task }

        for (seriesID, from) in earliestBySeries {
            let request = TaskEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "seriesID == %@ AND date >= %@", seriesID as CVarArg, from as NSDate
            )
            for match in (try? context.fetch(request)) ?? [] {
                collected[match.objectID] = match
            }
        }

        self.seriesTasks = collected.values.sorted { $0.resolvedStartTime < $1.resolvedStartTime }
    }
}
