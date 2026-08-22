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

    var endTime: Date {
        startTime.addingTimeInterval(TimeInterval(durationMinutes * 60))
    }
}
