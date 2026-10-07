import Foundation
import CoreData

/// What a search turns up: the goals that match, then the tasks that match.
///
/// **Goals are results now because they're places.** When search was built a goal wasn't
/// somewhere you could go, so matching its *name* against tasks was the only way to use it —
/// type "Spanish", get the goal's membership list. The goal centre made a goal a destination,
/// and search went on returning forty-four tasks and no way to reach the thing they belong to.
enum SearchResults {

    /// Tasks match on their **own** text. A task is not a match because its goal's name is.
    ///
    /// This is the behaviour change. Searching "spanish" used to return every task under Learn
    /// Spanish — none of which say "spanish" anywhere — because goal-name matching was the only
    /// route to a goal. Now the goal itself is the first result, and tapping it shows those same
    /// tasks grouped by overdue/today/upcoming, which is a better view of them than a flat list
    /// of forty-four rows was ever going to be.
    static func tasks(
        matching query: String,
        in tasks: [TaskEntity],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [TaskEntity] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        let today = calendar.startOfDay(for: now)
        return tasks
            .filter { task in
                (task.title ?? "").localizedCaseInsensitiveContains(q)
                    || (task.notes ?? "").localizedCaseInsensitiveContains(q)
            }
            .sorted { lhs, rhs in
                // **Nearest to today first**, not earliest ever. The fetch behind this is sorted
                // by `startTime` ascending across all of history, so the first thing you saw was
                // the oldest match in the database and today's was somewhere below the fold.
                // Searching is nearly always "where is that task", and the answer is nearly
                // always near now.
                let l = abs(calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: lhs.resolvedDate)).day ?? 0)
                let r = abs(calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: rhs.resolvedDate)).day ?? 0)
                if l != r { return l < r }
                // Same distance: the future one first. "Tomorrow" is more use than "yesterday"
                // when both are one day away.
                let lFuture = lhs.resolvedDate >= today
                let rFuture = rhs.resolvedDate >= today
                if lFuture != rFuture { return lFuture }
                return lhs.resolvedStartTime < rhs.resolvedStartTime
            }
    }

    /// Goals match on name or notes.
    static func goals(matching query: String, in goals: [GoalEntity]) -> [GoalEntity] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return goals.filter {
            ($0.name ?? "").localizedCaseInsensitiveContains(q)
                || ($0.notes ?? "").localizedCaseInsensitiveContains(q)
        }
    }
}
