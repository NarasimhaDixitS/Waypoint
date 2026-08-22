import Foundation
import UserNotifications

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
            center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    static func disableAll() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
    }

    // MARK: - Per-task reminders

    static func reminderIdentifier(for taskID: UUID) -> String {
        "wp.task.\(taskID.uuidString)"
    }

    static func scheduleReminder(taskID: UUID, title: String, startTime: Date) {
        cancelReminder(taskID: taskID)

        let fireDate = startTime.addingTimeInterval(-reminderLeadTime)
        guard fireDate > .now else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "Starts in 5 minutes"
        content.sound = .default

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: reminderIdentifier(for: taskID), content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
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
