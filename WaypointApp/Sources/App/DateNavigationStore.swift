import Foundation

/// The day currently being browsed on the Today screen — shared so that other screens
/// (e.g. tapping a day in Week) can jump Today to a specific date.
@MainActor
final class DateNavigationStore: ObservableObject {
    @Published var selectedDate: Date = DateNavigationStore.launchDate

    /// `-wpDay 1` starts on tomorrow, `-wpDay -2` on the day before yesterday. Debug only, same
    /// family as `-wpTab`: reaching another day otherwise needs a swipe, and the simulator here
    /// is driven by hand.
    private static var launchDate: Date {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-wpDay"), flag + 1 < args.count,
              let offset = Int(args[flag + 1]),
              let day = Calendar.current.date(byAdding: .day, value: offset, to: .now) else { return .now }
        return day
        #else
        return .now
        #endif
    }
}
