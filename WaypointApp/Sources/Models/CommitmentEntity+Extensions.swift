import Foundation
import CoreData
import SwiftUI

extension CommitmentEntity {
    static let weekdaySymbols = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var dayList: [String] {
        (daysOfWeek ?? "").split(separator: ",").map(String.init)
    }

    /// `startTime`/`endTime` are generated as `Date?` by Core Data codegen regardless of the
    /// model's "Optional" flag; every commitment is created with both, so these are safe
    /// fallbacks, not real degenerate cases.
    var resolvedStartTime: Date {
        startTime ?? .now
    }

    var resolvedEndTime: Date {
        endTime ?? .now
    }

    var timeRangeLabel: String {
        let days = dayList
        let dayLabel: String
        if days.count >= 6 {
            dayLabel = "Every day"
        } else if days == ["Mon", "Tue", "Wed", "Thu", "Fri"] {
            dayLabel = "Mon-Fri"
        } else {
            dayLabel = days.joined(separator: ", ")
        }
        return "\(dayLabel)  \(resolvedStartTime.formatted(.dateTime.hour().minute()))-\(resolvedEndTime.formatted(.dateTime.hour().minute()))"
    }

    func occurs(on date: Date) -> Bool {
        let weekdayIndex = (Calendar.current.component(.weekday, from: date) + 5) % 7 // 0 = Mon
        let symbol = Self.weekdaySymbols[weekdayIndex]
        return dayList.contains(symbol)
    }

    func instance(on date: Date) -> (start: Date, end: Date) {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        let startComps = cal.dateComponents([.hour, .minute], from: resolvedStartTime)
        let endComps = cal.dateComponents([.hour, .minute], from: resolvedEndTime)
        let start = cal.date(byAdding: startComps, to: dayStart)!
        let end = cal.date(byAdding: endComps, to: dayStart)!
        return (start, end)
    }

    var iconSystemName: String {
        switch icon {
        case "work": "briefcase.fill"
        case "gym": "figure.run"
        case "class": "book.fill"
        case "meeting": "person.2.fill"
        case "sleep": "moon.fill"
        default: "calendar"
        }
    }

    @discardableResult
    static func create(
        in context: NSManagedObjectContext,
        name: String,
        icon: String,
        days: [String],
        startTime: Date,
        endTime: Date
    ) -> CommitmentEntity {
        let commitment = CommitmentEntity(context: context)
        commitment.id = UUID()
        commitment.name = name
        commitment.icon = icon
        commitment.daysOfWeek = days.joined(separator: ",")
        commitment.startTime = startTime
        commitment.endTime = endTime
        commitment.createdAt = .now
        return commitment
    }
}
