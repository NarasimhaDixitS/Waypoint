import Combine
import Foundation

/// The facts a finished goal is celebrated with, lifted out of Core Data at the moment it
/// finishes.
///
/// A snapshot rather than the `GoalEntity` itself, for two reasons. The screen outlives the
/// tap that triggered it — it's presented from `MainTabView`, not from whichever list the
/// last task was ticked in — and a managed object read later can have moved on. And the
/// numbers being shown are a statement about a moment: "38 tasks over 45 days" is what was
/// true when it was finished, not what `sortedTasks` happens to return once someone adds a
/// task to a completed goal.
struct GoalCelebration: Identifiable, Equatable {
    let id: String
    let name: String
    let days: Int
    let tasksDone: Int
}

/// Which goals have had their finish celebrated, and which one is waiting to be.
///
/// **A singleton for the same reason `PendingDeletions` is one.** The check belongs inside
/// `TaskEntity.toggleDone`, which is the one place a task is manually ticked — so a new
/// screen that ticks a task gets the celebration without knowing it exists, and can't opt
/// out by omission. Four lists can complete a goal's last task today (Today, the goal page,
/// the no-goal list, and the Week tab) and the count only goes up.
///
/// `toggleDone` is the hook rather than `isDone` itself, deliberately: `SampleData` sets
/// `isDone` directly when it seeds forty-five days of history, and `markAutoCompleted` sets
/// it when a task's window simply elapsed. Neither is somebody finishing something, and
/// neither should throw a party — loading the demo fixture would otherwise open a
/// celebration for a goal the user has never seen.
///
/// The record of what's been celebrated is in `UserDefaults` rather than on the entity,
/// because it describes something that happened to the *person*, not to the goal: re-ticking
/// the last task after un-ticking it is not a second achievement.
final class GoalCelebrations: ObservableObject {
    static let shared = GoalCelebrations()

    /// Non-nil while a finished goal is waiting to be shown. `MainTabView` binds to it.
    @Published var pending: GoalCelebration?

    private static let defaultsKey = "celebratedGoalIDs"
    private var celebrated: Set<String>

    private init() {
        celebrated = Set(UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? [])
    }

    /// Called when a task is manually ticked. Does nothing unless that tick was the one that
    /// finished its goal, and nothing at all the second time.
    func noteCompletion(of goal: GoalEntity?) {
        guard let goal, let id = goal.id?.uuidString else { return }
        guard goal.completionFraction >= 1 else { return }
        guard !celebrated.contains(id) else { return }

        celebrated.insert(id)
        UserDefaults.standard.set(Array(celebrated), forKey: Self.defaultsKey)

        pending = GoalCelebration(
            id: id,
            name: goal.name ?? "Your goal",
            days: goal.totalDayCount,
            tasksDone: goal.doneTaskCount
        )
    }

    /// True between a goal finishing and its screen being dismissed.
    ///
    /// `TaskRowView` reads this to stay quiet: ticking the last task of a goal is one moment,
    /// and firing the row's own success haptic a few milliseconds before the celebration's
    /// turns a single event into a stutter.
    var isCelebrating: Bool { pending != nil }

    /// Puts the app back to a state where every goal can be finished again.
    ///
    /// **Not `#if DEBUG`**, though `-wpFresh` is the reason it exists. `FreshInstall.wipe` is
    /// compiled in every configuration — Settings offers it as a button — and it is the one
    /// place that must leave no trace of the app having been used. A guard here only made
    /// the release build fail to compile, which is the cheap version of the real bug: a
    /// "fresh install" that quietly remembers which goals you'd already finished.
    func forgetAll() {
        celebrated.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
    }
}
