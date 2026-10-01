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
    /// the whole queue, counting the day summary, the streak nudge and a running Pomodoro
    /// alongside every task reminder. Past that it keeps the 64 that fire soonest and silently
    /// discards the rest: `add` calls back with no error, so the app cannot tell it happened and
    /// the reminder someone was relying on simply never arrives.
    ///
    /// That limit is why a reminder being *on* and a reminder being *in iOS's queue* are kept as
    /// two different things. The flag lives on the task; only a rolling window of them is ever
    /// handed to the system. A daily repeating task with reminders on therefore costs two slots,
    /// not three hundred and sixty-five — without that split, one habit would quietly evict
    /// every other reminder in the app.
    static let maxPendingReminders = 64

    /// The day summary, the streak nudge and a running Pomodoro each hold a slot, so task
    /// reminders can't be allowed to fill the queue right to the cap.
    private static let reservedNonTaskSlots = 4

    /// How far ahead reminders are materialised.
    ///
    /// Not "today", which is what this used to be. Nothing schedules these except the app
    /// itself, and nothing wakes the app in the background to do it — so a day you never opened
    /// Waypoint was a day with no reminders at all, which is a poor showing for a feature whose
    /// entire promise is that you won't miss something. Two days means missing a day costs
    /// nothing. It isn't longer because a nudge about next Thursday isn't a reminder, it's noise.
    static let schedulingWindow: TimeInterval = 48 * 60 * 60

    static func reminderIdentifier(for taskID: UUID) -> String {
        "wp.task.\(taskID.uuidString)"
    }

    /// Which tasks should hold a slot right now, in the order they should get one.
    ///
    /// Pure and separated from the scheduling call so the budget rule can be tested — it is the
    /// part that fails invisibly, and a wrong answer here looks exactly like a working app.
    ///
    /// Ordered by priority before start time. Sorting by time alone, which is what this did,
    /// means an overflowing queue drops the *latest* tasks: a 9am errand would keep its slot
    /// while a 10am interview silently lost one. Priority is a weak rule for deciding whether to
    /// interrupt someone, but it is the right rule for deciding who loses when there isn't room
    /// for everyone.
    static func remindableTasks(from tasks: [TaskEntity], now: Date = .now) -> [TaskEntity] {
        let horizon = now.addingTimeInterval(schedulingWindow)
        return tasks
            .filter { task in
                guard let fire = task.reminderFireDate(now: now) else { return false }
                return fire <= horizon
            }
            .sorted { a, b in
                let (pa, pb) = (a.priorityValue.sortWeight, b.priorityValue.sortWeight)
                if pa != pb { return pa < pb }
                return a.resolvedStartTime < b.resolvedStartTime
            }
            .prefix(maxPendingReminders - reservedNonTaskSlots)
            .map { $0 }
    }

    /// Rebuilds reminders from the store rather than from whatever list a screen happens to
    /// hold. Every caller wants the same answer, and the window is wider than any one screen's
    /// fetch, so letting callers supply the tasks only invited them to disagree about the rules.
    static func refreshTaskReminders(in context: NSManagedObjectContext, enabled: Bool, now: Date = .now) {
        let cal = Calendar.current
        // Days, padded past the window: the fetch filters on `date`, which is a start-of-day,
        // while the window is measured against each task's own start time. `remindableTasks`
        // does the precise cut — this just has to not exclude anything it would have kept.
        let request = TaskEntity.fetchRequest(
            from: cal.startOfDay(for: now),
            to: now.addingTimeInterval(schedulingWindow + 86_400)
        )
        refreshTaskReminders(tasks: (try? context.fetch(request)) ?? [], enabled: enabled, now: now)
    }

    /// Rebuilds the whole reminder set from the tasks it's given.
    ///
    /// Wholesale rather than per-task: the original code cancelled and re-added one task at a
    /// time from two different screens, so a task deleted somewhere that forgot to call it kept
    /// its reminder and fired for work that no longer existed. Rebuilding from the current list
    /// can't drift, because the list *is* the source of truth.
    ///
    /// - Parameter tasks: every task within the scheduling window, done or not. Filtering
    ///   happens here so callers can't disagree about the rules.
    static func refreshTaskReminders(tasks: [TaskEntity], enabled: Bool, now: Date = .now) {
        let center = UNUserNotificationCenter.current()
        // Snapshot on the caller's actor: the completion handler below runs off the main queue,
        // and a managed object read from there is a crash waiting for a slow day.
        let due: [(id: UUID, title: String, fire: Date, lead: Int)] = enabled
            ? remindableTasks(from: tasks, now: now).compactMap { task in
                guard let id = task.id, let fire = task.reminderFireDate(now: now) else { return nil }
                return (id, task.title ?? "Task", fire, task.resolvedReminderLeadMinutes)
            }
            : []

        center.getPendingNotificationRequests { pending in
            let stale = pending.map(\.identifier).filter { $0.hasPrefix("wp.task.") }
            center.removePendingNotificationRequests(withIdentifiers: stale)
            for task in due {
                center.add(reminderRequest(taskID: task.id, title: task.title, fireDate: task.fire, leadMinutes: task.lead))
            }
        }
    }

    /// How a lead time reads in a notification body. Fixed English rather than a formatter: the
    /// device region here is `en_IN`, whose locale data has rendered blank elsewhere in this app,
    /// and the vocabulary is four phrases long.
    static func leadDescription(minutes: Int) -> String {
        switch minutes {
        case ...0: "Starting now"
        case 1: "Starts in a minute"
        case 60: "Starts in an hour"
        case let m where m % 60 == 0: "Starts in \(m / 60) hours"
        case let m: "Starts in \(m) minutes"
        }
    }

    private static func reminderRequest(taskID: UUID, title: String, fireDate: Date, leadMinutes: Int) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = leadDescription(minutes: leadMinutes)
        content.sound = .default
        // As close to an alarm as a third-party app is allowed to get: only Apple's Clock rings
        // through silent mode, and `.timeSensitive` is the one level that breaks through a Focus
        // mode when the user permits it.
        //
        // It does **not** currently work in this build. The level requires the
        // `com.apple.developer.usernotifications.time-sensitive` entitlement, which
        // `Generated/Waypoint.entitlements` does not carry — without it iOS downgrades the
        // request silently, so these behave as ordinary notifications. Adding the entitlement
        // needs a provisioning profile from a paid developer account; doing it before then
        // breaks signing. Left set so the behaviour arrives with the account rather than needing
        // to be remembered, and said plainly here so nobody reads the line and believes it.
        content.interruptionLevel = .timeSensitive
        content.threadIdentifier = "wp.task"

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
