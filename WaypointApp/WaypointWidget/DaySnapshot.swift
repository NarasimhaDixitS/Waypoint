import Foundation

/// Today, as the widget needs it.
///
/// A plain snapshot rather than managed objects: a widget timeline entry outlives the context
/// that produced it, and handing `TaskEntity` across that boundary means faulting a deleted
/// object on a background process minutes later. Values can't fault.
struct DaySnapshot {
    struct Item: Identifiable, Hashable {
        let id: UUID
        let title: String
        let start: Date
        let end: Date
        let isDone: Bool

        var isRunning: Bool { Date.now >= start && Date.now < end && !isDone }
    }

    let date: Date
    let items: [Item]

    var done: Int { items.filter(\.isDone).count }
    var total: Int { items.count }
    var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }

    /// Planned effort still outstanding — the same figure the Today card shows, and the most
    /// useful single number the widget can carry.
    var remainingMinutes: Int {
        items.filter { !$0.isDone }.reduce(0) { $0 + Int($1.end.timeIntervalSince($1.start) / 60) }
    }

    var remainingLabel: String {
        let minutes = remainingMinutes
        guard minutes > 0 else { return "Nothing left" }
        let hours = minutes / 60
        let mins = minutes % 60
        let span = hours > 0 ? (mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h") : "\(mins)m"
        return "\(span) of work left"
    }

    /// The one the widget leads with: what's running now, or what's next.
    var focus: Item? {
        items.first(where: \.isRunning) ?? items.first { !$0.isDone && $0.end > .now }
    }

    static let placeholder = DaySnapshot(
        date: .now,
        items: (0..<4).map { index in
            Item(
                id: UUID(),
                title: ["Morning miles", "Deep work", "Vocab drill", "Review PRs"][index],
                start: Date.now.addingTimeInterval(Double(index) * 3600),
                end: Date.now.addingTimeInterval(Double(index) * 3600 + 1800),
                isDone: index == 0
            )
        }
    )
}

extension DaySnapshot {
    /// When the widget should next redraw, taken from the day's own shape rather than a fixed
    /// interval.
    ///
    /// A widget gets a limited number of wake-ups a day, and polling every fifteen minutes
    /// spends them on moments when nothing changed. Every task's start and end is a moment when
    /// something genuinely does — a row becomes current, or stops being — so those are the only
    /// times worth waking for.
    func refreshDates(now: Date = .now, limit: Int = 24) -> [Date] {
        var dates = Set<Date>()
        for item in items {
            if item.start > now { dates.insert(item.start) }
            if item.end > now { dates.insert(item.end) }
        }
        // Midnight, so an untouched widget rolls over to the new day on its own.
        if let midnight = Calendar.current.nextDate(
            after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime
        ) {
            dates.insert(midnight)
        }
        return Array(dates.sorted().prefix(limit))
    }
}
