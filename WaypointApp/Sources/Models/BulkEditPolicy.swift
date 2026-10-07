import Foundation

/// Which days may be edited in bulk.
///
/// **This is a free function with a test rather than a line inside a view**, because it is the
/// one rule in this feature that is easy to relax by accident and expensive to get wrong. A
/// future change that makes selection available everywhere would look, from inside `TodayView`,
/// like deleting a `guard`.
///
/// The rule: **forward only**. Operating on today's or a future day's tasks is planning — you
/// created six instances of a repeat with the wrong duration and you want them gone. Operating
/// on a past day's tasks is erasing the record, and the whole premise of keeping overdue tasks
/// visible is that they stay visible. Selecting every task you missed last week and deleting
/// them in one tap is the same move as "move all unfinished to tomorrow", which this app
/// deliberately doesn't offer.
///
/// A past task can still be deleted individually through its own editor. That is the intended
/// cost: one deliberate act per task, and the deletion is logged as an abandonment by
/// `TaskEventLog.recordAbandonmentIfNeeded`, which is exactly the signal a bulk sweep would
/// destroy — 130 abandonments recorded in one tap is not 130 decisions.
enum BulkEditPolicy {

    /// - Parameters:
    ///   - day: The day being viewed.
    ///   - canEditDay: What the subscription gate already decided about this day. Passed in
    ///     rather than consulted here so there is one owner of that question; bulk must never
    ///     become a way around the free tier.
    static func allowsBulkEditing(
        on day: Date,
        canEditDay: Bool,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        guard canEditDay else { return false }
        return calendar.startOfDay(for: day) >= calendar.startOfDay(for: now)
    }
}
