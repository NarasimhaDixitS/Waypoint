import Foundation
import Combine

/// Sleep is a mandatory, always-on protected block rather than an optional commitment —
/// every user gets one, pre-filled with a sensible default, confirmable/editable during
/// onboarding and again later in Settings.
@MainActor
final class SleepSettings: ObservableObject {
    static let shared = SleepSettings()

    /// Time-of-day (only hour/minute are read) sleep begins.
    @Published var startTimeOfDay: Date {
        didSet { UserDefaults.standard.set(startTimeOfDay, forKey: Keys.start) }
    }
    @Published var durationMinutes: Int {
        didSet { UserDefaults.standard.set(durationMinutes, forKey: Keys.duration) }
    }
    /// Whether the user has confirmed/adjusted this during onboarding (vs. still on the
    /// untouched default).
    @Published var isConfirmed: Bool {
        didSet { UserDefaults.standard.set(isConfirmed, forKey: Keys.confirmed) }
    }

    static let defaultDurationMinutes = 7 * 60

    private enum Keys {
        static let start = "sleepStartTimeOfDay"
        static let duration = "sleepDurationMinutes"
        static let confirmed = "sleepConfirmed"
    }

    private init() {
        let defaults = UserDefaults.standard
        startTimeOfDay = defaults.object(forKey: Keys.start) as? Date ?? Self.defaultStart()
        durationMinutes = defaults.object(forKey: Keys.duration) as? Int ?? Self.defaultDurationMinutes
        isConfirmed = defaults.bool(forKey: Keys.confirmed)
    }

    private static func defaultStart() -> Date {
        var comps = DateComponents()
        comps.hour = 23
        comps.minute = 0
        return Calendar.current.date(from: comps) ?? .now
    }

    var endTimeOfDayLabel: String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: startTimeOfDay)
        let start = cal.date(bySettingHour: comps.hour ?? 23, minute: comps.minute ?? 0, second: 0, of: .now) ?? .now
        return start.addingTimeInterval(TimeInterval(durationMinutes * 60)).formatted(.dateTime.hour().minute())
    }

    /// The concrete sleep window that *begins* on the given calendar day.
    func range(startingOn day: Date) -> (start: Date, end: Date) {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: startTimeOfDay)
        let dayStart = cal.startOfDay(for: day)
        let start = cal.date(byAdding: comps, to: dayStart) ?? dayStart
        let end = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
        return (start, end)
    }

    /// All sleep windows that overlap the given calendar day at all — the tail end of the
    /// previous night's sleep (early morning) and the start of that night's sleep (late
    /// evening), since sleep spans midnight.
    func rangesTouching(_ day: Date) -> [(start: Date, end: Date)] {
        let cal = Calendar.current
        let previousDay = cal.date(byAdding: .day, value: -1, to: day) ?? day
        return [range(startingOn: previousDay), range(startingOn: day)]
    }
}
