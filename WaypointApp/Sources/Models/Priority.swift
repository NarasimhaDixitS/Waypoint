import SwiftUI

enum Priority: String, CaseIterable, Identifiable, Hashable {
    case high, medium, low

    var id: String { rawValue }

    var label: String {
        switch self {
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }

    var sortWeight: Int {
        switch self {
        case .high: 0
        case .medium: 1
        case .low: 2
        }
    }

    /// References `ColorTokens` rather than hardcoding hex values, so a future palette change
    /// (like the warning/priorityMedium shift made to avoid colliding with accent swatches)
    /// only has to happen in one place.
    var tintColor: Color {
        switch self {
        case .high: ColorTokens.warning
        case .medium: ColorTokens.priorityMedium
        case .low: ColorTokens.textSecondary
        }
    }
}

enum PlanningMode: String, Hashable {
    case ai
    case manual
}

enum TaskState: Hashable {
    case done
    /// Not done, and its day is before today — missed, must be rescheduled rather than
    /// completed after the fact.
    case overdue
    /// Not done, and its day is after today.
    case future
    case inProgress
    case pending

    static func resolve(isDone: Bool, date: Date, startTime: Date, durationMinutes: Int, now: Date = .now) -> TaskState {
        if isDone { return .done }
        let cal = Calendar.current
        if cal.startOfDay(for: date) < cal.startOfDay(for: now) { return .overdue }
        if cal.startOfDay(for: date) > cal.startOfDay(for: now) { return .future }
        let end = startTime.addingTimeInterval(TimeInterval(durationMinutes * 60))
        if now >= startTime && now < end { return .inProgress }
        return .pending
    }
}
