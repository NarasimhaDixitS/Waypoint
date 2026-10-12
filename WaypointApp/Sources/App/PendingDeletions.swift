import Foundation
import CoreData

/// Deletes that have left the screen but not yet left the store.
///
/// Deleting a task in Waypoint is two-phase on purpose: the row goes immediately, and the real
/// `context.delete` happens four seconds later so "Undo" has something to undo. For those four
/// seconds the task is invisible and still completely present in Core Data — and that is a fact
/// the rest of the app has to be *told*, not left to discover.
///
/// **It used to be `@State` inside `TodayView`, and that produced three separate bugs.**
/// `ScheduleEngine` fetches straight from Core Data, so a task mid-undo-window still occupied
/// its slot: deleting a task and immediately creating another in the same place raised the bump
/// prompt, naming a task that was no longer on screen. `TaskReplicator` consulted the same
/// engine, so a repeating occurrence could be silently skipped for colliding with a ghost. And
/// because the set was local to one screen, the row that had just vanished from Today was still
/// drawn in Week and on goal pages.
///
/// **The worse half had nothing to do with collisions.** The second phase was a bare
/// `DispatchQueue.main.asyncAfter`, with nothing watching the scene phase. If the process died
/// inside those four seconds — and iOS terminates suspended apps constantly — `context.delete`
/// was never reached and the delete was lost for good: delete a task, leave the app, come back
/// to find it still there. `WaypointApp` now finalizes on `.background`, which is the last
/// moment the app is guaranteed to be told anything.
///
/// A singleton read directly by `ScheduleEngine` rather than a parameter threaded through it.
/// A defaulted `excluding:` argument would mean every future call site silently opting back in
/// to the bug this exists to fix; one choke point cannot be forgotten.
@MainActor
final class PendingDeletions: ObservableObject {
    static let shared = PendingDeletions()

    /// How long "Undo" stays on offer. Shared by every screen that deletes, so the toast and
    /// the commit can't drift apart.
    static let undoWindow: TimeInterval = 4

    /// One batch, whether it came from a single swipe or a bulk selection.
    ///
    /// `title` is the display phrase the toast shows — "“Task name”" for one, "12 tasks" for a
    /// series — so the toast never needs to know which case it is in.
    struct Pending: Identifiable {
        let id = UUID()
        let tasks: [TaskEntity]
        let title: String
    }

    @Published private(set) var pending: Pending?

    /// Every task currently hidden by an in-flight delete, whatever day it falls on. Separate
    /// from `pending` so a view can filter against a plain set without knowing about the toast.
    @Published private(set) var hiddenIDs: Set<NSManagedObjectID> = []

    /// Held so `finalize()` can run without a view — it is called from the scene-phase change,
    /// where there is no `@Environment` to read.
    private var context: NSManagedObjectContext?

    /// Hides the tasks and starts the undo window. Only one batch is pending at a time:
    /// starting a second commits the first, the same "next toast replaces the last" behaviour
    /// most apps use.
    ///
    /// Reminders are cancelled up front rather than at commit, so none of them can fire during
    /// the window for a task the user has already dismissed from the screen.
    func requestDelete(_ tasks: [TaskEntity], title: String, in context: NSManagedObjectContext) {
        guard !tasks.isEmpty else { return }
        finalize()
        self.context = context
        for task in tasks {
            if let id = task.id { NotificationManager.cancelReminder(taskID: id) }
        }
        hiddenIDs.formUnion(tasks.map(\.objectID))
        let batch = Pending(tasks: tasks, title: title)
        pending = batch
        let token = batch.id
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.undoWindow) { [weak self] in
            guard let self, self.pending?.id == token else { return }
            self.finalize()
        }
    }

    /// Makes the delete real. Safe to call at any time, including when nothing is pending —
    /// which is what lets the scene-phase hook call it unconditionally.
    func finalize() {
        guard let batch = pending, let context else { return }
        pending = nil
        hiddenIDs.subtract(batch.tasks.map(\.objectID))
        for task in batch.tasks {
            // A task can leave the store by another door while this window is open: the goal
            // page's series delete removes occurrences outright, and a demo reseed empties
            // everything. Reading a deleted object's properties is undefined behaviour, and
            // skipping it is the right answer anyway — what this wanted has already happened.
            guard !task.isDeleted, task.managedObjectContext != nil else { continue }
            // Logged here rather than in `requestDelete` on purpose: this is the point the
            // delete becomes real. A delete the user undid inside the window is a decision they
            // reversed, and recording it would count a failure that didn't happen.
            TaskEventLog.recordAbandonmentIfNeeded(task: task, in: context)
            context.delete(task)
        }
        try? context.save()
    }

    /// Drops the window without committing, for a store being emptied underneath us and for
    /// tests, which share the singleton and would otherwise leak a hidden ID into each other.
    func reset() {
        pending = nil
        hiddenIDs = []
        context = nil
    }

    /// Puts the tasks back. Nothing was removed from the store, so this only stops hiding them —
    /// and rebuilds the reminder window, since `requestDelete` cancelled theirs.
    func undo() {
        guard let batch = pending, let context else { return }
        pending = nil
        hiddenIDs.subtract(batch.tasks.map(\.objectID))
        // `SelectableTaskList` used to skip this half, so undoing a bulk delete there left
        // every one of those tasks silently without its reminder.
        NotificationManager.refreshTaskReminders(
            in: context,
            enabled: ThemeManager.shared.notificationsEnabled
        )
    }
}
