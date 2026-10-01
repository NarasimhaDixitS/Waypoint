import Foundation

/// A not-yet-persisted task, used to carry state between the New Task sheet and the
/// ad-hoc bump flow before it's actually written to Core Data.
struct TaskDraft: Identifiable {
    let id = UUID()
    var title: String
    var date: Date
    var startTime: Date
    var durationMinutes: Int
    var priority: Priority
    var notes: String?
    var goal: GoalEntity?
    /// Non-empty when this draft should also repeat on these weekdays after it's created —
    /// set at creation time, rather than requiring a separate "Repeat on other days" trip
    /// after the fact. Empty means "just this once" (the default for every existing caller).
    var repeatWeekdays: Set<String> = []
    var repeatWeeks: Int = 4

    /// Off unless the user says otherwise, for every task and every caller.
    ///
    /// The app used to remind you about everything on today's list the moment notifications
    /// were on at all. A nudge that arrives for all twelve of today's tasks teaches you to
    /// dismiss it unread, and then the one you actually needed goes with the rest — the value
    /// of an interruption is entirely in how rarely it comes.
    var reminderEnabled: Bool = false
    /// `-1` means "follow my priority". See `TaskEntity.reminderLeadFollowsPriority`.
    var reminderLeadMinutes: Int = -1
    /// Whether this reminder setting should carry to the rest of the repeat series, from this
    /// occurrence forward. Ignored for tasks that aren't part of one.
    var reminderAppliesToSeries: Bool = false

    var endTime: Date {
        startTime.addingTimeInterval(TimeInterval(durationMinutes * 60))
    }
}
