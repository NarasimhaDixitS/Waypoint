import Foundation
import CoreData

/// Puts the app back to the state a brand-new user actually meets.
///
/// **Why "delete the app" doesn't do this.** The trial start is in the Keychain, deliberately,
/// so that deleting and reinstalling can't earn a second fourteen days — see `TrialRecord`.
/// That protection also means the one thing you cannot reset by hand is the one that decides
/// whether a new user sees a trial at all, which made testing the first run a guessing game.
///
/// **And loading the demo fixture is the opposite of this.** It fills the app with forty-five
/// days of history, which is exactly the experience a new user doesn't have — a Progress page
/// full of charts, goals already running, streaks already going. The two buttons answer
/// opposite questions: "what does this look like with data" and "what does this look like
/// without any".
///
/// **Lives in `Sources/App`, not `Sources/Models`.** The widget target compiles `Sources/Models`
/// and pulls only a hand-picked few files from elsewhere — so anything in there that reaches for
/// `TrialRecord` or `FirstRunHint` builds for the app and fails for the widget, which is exactly
/// how this file announced itself.
///
/// Debug only. It destroys everything.
enum FreshInstall {

    /// Everything that makes the app believe it has met this person before.
    ///
    /// Theme and accent are deliberately left alone: they're a device preference rather than
    /// evidence of use, and resetting them on every pass makes it harder to check a first run
    /// in paper or in dark.
    private static let defaultsKeys = [
        "hasSeenWelcome",
        "hasCompletedOnboarding",
        "sleepStartTimeOfDay",
        "sleepDurationMinutes",
        "sleepConfirmed",
        "progress.announcedCharts",
        // `SubscriptionManager.Keys`, spelled out because they're private to it. Checked
        // against that file rather than guessed; a typo here leaves someone "subscribed" on a
        // fresh install and the first run is then the wrong first run entirely.
        "subscription.plan",
        "subscription.renewsAt",
    ]

    static func wipe(in context: NSManagedObjectContext) {
        // Every entity, including the ones `SampleData.clearContent` deliberately keeps.
        // `AppSessionEntity` is a log of the real person at the keyboard, which the demo seed is
        // right to preserve and a fresh install is right to destroy — the whole point here is to
        // leave no trace of having been used.
        for entity in ["TaskEntity", "GoalEntity", "TaskEventEntity", "FocusSessionEntity",
                       "MilestoneEntity", "CommitmentEntity", "AppSessionEntity"] {
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: entity)
            guard let objects = try? context.fetch(request) as? [NSManagedObject] else { continue }
            objects.forEach(context.delete)
        }
        try? context.save()

        for key in defaultsKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        FirstRunHint.resetAll()

        // The Keychain item, which is the only part of this that survives deleting the app.
        TrialRecord.clear()
    }
}
