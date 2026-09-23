import Foundation
import UserNotifications
import CoreData

/// Local-notification scheduling for task reminders, the evening day summary, and streak
/// nudges. Everything here is on-device (UNUserNotificationCenter) — there's no APNs/backend
/// wired up yet, so this covers the free-tier "Push notifications" spec item as far as it can
/// go without a server.
@MainActor
enum NotificationManager {
    private static let dailySummaryIdentifier = "wp.dailySummary"
    private static let streakNudgeIdentifier = "wp.streakNudge"
    private static let reminderLeadTime: TimeInterval = 5 * 60

    static func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            // `.timeSensitive` in the options is what lets a notification request that
            // interruption level at all; without it the level is silently downgraded.
            center.requestAuthorization(options: [.alert, .sound, .badge, .timeSensitive]) { _, _ in }
        }
    }

    static func disableAll() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
    }

    // MARK: - Task reminders

    /// iOS keeps at most **64 pending local notifications per app** — not per day, per app, for
    /// the whole queue. Past that it keeps the 64 that fire soonest and silently discards the
    /// rest, with nothing to tell you it happened.
    ///
    /// This used to schedule one per task for every future task, so three weeks of planned work
    /// sat at 30–60 and real use would quietly cross the line. Reminders would then stop
    /// arriving for no visible reason — the worst kind of bug, because the app looks fine.
    ///
    /// Only *today* is ever scheduled, which caps the queue at a handful and matches what a
    /// reminder is for: a day has maybe a dozen tasks, and a nudge about next Thursday isn't a
    /// reminder, it's noise.
    static let maxPendingReminders = 64

    static func reminderIdentifier(for taskID: UUID) -> String {
        "wp.task.\(taskID.uuidString)"
    }

    /// Rebuilds the whole reminder set from today's tasks.
    ///
    /// Wholesale rather than per-task: the previous code cancelled and re-added one task at a
    /// time from two different screens, so a task deleted somewhere that forgot to call it kept
    /// its reminder and fired for work that no longer existed. Rebuilding from the current list
    /// can't drift, because the list *is* the source of truth.
    ///
    /// - Parameter tasks: every task for today, done or not. Filtering happens here so callers
    ///   can't disagree about the rules.
    static func refreshTaskReminders(tasks: [TaskEntity], enabled: Bool, now: Date = .now) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let stale = pending.map(\.identifier).filter { $0.hasPrefix("wp.task.") }
            center.removePendingNotificationRequests(withIdentifiers: stale)

            guard enabled else { return }
            let cal = Calendar.current
            let today = cal.startOfDay(for: now)
            let due = tasks
                .filter { !$0.isDone }
                .filter { cal.startOfDay(for: $0.resolvedDate) == today }
                .filter { $0.resolvedStartTime.addingTimeInterval(-reminderLeadTime) > now }
                .sorted { $0.resolvedStartTime < $1.resolvedStartTime }
                .prefix(maxPendingReminders - reservedNonTaskSlots)

            for task in due {
                guard let id = task.id else { continue }
                center.add(reminderRequest(taskID: id, title: task.title ?? "Task", startTime: task.resolvedStartTime))
            }
        }
    }

    /// The day summary, the streak nudge and a running Pomodoro each hold a slot, so task
    /// reminders can't be allowed to fill the queue right to the cap.
    private static let reservedNonTaskSlots = 4

    private static func reminderRequest(taskID: UUID, title: String, startTime: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "Starts in 5 minutes"
        content.sound = .default
        // As close to an alarm as a third-party app is allowed to get. Only Apple's Clock can
        // ring through silent mode; `.timeSensitive` is the one level that breaks through a
        // Focus mode when the user permits it, and it needs no special entitlement — unlike
        // `.critical`, which Apple grants to medical and safety apps and would not grant here.
        content.interruptionLevel = .timeSensitive
        content.threadIdentifier = "wp.task"

        let fireDate = startTime.addingTimeInterval(-reminderLeadTime)
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        return UNNotificationRequest(identifier: reminderIdentifier(for: taskID), content: content, trigger: trigger)
    }

    static func cancelReminder(taskID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reminderIdentifier(for: taskID)])
    }

    // MARK: - Day summary

    static func scheduleDailySummary(hour: Int = 20, minute: Int = 0) {
        let content = UNMutableNotificationContent()
        content.title = "Waypoint"
        content.body = "See how today went and what's queued for tomorrow."
        content.sound = .default

        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: dailySummaryIdentifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func cancelDailySummary() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [dailySummaryIdentifier])
    }

    // MARK: - Streak nudge

    static func scheduleStreakNudge(streak: Int, hour: Int = 9, minute: Int = 0) {
        cancelStreakNudge()
        guard streak > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(streak)-day streak"
        content.body = "Keep it going — plan today's first task in Waypoint."
        content.sound = .default

        let cal = Calendar.current
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: .now),
              let fireDate = cal.date(bySettingHour: hour, minute: minute, second: 0, of: tomorrow) else { return }
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: streakNudgeIdentifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func cancelStreakNudge() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [streakNudgeIdentifier])
    }

    // MARK: - Pomodoro

    private static let pomodoroIdentifier = "wp.pomodoro"

    static func schedulePomodoroComplete(in seconds: TimeInterval, taskTitle: String?) {
        cancelPomodoroComplete()
        guard seconds > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Focus session complete"
        content.body = taskTitle.map { "Nice work on \"\($0)\"." } ?? "Time for a break."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: pomodoroIdentifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func cancelPomodoroComplete() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [pomodoroIdentifier])
    }
}
