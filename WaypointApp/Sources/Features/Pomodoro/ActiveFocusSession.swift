import Foundation

/// A focus session that outlives the screen showing it.
///
/// **Closing the sheet used to throw the session away.** Every bit of it lived in `@State`, so
/// tapping × — or reaching for it by accident — reset the clock to full and drained the water
/// back to nothing. Whatever you'd actually worked was gone, and the screen you came back to
/// claimed you hadn't started.
///
/// **It's anchored to the wall clock, not to a tick count.** `endsAt` is a real `Date`, so a
/// session survives the app being suspended or killed: reopening computes what's left from the
/// clock rather than from however many times a timer fired. That was already true while the
/// timer ran; it just had nowhere to live once the view went away.
///
/// One at a time, deliberately. Two concurrent focus sessions is not a thing a person does, and
/// storing a set of them would mean deciding which one the screen is about.
struct ActiveFocusSession: Codable, Equatable {
    var taskID: UUID?
    var taskTitle: String?
    var selectedMinutes: Int

    /// When the current run stretch ends. `nil` while paused.
    var endsAt: Date?
    /// Seconds left, written whenever the session pauses.
    var pausedRemaining: Int
    /// Focused seconds banked from earlier stretches. See `PomodoroView`'s session accounting:
    /// a timer paused over lunch must not count the lunch.
    var bankedSeconds: Int
    /// When the user first pressed play.
    var startedAt: Date

    var isRunning: Bool { endsAt != nil }

    /// Seconds left right now, from the clock.
    func remaining(at now: Date = .now) -> Int {
        guard let endsAt else { return pausedRemaining }
        return max(0, Int(endsAt.timeIntervalSince(now).rounded()))
    }

    /// Focused seconds right now, counting the live stretch.
    func focusedSeconds(at now: Date = .now, totalMinutes: Int) -> Int {
        guard endsAt != nil else { return bankedSeconds }
        let elapsedThisStretch = totalMinutes * 60 - bankedSeconds - remaining(at: now)
        return bankedSeconds + max(0, elapsedThisStretch)
    }

    /// Whether this stored session is the one the given screen is about.
    ///
    /// Compared on the task, not on the title: two tasks can share a name, and a renamed task
    /// is still the same task.
    func matches(taskID: UUID?) -> Bool { self.taskID == taskID }
}

enum ActiveFocusStore {
    private static let key = "focus.activeSession"

    static var current: ActiveFocusSession? {
        get {
            guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
            return try? JSONDecoder().decode(ActiveFocusSession.self, from: data)
        }
        set {
            guard let newValue, let data = try? JSONEncoder().encode(newValue) else {
                UserDefaults.standard.removeObject(forKey: key)
                return
            }
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func clear() { current = nil }
}
