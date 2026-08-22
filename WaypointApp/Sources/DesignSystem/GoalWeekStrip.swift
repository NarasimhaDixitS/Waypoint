import SwiftUI

/// The goal banner's week ring-strip — seven dots reusing the same filled/hollow ring
/// vocabulary as `ProgressRing` and every task's status dot, instead of a separate flame
/// icon. A missed day stays visibly hollow rather than resetting a hidden counter to zero.
struct GoalWeekStrip: View {
    var days: [(date: Date, done: Bool)]

    var body: some View {
        HStack(spacing: 9) {
            ForEach(days, id: \.date) { day in
                VStack(spacing: 4) {
                    dot(for: day)
                    Text(Self.weekdayLetter(for: day.date))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
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

    private func dot(for day: (date: Date, done: Bool)) -> some View {
        let isToday = Calendar.current.isDateInToday(day.date)
        return ZStack {
            if isToday {
                Circle().fill(Color.white.opacity(0.18)).frame(width: 21, height: 21)
            }
            Circle()
                .strokeBorder(.white.opacity(day.done || isToday ? 1 : 0.35), lineWidth: isToday ? 2 : 1.6)
                .background(Circle().fill(day.done ? Color.white : .clear))
                .frame(width: 15, height: 15)
        }
        .frame(width: 21, height: 21)
    }
}
