import SwiftUI

/// The week ring-strip — seven dots reusing the same filled/hollow vocabulary as
/// `ProgressRing` and every task's status dot, instead of a separate flame icon. A missed day
/// stays visibly hollow rather than resetting a hidden counter to zero.
///
/// **Three states, not two.** Filled is done, hollow is missed, and faint is neither — a day
/// before this person had ever opened the app. Without that last one, someone on their second
/// day is shown five hollow rings for days they were never here for, which reads as a week of
/// failure and is simply false. It is the difference between "you're starting" and "you failed",
/// drawn from the same data.
struct GoalWeekStrip: View {
    var days: [(date: Date, done: Bool)]
    /// Days before this are drawn as not-applicable. `nil` treats every day as in scope, which
    /// is right for a goal strip scoped to a goal that already exists.
    var activeSince: Date?
    /// The one colour everything here is drawn in, at varying opacity.
    ///
    /// White by default because this was built for Today's banner, which is a card filled with
    /// the accent — and it was hardcoded white until the goal centre put the same strip on a
    /// `surface1` card, where white on white rendered nothing at all. The strip has no business
    /// knowing which ground it is on; the caller does.
    var tint: Color = .white

    var body: some View {
        HStack(spacing: 9) {
            ForEach(days, id: \.date) { day in
                VStack(spacing: 4) {
                    dot(for: day)
                    Text(Self.weekdayLetter(for: day.date))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(tint.opacity(isBeforeStart(day.date) ? 0.4 : 0.85))
                }
            }
        }
    }

    /// Hardcoded rather than pulled from `Calendar`/`DateFormatter` — both read the
    /// device's region (this simulator is set to `en_IN`), whose narrow-weekday data
    /// turned out to render wrong/blank letters here. A fixed English S/M/T/W/T/F/S avoids
    /// depending on locale data for a two-word caption's worth of labels.
    private static let weekdayLetters = ["S", "M", "T", "W", "T", "F", "S"]

    /// `Calendar.component(.weekday:)` returns 1-indexed from Sunday; `weekdayLetters` is
    /// 0-indexed from Sunday, hence `- 1`.
    private static func weekdayLetter(for date: Date) -> String {
        weekdayLetters[Calendar.current.component(.weekday, from: date) - 1]
    }

    /// True for a day that predates this person entirely.
    private func isBeforeStart(_ date: Date) -> Bool {
        guard let activeSince else { return false }
        let cal = Calendar.current
        return cal.startOfDay(for: date) < cal.startOfDay(for: activeSince)
    }

    private func dot(for day: (date: Date, done: Bool)) -> some View {
        let cal = Calendar.current
        let isToday = cal.isDateInToday(day.date)
        let outOfScope = isBeforeStart(day.date)
        return ZStack {
            if isToday {
                Circle().fill(tint.opacity(0.18)).frame(width: 21, height: 21)
            }
            if outOfScope {
                // A dot, not a ring. A ring is a container with nothing in it, which is what
                // "missed" looks like; a mark this small just holds the place in the row.
                Circle()
                    .fill(tint.opacity(0.22))
                    .frame(width: 5, height: 5)
            } else {
                Circle()
                    .strokeBorder(tint.opacity(day.done || isToday ? 1 : 0.35), lineWidth: isToday ? 2 : 1.6)
                    .background(Circle().fill(day.done ? tint : .clear))
                    .frame(width: 15, height: 15)
            }
        }
        .frame(width: 21, height: 21)
    }
}
